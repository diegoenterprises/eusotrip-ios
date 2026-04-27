-- =============================================================================
-- Wave-4 · Theme 2.8 · Gamification / missions / streaks split
-- Migration: 0170_missions_achievements_referrals.sql
-- Author:    Wave-4 Build Agent #9
-- Date:      2026-04-18
--
-- Purpose. Introduces the three tables that back the split of
-- `gamification.ts` / `advancedGamification.ts` into `missions.ts`,
-- `achievements.ts`, and `referrals.ts`:
--
--   * missions          — per-driver mission instances with status FSM,
--                         cash reward (cents) and/or badge reward.
--   * rank_locks        — HOLD rank-lock rows for a driver on a leaderboard
--                         (backs the "HOLD" pill on 068 The Haul Leaderboard).
--   * referrals         — persistent driver-to-driver referral codes with
--                         referrer/referred FK and lifecycle status.
--
-- Additive only — no destructive changes to the existing `missions`,
-- `mission_progress`, `leaderboards`, or `user_badges` tables living in
-- `drizzle/schema.ts`. The existing `missions` table (templates) stays
-- authoritative for mission catalog rows; the new `missions` table in this
-- migration is the per-driver INSTANCE table. The names differ in the code
-- seams: we import the new table under the drizzle symbol
-- `driverMissions` (see `drizzle/schema.additions.wave4-9.ts`).
--
-- Targeting PostgreSQL to match the migration file style used by the
-- Wave-4 sibling migrations (0140_notifications.sql, 0160_availability_dvir.sql).
-- Rollback block at the bottom is commented out by design.
-- =============================================================================

BEGIN;

-- ─── 1. mission_status enum ──────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE "mission_status" AS ENUM (
    'active',      -- accepted, progress accruing
    'verifying',   -- claim() submitted, awaiting verification
    'verified',    -- verified by system/ops, ready to redeem
    'completed',   -- redeemed, rewards dispensed
    'expired',     -- window closed before verification
    'cancelled'    -- voluntarily cancelled by driver
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ─── 2. mission_kind enum ────────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE "mission_kind" AS ENUM (
    'cash_reward',   -- pays out cash via wallet on redeem()
    'badge',         -- awards user_badges row on redeem()
    'combo',         -- both cash AND badge
    'xp_only'        -- XP only (legacy, kept for migration of existing rows)
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ─── 3. missions (driver_missions) ──────────────────────────────────────────
-- Per-driver mission instances. Distinct from `missions` catalog table in
-- `drizzle/schema.ts` (kept unchanged). The catalog row id is referenced via
-- `template_mission_id` so templates keep authoring missions.
CREATE TABLE IF NOT EXISTS "driver_missions" (
  "id"                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "driver_id"           INT NOT NULL,
  "template_mission_id" INT NULL,
  "kind"                "mission_kind" NOT NULL,
  "status"              "mission_status" NOT NULL DEFAULT 'active',
  "cash_reward_cents"   INT NULL,
  "badge_id"            INT NULL,
  "xp_reward"           INT NULL DEFAULT 0,
  "title"               VARCHAR(255) NOT NULL,
  "description"         TEXT NULL,
  "progress"            JSONB NULL,        -- objective-level progress payload
  "started_at"          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "verified_at"         TIMESTAMPTZ NULL,
  "completed_at"        TIMESTAMPTZ NULL,
  "expires_at"          TIMESTAMPTZ NULL,
  "created_at"          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at"          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT "driver_missions_driver_fk"
    FOREIGN KEY ("driver_id") REFERENCES "users"("id") ON DELETE CASCADE,
  CONSTRAINT "driver_missions_badge_fk"
    FOREIGN KEY ("badge_id") REFERENCES "badges"("id") ON DELETE SET NULL,
  CONSTRAINT "driver_missions_cash_nonneg" CHECK (
    "cash_reward_cents" IS NULL OR "cash_reward_cents" >= 0
  ),
  CONSTRAINT "driver_missions_kind_payload" CHECK (
    ("kind" = 'cash_reward' AND "cash_reward_cents" IS NOT NULL) OR
    ("kind" = 'badge'       AND "badge_id" IS NOT NULL) OR
    ("kind" = 'combo'       AND "cash_reward_cents" IS NOT NULL
                            AND "badge_id" IS NOT NULL) OR
    ("kind" = 'xp_only')
  )
);

-- Required index per brief: (driver_id, status) — hot path for listForMe.
CREATE INDEX IF NOT EXISTS "idx_driver_missions_driver_status"
  ON "driver_missions" ("driver_id", "status");

-- Secondary indexes for common filters.
CREATE INDEX IF NOT EXISTS "idx_driver_missions_template"
  ON "driver_missions" ("template_mission_id");
CREATE INDEX IF NOT EXISTS "idx_driver_missions_expires"
  ON "driver_missions" ("expires_at")
  WHERE "expires_at" IS NOT NULL;

-- ─── 4. rank_locks ──────────────────────────────────────────────────────────
-- HOLD / rank-lock state for a driver on a specific leaderboard. When a row
-- exists with `locked_until > NOW()`, the driver's leaderboard rank pill is
-- rendered as "HOLD" on 068 The Haul Leaderboard.
CREATE TABLE IF NOT EXISTS "rank_locks" (
  "id"              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "driver_id"       INT NOT NULL,
  "leaderboard_id"  INT NOT NULL,
  "locked_until"    TIMESTAMPTZ NOT NULL,
  "reason"          VARCHAR(255) NOT NULL,
  "created_by"      INT NULL,    -- ops user id, NULL if system-generated
  "created_at"      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT "rank_locks_driver_fk"
    FOREIGN KEY ("driver_id") REFERENCES "users"("id") ON DELETE CASCADE,
  CONSTRAINT "rank_locks_leaderboard_fk"
    FOREIGN KEY ("leaderboard_id") REFERENCES "leaderboards"("id") ON DELETE CASCADE,
  CONSTRAINT "rank_locks_future"
    CHECK ("locked_until" > "created_at")
);

CREATE INDEX IF NOT EXISTS "idx_rank_locks_driver"
  ON "rank_locks" ("driver_id");
CREATE INDEX IF NOT EXISTS "idx_rank_locks_leaderboard"
  ON "rank_locks" ("leaderboard_id");
CREATE INDEX IF NOT EXISTS "idx_rank_locks_active"
  ON "rank_locks" ("driver_id", "leaderboard_id", "locked_until");

-- ─── 5. referral_status enum ────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE "referral_status" AS ENUM (
    'pending',          -- code shared, not yet claimed
    'claimed',          -- referee attached but not onboarded
    'onboarded',        -- referee finished onboarding flow
    'first_haul',       -- referee completed first haul — triggers credit
    'credited',         -- both sides received referral_credit
    'expired',          -- code expired before claim
    'revoked'           -- revoked by ops / fraud
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ─── 6. referrals ───────────────────────────────────────────────────────────
-- Persistent driver-to-driver referral ledger. Each referrer has a durable
-- code (generated on first getMyCode() call) that can be claimed by a
-- new driver. Both sides receive a `referral_credit` wallet transaction
-- when the referee hits `first_haul` status.
CREATE TABLE IF NOT EXISTS "referrals" (
  "id"                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "referrer_user_id"   INT NOT NULL,
  "referred_user_id"   INT NULL,           -- NULL until claim() is called
  "code"               VARCHAR(16) NOT NULL,
  "status"             "referral_status" NOT NULL DEFAULT 'pending',
  "credit_cents"       INT NOT NULL DEFAULT 15000,   -- $150 default; per-row override allowed
  "credited_at"        TIMESTAMPTZ NULL,
  "expires_at"         TIMESTAMPTZ NULL,
  "created_at"         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at"         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT "referrals_referrer_fk"
    FOREIGN KEY ("referrer_user_id") REFERENCES "users"("id") ON DELETE CASCADE,
  CONSTRAINT "referrals_referred_fk"
    FOREIGN KEY ("referred_user_id") REFERENCES "users"("id") ON DELETE SET NULL,
  CONSTRAINT "referrals_no_self" CHECK (
    "referred_user_id" IS NULL OR "referrer_user_id" <> "referred_user_id"
  ),
  CONSTRAINT "referrals_credit_nonneg" CHECK ("credit_cents" >= 0)
);

-- A referrer has exactly ONE durable code, surfaced as "MEX-742" on 070.
CREATE UNIQUE INDEX IF NOT EXISTS "referrals_code_uk"
  ON "referrals" ("code");

-- Durable-code lookup: most recent pending/active code per referrer.
CREATE INDEX IF NOT EXISTS "idx_referrals_referrer_status"
  ON "referrals" ("referrer_user_id", "status");

-- Referee lookup (listMyReferrals when caller is referrer).
CREATE INDEX IF NOT EXISTS "idx_referrals_referred"
  ON "referrals" ("referred_user_id");

-- A referee can only be claimed by ONE referrer — enforce at the row level.
CREATE UNIQUE INDEX IF NOT EXISTS "referrals_referred_uk"
  ON "referrals" ("referred_user_id")
  WHERE "referred_user_id" IS NOT NULL;

COMMIT;

-- =============================================================================
-- Rollback (kept for reference — do NOT run in forward migration)
-- =============================================================================
-- BEGIN;
--   DROP TABLE IF EXISTS "referrals";
--   DROP TYPE  IF EXISTS "referral_status";
--   DROP TABLE IF EXISTS "rank_locks";
--   DROP TABLE IF EXISTS "driver_missions";
--   DROP TYPE  IF EXISTS "mission_kind";
--   DROP TYPE  IF EXISTS "mission_status";
-- COMMIT;
