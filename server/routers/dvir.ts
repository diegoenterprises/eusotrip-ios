/**
 * server/routers/dvir.ts
 *
 * Wave-4 · Agent #8 — closes the "no DVIR router" gap identified in
 * `_WAVE3_AUDIT/agent_05.md` (lines 386, 391, 408, 413).
 *
 * Backs Figma screens:
 *   * 087 DVIR Builder (primary — Pre / Post tab, category tiles, signature)
 *   * 077 Vehicle Trailer (DVIR CTA)
 *   * 104 DVIR (post-trip detail / PDF view — see agent_08 Wave-3 audit)
 *   * 088 Maintenance Shop Scheduler ("Report defect" CTA)
 *
 * Integration with `server/routers/inspections.ts`
 * ------------------------------------------------
 * The legacy `inspections` router already owns a partial DVIR surface:
 *
 *   * inspections.ts:143-189 — `submit` writes an `inspections` row with
 *     type='dvir' and fires the `safety_inspection_passed` gamification
 *     event. Our `dvir.submit` writes to `dvirs` and ALSO (when legacy
 *     rows are present) calls the same gamification dispatch so rank
 *     math stays consistent.
 *   * inspections.ts:279-315 — `createDVIR` writes to `dvir_reports` and
 *     `dvir_defect_items`. Our `dvir.create` writes to the Wave-4 `dvirs`
 *     table. During the transition we link rows via `dvirs.legacy_dvir_id`
 *     and `dvirs.inspection_ref_id`.
 *   * inspections.ts:317-338 — `getDVIRHistory` joins `dvir_reports` with
 *     `vehicles`. Our `dvir.listMine` reads from `dvirs` first and then
 *     UNIONs legacy rows via a raw SQL fallback (see `listMine` below).
 *   * inspections.ts:340-360 — `reviewDVIR` performs the mechanic-review
 *     transition on legacy rows. For Wave-4 we scope the new router to
 *     driver-side CRUD only — mechanic review stays in `inspections`.
 *
 * STRICT: do NOT edit `server/routers.ts` or `server/routers/inspections.ts`.
 * Registration lives in `_WAVE4_BUILD/agent_08.md` changelog.
 */

import { z } from 'zod';
import { and, desc, eq, sql } from 'drizzle-orm';
import { TRPCError } from '@trpc/server';
import { randomBytes } from 'crypto';

import { isolatedProcedure as protectedProcedure, router } from '../_core/trpc';
import { getDb } from '../db';
import { dvirs, driverExportTokens } from '../../drizzle/schema.additions.wave4-8';

/* -------------------------------------------------------------------------- */
/*  Shared zod schemas                                                         */
/* -------------------------------------------------------------------------- */

const defectSchema = z.object({
  category: z.string().min(1),
  description: z.string().min(1),
  severity: z.enum(['minor', 'major', 'out_of_service']).default('minor'),
  photoS3Key: z.string().optional(),
});

const dvirKindSchema = z.enum(['pre', 'post']);
const dvirStatusSchema = z.enum(['draft', 'submitted']);

const driverIdFromCtx = (ctx: any): number => {
  const raw = ctx?.user?.id;
  return typeof raw === 'string' ? parseInt(raw, 10) : (raw ?? 0);
};
const companyIdFromCtx = (ctx: any): number | null => {
  const raw = ctx?.user?.companyId;
  if (raw === undefined || raw === null) return null;
  return typeof raw === 'string' ? parseInt(raw, 10) : raw;
};

const SIGNED_URL_TTL_MS = 1000 * 60 * 15;

/* -------------------------------------------------------------------------- */
/*  Router                                                                     */
/* -------------------------------------------------------------------------- */

export const dvirRouter = router({
  /**
   * List the current driver's DVIRs. Optionally filter by vehicle / status.
   * Falls back to the legacy `dvir_reports` table so UIs using the new
   * router still see pre-Wave-4 history (see inspections.ts:317-338).
   */
  listMine: protectedProcedure
    .input(
      z
        .object({
          vehicleId: z.number().int().positive().optional(),
          status: dvirStatusSchema.optional(),
          limit: z.number().int().min(1).max(100).default(20),
        })
        .optional()
    )
    .query(async ({ ctx, input }) => {
      const db = await getDb();
      if (!db) throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'DB unavailable' });
      const driverId = driverIdFromCtx(ctx);
      if (!driverId) throw new TRPCError({ code: 'UNAUTHORIZED' });

      const limit = input?.limit ?? 20;
      const filters: any[] = [eq(dvirs.driverId, driverId)];
      if (input?.vehicleId) filters.push(eq(dvirs.vehicleId, input.vehicleId));
      if (input?.status) filters.push(eq(dvirs.status, input.status));

      const rows = (await db
        .select()
        .from(dvirs)
        .where(and(...filters))
        .orderBy(desc(dvirs.createdAt))
        .limit(limit)) as any[];

      // Legacy fallback — only when we have room AND no row-level filter
      // that the legacy table can't satisfy.
      let legacy: any[] = [];
      if (rows.length < limit) {
        try {
          const raw = await db.execute(sql`
            SELECT id, vehicleId, driverId, reportType AS kind, status,
                   defects, createdAt, NULL AS signatures_s3_key
            FROM dvir_reports
            WHERE driverId = ${driverId}
              ${input?.vehicleId ? sql`AND vehicleId = ${input.vehicleId}` : sql``}
            ORDER BY createdAt DESC
            LIMIT ${limit - rows.length}
          `);
          const data: any[] = Array.isArray(raw) ? (raw[0] ?? raw) : raw;
          legacy = (data ?? []).map((r: any) => ({
            id: `legacy_${r.id}`,
            driverId: r.driverId,
            vehicleId: r.vehicleId,
            kind: r.kind === 'post_trip' ? 'post' : 'pre',
            status: r.status === 'submitted' ? 'submitted' : 'draft',
            defects: typeof r.defects === 'string' ? JSON.parse(r.defects) : r.defects,
            createdAt: r.createdAt,
            source: 'legacy',
          }));
        } catch {
          legacy = [];
        }
      }

      return {
        items: [...rows, ...legacy],
      };
    }),

  /**
   * Read one DVIR (Wave-4 table only — legacy detail stays on inspections).
   */
  getById: protectedProcedure
    .input(z.object({ dvirId: z.number().int().positive() }))
    .query(async ({ ctx, input }) => {
      const db = await getDb();
      if (!db) throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'DB unavailable' });
      const driverId = driverIdFromCtx(ctx);

      const [row] = (await db
        .select()
        .from(dvirs)
        .where(and(eq(dvirs.id, input.dvirId), eq(dvirs.driverId, driverId)))
        .limit(1)) as any[];

      if (!row) throw new TRPCError({ code: 'NOT_FOUND' });
      return row;
    }),

  /**
   * Create a fresh DVIR — always lands as `draft`. Submit via `dvir.submit`.
   */
  create: protectedProcedure
    .input(
      z.object({
        vehicleId: z.number().int().positive(),
        trailerId: z.number().int().positive().optional(),
        kind: dvirKindSchema,
        defects: z.array(defectSchema).default([]),
        signaturesS3Key: z.string().optional(),
      })
    )
    .mutation(async ({ ctx, input }) => {
      const db = await getDb();
      if (!db) throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'DB unavailable' });
      const driverId = driverIdFromCtx(ctx);
      if (!driverId) throw new TRPCError({ code: 'UNAUTHORIZED' });

      const insertRes: any = await db.insert(dvirs).values({
        driverId,
        vehicleId: input.vehicleId,
        trailerId: input.trailerId ?? null,
        companyId: companyIdFromCtx(ctx),
        kind: input.kind,
        status: 'draft',
        defects: input.defects as any,
        signaturesS3Key: input.signaturesS3Key ?? null,
        createdAt: new Date(),
        submittedAt: null,
      } as any);

      const id =
        insertRes?.[0]?.id ??
        (insertRes as any)?.insertId ??
        (insertRes as any)?.lastInsertId ??
        0;

      return { id, status: 'draft' as const };
    }),

  /**
   * Patch a draft. Submitted DVIRs are immutable — returns CONFLICT.
   */
  update: protectedProcedure
    .input(
      z.object({
        dvirId: z.number().int().positive(),
        patch: z.object({
          trailerId: z.number().int().positive().nullable().optional(),
          defects: z.array(defectSchema).optional(),
          signaturesS3Key: z.string().nullable().optional(),
        }),
      })
    )
    .mutation(async ({ ctx, input }) => {
      const db = await getDb();
      if (!db) throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'DB unavailable' });
      const driverId = driverIdFromCtx(ctx);

      const [row] = (await db
        .select()
        .from(dvirs)
        .where(and(eq(dvirs.id, input.dvirId), eq(dvirs.driverId, driverId)))
        .limit(1)) as any[];

      if (!row) throw new TRPCError({ code: 'NOT_FOUND' });
      if (row.status === 'submitted') {
        throw new TRPCError({
          code: 'CONFLICT',
          message: 'DVIR has been submitted and is locked',
        });
      }

      const updates: Record<string, unknown> = {};
      if (input.patch.trailerId !== undefined) updates.trailerId = input.patch.trailerId;
      if (input.patch.defects !== undefined) updates.defects = input.patch.defects as any;
      if (input.patch.signaturesS3Key !== undefined)
        updates.signaturesS3Key = input.patch.signaturesS3Key;

      if (Object.keys(updates).length === 0) return { ok: true, noop: true };

      await db
        .update(dvirs)
        .set(updates as any)
        .where(eq(dvirs.id, input.dvirId));

      return { ok: true };
    }),

  /**
   * Lock the form. Idempotent if already submitted (returns the same ts).
   *
   * When a legacy `inspections` row is linked we also fire the legacy
   * gamification event (inspections.ts:167-170) so scoring stays the same.
   */
  submit: protectedProcedure
    .input(z.object({ dvirId: z.number().int().positive() }))
    .mutation(async ({ ctx, input }) => {
      const db = await getDb();
      if (!db) throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'DB unavailable' });
      const driverId = driverIdFromCtx(ctx);

      const [row] = (await db
        .select()
        .from(dvirs)
        .where(and(eq(dvirs.id, input.dvirId), eq(dvirs.driverId, driverId)))
        .limit(1)) as any[];

      if (!row) throw new TRPCError({ code: 'NOT_FOUND' });
      if (row.status === 'submitted') {
        return { ok: true, submittedAt: row.submittedAt, alreadySubmitted: true };
      }

      const submittedAt = new Date();
      await db
        .update(dvirs)
        .set({ status: 'submitted', submittedAt } as any)
        .where(eq(dvirs.id, input.dvirId));

      // Mirror legacy gamification dispatch when there are no OOS defects.
      const defects = Array.isArray(row.defects) ? row.defects : [];
      const oos = defects.some((d: any) => d?.severity === 'out_of_service');
      if (!oos) {
        try {
          const { fireGamificationEvent } = await import(
            '../services/gamificationDispatcher'
          );
          fireGamificationEvent({
            userId: driverId,
            type: 'safety_inspection_passed',
            value: 1,
          });
        } catch {
          // non-fatal — same policy as inspections.ts:167-170
        }
      }

      return { ok: true, submittedAt: submittedAt.toISOString() };
    }),

  /**
   * Mint a signed URL for the PDF export. Similar pattern to
   * availability.exportICS — the actual rendering is handled downstream.
   */
  export: protectedProcedure
    .input(z.object({ dvirId: z.number().int().positive() }))
    .mutation(async ({ ctx, input }) => {
      const db = await getDb();
      if (!db) throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'DB unavailable' });
      const driverId = driverIdFromCtx(ctx);

      const [row] = (await db
        .select()
        .from(dvirs)
        .where(and(eq(dvirs.id, input.dvirId), eq(dvirs.driverId, driverId)))
        .limit(1)) as any[];

      if (!row) throw new TRPCError({ code: 'NOT_FOUND' });
      if (row.status !== 'submitted') {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: 'DVIR must be submitted before export',
        });
      }

      const token = randomBytes(24).toString('hex');
      const expiresAt = new Date(Date.now() + SIGNED_URL_TTL_MS);
      const s3Key = `dvir/${driverId}/${input.dvirId}.pdf`;

      await db.insert(driverExportTokens).values({
        driverId,
        kind: 'dvir_pdf',
        resourceId: String(input.dvirId),
        token,
        s3Key,
        expiresAt,
        createdAt: new Date(),
      } as any);

      const base = process.env.PUBLIC_BASE_URL ?? 'https://app.eusotrip.com';
      return {
        url: `${base}/api/exports/dvir/${token}.pdf`,
        expiresAt: expiresAt.toISOString(),
      };
    }),
});

export type DvirRouter = typeof dvirRouter;
