/**
 * drizzle/schema.additions.wave4-9.ts
 *
 * Wave-4 · Agent #9 · Theme 2.8 — missions / achievements / referrals split.
 *
 * These tables live alongside the canonical `drizzle/schema.ts` on purpose —
 * per the build brief (STRICT RULES) we MUST NOT edit the central schema.
 * The follow-up wave that re-unifies the schema will:
 *   1. move the `export const` blocks below into `schema.ts`
 *   2. update `schema.ts`'s re-exports
 *   3. update the imports in `server/routers/missions.ts`,
 *      `server/routers/achievements.ts`, and `server/routers/referrals.ts`
 *      to pull from `schema` directly.
 *
 * Until then the new routers import from here. See `_WAVE4_BUILD/agent_09.md`
 * §Changelog for the list of central-schema edits required.
 *
 * Migration source of truth: `drizzle/0170_missions_achievements_referrals.sql`.
 */

import {
  mysqlTable,
  int,
  varchar,
  text,
  datetime,
  mysqlEnum,
  json,
  index,
  uniqueIndex,
} from 'drizzle-orm/mysql-core';

/* -------------------------------------------------------------------------- */
/*  mission_status / mission_kind — string-literal tuples exported for zod    */
/* -------------------------------------------------------------------------- */
export const MISSION_STATUSES = [
  'active',
  'verifying',
  'verified',
  'completed',
  'expired',
  'cancelled',
] as const;
export type MissionStatus = (typeof MISSION_STATUSES)[number];

export const MISSION_KINDS = [
  'cash_reward',
  'badge',
  'combo',
  'xp_only',
] as const;
export type MissionKind = (typeof MISSION_KINDS)[number];

/* -------------------------------------------------------------------------- */
/*  driver_missions — per-driver mission instances (NEW)                       */
/* -------------------------------------------------------------------------- */
export const driverMissions = mysqlTable(
  'driver_missions',
  {
    id: varchar('id', { length: 36 }).primaryKey(),
    driverId: int('driver_id').notNull(),
    templateMissionId: int('template_mission_id'),
    kind: mysqlEnum('kind', MISSION_KINDS).notNull(),
    status: mysqlEnum('status', MISSION_STATUSES).notNull().default('active'),
    cashRewardCents: int('cash_reward_cents'),
    badgeId: int('badge_id'),
    xpReward: int('xp_reward').default(0),
    title: varchar('title', { length: 255 }).notNull(),
    description: text('description'),
    progress: json('progress').$type<DriverMissionProgress>(),
    startedAt: datetime('started_at').notNull(),
    verifiedAt: datetime('verified_at'),
    completedAt: datetime('completed_at'),
    expiresAt: datetime('expires_at'),
    createdAt: datetime('created_at').notNull(),
    updatedAt: datetime('updated_at').notNull(),
  },
  (t) => ({
    driverStatusIdx: index('idx_driver_missions_driver_status').on(
      t.driverId,
      t.status
    ),
    templateIdx: index('idx_driver_missions_template').on(t.templateMissionId),
    expiresIdx: index('idx_driver_missions_expires').on(t.expiresAt),
  })
);

export type DriverMission = typeof driverMissions.$inferSelect;
export type InsertDriverMission = typeof driverMissions.$inferInsert;

/** JSON shape for driver_missions.progress. */
export interface DriverMissionProgress {
  objectives: Array<{
    key: string;
    label: string;
    done: number;
    target: number;
    verified: boolean;
  }>;
  /** Overall 0..1. Client-rendered as the progress bar on 067 The Haul Mission. */
  pct: number;
}

/* -------------------------------------------------------------------------- */
/*  rank_locks — HOLD state on a leaderboard (NEW)                             */
/* -------------------------------------------------------------------------- */
export const rankLocks = mysqlTable(
  'rank_locks',
  {
    id: varchar('id', { length: 36 }).primaryKey(),
    driverId: int('driver_id').notNull(),
    leaderboardId: int('leaderboard_id').notNull(),
    lockedUntil: datetime('locked_until').notNull(),
    reason: varchar('reason', { length: 255 }).notNull(),
    createdBy: int('created_by'),
    createdAt: datetime('created_at').notNull(),
  },
  (t) => ({
    driverIdx: index('idx_rank_locks_driver').on(t.driverId),
    leaderboardIdx: index('idx_rank_locks_leaderboard').on(t.leaderboardId),
    activeIdx: index('idx_rank_locks_active').on(
      t.driverId,
      t.leaderboardId,
      t.lockedUntil
    ),
  })
);

export type RankLock = typeof rankLocks.$inferSelect;
export type InsertRankLock = typeof rankLocks.$inferInsert;

/* -------------------------------------------------------------------------- */
/*  referral_status — string-literal tuple                                     */
/* -------------------------------------------------------------------------- */
export const REFERRAL_STATUSES = [
  'pending',
  'claimed',
  'onboarded',
  'first_haul',
  'credited',
  'expired',
  'revoked',
] as const;
export type ReferralStatus = (typeof REFERRAL_STATUSES)[number];

/* -------------------------------------------------------------------------- */
/*  referrals — persistent driver-to-driver referral ledger (NEW)              */
/* -------------------------------------------------------------------------- */
export const referrals = mysqlTable(
  'referrals',
  {
    id: varchar('id', { length: 36 }).primaryKey(),
    referrerUserId: int('referrer_user_id').notNull(),
    referredUserId: int('referred_user_id'),
    code: varchar('code', { length: 16 }).notNull(),
    status: mysqlEnum('status', REFERRAL_STATUSES).notNull().default('pending'),
    creditCents: int('credit_cents').notNull().default(15000),
    creditedAt: datetime('credited_at'),
    expiresAt: datetime('expires_at'),
    createdAt: datetime('created_at').notNull(),
    updatedAt: datetime('updated_at').notNull(),
  },
  (t) => ({
    codeUk: uniqueIndex('referrals_code_uk').on(t.code),
    referrerStatusIdx: index('idx_referrals_referrer_status').on(
      t.referrerUserId,
      t.status
    ),
    referredIdx: index('idx_referrals_referred').on(t.referredUserId),
    referredUk: uniqueIndex('referrals_referred_uk').on(t.referredUserId),
  })
);

export type Referral = typeof referrals.$inferSelect;
export type InsertReferral = typeof referrals.$inferInsert;

/* -------------------------------------------------------------------------- */
/*  Rarity tuple for achievements.getRarityCounts                              */
/*                                                                             */
/*  NOTE: the existing `badges` table (drizzle/schema.ts:2265) already has a   */
/*  `category` enum that includes 'epic' and 'legendary' and a `tier` enum    */
/*  that includes bronze→diamond. Rarity is computed by the achievements       */
/*  router from (category, tier, isRare) — see server/routers/achievements.ts. */
/* -------------------------------------------------------------------------- */
export const ACHIEVEMENT_RARITIES = [
  'common',
  'uncommon',
  'rare',
  'epic',
  'legendary',
] as const;
export type AchievementRarity = (typeof ACHIEVEMENT_RARITIES)[number];
