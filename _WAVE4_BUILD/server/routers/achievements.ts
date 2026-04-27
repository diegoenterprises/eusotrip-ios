/**
 * Wave-4 · Theme 2.8 · NEW router — `achievements`.
 *
 * Path in the web repo: `server/routers/achievements.ts`.
 * Mount as `achievements: achievementsRouter` in `server/routers.ts`.
 * See `_WAVE4_BUILD/agent_09.md` §Changelog for the exact edit.
 *
 * Driver-side UI entry points backed by this router:
 *   - 069 Achievements Wall — badge grid, rarity counter, share button.
 *
 * Split rationale. `gamification.getBadges` (server/routers/gamification.ts:528)
 * and `advancedGamification.getAchievements` stay in place. This new router
 * exposes the three driver-facing endpoints the wall explicitly needs that
 * are not currently available:
 *
 *   - `listMine`          — my earned badges with rarity.
 *   - `getById`           — badge detail (screen tap → detail modal).
 *   - `share`             — signed short URL for social share.
 *   - `getRarityCounts`   — the five-bucket aggregate the UI counter reads.
 *
 * Rarity derivation. The existing `badges` table has a `category` enum
 * (milestone|performance|specialty|seasonal|epic|legendary) and a `tier`
 * enum (bronze|silver|gold|platinum|diamond) plus an `isRare` flag. We fold
 * those into the five-bucket `achievement_rarity` type the UI needs:
 *
 *   category='legendary'                         → legendary
 *   category='epic' OR isRare=1                  → epic
 *   tier IN ('platinum','diamond')               → rare
 *   tier = 'gold'                                → uncommon
 *   otherwise                                    → common
 */

import { z } from 'zod';
import { and, eq } from 'drizzle-orm';
import { TRPCError } from '@trpc/server';
import { createHmac, randomBytes } from 'node:crypto';

import {
  isolatedProcedure as protectedProcedure,
  router,
} from '../_core/trpc';
import { logger } from '../_core/logger';
import { getDb } from '../db';
import { badges, userBadges } from '../../drizzle/schema';
import {
  ACHIEVEMENT_RARITIES,
  type AchievementRarity,
} from '../../drizzle/schema.additions.wave4-9';

/* -------------------------------------------------------------------------- */
/*  Zod schemas                                                                */
/* -------------------------------------------------------------------------- */
const RaritySchema = z.enum(ACHIEVEMENT_RARITIES);

/* -------------------------------------------------------------------------- */
/*  Rarity derivation                                                          */
/* -------------------------------------------------------------------------- */
export function deriveRarity(b: typeof badges.$inferSelect): AchievementRarity {
  if (b.category === 'legendary') return 'legendary';
  if (b.category === 'epic' || b.isRare) return 'epic';
  if (b.tier === 'platinum' || b.tier === 'diamond') return 'rare';
  if (b.tier === 'gold') return 'uncommon';
  return 'common';
}

/* -------------------------------------------------------------------------- */
/*  Signed share URL                                                           */
/*                                                                             */
/*  Short-lived (7d) HMAC-signed token the web UI can drop into share sheets. */
/*  Token payload = base64url(`${userId}:${badgeId}:${expiresAtMs}`) followed */
/*  by the HMAC-SHA256 signature. Verification lives in a future `/s/:token`  */
/*  edge route; it is NOT a tRPC procedure on purpose — that keeps the share  */
/*  link public-friendly (no auth cookie needed).                             */
/* -------------------------------------------------------------------------- */
const SHARE_SECRET =
  process.env.ACHIEVEMENT_SHARE_SECRET ??
  process.env.APP_SESSION_SECRET ??
  'eusotrip-dev-share-secret';

const SHARE_BASE_URL =
  process.env.PUBLIC_SHARE_BASE_URL ?? 'https://eusotrip.com/s';

function signShareToken(userId: number, badgeId: number, ttlMs: number): string {
  const expiresAtMs = Date.now() + ttlMs;
  const body = `${userId}:${badgeId}:${expiresAtMs}`;
  const mac = createHmac('sha256', SHARE_SECRET).update(body).digest('hex');
  // base64url encode body to keep URL safe
  const b64 = Buffer.from(body, 'utf8')
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
  // 12-char nonce to make replay/cache busting easier on CDN
  const nonce = randomBytes(6).toString('hex');
  return `${b64}.${mac.slice(0, 32)}.${nonce}`;
}

/* -------------------------------------------------------------------------- */
/*  Router                                                                     */
/* -------------------------------------------------------------------------- */
export const achievementsRouter = router({
  /**
   * listMine — every badge the caller has earned, optionally rarity-filtered.
   * Returns rows joined with `badges` so the UI has name/icon/tier in one
   * round-trip.
   */
  listMine: protectedProcedure
    .input(
      z
        .object({
          rarity: RaritySchema.optional(),
        })
        .optional()
    )
    .query(async ({ ctx, input }) => {
      const db = await getDb();
      const userId = Number(ctx.user?.id);
      if (!db || !userId) return { achievements: [] };

      const rows = await db
        .select({
          userBadgeId: userBadges.id,
          earnedAt: userBadges.earnedAt,
          isDisplayed: userBadges.isDisplayed,
          badge: badges,
        })
        .from(userBadges)
        .innerJoin(badges, eq(badges.id, userBadges.badgeId))
        .where(eq(userBadges.userId, userId));

      const enriched = rows.map((r) => ({
        userBadgeId: r.userBadgeId,
        earnedAt: r.earnedAt,
        isDisplayed: r.isDisplayed,
        badge: r.badge,
        rarity: deriveRarity(r.badge),
      }));

      const filtered = input?.rarity
        ? enriched.filter((e) => e.rarity === input.rarity)
        : enriched;

      return { achievements: filtered };
    }),

  /**
   * getById — badge detail for tap-through. Works for BOTH earned and
   * not-yet-earned badges so the UI can show the locked-state modal.
   */
  getById: protectedProcedure
    .input(z.object({ achievementId: z.number().int().positive() }))
    .query(async ({ ctx, input }) => {
      const db = await getDb();
      const userId = Number(ctx.user?.id);
      if (!db || !userId) {
        throw new TRPCError({ code: 'UNAUTHORIZED' });
      }

      const [badge] = await db
        .select()
        .from(badges)
        .where(eq(badges.id, input.achievementId))
        .limit(1);

      if (!badge) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: 'achievement not found',
        });
      }

      const [earned] = await db
        .select()
        .from(userBadges)
        .where(
          and(
            eq(userBadges.userId, userId),
            eq(userBadges.badgeId, badge.id)
          )
        )
        .limit(1);

      return {
        badge,
        rarity: deriveRarity(badge),
        earned: earned ?? null,
        isEarned: Boolean(earned),
      };
    }),

  /**
   * share — returns a signed short URL the caller can drop into a system
   * share sheet. Only returns a URL if the caller actually owns the badge;
   * otherwise throws FORBIDDEN.
   *
   * Token TTL: 7 days. The redeeming edge route must reject expired /
   * signature-invalid tokens.
   */
  share: protectedProcedure
    .input(z.object({ achievementId: z.number().int().positive() }))
    .mutation(async ({ ctx, input }) => {
      const db = await getDb();
      const userId = Number(ctx.user?.id);
      if (!db || !userId) {
        throw new TRPCError({ code: 'UNAUTHORIZED' });
      }

      const [earned] = await db
        .select()
        .from(userBadges)
        .where(
          and(
            eq(userBadges.userId, userId),
            eq(userBadges.badgeId, input.achievementId)
          )
        )
        .limit(1);

      if (!earned) {
        throw new TRPCError({
          code: 'FORBIDDEN',
          message: 'cannot share an achievement you have not earned',
        });
      }

      const token = signShareToken(
        userId,
        input.achievementId,
        7 * 24 * 60 * 60 * 1000
      );
      const url = `${SHARE_BASE_URL}/${token}`;
      const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

      logger.info(
        `[achievements.share] user=${userId} badge=${input.achievementId} token_prefix=${token.slice(0, 12)}`
      );
      return { url, token, expiresAt };
    }),

  /**
   * getRarityCounts — five-bucket aggregate for the 069 header counter.
   * Always returns every key so the UI can render 0s without null-checks.
   */
  getRarityCounts: protectedProcedure.query(async ({ ctx }) => {
    const db = await getDb();
    const userId = Number(ctx.user?.id);

    const base: Record<AchievementRarity, number> = {
      common: 0,
      uncommon: 0,
      rare: 0,
      epic: 0,
      legendary: 0,
    };

    if (!db || !userId) return base;

    const rows = await db
      .select({ badge: badges })
      .from(userBadges)
      .innerJoin(badges, eq(badges.id, userBadges.badgeId))
      .where(eq(userBadges.userId, userId));

    for (const r of rows) {
      base[deriveRarity(r.badge)] += 1;
    }
    return base;
  }),
});

export type AchievementsRouter = typeof achievementsRouter;
