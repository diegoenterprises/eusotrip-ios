/**
 * Wave-4 · Theme 2.8 · NEW router — `missions`.
 *
 * Path in the web repo: `server/routers/missions.ts`.
 * Mount as `missions: missionsRouter` in `server/routers.ts`. See
 * `_WAVE4_BUILD/agent_09.md` §Changelog for the exact edit.
 *
 * Driver-side UI entry points backed by this router:
 *   - 067 The Haul Mission — mission card, objectives, reward preview.
 *   - 068 The Haul Leaderboard — "Claim" / "Redeem" CTAs tying into wallet.
 *
 * Split rationale. `server/routers/gamification.ts` and
 * `server/routers/advancedGamification.ts` remain unmodified per the brief.
 * The sub-set of mission lifecycle APIs that needed cash-reward + HOLD
 * + Verifying semantics is carved out here so it can evolve separately.
 * When the catalog `missions` table is ready to become per-driver instances,
 * delete the duplicate logic inside gamification.ts and point the UI at
 * `missions.*` — see agent_09.md changelog item (D).
 *
 * Authorization model. All procedures require a signed-in driver (isolated
 * procedure = requireUser + tenant isolation + audit). A driver can only
 * see or mutate their OWN missions.
 */

import { z } from 'zod';
import { and, desc, eq, inArray } from 'drizzle-orm';
import { TRPCError } from '@trpc/server';
import { randomUUID } from 'node:crypto';

import {
  isolatedProcedure as protectedProcedure,
  router,
} from '../_core/trpc';
import { logger } from '../_core/logger';
import { getDb } from '../db';
import {
  driverMissions,
  MISSION_STATUSES,
  type MissionStatus,
  type DriverMission,
} from '../../drizzle/schema.additions.wave4-9';
import { badges, userBadges, wallets, walletTransactions } from '../../drizzle/schema';

/* -------------------------------------------------------------------------- */
/*  Zod input schemas                                                          */
/* -------------------------------------------------------------------------- */

const MissionIdSchema = z.string().uuid();

/** listForMe status filter is a proper subset of MISSION_STATUSES. */
const ListStatusSchema = z.enum(['active', 'verifying', 'completed']);

/* -------------------------------------------------------------------------- */
/*  Helpers                                                                    */
/* -------------------------------------------------------------------------- */

/**
 * Fetch a mission for the caller + sanity-check ownership.
 * Throws NOT_FOUND if missing OR owned by a different driver (avoid leaking
 * existence of other drivers' mission ids).
 */
async function loadMyMission(
  db: NonNullable<Awaited<ReturnType<typeof getDb>>>,
  driverId: number,
  missionId: string
): Promise<DriverMission> {
  const [row] = await db
    .select()
    .from(driverMissions)
    .where(
      and(
        eq(driverMissions.id, missionId),
        eq(driverMissions.driverId, driverId)
      )
    )
    .limit(1);

  if (!row) {
    throw new TRPCError({ code: 'NOT_FOUND', message: 'mission not found' });
  }
  return row;
}

/**
 * Ensure the driver has a wallet row; mirrors `ensureWallet` in
 * server/routers/wallet.ts (kept local to avoid importing that router's
 * private helper and to skip Stripe side-effects for reward payouts).
 */
async function ensureWallet(
  db: NonNullable<Awaited<ReturnType<typeof getDb>>>,
  userId: number
) {
  let [wallet] = await db
    .select()
    .from(wallets)
    .where(eq(wallets.userId, userId))
    .limit(1);

  if (!wallet) {
    await db.insert(wallets).values({
      userId,
      availableBalance: '0',
      pendingBalance: '0',
      reservedBalance: '0',
      currency: 'USD',
    });
    [wallet] = await db
      .select()
      .from(wallets)
      .where(eq(wallets.userId, userId))
      .limit(1);
  }
  if (!wallet) {
    throw new TRPCError({
      code: 'INTERNAL_SERVER_ERROR',
      message: 'unable to provision wallet for reward payout',
    });
  }
  return wallet;
}

/**
 * Transition guard for the mission FSM.
 *
 *   active ─claim()→ verifying
 *   verifying ─(system/ops)→ verified
 *   verified ─redeem()→ completed
 */
function assertLegalTransition(
  from: MissionStatus,
  to: MissionStatus
): void {
  const LEGAL: Record<MissionStatus, MissionStatus[]> = {
    active: ['verifying', 'cancelled', 'expired'],
    verifying: ['verified', 'expired'],
    verified: ['completed', 'expired'],
    completed: [],
    expired: [],
    cancelled: [],
  };
  if (!LEGAL[from]?.includes(to)) {
    throw new TRPCError({
      code: 'BAD_REQUEST',
      message: `illegal mission transition ${from} → ${to}`,
    });
  }
}

/* -------------------------------------------------------------------------- */
/*  Router                                                                     */
/* -------------------------------------------------------------------------- */

export const missionsRouter = router({
  /**
   * listForMe — every mission the caller owns, filtered by the UI pill.
   * The UI (067 The Haul Mission) only needs active / verifying / completed;
   * other states (verified, expired, cancelled) are surfaced via getById.
   */
  listForMe: protectedProcedure
    .input(
      z
        .object({
          status: ListStatusSchema.optional(),
        })
        .optional()
    )
    .query(async ({ ctx, input }) => {
      const db = await getDb();
      const driverId = Number(ctx.user?.id);
      if (!db || !driverId) return { missions: [] };

      // When filter = completed, include legacy `verified` as well because
      // the UI groups verified + completed under "COMPLETED" until redeem.
      const statusFilter: MissionStatus[] = !input?.status
        ? ['active', 'verifying', 'verified', 'completed']
        : input.status === 'completed'
          ? ['verified', 'completed']
          : [input.status];

      const rows = await db
        .select()
        .from(driverMissions)
        .where(
          and(
            eq(driverMissions.driverId, driverId),
            inArray(driverMissions.status, statusFilter)
          )
        )
        .orderBy(desc(driverMissions.startedAt));

      return { missions: rows };
    }),

  /**
   * getById — full detail of one mission (objectives, reward preview).
   */
  getById: protectedProcedure
    .input(z.object({ missionId: MissionIdSchema }))
    .query(async ({ ctx, input }) => {
      const db = await getDb();
      const driverId = Number(ctx.user?.id);
      if (!db || !driverId) {
        throw new TRPCError({ code: 'UNAUTHORIZED' });
      }

      const mission = await loadMyMission(db, driverId, input.missionId);

      // Enrich with badge info if this mission pays a badge.
      let badge: typeof badges.$inferSelect | null = null;
      if (mission.badgeId) {
        const [row] = await db
          .select()
          .from(badges)
          .where(eq(badges.id, mission.badgeId))
          .limit(1);
        badge = row ?? null;
      }

      return { mission, badge };
    }),

  /**
   * claim — driver asserts objectives are done → mission moves to 'verifying'.
   * Verification (system/ops) flips it to 'verified' asynchronously; the
   * redeem() step dispenses the cash reward (see below).
   */
  claim: protectedProcedure
    .input(z.object({ missionId: MissionIdSchema }))
    .mutation(async ({ ctx, input }) => {
      const db = await getDb();
      const driverId = Number(ctx.user?.id);
      if (!db || !driverId) {
        throw new TRPCError({ code: 'UNAUTHORIZED' });
      }

      const mission = await loadMyMission(db, driverId, input.missionId);
      assertLegalTransition(mission.status, 'verifying');

      const now = new Date();
      await db
        .update(driverMissions)
        .set({ status: 'verifying', updatedAt: now })
        .where(eq(driverMissions.id, mission.id));

      logger.info(
        `[missions.claim] driver=${driverId} mission=${mission.id} -> verifying`
      );
      return { ok: true as const, status: 'verifying' as const };
    }),

  /**
   * redeem — transitions verified → completed AND dispenses the cash reward
   * via the wallet in the same transaction. No-op on non-cash missions
   * (badge-only rewards are awarded eagerly by the verifier; redeem() still
   * closes the row to 'completed' for those).
   */
  redeem: protectedProcedure
    .input(z.object({ missionId: MissionIdSchema }))
    .mutation(async ({ ctx, input }) => {
      const db = await getDb();
      const driverId = Number(ctx.user?.id);
      if (!db || !driverId) {
        throw new TRPCError({ code: 'UNAUTHORIZED' });
      }

      const mission = await loadMyMission(db, driverId, input.missionId);
      assertLegalTransition(mission.status, 'completed');

      if (mission.status !== 'verified') {
        // Defence-in-depth: assertLegalTransition already enforces this,
        // but make the error message precise.
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: `mission must be verified before redeem (current: ${mission.status})`,
        });
      }

      const now = new Date();
      const cash = mission.cashRewardCents ?? 0;

      // Transaction: close mission + (optional) wallet credit + badge grant.
      return await db.transaction(async (tx) => {
        // 1 · close the mission row
        await tx
          .update(driverMissions)
          .set({
            status: 'completed',
            completedAt: now,
            updatedAt: now,
          })
          .where(eq(driverMissions.id, mission.id));

        // 2 · cash payout (if any)
        let walletTxId: number | null = null;
        if (cash > 0) {
          const wallet = await ensureWallet(tx as any, driverId);
          const cents = cash;
          const dollars = (cents / 100).toFixed(2);

          const [inserted] = await (tx as any)
            .insert(walletTransactions)
            .values({
              walletId: wallet.id,
              type: 'bonus',
              amount: dollars,
              fee: '0',
              netAmount: dollars,
              currency: 'USD',
              status: 'completed',
              description: `Mission reward — ${mission.title}`,
              metadata: {
                source: 'missions.redeem',
                missionId: mission.id,
                kind: mission.kind,
              },
              completedAt: now,
            })
            .$returningId?.() ?? [];
          walletTxId = inserted?.id ?? null;

          // bump wallet balance (available + totalReceived)
          await (tx as any)
            .update(wallets)
            .set({
              availableBalance: String(
                (parseFloat(wallet.availableBalance as any) || 0) +
                  parseFloat(dollars)
              ),
              totalReceived: String(
                (parseFloat(wallet.totalReceived as any) || 0) +
                  parseFloat(dollars)
              ),
            })
            .where(eq(wallets.id, wallet.id));
        }

        // 3 · badge grant (if any) — idempotent on (userId, badgeId).
        if (mission.badgeId) {
          try {
            await (tx as any).insert(userBadges).values({
              userId: driverId,
              badgeId: mission.badgeId,
              earnedAt: now,
              isDisplayed: true,
              metadata: { missionId: mission.id },
            });
          } catch (e: any) {
            // unique-index race → badge already earned; swallow.
            if (!/duplicate/i.test(String(e?.message))) throw e;
          }
        }

        logger.info(
          `[missions.redeem] driver=${driverId} mission=${mission.id} cash_cents=${cash} walletTxId=${walletTxId}`
        );

        return {
          ok: true as const,
          status: 'completed' as const,
          cashPaidCents: cash,
          walletTxId,
          badgeAwardedId: mission.badgeId ?? null,
        };
      });
    }),
});

export type MissionsRouter = typeof missionsRouter;
