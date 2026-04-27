/**
 * Wave-4 · Theme 2.7 · New router file.
 *
 * Path in the web repo: `server/routers/notificationsDraft.ts`
 *
 * Exposes `notifications.draft.*` via mounting as `draft: notificationsDraftRouter`
 * inside the existing `notificationsRouter`. See agent_06.md §Changelog for the
 * exact edit to `notifications.ts` to mount this subrouter.
 *
 * The driver-side UI entry points are:
 *   - 112 Inbox · `Reply Sarah` → creates a draft
 *   - 113 Thread · ESANG "Draft Ready" chips → update/send
 *   - 114 Broadcasts · (not drafted — broadcasts are read-only)
 *   - 115 Voice Reply · carried-replies queue reads from draft.list
 */

import { z } from 'zod';
import { and, desc, eq } from 'drizzle-orm';
import { TRPCError } from '@trpc/server';
import { createTRPCRouter, protectedProcedure } from '../trpc';
import { db } from '../db';
import { notificationDrafts, notifications, users } from '../schema';
import { NotificationChannelEnum } from './notifications';

const DraftStatusEnum = z.enum(['draft', 'sent', 'discarded']);

const PatchSchema = z
  .object({
    to: z.string().uuid().optional(),
    channel: NotificationChannelEnum.optional(),
    body: z.string().trim().max(4000).optional(),
  })
  .refine((p) => Object.keys(p).length > 0, {
    message: 'patch must contain at least one field',
  });

export const notificationsDraftRouter = createTRPCRouter({
  /* ----------------------------------------------------------------------
   * list — every draft authored by the current user, newest first.
   * -------------------------------------------------------------------- */
  list: protectedProcedure
    .input(
      z
        .object({
          status: DraftStatusEnum.optional(),
          limit: z.number().int().min(1).max(100).default(50),
        })
        .optional(),
    )
    .query(async ({ ctx, input }) => {
      const conds = [eq(notificationDrafts.authorUserId, ctx.user.id)];
      if (input?.status) conds.push(eq(notificationDrafts.status, input.status));

      const rows = await db
        .select()
        .from(notificationDrafts)
        .where(and(...conds))
        .orderBy(desc(notificationDrafts.updatedAt))
        .limit(input?.limit ?? 50);

      return { drafts: rows };
    }),

  /* ----------------------------------------------------------------------
   * create — new draft. The author can compose to any user they have a
   * messaging relationship with; row-level membership check is delegated
   * to middleware (see `assertCanMessage` in ../middleware/messaging).
   * -------------------------------------------------------------------- */
  create: protectedProcedure
    .input(
      z.object({
        to: z.string().uuid(),
        channel: NotificationChannelEnum,
        body: z.string().trim().min(1).max(4000),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      if (input.to === ctx.user.id) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: 'cannot create a draft addressed to yourself',
        });
      }
      // light existence check — hard permission check lives in middleware
      const [target] = await db
        .select({ id: users.id })
        .from(users)
        .where(eq(users.id, input.to))
        .limit(1);
      if (!target) {
        throw new TRPCError({ code: 'NOT_FOUND', message: 'recipient user not found' });
      }

      const now = new Date();
      const [row] = await db
        .insert(notificationDrafts)
        .values({
          authorUserId: ctx.user.id,
          toUserId: input.to,
          channel: input.channel,
          body: input.body,
          status: 'draft',
          createdAt: now,
          updatedAt: now,
        })
        .returning();

      return { draft: row };
    }),

  /* ----------------------------------------------------------------------
   * update — patch body / channel / recipient on a draft (only while in
   * the `draft` state). `sent` / `discarded` rows are immutable.
   * -------------------------------------------------------------------- */
  update: protectedProcedure
    .input(
      z.object({
        draftId: z.string().uuid(),
        patch: PatchSchema,
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const [existing] = await db
        .select()
        .from(notificationDrafts)
        .where(
          and(
            eq(notificationDrafts.id, input.draftId),
            eq(notificationDrafts.authorUserId, ctx.user.id),
          ),
        )
        .limit(1);

      if (!existing) {
        throw new TRPCError({ code: 'NOT_FOUND', message: 'draft not found' });
      }
      if (existing.status !== 'draft') {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: `cannot update a ${existing.status} draft`,
        });
      }

      const now = new Date();
      const [row] = await db
        .update(notificationDrafts)
        .set({
          toUserId: input.patch.to ?? existing.toUserId,
          channel: input.patch.channel ?? existing.channel,
          body: input.patch.body ?? existing.body,
          updatedAt: now,
        })
        .where(eq(notificationDrafts.id, input.draftId))
        .returning();

      return { draft: row };
    }),

  /* ----------------------------------------------------------------------
   * send — flip status to `sent` AND insert a real notification row for the
   * recipient. Atomic via transaction.
   * -------------------------------------------------------------------- */
  send: protectedProcedure
    .input(z.object({ draftId: z.string().uuid() }))
    .mutation(async ({ ctx, input }) => {
      return await db.transaction(async (tx) => {
        const [draft] = await tx
          .select()
          .from(notificationDrafts)
          .where(
            and(
              eq(notificationDrafts.id, input.draftId),
              eq(notificationDrafts.authorUserId, ctx.user.id),
            ),
          )
          .limit(1);

        if (!draft) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'draft not found' });
        }
        if (draft.status !== 'draft') {
          throw new TRPCError({
            code: 'BAD_REQUEST',
            message: `cannot send a ${draft.status} draft`,
          });
        }

        const now = new Date();
        const [notif] = await tx
          .insert(notifications)
          .values({
            userId: draft.toUserId,
            channel: draft.channel,
            title: `Message from ${ctx.user.displayName ?? 'a teammate'}`,
            body: draft.body,
            category: draft.channel, // align with legacy category column
            isRead: false,
            createdAt: now,
            updatedAt: now,
            sourceDraftId: draft.id,
          })
          .returning({ id: notifications.id });

        const [updated] = await tx
          .update(notificationDrafts)
          .set({ status: 'sent', updatedAt: now })
          .where(eq(notificationDrafts.id, draft.id))
          .returning();

        return { ok: true as const, draft: updated, notificationId: notif.id };
      });
    }),

  /* ----------------------------------------------------------------------
   * discard — soft-close the draft; kept for audit.
   * -------------------------------------------------------------------- */
  discard: protectedProcedure
    .input(z.object({ draftId: z.string().uuid() }))
    .mutation(async ({ ctx, input }) => {
      const now = new Date();
      const [row] = await db
        .update(notificationDrafts)
        .set({ status: 'discarded', updatedAt: now })
        .where(
          and(
            eq(notificationDrafts.id, input.draftId),
            eq(notificationDrafts.authorUserId, ctx.user.id),
            eq(notificationDrafts.status, 'draft'),
          ),
        )
        .returning();

      if (!row) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: 'draft not found or no longer editable',
        });
      }
      return { ok: true as const, draft: row };
    }),
});

export type NotificationsDraftRouter = typeof notificationsDraftRouter;
