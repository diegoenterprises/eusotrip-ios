-- =============================================================================
-- Wave-4 · Theme 2.11 · Earnings composition + goals + tax form index
-- Migration: 0180_earnings_tax.sql
-- Author:    Wave-4 Build Agent #10
-- Date:      2026-04-18
--
-- Additive only. No destructive changes to pre-existing rows.
-- =============================================================================

BEGIN;

-- ─── 1. earnings_composition_snapshots ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS "earnings_composition_snapshots" (
  "id"            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "load_id"       UUID NOT NULL,
  "snapshot_json" JSONB NOT NULL,
  "created_at"    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS "idx_earnings_comp_snaps_load_created"
  ON "earnings_composition_snapshots" ("load_id", "created_at" DESC);

-- ─── 2. earnings_goal_period enum ────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE "earnings_goal_period" AS ENUM ('week', 'month');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ─── 3. earnings_goals ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "earnings_goals" (
  "driver_id"    UUID NOT NULL,
  "period"       "earnings_goal_period" NOT NULL,
  "target_cents" INTEGER NOT NULL,
  "set_at"       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "earnings_goals_pk" PRIMARY KEY ("driver_id", "period"),
  CONSTRAINT "earnings_goals_driver_fk"
    FOREIGN KEY ("driver_id") REFERENCES "users"("id") ON DELETE CASCADE,
  CONSTRAINT "earnings_goals_target_positive" CHECK ("target_cents" > 0)
);

-- ─── 4. tax_forms(user_id, year, kind) index — conditional on table presence ─
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = 'tax_forms'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_indexes
       WHERE schemaname = 'public'
         AND tablename = 'tax_forms'
         AND indexname = 'idx_tax_forms_user_year_kind'
    ) THEN
      EXECUTE 'CREATE INDEX "idx_tax_forms_user_year_kind"
               ON "tax_forms" ("user_id", "year", "kind")';
    END IF;
  ELSE
    RAISE NOTICE
      '[0180] tax_forms not present — index idx_tax_forms_user_year_kind skipped (see agent_10.md changelog).';
  END IF;
END $$;

COMMIT;

-- =============================================================================
-- Rollback (reference only — do NOT run in forward direction)
-- =============================================================================
-- BEGIN;
--   DROP INDEX IF EXISTS "idx_tax_forms_user_year_kind";
--   DROP TABLE IF EXISTS "earnings_goals";
--   DROP TYPE  IF EXISTS "earnings_goal_period";
--   DROP INDEX IF EXISTS "idx_earnings_comp_snaps_load_created";
--   DROP TABLE IF EXISTS "earnings_composition_snapshots";
-- COMMIT;
