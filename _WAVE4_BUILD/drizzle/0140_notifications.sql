-- =============================================================================
-- Wave-4 · Theme 2.7 · Notifications mutation surface + draft subsurface
-- Migration: 0140_notifications.sql
-- Author: Wave-4 Build Agent #6
-- Date: 2026-04-18
--
-- Additive only — no destructive changes to existing notifications rows.
-- =============================================================================

BEGIN;

-- ─── 1. notifications.snoozed_until ──────────────────────────────────────────
ALTER TABLE "notifications"
  ADD COLUMN IF NOT EXISTS "snoozed_until" TIMESTAMPTZ NULL;

-- link back to draft that authored this notification (for send() trace)
ALTER TABLE "notifications"
  ADD COLUMN IF NOT EXISTS "source_draft_id" UUID NULL;

-- index so the driver inbox query can `WHERE snoozed_until IS NULL OR snoozed_until < now()`
CREATE INDEX IF NOT EXISTS "idx_notifications_user_snoozed"
  ON "notifications" ("user_id", "snoozed_until")
  WHERE "snoozed_until" IS NOT NULL;

-- ─── 2. notification_channel enum ────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE "notification_channel" AS ENUM (
    'dispatch',
    'ops',
    'safety',
    'hos',
    'marketing',
    'ai_coach'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- add the enum column to notifications if it doesn't already live there
ALTER TABLE "notifications"
  ADD COLUMN IF NOT EXISTS "channel" "notification_channel" NULL;

CREATE INDEX IF NOT EXISTS "idx_notifications_user_channel_created"
  ON "notifications" ("user_id", "channel", "created_at" DESC);

-- ─── 3. notification_channel_preferences ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS "notification_channel_preferences" (
  "user_id"    UUID NOT NULL,
  "channel"    "notification_channel" NOT NULL,
  "enabled"    BOOLEAN NOT NULL DEFAULT TRUE,
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "notification_channel_preferences_pk"
    PRIMARY KEY ("user_id", "channel"),
  CONSTRAINT "notification_channel_preferences_user_fk"
    FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);

-- ─── 4. notification_draft_status enum ───────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE "notification_draft_status" AS ENUM ('draft', 'sent', 'discarded');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ─── 5. notification_drafts ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "notification_drafts" (
  "id"              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "author_user_id"  UUID NOT NULL,
  "to_user_id"      UUID NOT NULL,
  "channel"         "notification_channel" NOT NULL,
  "body"            TEXT NOT NULL,
  "status"          "notification_draft_status" NOT NULL DEFAULT 'draft',
  "created_at"      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at"      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "notification_drafts_author_fk"
    FOREIGN KEY ("author_user_id") REFERENCES "users"("id") ON DELETE CASCADE,
  CONSTRAINT "notification_drafts_to_fk"
    FOREIGN KEY ("to_user_id") REFERENCES "users"("id") ON DELETE CASCADE,
  CONSTRAINT "notification_drafts_body_nonempty" CHECK (char_length("body") > 0)
);

CREATE INDEX IF NOT EXISTS "idx_notification_drafts_author_status_updated"
  ON "notification_drafts" ("author_user_id", "status", "updated_at" DESC);

CREATE INDEX IF NOT EXISTS "idx_notification_drafts_to_status"
  ON "notification_drafts" ("to_user_id", "status");

-- wire the source_draft_id FK now that the referenced table exists
ALTER TABLE "notifications"
  ADD CONSTRAINT IF NOT EXISTS "notifications_source_draft_fk"
  FOREIGN KEY ("source_draft_id")
  REFERENCES "notification_drafts"("id")
  ON DELETE SET NULL;

COMMIT;

-- =============================================================================
-- Rollback (kept for reference — do NOT run in forward migration)
-- =============================================================================
-- BEGIN;
--   ALTER TABLE "notifications" DROP CONSTRAINT IF EXISTS "notifications_source_draft_fk";
--   DROP TABLE IF EXISTS "notification_drafts";
--   DROP TYPE IF EXISTS "notification_draft_status";
--   DROP TABLE IF EXISTS "notification_channel_preferences";
--   ALTER TABLE "notifications" DROP COLUMN IF EXISTS "channel";
--   DROP TYPE IF EXISTS "notification_channel";
--   ALTER TABLE "notifications" DROP COLUMN IF EXISTS "source_draft_id";
--   ALTER TABLE "notifications" DROP COLUMN IF EXISTS "snoozed_until";
-- COMMIT;
