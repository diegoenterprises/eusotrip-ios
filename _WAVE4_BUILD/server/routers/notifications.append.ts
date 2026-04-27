/**
 * Wave-4 · Theme 2.7 · APPEND-ONLY patch for `server/routers/notifications.ts`.
 *
 * DO NOT replace the existing router. Paste the block below INSIDE the
 * existing `createTRPCRouter({ ... })` definition (just before the closing
 * `});`). Imports at the top of the file need to be extended — the exact
 * additions are listed in `_WAVE4_BUILD/agent_06.md` changelog.
 *
 * Auth: every procedure is `protectedProcedure` — notifications are always
 * scoped to `ctx.user.id`. No admin-only branches here.
 */

// ────────────────────────────────────────────────────────────────────────────
// Imports to add to the existing notifications.ts file (top of file)
// ────────────────────────────────────────────────────────────────────────────
import { z } from 'zod';
import { and, eq, inArray, isNotNull, lt, sql } from 'drizzle-orm';
import { TRPCError } from '@trpc/server';
import { protectedProcedure, createTRPCRouter } from '../trpc';
import { db } from '../db';
import {
  notifications,
  notificationChannelPreferences,
} from '../schema';
// ────────────────────────────────────────────────────────────────────────────

/** Channel enum — keep in sync with schema enum `notification_channel`. */
export const NotificationChannelEnum = z.enum([
  'dispatch',
  'ops',
  'safety',
  'hos',
  'marketing',
  'ai_coach',
]);
export type NotificationChannel = z.infer<typeof NotificationChannelEnum>;

/**
 * ==========================================================================
 *  APPEND inside existing `notificationsRouter = createTRPCRouter({ ... })`
 * ==========================================================================
 */
export const notificationsWave4Procedures = {
  /* ----------------------------------------------------------------------
   * snooze — hide a notification from the inbox until the given timestamp.
   * UI origins: 064 Notifications Inbox "SNOOZE 6h", 114 Broadcasts "Snooze 2h".
   * Validation: `until` must be in the future; hard-capped at +30d.
   * -------------------------------------------------------------------- */
  snooze: protectedProcedure
    .input(
      z.object({
        notificationId: z.string().uuid(),
        until: z.date(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const now = new Date();
      if (input.until <= now) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: 'snooze.until must be in the future',
        });
      }
      const maxUntil = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
      if (input.until > maxUntil) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: 'snooze.until cannot exceed 30 days from now',
        });
      }

      const [row] = await db
        .update(notifications)
        .set({
          snoozedUntil: input.until,
          updatedAt: now,
        })
        .where(
          and(
            eq(notifications.id, input.notificationId),
            eq(notifications.userId, ctx.user.id),
          ),
        )
        .returning({
          id: notifications.id,
          snoozedUntil: notifications.snoozedUntil,
        });

      if (!row) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: 'notification not found or not owned by user',
        });
      }
      return { ok: true as const, id: row.id, snoozedUntil: row.snoozedUntil };
    }),

  /* ----------------------------------------------------------------------
   * clearRead — delete read notifications older than 7 days (user-scoped).
   * UI origin: 064 Notifications Inbox "Clear read".
   * -------------------------------------------------------------------- */
  clearRead: protectedProcedure.mutation(async ({ ctx }) => {
    const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const deleted = await db
      .delete(notifications)
      .where(
        and(
          eq(notifications.userId, ctx.user.id),
          eq(notifications.isRead, true),
          lt(notifications.readAt, cutoff),
        ),
      )
      .returning({ id: notifications.id });
    return { ok: true as const, removed: deleted.length };
  }),

  /* ----------------------------------------------------------------------
   * markAllRead — bulk mark every unread notification as read.
   * UI origins: 064 / 074 / 095 "Mark all read".
   * NOTE: `markAllAsRead` already exists in the existing router (line 198
   * per agent_04 report). This new `markAllRead` is the canonical camelCase
   * alias requested in roadmap 2.7. The existing one is kept for back-compat
   * and simply calls this.
   * -------------------------------------------------------------------- */
  markAllRead: protectedProcedure
    .input(
      z
        .object({
          channel: NotificationChannelEnum.optional(),
        })
        .optional(),
    )
    .mutation(async ({ ctx, input }) => {
      const now = new Date();
      const conds = [
        eq(notifications.userId, ctx.user.id),
        eq(notifications.isRead, false),
      ];
      if (input?.channel) {
        conds.push(eq(notifications.channel, input.channel));
      }
      const updated = await db
        .update(notifications)
        .set({ isRead: true, readAt: now, updatedAt: now })
        .where(and(...conds))
        .returning({ id: notifications.id });
      return { ok: true as const, updated: updated.length };
    }),

  /* ----------------------------------------------------------------------
   * setChannelPreferences — turn a channel on or off for the current user.
   * UI origin: 063 Preferences channel toggles, 095 Notifications prefs.
   * Upserts into notification_channel_preferences (PK user_id, channel).
   * -------------------------------------------------------------------- */
  setChannelPreferences: protectedProcedure
    .input(
      z.object({
        channel: NotificationChannelEnum,
        enabled: z.boolean(),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const now = new Date();
      await db
        .insert(notificationChannelPreferences)
        .values({
          userId: ctx.user.id,
          channel: input.channel,
          enabled: input.enabled,
          updatedAt: now,
        })
        .onConflictDoUpdate({
          target: [
            notificationChannelPreferences.userId,
            notificationChannelPreferences.channel,
          ],
          set: {
            enabled: input.enabled,
            updatedAt: now,
          },
        });
      return { ok: true as const, channel: input.channel, enabled: input.enabled };
    }),

  /* ----------------------------------------------------------------------
   * getChannelPreferences — all six channels with their enabled flags.
   * Fills in defaults for channels the user never flipped.
   * -------------------------------------------------------------------- */
  getChannelPreferences: protectedProcedure.query(async ({ ctx }) => {
    const rows = await db
      .select()
      .from(notificationChannelPreferences)
      .where(eq(notificationChannelPreferences.userId, ctx.user.id));

    // sensible defaults — marketing off, everything else on
    const defaults: Record<NotificationChannel, boolean> = {
      dispatch: true,
      ops: true,
      safety: true,
      hos: true,
      marketing: false,
      ai_coach: true,
    };
    const map = new Map<NotificationChannel, boolean>(
      rows.map((r) => [r.channel as NotificationChannel, r.enabled]),
    );

    const out = (Object.keys(defaults) as NotificationChannel[]).map((ch) => ({
      channel: ch,
      enabled: map.has(ch) ? (map.get(ch) as boolean) : defaults[ch],
      isDefault: !map.has(ch),
      updatedAt: rows.find((r) => r.channel === ch)?.updatedAt ?? null,
    }));

    return { channels: out };
  }),
};

/**
 * In the existing file, mutate the router literal like so:
 *
 *   export const notificationsRouter = createTRPCRouter({
 *     // … existing procedures (list, getGroupedByDay, archive, markAllAsRead,
 *     //   getSummary, getPreferences, updatePreferences, getUnreadCount, …)
 *
 *     // ── Wave-4 Theme 2.7 additions ──
 *     ...notificationsWave4Procedures,
 *
 *     // draft subsurface — defined in notificationsDraft.ts
 *     draft: notificationsDraftRouter,
 *   });
 */
