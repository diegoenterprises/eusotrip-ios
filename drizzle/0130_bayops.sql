-- drizzle/0130_bayops.sql
-- Wave-4 · Theme 2.3 — bay_ops_events table + indexes.
-- Covers: discharge / disconnect / connectHose / backingAssist wizards.

BEGIN;

CREATE TABLE IF NOT EXISTS "bay_ops_events" (
  "id"                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "load_id"                 uuid NOT NULL,
  "wizard_kind"             text NOT NULL
    CHECK ("wizard_kind" IN ('discharge','disconnect','connectHose','backingAssist')),
  "step"                    text NOT NULL,
  "payload"                 jsonb NOT NULL DEFAULT '{}'::jsonb,
  "evidence_s3_key"         text NULL,
  "created_at"              timestamptz NOT NULL DEFAULT now(),
  "created_by_driver_id"    uuid NOT NULL
);

-- Fast replay of a single wizard for a single load (driver + dispatcher reads).
CREATE INDEX IF NOT EXISTS "bay_ops_events_load_wizard_idx"
  ON "bay_ops_events" ("load_id", "wizard_kind");

-- Per-driver activity feed, newest first (audit / compliance queries).
CREATE INDEX IF NOT EXISTS "bay_ops_events_driver_recent_idx"
  ON "bay_ops_events" ("created_by_driver_id", "created_at" DESC);

COMMIT;
