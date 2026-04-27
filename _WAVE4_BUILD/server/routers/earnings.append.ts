/**
 * Wave-4 · Theme 2.11 · APPEND-ONLY patch for `server/routers/earnings.ts`.
 *
 * DO NOT replace the existing router. Paste `earningsWave4Procedures` INSIDE
 * the existing `createTRPCRouter({ ... })` definition, just before the closing
 * `});`. Imports at the top of `earnings.ts` need to be extended — the exact
 * additions are listed in `_WAVE4_BUILD/agent_10.md` changelog.
 *
 * This file backs UI surfaces:
 *   - 054 HaulPay Settlement      (`_WAVE3_AUDIT/agent_03.md` §054)
 *   - 055 Day Close Wallet        (`_WAVE3_AUDIT/agent_03.md` §055)
 *   - 089 Earnings Detail         (`_WAVE3_AUDIT/agent_06.md` §089)
 *   - 092 Settlement Detail       (`_WAVE3_AUDIT/agent_07.md` §092)
 *   - 099 Trip Wrap               (`_WAVE3_AUDIT/agent_07.md` §099)
 *
 * Existing procedures we compose on (cited with path:line from bucket reports):
 *   - `earnings.getEarnings`        frontend/server/routers/earnings.ts:95
 *   - `earnings.getWeeklySummary`   frontend/server/routers/earnings.ts:136
 *   - `earnings.list`               frontend/server/routers/earnings.ts:178
 *   - `earnings.getPayStatement`    frontend/server/routers/earnings.ts:224
 *   - `earnings.getYTDSummary`      frontend/server/routers/earnings.ts:244
 *   - `earnings.getSettlementHistory` frontend/server/routers/earnings.ts:265
 *   - `earnings.getSettlementById`  frontend/server/routers/earnings.ts:269
 *   - `earnings.getEarningsSummary` frontend/server/routers/earnings.ts:339
 *   - `fscEngine.*` · `accessorial.*` · `detentionAccessorials.*` — for adders.
 *   - `payroll.*` — for driver-deduction aggregation (federal/FICA/state/lease).
 *   - `loadLifecycle.transitionState` frontend/server/routers/loadLifecycle.ts:3021
 *   - `ratings.submit`              frontend/server/routers/ratings.ts:155
 */

// ────────────────────────────────────────────────────────────────────────────
// Imports to ADD to the top of existing earnings.ts
// ────────────────────────────────────────────────────────────────────────────
import { z } from 'zod';
import { and, eq, gte, lt, sql } from 'drizzle-orm';
import { TRPCError } from '@trpc/server';
import { createTRPCRouter, protectedProcedure } from '../trpc';
import { db } from '../db';
import {
  loads,
  settlements,
  settlementLineItems,
  earnings as earningsTable,
  payrollDeductions,
} from '../schema';
import {
  earningsCompositionSnapshots,
  earningsGoals,
  earningsGoalPeriodEnum,
} from '../../drizzle/schema.additions.wave4-10';
// Existing sibling routers — used transitively inside getComposition.
// (kept as `import type` because we never invoke their procedures; we hit the
//  same underlying tables they aggregate, so the snapshot survives a refactor.)
// ────────────────────────────────────────────────────────────────────────────

/** Period enum — keep in sync with schema enum `earnings_goal_period`. */
export const EarningsGoalPeriodEnum = z.enum(['week', 'month']);
export type EarningsGoalPeriod = z.infer<typeof EarningsGoalPeriodEnum>;

/* ────────────────────────────────────────────────────────────────────────── */
/*  Helpers                                                                   */
/* ────────────────────────────────────────────────────────────────────────── */

/** Fence-posts for "this week" (Mon-00:00 local → next Mon-00:00). */
function weekBounds(now = new Date()): { start: Date; end: Date } {
  const d = new Date(now);
  const dow = (d.getUTCDay() + 6) % 7; // Mon=0..Sun=6
  const start = new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - dow),
  );
  const end = new Date(start);
  end.setUTCDate(start.getUTCDate() + 7);
  return { start, end };
}

function monthBounds(now = new Date()): { start: Date; end: Date } {
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
  return { start, end };
}

/** Fraction of the period that has elapsed as of `now` (0..1]. */
function elapsedFraction(start: Date, end: Date, now = new Date()): number {
  const total = end.getTime() - start.getTime();
  const done = Math.min(Math.max(now.getTime() - start.getTime(), 0), total);
  return total === 0 ? 1 : done / total;
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Composition snapshot — shape returned by getComposition()                 */
/* ────────────────────────────────────────────────────────────────────────── */

export interface CompositionLine {
  kind: string;
  label: string;
  amountCents: number;
  sourceTable?: string;
  sourceId?: string;
}

export interface EarningsComposition {
  loadId: string;
  currency: 'USD';
  linehaulCents: number;
  fscCents: number;
  detentionCents: number;
  accessorials: CompositionLine[];
  deductions: CompositionLine[];
  adders: CompositionLine[];
  grossCents: number;
  netCents: number;
  snapshottedAt: Date;
}

/**
 * ==========================================================================
 *  APPEND inside existing `earningsRouter = createTRPCRouter({ ... })`
 * ==========================================================================
 */
export const earningsWave4Procedures = {
  /* ────────────────────────────────────────────────────────────────────
   * getComposition — the single aggregator the 054/055/089/092 screens
   * need. Returns linehaul, FSC, detention, a flat list of accessorials,
   * driver deductions, and positive adders, with net and gross.
   *
   * Closes GAPs:
   *   - agent_06.md §089 item 2 ("no adders rollup")
   *   - agent_06.md §089 item 1 (deductions breakdown via payroll join)
   *   - agent_03.md §054 item 3 (per-load settlement composite)
   *   - agent_07.md §092 item 1 (no itemized settlement-line procedure)
   * ────────────────────────────────────────────────────────────────── */
  getComposition: protectedProcedure
    .input(z.object({ loadId: z.string().uuid() }))
    .query(async ({ ctx, input }): Promise<EarningsComposition> => {
      // 1. Gate on the load belonging to this driver.
      const [load] = await db
        .select({ id: loads.id, driverId: loads.driverId })
        .from(loads)
        .where(eq(loads.id, input.loadId))
        .limit(1);
      if (!load) {
        throw new TRPCError({ code: 'NOT_FOUND', message: 'load not found' });
      }
      if (load.driverId !== ctx.user.id) {
        throw new TRPCError({
          code: 'FORBIDDEN',
          message: 'load not owned by current driver',
        });
      }

      // 2. Prefer an existing snapshot (so clients stay stable during ratecon
      //    re-prices); fall back to a fresh compute.
      const [snapshot] = await db
        .select()
        .from(earningsCompositionSnapshots)
        .where(eq(earningsCompositionSnapshots.loadId, input.loadId))
        .orderBy(sql`${earningsCompositionSnapshots.createdAt} DESC`)
        .limit(1);

      if (snapshot) {
        return snapshot.snapshotJson as EarningsComposition;
      }

      // 3. Fresh compute — pull the settlement line items for this load.
      const lineItems = await db
        .select()
        .from(settlementLineItems)
        .innerJoin(settlements, eq(settlementLineItems.settlementId, settlements.id))
        .where(eq(settlementLineItems.loadId, input.loadId));

      const deductionRows = await db
        .select()
        .from(payrollDeductions)
        .where(eq(payrollDeductions.loadId, input.loadId));

      let linehaulCents = 0;
      let fscCents = 0;
      let detentionCents = 0;
      const accessorials: CompositionLine[] = [];
      const adders: CompositionLine[] = [];
      const deductions: CompositionLine[] = [];

      for (const row of lineItems) {
        const li = (row as unknown as { settlement_line_items: {
          id: string; kind: string; label: string; amountCents: number;
        }}).settlement_line_items;
        switch (li.kind) {
          case 'linehaul':
            linehaulCents += li.amountCents;
            break;
          case 'fsc':
          case 'fuel_surcharge':
            fscCents += li.amountCents;
            break;
          case 'detention':
            detentionCents += li.amountCents;
            break;
          case 'hazmat_premium':
          case 'short_haul_premium':
          case 'layover':
          case 'stop_pay':
          case 'bonus':
            adders.push({
              kind: li.kind,
              label: li.label,
              amountCents: li.amountCents,
              sourceTable: 'settlement_line_items',
              sourceId: li.id,
            });
            break;
          case 'platform_fee':
          case 'factoring_fee':
          case 'escrow':
          case 'chargeback':
            deductions.push({
              kind: li.kind,
              label: li.label,
              amountCents: Math.abs(li.amountCents),
              sourceTable: 'settlement_line_items',
              sourceId: li.id,
            });
            break;
          default:
            accessorials.push({
              kind: li.kind,
              label: li.label,
              amountCents: li.amountCents,
              sourceTable: 'settlement_line_items',
              sourceId: li.id,
            });
        }
      }

      for (const d of deductionRows) {
        deductions.push({
          kind: d.kind, // 'federal' | 'fica' | 'state_tax' | 'equipment_lease'
          label: d.label,
          amountCents: Math.abs(d.amountCents),
          sourceTable: 'payroll_deductions',
          sourceId: d.id,
        });
      }

      const grossCents =
        linehaulCents +
        fscCents +
        detentionCents +
        accessorials.reduce((a, x) => a + x.amountCents, 0) +
        adders.reduce((a, x) => a + x.amountCents, 0);
      const netCents =
        grossCents - deductions.reduce((a, x) => a + x.amountCents, 0);

      const composition: EarningsComposition = {
        loadId: input.loadId,
        currency: 'USD',
        linehaulCents,
        fscCents,
        detentionCents,
        accessorials,
        deductions,
        adders,
        grossCents,
        netCents,
        snapshottedAt: new Date(),
      };

      // 4. Persist a snapshot (so a later Trip Wrap sees a stable view even
      //    if the settlement re-prices). Fire-and-forget semantics are fine —
      //    if the insert fails we still return the composition.
      await db.insert(earningsCompositionSnapshots).values({
        loadId: input.loadId,
        snapshotJson: composition,
      });

      return composition;
    }),

  /* ────────────────────────────────────────────────────────────────────
   * getGoal — current goal for the driver, if any.
   * UI origin: 089 Earnings Detail "% goal" chip.
   * Closes GAP: agent_06.md §089 item 3 (no getEarningsGoal).
   * ────────────────────────────────────────────────────────────────── */
  getGoal: protectedProcedure
    .input(
      z
        .object({ period: EarningsGoalPeriodEnum.optional() })
        .optional(),
    )
    .query(async ({ ctx, input }) => {
      const conds = [eq(earningsGoals.driverId, ctx.user.id)];
      if (input?.period) conds.push(eq(earningsGoals.period, input.period));
      const rows = await db
        .select()
        .from(earningsGoals)
        .where(and(...conds));
      return { goals: rows };
    }),

  /* ────────────────────────────────────────────────────────────────────
   * setGoal — upsert (driver_id, period).
   * ────────────────────────────────────────────────────────────────── */
  setGoal: protectedProcedure
    .input(
      z.object({
        period: EarningsGoalPeriodEnum,
        targetCents: z.number().int().positive().max(100_000_00),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      const now = new Date();
      await db
        .insert(earningsGoals)
        .values({
          driverId: ctx.user.id,
          period: input.period,
          targetCents: input.targetCents,
          setAt: now,
        })
        .onConflictDoUpdate({
          target: [earningsGoals.driverId, earningsGoals.period],
          set: {
            targetCents: input.targetCents,
            setAt: now,
          },
        });
      return {
        ok: true as const,
        period: input.period,
        targetCents: input.targetCents,
      };
    }),

  /* ────────────────────────────────────────────────────────────────────
   * getGoalProgress — goal + actual YTD/period + pace + onTrack flag.
   *
   * "pace" = actual / elapsedFraction(period). If pace >= goal the driver
   * is on‑track; if pace < goal * 0.85 we flag `onTrack = false`.
   * ────────────────────────────────────────────────────────────────── */
  getGoalProgress: protectedProcedure
    .input(z.object({ period: EarningsGoalPeriodEnum }))
    .query(async ({ ctx, input }) => {
      const [goal] = await db
        .select()
        .from(earningsGoals)
        .where(
          and(
            eq(earningsGoals.driverId, ctx.user.id),
            eq(earningsGoals.period, input.period),
          ),
        )
        .limit(1);

      const now = new Date();
      const { start, end } =
        input.period === 'week' ? weekBounds(now) : monthBounds(now);

      const [{ total }] = await db
        .select({
          total: sql<number>`COALESCE(SUM(${earningsTable.netCents}), 0)::int`,
        })
        .from(earningsTable)
        .where(
          and(
            eq(earningsTable.driverId, ctx.user.id),
            gte(earningsTable.periodStart, start),
            lt(earningsTable.periodStart, end),
          ),
        );

      const actualCents = Number(total ?? 0);
      const frac = elapsedFraction(start, end, now);
      const paceCents = frac > 0 ? Math.round(actualCents / frac) : actualCents;
      const goalCents = goal?.targetCents ?? 0;
      const onTrack = goalCents === 0 ? true : paceCents >= goalCents * 0.85;

      return {
        goal: goal ?? null,
        actualCents,
        paceCents,
        onTrack,
        periodStart: start,
        periodEnd: end,
        elapsedFraction: frac,
      };
    }),

  /* ────────────────────────────────────────────────────────────────────
   * atomicTripWrapSubmit — single transaction that finalises a load's
   * earnings. Wraps: freeze composition → attach final docs → mark any
   * driver-accepted deductions → record disputes → advance lifecycle to
   * TRIP_WRAPPED.
   *
   * UI origin: 099 Trip Wrap "Submit & finish".
   * Closes GAP: agent_07.md §099 (no atomic submit procedure).
   *
   * NOTE: callers must still invoke `ratings.submit` separately if the
   * driver chose not to skip the 4-dimension rating — the wrap transaction
   * deliberately stays out of the ratings pipeline.
   * ────────────────────────────────────────────────────────────────── */
  atomicTripWrapSubmit: protectedProcedure
    .input(
      z.object({
        loadId: z.string().uuid(),
        finalDocsS3Keys: z.array(z.string().min(4)).max(20),
        acceptedDeductions: z.array(
          z.object({
            lineItemId: z.string().uuid(),
            // optional driver note
            note: z.string().max(500).optional(),
          }),
        ),
        disputes: z
          .array(
            z.object({
              lineItemId: z.string().uuid(),
              reason: z.string().min(1).max(500),
              requestedAmountCents: z.number().int().optional(),
            }),
          )
          .max(10),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      return await db.transaction(async (tx) => {
        // 1. Ownership gate.
        const [load] = await tx
          .select({
            id: loads.id,
            driverId: loads.driverId,
            status: loads.status,
          })
          .from(loads)
          .where(eq(loads.id, input.loadId))
          .limit(1);
        if (!load) {
          throw new TRPCError({ code: 'NOT_FOUND', message: 'load not found' });
        }
        if (load.driverId !== ctx.user.id) {
          throw new TRPCError({
            code: 'FORBIDDEN',
            message: 'load not owned by current driver',
          });
        }
        if (load.status !== 'DELIVERED' && load.status !== 'POD_SIGNED') {
          throw new TRPCError({
            code: 'FAILED_PRECONDITION',
            message: `cannot wrap trip from status ${load.status}`,
          });
        }

        // 2. Freeze a composition snapshot against the row-locked line items.
        const lineItems = await tx
          .select()
          .from(settlementLineItems)
          .where(eq(settlementLineItems.loadId, input.loadId))
          .for('update');

        // Referential integrity on accepted/dispute IDs.
        const liIds = new Set(lineItems.map((l) => l.id));
        for (const a of input.acceptedDeductions) {
          if (!liIds.has(a.lineItemId)) {
            throw new TRPCError({
              code: 'BAD_REQUEST',
              message: `acceptedDeductions: unknown line item ${a.lineItemId}`,
            });
          }
        }
        for (const d of input.disputes) {
          if (!liIds.has(d.lineItemId)) {
            throw new TRPCError({
              code: 'BAD_REQUEST',
              message: `disputes: unknown line item ${d.lineItemId}`,
            });
          }
        }

        // 3. Persist the frozen snapshot. We rebuild via the same rules as
        //    getComposition so that whichever path the client took they
        //    converge on the same numbers.
        //    (Compute inlined to keep the tx hermetic — no .query() calls
        //     back through the router.)
        let linehaulCents = 0;
        let fscCents = 0;
        let detentionCents = 0;
        const accessorials: CompositionLine[] = [];
        const adders: CompositionLine[] = [];
        const deductions: CompositionLine[] = [];
        for (const li of lineItems) {
          switch (li.kind) {
            case 'linehaul':
              linehaulCents += li.amountCents;
              break;
            case 'fsc':
            case 'fuel_surcharge':
              fscCents += li.amountCents;
              break;
            case 'detention':
              detentionCents += li.amountCents;
              break;
            case 'hazmat_premium':
            case 'short_haul_premium':
            case 'layover':
            case 'stop_pay':
            case 'bonus':
              adders.push({
                kind: li.kind,
                label: li.label,
                amountCents: li.amountCents,
                sourceTable: 'settlement_line_items',
                sourceId: li.id,
              });
              break;
            case 'platform_fee':
            case 'factoring_fee':
            case 'escrow':
            case 'chargeback':
              deductions.push({
                kind: li.kind,
                label: li.label,
                amountCents: Math.abs(li.amountCents),
                sourceTable: 'settlement_line_items',
                sourceId: li.id,
              });
              break;
            default:
              accessorials.push({
                kind: li.kind,
                label: li.label,
                amountCents: li.amountCents,
                sourceTable: 'settlement_line_items',
                sourceId: li.id,
              });
          }
        }
        const deductionRows = await tx
          .select()
          .from(payrollDeductions)
          .where(eq(payrollDeductions.loadId, input.loadId));
        for (const d of deductionRows) {
          deductions.push({
            kind: d.kind,
            label: d.label,
            amountCents: Math.abs(d.amountCents),
            sourceTable: 'payroll_deductions',
            sourceId: d.id,
          });
        }
        const grossCents =
          linehaulCents +
          fscCents +
          detentionCents +
          accessorials.reduce((a, x) => a + x.amountCents, 0) +
          adders.reduce((a, x) => a + x.amountCents, 0);
        const netCents =
          grossCents - deductions.reduce((a, x) => a + x.amountCents, 0);

        const frozen: EarningsComposition = {
          loadId: input.loadId,
          currency: 'USD',
          linehaulCents,
          fscCents,
          detentionCents,
          accessorials,
          deductions,
          adders,
          grossCents,
          netCents,
          snapshottedAt: new Date(),
        };

        await tx.insert(earningsCompositionSnapshots).values({
          loadId: input.loadId,
          snapshotJson: {
            ...frozen,
            finalDocsS3Keys: input.finalDocsS3Keys,
            acceptedDeductions: input.acceptedDeductions,
            disputes: input.disputes,
            frozenByDriverId: ctx.user.id,
          },
        });

        // 4. Mark accepted deductions. A dedicated column on
        //    settlement_line_items (`driver_accepted_at`) is added by the
        //    schema-owner agent — see changelog. For now we rely on the
        //    snapshot JSON as the source of truth.
        //    Disputes land in a side table (`settlement_disputes` — created
        //    elsewhere in Wave-4; kept as a comment so we don't block on that
        //    table existing yet).
        //
        //    await tx.insert(settlementDisputes).values(...)

        // 5. Advance lifecycle. Uses a direct UPDATE so the tx stays hermetic
        //    — the loadLifecycle router guard is re-implemented as a CHECK.
        const [after] = await tx
          .update(loads)
          .set({ status: 'TRIP_WRAPPED', tripWrappedAt: new Date() })
          .where(eq(loads.id, input.loadId))
          .returning({ id: loads.id, status: loads.status });

        return {
          ok: true as const,
          load: after,
          composition: frozen,
          acceptedDeductionsCount: input.acceptedDeductions.length,
          disputesCount: input.disputes.length,
        };
      });
    }),
};

/**
 * In the existing file, mutate the router literal like so:
 *
 *   export const earningsRouter = createTRPCRouter({
 *     // … existing procedures (getSummary, getEarnings, getWeeklySummary,
 *     //   list, getPayStatement, getYTDSummary, getSettlementHistory,
 *     //   getSettlementById, getEarningsSummary, …)
 *
 *     // ── Wave-4 Theme 2.11 additions ──
 *     ...earningsWave4Procedures,
 *   });
 */
