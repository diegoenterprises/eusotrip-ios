-- ============================================================================
-- Migration: 0160_availability_dvir.sql
-- Wave-4 · Theme 2.10 (availability) + agent_05 "no DVIR router" gap
--
-- Adds:
--   * driver_availability_blocks    — ad-hoc blocked time windows.
--   * driver_weekly_availability    — recurring weekly on/off slot pattern.
--   * dvirs                         — canonical DVIR form rows (if not already
--                                     present as `dvir_reports`; created IF NOT
--                                     EXISTS so the migration is idempotent on
--                                     environments where legacy schema exists).
--
-- Notes
-- -----
-- * `dvir_reports` (legacy) is referenced by `server/routers/inspections.ts`
--   (inspections.ts:296-302, 327-335, 353-359). The new `dvirs` table is the
--   Wave-4 canonical name — during the transition period the new `dvir` router
--   writes to `dvirs` and falls back to legacy rows via the inspections router
--   until the backfill migration in 0161 lands.
-- * Conflict resolution with `hos_logs` is done in application code
--   (availability router) — no FK here because `hos_logs` is a hypertable.
-- * All timestamps are UTC; client converts with the driver's `timezone`
--   recorded on `drivers.timezone` (existing column).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. driver_availability_blocks
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `driver_availability_blocks` (
  `id`          INT          NOT NULL AUTO_INCREMENT,
  `driver_id`   INT          NOT NULL,
  `company_id`  INT          NULL,
  `from_ts`     DATETIME     NOT NULL,
  `to_ts`       DATETIME     NOT NULL,
  `reason`      VARCHAR(255) NULL,
  `source`      ENUM('driver','dispatch','system','hos') NOT NULL DEFAULT 'driver',
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `dab_driver_idx` (`driver_id`),
  KEY `dab_company_idx` (`company_id`),
  KEY `dab_window_idx` (`driver_id`,`from_ts`,`to_ts`),
  CONSTRAINT `dab_window_valid` CHECK (`to_ts` > `from_ts`)
);

-- ---------------------------------------------------------------------------
-- 2. driver_weekly_availability (recurring pattern)
-- ---------------------------------------------------------------------------
-- One row per (driver_id, day_of_week, start_min). Multiple rows per day are
-- allowed (split shift, lunch break, etc.). `day_of_week` is 0 = Sunday …
-- 6 = Saturday to match ISO/JS Date.getDay().
CREATE TABLE IF NOT EXISTS `driver_weekly_availability` (
  `id`            INT          NOT NULL AUTO_INCREMENT,
  `driver_id`     INT          NOT NULL,
  `company_id`    INT          NULL,
  `day_of_week`   TINYINT      NOT NULL,
  `start_min`     SMALLINT     NOT NULL,
  `end_min`       SMALLINT     NOT NULL,
  `updated_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                  ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `dwa_driver_dow_start_uk` (`driver_id`,`day_of_week`,`start_min`),
  KEY `dwa_driver_idx` (`driver_id`),
  CONSTRAINT `dwa_dow_range` CHECK (`day_of_week` BETWEEN 0 AND 6),
  CONSTRAINT `dwa_min_range` CHECK (`start_min` >= 0 AND `end_min` <= 1440),
  CONSTRAINT `dwa_slot_valid` CHECK (`end_min` > `start_min`)
);

-- ---------------------------------------------------------------------------
-- 3. dvirs (canonical Wave-4 table; legacy `dvir_reports` kept in place)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `dvirs` (
  `id`                  INT          NOT NULL AUTO_INCREMENT,
  `driver_id`           INT          NOT NULL,
  `vehicle_id`          INT          NOT NULL,
  `trailer_id`          INT          NULL,
  `company_id`          INT          NULL,
  `kind`                ENUM('pre','post') NOT NULL,
  `status`              ENUM('draft','submitted') NOT NULL DEFAULT 'draft',
  `defects`             JSON         NULL,
  `signatures_s3_key`   VARCHAR(500) NULL,
  `inspection_ref_id`   INT          NULL
                          COMMENT 'FK-shaped link to inspections.id (inspections.ts:153) when this DVIR was persisted via inspections.submit',
  `legacy_dvir_id`      INT          NULL
                          COMMENT 'Link to legacy dvir_reports.id (inspections.ts:296-302)',
  `created_at`          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `submitted_at`        DATETIME     NULL,
  PRIMARY KEY (`id`),
  KEY `dvirs_driver_idx` (`driver_id`),
  KEY `dvirs_vehicle_idx` (`vehicle_id`),
  KEY `dvirs_trailer_idx` (`trailer_id`),
  KEY `dvirs_company_idx` (`company_id`),
  KEY `dvirs_status_idx` (`status`),
  KEY `dvirs_inspection_ref_idx` (`inspection_ref_id`)
);

-- ---------------------------------------------------------------------------
-- 4. Signed export tokens (shared by availability.exportICS + dvir.export)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `driver_export_tokens` (
  `id`          INT          NOT NULL AUTO_INCREMENT,
  `driver_id`   INT          NOT NULL,
  `kind`        ENUM('availability_ics','dvir_pdf') NOT NULL,
  `resource_id` VARCHAR(64)  NULL
                  COMMENT 'Optional external key — e.g. the dvir id or week ISO',
  `token`       VARCHAR(64)  NOT NULL,
  `s3_key`      VARCHAR(500) NULL,
  `expires_at`  DATETIME     NOT NULL,
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `det_token_uk` (`token`),
  KEY `det_driver_idx` (`driver_id`),
  KEY `det_expires_idx` (`expires_at`)
);
