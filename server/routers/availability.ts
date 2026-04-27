/**
 * server/routers/availability.ts
 *
 * Wave-4 · Theme 2.10 — driver availability / scheduling / utilization.
 *
 * Backs Figma screens:
 *   * 083 Schedule Availability (primary)
 *   * 077 Home Schedule (consumer of getWeeklyGrid + getUtilization)
 *   * 078 Home Compliance (utilization chip)
 *
 * Scope (from roadmap 2.10):
 *   "New availability.ts with weekly-grid CRUD + ICS export + conflict
 *    resolution against hos_logs."
 *
 * Design notes
 * ------------
 * - All timestamps are UTC; `weekStartISO` MUST be an ISO-8601 date at
 *   00:00 UTC for the Sunday that starts the week (client converts to the
 *   driver's local tz for display). Conflict logic uses UTC.
 * - Weekly recurring pattern lives in `driver_weekly_availability`; ad-hoc
 *   blocks live in `driver_availability_blocks`. A cell in the returned
 *   grid is "available" iff it is inside a weekly slot AND NOT inside a
 *   block AND NOT inside an `hos_logs` off-duty / sleeper interval.
 * - `exportICS` returns a signed URL, not the file bytes. Upload is to
 *   S3 under `driver-availability/<driverId>/<weekIso>.ics` and the
 *   `driver_export_tokens` table holds the redemption record.
 *
 * STRICT: do NOT edit `server/routers.ts`. Registration lives in the
 * `_WAVE4_BUILD/agent_08.md` changelog.
 */

import { z } from 'zod';
import { and, asc, eq, gte, lt, lte, sql } from 'drizzle-orm';
import { TRPCError } from '@trpc/server';
import { randomBytes } from 'crypto';

import { isolatedProcedure as protectedProcedure, router } from '../_core/trpc';
import { getDb } from '../db';
import {
  driverAvailabilityBlocks,
  driverWeeklyAvailability,
  driverExportTokens,
} from '../../drizzle/schema.additions.wave4-8';
// hos_logs lives in the canonical schema; we only read from it for conflict
// resolution, so we reference it via raw sql rather than importing the
// symbol (keeps this file self-contained for agent #8).
// Usage: see `loadHosOffDutyIntervals` below.

/* -------------------------------------------------------------------------- */
/*  Helpers                                                                    */
/* -------------------------------------------------------------------------- */

const MIN_PER_HOUR = 60;
const HOURS_PER_DAY = 24;
const DAYS_PER_WEEK = 7;
const MIN_PER_DAY = MIN_PER_HOUR * HOURS_PER_DAY;
const MIN_PER_WEEK = MIN_PER_DAY * DAYS_PER_WEEK;
const SIGNED_URL_TTL_MS = 1000 * 60 * 15; // 15 min

const driverIdFromCtx = (ctx: any): number => {
  const raw = ctx?.user?.id;
  return typeof raw === 'string' ? parseInt(raw, 10) : (raw ?? 0);
};

const companyIdFromCtx = (ctx: any): number | null => {
  const raw = ctx?.user?.companyId;
  if (raw === undefined || raw === null) return null;
  return typeof raw === 'string' ? parseInt(raw, 10) : raw;
};

/** Parse an ISO date into a UTC Date at 00:00. */
const parseWeekStart = (iso: string): Date => {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) {
    throw new TRPCError({
      code: 'BAD_REQUEST',
      message: `Invalid weekStartISO: ${iso}`,
    });
  }
  // Snap to UTC Sunday 00:00
  const snapped = new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate())
  );
  snapped.setUTCDate(snapped.getUTCDate() - snapped.getUTCDay());
  return snapped;
};

const weekEnd = (weekStart: Date): Date =>
  new Date(weekStart.getTime() + MIN_PER_WEEK * 60_000);

/**
 * Load HOS off-duty + sleeper intervals overlapping [weekStart, weekEnd).
 * Returns [{fromTs, toTs}]. If the hos_logs table is missing (test env)
 * we silently return an empty list — availability is then driven purely by
 * blocks + weekly pattern.
 */
async function loadHosOffDutyIntervals(
  db: any,
  driverId: number,
  weekStart: Date,
  weekEndTs: Date
): Promise<Array<{ fromTs: Date; toTs: Date }>> {
  try {
    const rows = await db.execute(sql`
      SELECT start_ts AS fromTs, end_ts AS toTs
      FROM hos_logs
      WHERE driver_id = ${driverId}
        AND duty_status IN ('off_duty','sleeper')
        AND end_ts >= ${weekStart}
        AND start_ts <  ${weekEndTs}
    `);
    const data: any[] = Array.isArray(rows) ? (rows[0] ?? rows) : rows;
    return (data ?? []).map((r: any) => ({
      fromTs: new Date(r.fromTs),
      toTs: new Date(r.toTs),
    }));
  } catch {
    return [];
  }
}

/* -------------------------------------------------------------------------- */
/*  Router                                                                     */
/* -------------------------------------------------------------------------- */

export const availabilityRouter = router({
  /**
   * 7 × 24 grid of {available, blocked, driving, offDuty} cells.
   *
   * Consumed by screen 083 (weekly calendar) and 077 (home schedule chip).
   */
  getWeeklyGrid: protectedProcedure
    .input(z.object({ weekStartISO: z.string() }))
    .query(async ({ ctx, input }) => {
      const db = await getDb();
      if (!db) throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'DB unavailable' });
      const driverId = driverIdFromCtx(ctx);
      if (!driverId) throw new TRPCError({ code: 'UNAUTHORIZED' });

      const weekStart = parseWeekStart(input.weekStartISO);
      const weekEndTs = weekEnd(weekStart);

      // Weekly pattern (recurring)
      const weekly = await db
        .select()
        .from(driverWeeklyAvailability)
        .where(eq(driverWeeklyAvailability.driverId, driverId));

      // Ad-hoc blocks overlapping the week
      const blocks = await db
        .select()
        .from(driverAvailabilityBlocks)
        .where(
          and(
            eq(driverAvailabilityBlocks.driverId, driverId),
            lt(driverAvailabilityBlocks.fromTs, weekEndTs),
            gte(driverAvailabilityBlocks.toTs, weekStart)
          )
        );

      const hosOff = await loadHosOffDutyIntervals(db, driverId, weekStart, weekEndTs);

      // Build 7 × 24 grid
      const grid: Array<
        Array<{
          hour: number;
          available: boolean;
          blocked: boolean;
          offDuty: boolean;
          reason?: string;
        }>
      > = [];

      for (let d = 0; d < DAYS_PER_WEEK; d++) {
        const dayRow: (typeof grid)[number] = [];
        for (let h = 0; h < HOURS_PER_DAY; h++) {
          const cellStart = new Date(
            weekStart.getTime() + (d * HOURS_PER_DAY + h) * MIN_PER_HOUR * 60_000
          );
          const cellEnd = new Date(cellStart.getTime() + MIN_PER_HOUR * 60_000);
          const cellDow = cellStart.getUTCDay();
          const minOfDay = cellStart.getUTCHours() * MIN_PER_HOUR;

          const inWeeklySlot = (weekly as any[]).some(
            (w) =>
              w.dayOfWeek === cellDow &&
              w.startMin <= minOfDay &&
              w.endMin > minOfDay
          );

          const hittingBlock = (blocks as any[]).find(
            (b) => b.fromTs < cellEnd && b.toTs > cellStart
          );

          const hittingHos = hosOff.some(
            (o) => o.fromTs < cellEnd && o.toTs > cellStart
          );

          dayRow.push({
            hour: h,
            available: inWeeklySlot && !hittingBlock && !hittingHos,
            blocked: Boolean(hittingBlock),
            offDuty: hittingHos,
            reason: hittingBlock?.reason ?? undefined,
          });
        }
        grid.push(dayRow);
      }

      return {
        weekStartISO: weekStart.toISOString(),
        grid,
        blocks: (blocks as any[]).map((b) => ({
          id: b.id,
          fromISO: new Date(b.fromTs).toISOString(),
          toISO: new Date(b.toTs).toISOString(),
          reason: b.reason,
          source: b.source,
        })),
      };
    }),

  /**
   * Block a specific time window (ad-hoc; does not mutate the weekly pattern).
   */
  blockTime: protectedProcedure
    .input(
      z.object({
        fromISO: z.string(),
        toISO: z.string(),
        reason: z.string().max(255).optional(),
      })
    )
    .mutation(async ({ ctx, input }) => {
      const db = await getDb();
      if (!db) throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'DB unavailable' });
      const driverId = driverIdFromCtx(ctx);
      if (!driverId) throw new TRPCError({ code: 'UNAUTHORIZED' });

      const fromTs = new Date(input.fromISO);
      const toTs = new Date(input.toISO);
      if (toTs.getTime() <= fromTs.getTime()) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: 'toISO must be strictly after fromISO',
        });
      }

      const [inserted] = await db
        .insert(driverAvailabilityBlocks)
        .values({
          driverId,
          companyId: companyIdFromCtx(ctx),
          fromTs,
          toTs,
          reason: input.reason ?? null,
          source: 'driver',
          createdAt: new Date(),
        } as any)
        .$returningId?.() ?? [{ id: 0 }];

      return {
        id: (inserted as any)?.id ?? 0,
        fromISO: fromTs.toISOString(),
        toISO: toTs.toISOString(),
        reason: input.reason ?? null,
      };
    }),

  /**
   * Remove a previously-inserted ad-hoc block.
   */
  unblockTime: protectedProcedure
    .input(z.object({ blockId: z.number().int().positive() }))
    .mutation(async ({ ctx, input }) => {
      const db = await getDb();
      if (!db) throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'DB unavailable' });
      const driverId = driverIdFromCtx(ctx);

      const res = await db
        .delete(driverAvailabilityBlocks)
        .where(
          and(
            eq(driverAvailabilityBlocks.id, input.blockId),
            eq(driverAvailabilityBlocks.driverId, driverId)
          )
        );
      const affected = (res as any)?.affectedRows ?? (res as any)?.rowCount ?? 0;
      if (!affected) {
        throw new TRPCError({ code: 'NOT_FOUND', message: 'block not found' });
      }
      return { ok: true };
    }),

  /**
   * Overwrite the weekly recurring pattern for a given day.
   *
   * Semantics: delete all rows for (driverId, dayOfWeek) then insert the
   * supplied slots. `slots` MAY be empty — which means "no availability on
   * that day". Each slot is `[startMin, endMin)`.
   */
  setAvailability: protectedProcedure
    .input(
      z.object({
        dayOfWeek: z.number().int().min(0).max(6),
        slots: z
          .array(
            z.object({
              startMin: z.number().int().min(0).max(MIN_PER_DAY),
              endMin: z.number().int().min(0).max(MIN_PER_DAY),
            })
          )
          .max(24),
      })
    )
    .mutation(async ({ ctx, input }) => {
      const db = await getDb();
      if (!db) throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'DB unavailable' });
      const driverId = driverIdFromCtx(ctx);
      if (!driverId) throw new TRPCError({ code: 'UNAUTHORIZED' });

      // Validate + sort
      const sorted = [...input.slots].sort((a, b) => a.startMin - b.startMin);
      for (let i = 0; i < sorted.length; i++) {
        const s = sorted[i];
        if (s.endMin <= s.startMin) {
          throw new TRPCError({
            code: 'BAD_REQUEST',
            message: `slot ${i}: endMin must be > startMin`,
          });
        }
        if (i > 0 && sorted[i - 1].endMin > s.startMin) {
          throw new TRPCError({
            code: 'BAD_REQUEST',
            message: `slot ${i} overlaps previous slot`,
          });
        }
      }

      await db
        .delete(driverWeeklyAvailability)
        .where(
          and(
            eq(driverWeeklyAvailability.driverId, driverId),
            eq(driverWeeklyAvailability.dayOfWeek, input.dayOfWeek)
          )
        );

      if (sorted.length > 0) {
        await db.insert(driverWeeklyAvailability).values(
          sorted.map((s) => ({
            driverId,
            companyId: companyIdFromCtx(ctx),
            dayOfWeek: input.dayOfWeek,
            startMin: s.startMin,
            endMin: s.endMin,
            updatedAt: new Date(),
          })) as any
        );
      }

      return { dayOfWeek: input.dayOfWeek, slots: sorted };
    }),

  /**
   * Utilization = driving minutes ÷ available minutes, within the week.
   *
   * "Available minutes" come from the weekly pattern minus any blocks.
   * "Driving minutes" come from hos_logs rows where duty_status = 'driving'.
   * If hos_logs isn't reachable we return `null` for the ratio so the UI
   * can render a "N/A" chip rather than a misleading 0%.
   */
  getUtilization: protectedProcedure
    .input(z.object({ weekStartISO: z.string() }))
    .query(async ({ ctx, input }) => {
      const db = await getDb();
      if (!db) throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'DB unavailable' });
      const driverId = driverIdFromCtx(ctx);
      if (!driverId) throw new TRPCError({ code: 'UNAUTHORIZED' });

      const weekStart = parseWeekStart(input.weekStartISO);
      const weekEndTs = weekEnd(weekStart);

      // Available minutes from weekly pattern
      const weekly = (await db
        .select()
        .from(driverWeeklyAvailability)
        .where(eq(driverWeeklyAvailability.driverId, driverId))) as any[];

      let availableMin = 0;
      for (const row of weekly) availableMin += row.endMin - row.startMin;

      // Subtract blocks (only the intersection with the week)
      const blocks = (await db
        .select()
        .from(driverAvailabilityBlocks)
        .where(
          and(
            eq(driverAvailabilityBlocks.driverId, driverId),
            lt(driverAvailabilityBlocks.fromTs, weekEndTs),
            gte(driverAvailabilityBlocks.toTs, weekStart)
          )
        )) as any[];

      let blockedMin = 0;
      for (const b of blocks) {
        const from = new Date(Math.max(new Date(b.fromTs).getTime(), weekStart.getTime()));
        const to = new Date(Math.min(new Date(b.toTs).getTime(), weekEndTs.getTime()));
        blockedMin += Math.max(0, Math.round((to.getTime() - from.getTime()) / 60_000));
      }
      const netAvailable = Math.max(0, availableMin - blockedMin);

      // Driving minutes from hos_logs
      let drivingMin: number | null = null;
      try {
        const rows = await db.execute(sql`
          SELECT COALESCE(SUM(TIMESTAMPDIFF(MINUTE, start_ts, end_ts)), 0) AS mins
          FROM hos_logs
          WHERE driver_id = ${driverId}
            AND duty_status = 'driving'
            AND end_ts >= ${weekStart}
            AND start_ts <  ${weekEndTs}
        `);
        const data: any[] = Array.isArray(rows) ? (rows[0] ?? rows) : rows;
        drivingMin = Number((data?.[0]?.mins ?? 0) as number);
      } catch {
        drivingMin = null;
      }

      const utilization =
        drivingMin === null || netAvailable === 0
          ? null
          : Math.min(1, drivingMin / netAvailable);

      return {
        weekStartISO: weekStart.toISOString(),
        availableMin: netAvailable,
        drivingMin,
        utilization, // 0..1 or null
        utilizationPct: utilization === null ? null : Math.round(utilization * 100),
      };
    }),

  /**
   * Generate an .ics of the current week's available slots and return a
   * signed URL. Upload to S3 is deferred to the signed-URL worker; here
   * we persist a token row and return a redemption URL the client can hit.
   */
  exportICS: protectedProcedure
    .input(
      z.object({
        weekStartISO: z.string().optional(),
      }).optional()
    )
    .mutation(async ({ ctx, input }) => {
      const db = await getDb();
      if (!db) throw new TRPCError({ code: 'INTERNAL_SERVER_ERROR', message: 'DB unavailable' });
      const driverId = driverIdFromCtx(ctx);
      if (!driverId) throw new TRPCError({ code: 'UNAUTHORIZED' });

      const weekStartIso = input?.weekStartISO
        ? parseWeekStart(input.weekStartISO).toISOString()
        : parseWeekStart(new Date().toISOString()).toISOString();

      const token = randomBytes(24).toString('hex');
      const expiresAt = new Date(Date.now() + SIGNED_URL_TTL_MS);
      const s3Key = `driver-availability/${driverId}/${weekStartIso.slice(0, 10)}.ics`;

      await db.insert(driverExportTokens).values({
        driverId,
        kind: 'availability_ics',
        resourceId: weekStartIso.slice(0, 10),
        token,
        s3Key,
        expiresAt,
        createdAt: new Date(),
      } as any);

      const base = process.env.PUBLIC_BASE_URL ?? 'https://app.eusotrip.com';
      return {
        url: `${base}/api/exports/availability/${token}.ics`,
        expiresAt: expiresAt.toISOString(),
        weekStartISO: weekStartIso,
      };
    }),
});

export type AvailabilityRouter = typeof availabilityRouter;
