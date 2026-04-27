/**
 * drizzle/schema.additions.wave4-8.ts
 *
 * Wave-4 · Agent #8 — Theme 2.10 (availability) + no-DVIR-router gap.
 *
 * These tables live alongside the canonical `drizzle/schema.ts` on purpose —
 * per the build brief (STRICT RULES) we MUST NOT edit the central schema.
 * The follow-up wave that re-unifies the schema will:
 *   1. move the `export const` blocks below into `schema.ts`
 *   2. update `schema.ts`'s re-exports
 *   3. update the import in `server/routers/availability.ts` and
 *      `server/routers/dvir.ts` to use `schema` directly.
 *
 * Until then routers import from here. See `_WAVE4_BUILD/agent_08.md`
 * changelog for the list of central-schema edits required.
 *
 * Migration source of truth: `drizzle/0160_availability_dvir.sql`.
 */

import {
  mysqlTable,
  int,
  tinyint,
  smallint,
  varchar,
  datetime,
  mysqlEnum,
  json,
  index,
  uniqueIndex,
} from 'drizzle-orm/mysql-core';

/* -------------------------------------------------------------------------- */
/*  driver_availability_blocks                                                 */
/* -------------------------------------------------------------------------- */
export const driverAvailabilityBlocks = mysqlTable(
  'driver_availability_blocks',
  {
    id: int('id').autoincrement().primaryKey(),
    driverId: int('driver_id').notNull(),
    companyId: int('company_id'),
    fromTs: datetime('from_ts').notNull(),
    toTs: datetime('to_ts').notNull(),
    reason: varchar('reason', { length: 255 }),
    source: mysqlEnum('source', ['driver', 'dispatch', 'system', 'hos'])
      .notNull()
      .default('driver'),
    createdAt: datetime('created_at').notNull(),
  },
  (t) => ({
    driverIdx: index('dab_driver_idx').on(t.driverId),
    companyIdx: index('dab_company_idx').on(t.companyId),
    windowIdx: index('dab_window_idx').on(t.driverId, t.fromTs, t.toTs),
  })
);

export type DriverAvailabilityBlock =
  typeof driverAvailabilityBlocks.$inferSelect;
export type InsertDriverAvailabilityBlock =
  typeof driverAvailabilityBlocks.$inferInsert;

/* -------------------------------------------------------------------------- */
/*  driver_weekly_availability                                                 */
/* -------------------------------------------------------------------------- */
export const driverWeeklyAvailability = mysqlTable(
  'driver_weekly_availability',
  {
    id: int('id').autoincrement().primaryKey(),
    driverId: int('driver_id').notNull(),
    companyId: int('company_id'),
    /** 0 = Sunday, 6 = Saturday (matches JS Date.getDay()). */
    dayOfWeek: tinyint('day_of_week').notNull(),
    /** Minutes since local midnight, 0 … 1440. */
    startMin: smallint('start_min').notNull(),
    endMin: smallint('end_min').notNull(),
    updatedAt: datetime('updated_at').notNull(),
  },
  (t) => ({
    driverDowStartUk: uniqueIndex('dwa_driver_dow_start_uk').on(
      t.driverId,
      t.dayOfWeek,
      t.startMin
    ),
    driverIdx: index('dwa_driver_idx').on(t.driverId),
  })
);

export type DriverWeeklyAvailability =
  typeof driverWeeklyAvailability.$inferSelect;
export type InsertDriverWeeklyAvailability =
  typeof driverWeeklyAvailability.$inferInsert;

/* -------------------------------------------------------------------------- */
/*  dvirs — canonical Wave-4 DVIR table                                        */
/*                                                                             */
/*  Legacy rows live in `dvir_reports` and are still written by               */
/*  `inspections.createDVIR` (server/routers/inspections.ts:296-302).         */
/*  The new dvir router writes here AND keeps a link via `legacy_dvir_id` /   */
/*  `inspection_ref_id` so existing UI using the inspections endpoints keeps   */
/*  working during the transition.                                            */
/* -------------------------------------------------------------------------- */
export const dvirs = mysqlTable(
  'dvirs',
  {
    id: int('id').autoincrement().primaryKey(),
    driverId: int('driver_id').notNull(),
    vehicleId: int('vehicle_id').notNull(),
    trailerId: int('trailer_id'),
    companyId: int('company_id'),
    kind: mysqlEnum('kind', ['pre', 'post']).notNull(),
    status: mysqlEnum('status', ['draft', 'submitted']).notNull().default('draft'),
    defects: json('defects').$type<DvirDefect[]>(),
    signaturesS3Key: varchar('signatures_s3_key', { length: 500 }),
    inspectionRefId: int('inspection_ref_id'),
    legacyDvirId: int('legacy_dvir_id'),
    createdAt: datetime('created_at').notNull(),
    submittedAt: datetime('submitted_at'),
  },
  (t) => ({
    driverIdx: index('dvirs_driver_idx').on(t.driverId),
    vehicleIdx: index('dvirs_vehicle_idx').on(t.vehicleId),
    trailerIdx: index('dvirs_trailer_idx').on(t.trailerId),
    companyIdx: index('dvirs_company_idx').on(t.companyId),
    statusIdx: index('dvirs_status_idx').on(t.status),
    inspectionRefIdx: index('dvirs_inspection_ref_idx').on(t.inspectionRefId),
  })
);

export type Dvir = typeof dvirs.$inferSelect;
export type InsertDvir = typeof dvirs.$inferInsert;

export interface DvirDefect {
  /** e.g. 'brakes', 'lights', 'tires', 'coupling'. */
  category: string;
  description: string;
  severity: 'minor' | 'major' | 'out_of_service';
  photoS3Key?: string;
}

/* -------------------------------------------------------------------------- */
/*  driver_export_tokens — signed URL bookkeeping                              */
/* -------------------------------------------------------------------------- */
export const driverExportTokens = mysqlTable(
  'driver_export_tokens',
  {
    id: int('id').autoincrement().primaryKey(),
    driverId: int('driver_id').notNull(),
    kind: mysqlEnum('kind', ['availability_ics', 'dvir_pdf']).notNull(),
    resourceId: varchar('resource_id', { length: 64 }),
    token: varchar('token', { length: 64 }).notNull(),
    s3Key: varchar('s3_key', { length: 500 }),
    expiresAt: datetime('expires_at').notNull(),
    createdAt: datetime('created_at').notNull(),
  },
  (t) => ({
    tokenUk: uniqueIndex('det_token_uk').on(t.token),
    driverIdx: index('det_driver_idx').on(t.driverId),
    expiresIdx: index('det_expires_idx').on(t.expiresAt),
  })
);

export type DriverExportToken = typeof driverExportTokens.$inferSelect;
export type InsertDriverExportToken = typeof driverExportTokens.$inferInsert;
