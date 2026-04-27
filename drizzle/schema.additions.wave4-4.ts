/**
 * drizzle/schema.additions.wave4-4.ts
 *
 * Wave-4 · Theme 2.3 — Schema additions for bayOps wizards.
 *
 * NOT merged into `drizzle/schema.ts` yet. Merger is a follow-up PR; the
 * changelog in `_WAVE4_BUILD/agent_04.md` lists the required edits.
 *
 * Companion SQL migration: `drizzle/0130_bayops.sql`.
 */

import {
  pgTable,
  uuid,
  text,
  jsonb,
  timestamp,
  index,
} from 'drizzle-orm/pg-core';

/**
 * Append-only event log for every bay-ops wizard step / evidence /
 * telemetry frame / abort. One row per user or sensor event.
 */
export const bayOpsEvents = pgTable(
  'bay_ops_events',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    loadId: uuid('load_id').notNull(),
    /** Enum mirrored in TypeScript: discharge | disconnect | connectHose | backingAssist. */
    wizardKind: text('wizard_kind').notNull(),
    /** Current FSM step at the time of the event. */
    step: text('step').notNull(),
    /**
     * Structured payload. Always carries a `phase` discriminator:
     *   start | advance | evidence | complete | abort | distance | telemetry
     */
    payload: jsonb('payload').notNull().default({}),
    /** S3 key of any attached blob (photo, clip, sensor log). Null if none. */
    evidenceS3Key: text('evidence_s3_key'),
    createdAt: timestamp('created_at', { withTimezone: true })
      .notNull()
      .defaultNow(),
    createdByDriverId: uuid('created_by_driver_id').notNull(),
  },
  (t) => ({
    /** Replay one wizard for one load — primary UI scan. */
    loadWizardIdx: index('bay_ops_events_load_wizard_idx').on(
      t.loadId,
      t.wizardKind,
    ),
    /** Per-driver audit trail, newest first. */
    driverRecentIdx: index('bay_ops_events_driver_recent_idx').on(
      t.createdByDriverId,
      t.createdAt.desc(),
    ),
  }),
);

export type BayOpsEventRow = typeof bayOpsEvents.$inferSelect;
export type NewBayOpsEvent = typeof bayOpsEvents.$inferInsert;
