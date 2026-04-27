/**
 * Wave-4 · Build Agent #10 · Theme 2.11
 *
 * Drizzle schema additions for the financial composition / tax estimate
 * surface. The schema-owner agent merges these re-exports into `schema.ts`;
 * this file is authoritative for the new tables/enums.
 *
 * New objects:
 *   - enum   earnings_goal_period
 *   - table  earnings_composition_snapshots
 *   - table  earnings_goals
 *   - index  idx_tax_forms_user_year_kind  (on pre-existing tax_forms, if
 *            table is present — see migration + changelog)
 */

import {
  pgEnum,
  pgTable,
  primaryKey,
  uuid,
  integer,
  jsonb,
  timestamp,
  index,
} from 'drizzle-orm/pg-core';
import { users } from './schema'; // existing base table

// ─── Enums ───────────────────────────────────────────────────────────────────
export const earningsGoalPeriodEnum = pgEnum('earnings_goal_period', [
  'week',
  'month',
]);

// ─── earnings_composition_snapshots ──────────────────────────────────────────
/**
 * Immutable frozen snapshots of a load's earnings composition. Written by
 * `earnings.getComposition` (cache warm) and by `earnings.atomicTripWrapSubmit`
 * (authoritative freeze). Multiple rows per load_id are allowed — the latest
 * snapshotted_at wins for reads.
 */
export const earningsCompositionSnapshots = pgTable(
  'earnings_composition_snapshots',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    loadId: uuid('load_id').notNull(),
    snapshotJson: jsonb('snapshot_json').notNull().$type<Record<string, unknown>>(),
    createdAt: timestamp('created_at', { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (t) => ({
    byLoadCreated: index('idx_earnings_comp_snaps_load_created').on(
      t.loadId,
      t.createdAt,
    ),
  }),
);

export type EarningsCompositionSnapshot =
  typeof earningsCompositionSnapshots.$inferSelect;
export type NewEarningsCompositionSnapshot =
  typeof earningsCompositionSnapshots.$inferInsert;

// ─── earnings_goals ──────────────────────────────────────────────────────────
/**
 * Per-driver net-earnings goal. PK on (driver_id, period) — one active goal
 * per period kind per driver.
 */
export const earningsGoals = pgTable(
  'earnings_goals',
  {
    driverId: uuid('driver_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    period: earningsGoalPeriodEnum('period').notNull(),
    targetCents: integer('target_cents').notNull(),
    setAt: timestamp('set_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.driverId, t.period] }),
  }),
);

export type EarningsGoal = typeof earningsGoals.$inferSelect;
export type NewEarningsGoal = typeof earningsGoals.$inferInsert;

/**
 * Composite index on `tax_forms(user_id, year, kind)` is declared in the
 * migration `drizzle/0180_earnings_tax.sql` (not via drizzle-orm because the
 * table is owned by the existing schema file). If `tax_forms` is missing
 * from the deployed DB (fresh environments), the migration skips the index
 * silently — see the CHANGELOG in `_WAVE4_BUILD/agent_10.md`.
 */
