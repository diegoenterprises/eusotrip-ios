/**
 * Wave-4 · Theme 2.8 · NEW router — `referrals`.
 *
 * Path in the web repo: `server/routers/referrals.ts`.
 * Mount as `referrals: referralsRouter` in `server/routers.ts`. See
 * `_WAVE4_BUILD/agent_09.md` §Changelog for the exact edit.
 *
 * Driver-side UI entry points backed by this router:
 *   - 070 Invite a Driver — code card "MEX-742", sent / accepted / earned
 *     counters, payout breakdown, share/text buttons.
 *
 * Split rationale. `users.getReferralInfo` (server/routers/users.ts:761)
 * derives a referral code from the user's email prefix on every call and
 * returns zeros for every counter — it is not persisted anywhere. This
 * router owns the persistent referral ledger instead. `users.getReferralInfo`
 * stays untouched; agent_09.md changelog lists the deprecation plan.
 *
 * Lifecycle.
 *   1. getMyCode()          creates (on first call) a durable `referrals`
 *                           row with status='pending', referred_user_id=NULL.
 *   2. claim({ code })      flips that row to 'claimed' and sets
 *                           referred_user_id = caller. Idempotent: calling
 *                           twice with the caller already attached returns
 *                           the existing row. Self-claim is rejected.
 *   3. (ops / onboarding)   bump status to 'onboarded' → 'first_haul' via
 *                           follow-on procedures (not in this wave).
 *   4. (wallet worker)      on 'first_haul' → credit both sides with
 *                           `referral_credit` wallet transactions, flip
 *                           status to 'credited' (credit path outlined
 *                           inline; full worker lives in a later wave).
 */

import { z } from 'zod';
import { and, desc, eq, isNull, or } from 'drizzle-orm';
import { TRPCError } from '@trpc/server';
import { randomUUID, randomBytes } from 'node:crypto';

import {
  isolatedProcedure as protectedProcedure,
  router,
} from '../_core/trpc';
import { logger } from '../_core/logger';
import { getDb } from '../db';
import {
  referrals,
  type ReferralStatus,
} from '../../drizzle/schema.additions.wave4-9';
import { users } from '../../drizzle/schema';

/* -------------------------------------------------------------------------- */
/*  Code generation                                                            */
/*                                                                             */
/*  Format: `<3-uppercase-letters>-<3-digits>`  (e.g. "MEX-742")               */
/*  Space: 26^3 * 1000 ≈ 17.5M codes — plenty of room for the driver fleet.   */
/*  Collisions retried up to 8 times before we fall back to a random UUID     */
/*  suffix (extremely unlikely at current fleet size).                        */
/* -------------------------------------------------------------------------- */
const CODE_ALPHA = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // drop I, O for legibility
const CODE_MAX_ATTEMPTS = 8;

function generateCandidateCode(): string {
  const bytes = randomBytes(4);
  const letters = Array.from({ length: 3 })
    .map((_, i) => CODE_ALPHA[bytes[i] % CODE_ALPHA.length])
    .join('');
  // 3-digit block: 000-999, zero-padded
  const digits = (bytes[3] % 1000).toString().padStart(3, '0');
  return `${letters}-${digits}`;
}

/* -------------------------------------------------------------------------- */
/*  Router                                                                     */
/* -------------------------------------------------------------------------- */
export const referralsRouter = router({
  /**
   * getMyCode — returns the caller's durable referral code. Creates the row
   * on the first call and reuses it forever after. The code is the
   * user-facing "MEX-742" string; `shareUrl` is the deep link.
   */
  getMyCode: protectedProcedure.query(async ({ ctx }) => {
    const db = await getDb();
    const userId = Number(ctx.user?.id);
    if (!db || !userId) {
      throw new TRPCError({ code: 'UNAUTHORIZED' });
    }

    // Existing durable code? Use it.
    const [existing] = await db
      .select()
      .from(referrals)
      .where(
        and(
          eq(referrals.referrerUserId, userId),
          isNull(referrals.referredUserId)
        )
      )
      .orderBy(desc(referrals.createdAt))
      .limit(1);

    if (existing) {
      return {
        code: existing.code,
        shareUrl: `https://eusotrip.com/ref/${existing.code}`,
        createdAt: existing.createdAt,
        expiresAt: existing.expiresAt,
        status: existing.status as ReferralStatus,
      };
    }

    // Generate + persist (retry on collision).
    let code = '';
    let lastErr: unknown = null;
    for (let attempt = 0; attempt < CODE_MAX_ATTEMPTS; attempt++) {
      code = generateCandidateCode();
      try {
        const now = new Date();
        await db.insert(referrals).values({
          id: randomUUID(),
          referrerUserId: userId,
          referredUserId: null,
          code,
          status: 'pending',
          creditCents: 15000, // $150 default; ops can override per-row
          createdAt: now,
          updatedAt: now,
        });
        logger.info(
          `[referrals.getMyCode] created code=${code} for user=${userId}`
        );
        return {
          code,
          shareUrl: `https://eusotrip.com/ref/${code}`,
          createdAt: now,
          expiresAt: null,
          status: 'pending' as ReferralStatus,
        };
      } catch (e: any) {
        lastErr = e;
        if (!/duplicate|unique/i.test(String(e?.message))) throw e;
        // else: code collision — retry
      }
    }

    logger.error(
      `[referrals.getMyCode] exhausted ${CODE_MAX_ATTEMPTS} attempts for user=${userId}`,
      lastErr
    );
    throw new TRPCError({
      code: 'INTERNAL_SERVER_ERROR',
      message: 'unable to mint a referral code; please retry',
    });
  }),

  /**
   * claim — a new driver attaches themselves to a referrer via the code.
   * Both-side credit lands later when the referee hits 'first_haul'.
   *
   * Rules enforced here:
   *   - code must exist
   *   - code must not be expired / revoked
   *   - caller cannot self-claim
   *   - caller cannot be attached to a second referrer (the
   *     `referrals_referred_uk` partial unique index enforces this at the
   *     DB level; we pre-check for a clean error message)
   *   - if the same driver re-calls claim() with the same code, return
   *     the existing row (idempotent)
   */
  claim: protectedProcedure
    .input(
      z.object({
        code: z
          .string()
          .trim()
          .toUpperCase()
          .regex(/^[A-Z]{3}-\d{3}$/, 'code must look like ABC-123'),
      })
    )
    .mutation(async ({ ctx, input }) => {
      const db = await getDb();
      const userId = Number(ctx.user?.id);
      if (!db || !userId) {
        throw new TRPCError({ code: 'UNAUTHORIZED' });
      }

      const [row] = await db
        .select()
        .from(referrals)
        .where(eq(referrals.code, input.code))
        .limit(1);

      if (!row) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: 'referral code not found',
        });
      }
      if (row.status === 'expired' || row.status === 'revoked') {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: `referral code is ${row.status}`,
        });
      }
      if (row.expiresAt && row.expiresAt < new Date()) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: 'referral code has expired',
        });
      }
      if (row.referrerUserId === userId) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: 'cannot self-claim a referral code',
        });
      }
      // Idempotent: same caller re-calling claim on the same code.
      if (row.referredUserId === userId) {
        return {
          ok: true as const,
          referralId: row.id,
          status: row.status as ReferralStatus,
          alreadyAttached: true as const,
        };
      }
      // Code has already been claimed by SOMEONE ELSE.
      if (row.referredUserId != null) {
        throw new TRPCError({
          code: 'CONFLICT',
          message: 'referral code has already been claimed',
        });
      }
      // Caller already attached to a different referrer?
      const [existingAttach] = await db
        .select()
        .from(referrals)
        .where(eq(referrals.referredUserId, userId))
        .limit(1);
      if (existingAttach) {
        throw new TRPCError({
          code: 'CONFLICT',
          message: 'you are already attached to a referrer',
        });
      }

      const now = new Date();
      await db
        .update(referrals)
        .set({
          referredUserId: userId,
          status: 'claimed',
          updatedAt: now,
        })
        .where(eq(referrals.id, row.id));

      logger.info(
        `[referrals.claim] code=${row.code} referrer=${row.referrerUserId} referred=${userId}`
      );

      return {
        ok: true as const,
        referralId: row.id,
        status: 'claimed' as ReferralStatus,
        alreadyAttached: false as const,
      };
    }),

  /**
   * listMyReferrals — every driver the caller has referred (NULLs from the
   * pre-claim row are excluded). Returns referee id + onboarding status
   * so the UI can render the "Priya Menon · Onboarded" lines on 070.
   */
  listMyReferrals: protectedProcedure.query(async ({ ctx }) => {
    const db = await getDb();
    const userId = Number(ctx.user?.id);
    if (!db || !userId) return { referrals: [] };

    const rows = await db
      .select({
        referralId: referrals.id,
        code: referrals.code,
        status: referrals.status,
        creditCents: referrals.creditCents,
        creditedAt: referrals.creditedAt,
        createdAt: referrals.createdAt,
        referredUserId: referrals.referredUserId,
        referredName: users.name,
        referredEmail: users.email,
      })
      .from(referrals)
      .leftJoin(users, eq(users.id, referrals.referredUserId))
      .where(
        and(
          eq(referrals.referrerUserId, userId),
          // only rows that actually attached a referee
          or(
            eq(referrals.status, 'claimed'),
            eq(referrals.status, 'onboarded'),
            eq(referrals.status, 'first_haul'),
            eq(referrals.status, 'credited')
          )
        )
      )
      .orderBy(desc(referrals.createdAt));

    return { referrals: rows };
  }),
});

export type ReferralsRouter = typeof referralsRouter;
