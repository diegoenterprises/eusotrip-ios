# 04 · Database and Schema

**What this covers.** The complete MySQL schema doctrine — 380+ tables across eleven functional domains, column-level detail on the critical tables, multi-tenancy model, 3-country data model (USMCA / Carta Porte / ACE/ACI / NOM / VUCEM), 9-vertical satellite tables, 3-mode decomposition (TRUCK / RAIL / VESSEL), the 37-state + 56-tanker-sub-state load machine, ENUM registry, Drizzle wave-files, raw-SQL bootstrap risks, indexing, partitioning, backup, migrations. Sources: wave-1 shard `team_B_agent_3` (introspection against production MySQL).

**When you need this.** Before writing any migration. Before designing a query. Before wiring multi-tenancy. Before onboarding a new vertical or country. Before any `INSERT`/`UPDATE` that might bypass tenancy.

**Cross-links.** Tenancy enforcement in middleware: [03_Backend_API_Contract.md §6](./03_Backend_API_Contract.md). Verticals × countries UX: [50_Verticals_Reference.md](./50_Verticals_Reference.md). Cross-border: [40_Intermodal_and_Cross_Border.md](./40_Intermodal_and_Cross_Border.md). Audit + security: [05_Auth_Security_Compliance.md](./05_Auth_Security_Compliance.md).

---

## 0. Top-level inventory

380+ tables across eleven domains: identity (users, tenants, companies), operations (loads, routes, dispatch), compliance (FMCSA, ADR, IMDG, FSMA), financial (payments, factoring, settlements, 1099), messaging (conversations, channels), gamification (missions, badges, guilds, seasons), asset management (vehicles, trailers, containers, railcars, vessels), telemetry (GPS, reefer_readings, ELD/HOS), integration (DTN, SCADA, portal_access_tokens), palace/memory (palace_drawers, esang_memories, freight_ai_*), cross-border (USMCA, carta_porte, pedimentos, ACE/ACI manifests, VUCEM).

Two naming conventions: **snake_case** (raw SQL, ad-hoc runtime bootstrapped — `haul_lobby_*`) and **lowerCamelCase columns** (Drizzle-managed — `loads`, `users`, `payments`). The mixed convention is historical. Migrations introducing snake_case columns (e.g., `hold_reason`, `held_by`, `held_at`, `previous_state` on `loads`) are raw-SQL hotfixes pre-dating the Drizzle standardization.

---

## 1. Critical tables — column doctrine

### 1.1 `users`

PK `id int auto_increment`. Identity: `openId varchar(64) UNIQUE` (Clerk/Auth0 subject claim), `email varchar(320) UNIQUE`, `name text`. Tenancy: `companyId int FK→companies.id MUL`. Authorization: `role enum(...)` with **24 values** — `SHIPPER, CATALYST, BROKER, DRIVER, DISPATCH, ESCORT, TERMINAL_MANAGER, COMPLIANCE_OFFICER, SAFETY_MANAGER, FACTORING, ADMIN, SUPER_ADMIN, RAIL_SHIPPER, RAIL_CATALYST, RAIL_DISPATCHER, RAIL_ENGINEER, RAIL_CONDUCTOR, RAIL_BROKER, VESSEL_SHIPPER, VESSEL_OPERATOR, PORT_MASTER, SHIP_CAPTAIN, VESSEL_BROKER, CUSTOMS_BROKER`. Lifecycle: `status varchar(20)` (free-form: `active`, `suspended`, `pending_verification`). No soft-delete column — deletion requests require scrubber. Indexes: `email`, `openId`, `companyId`.

### 1.2 `companies`

`id int PK`. `name, legalName varchar(255)`, `dotNumber varchar(50) MUL`, `mcNumber varchar(50) MUL`, `ein varchar(20)`. Address block: `address text, city, state, zipCode, country default 'USA'`. Compliance: `insurancePolicy, insuranceExpiry, twicCard, twicExpiry, hazmatLicense, hazmatExpiry`. `complianceStatus enum('compliant','pending','expired','non_compliant') default 'pending' MUL`. Billing: `stripeAccountId varchar(255)`. Supply-chain meta: `supplyChainRole enum('PRODUCER','REFINER','MARKETER','WHOLESALER','RETAILER','TERMINAL_OPERATOR','TRANSPORTER')`, `marketerType enum('branded','independent','used_oil')`, `supplyChainMeta json`, `supportedModes json` (array of `TRUCK`|`RAIL`|`VESSEL`), `companyCategory enum(15 values)` (`motor_carrier`, `freight_broker`, `owner_operator`, `3pl`, `class_i_railroad`, `class_ii_railroad`, `class_iii_railroad`, `intermodal_marketing`, `rail_broker`, `vocc`, `nvocc`, `ocean_freight_forwarder`, `customs_broker`, `terminal_operator`, `ship_management`). Soft delete: `deletedAt`. Indexes: `dotNumber`, `mcNumber`, `complianceStatus`.

### 1.3 `loads`

Core transactional entity. 57 columns. `id int PK`, `shipperId int NOT NULL MUL FK→users.id`, `catalystId int MUL FK→users.id` (carrier principal), `driverId int MUL`, `vehicleId int`. `loadNumber varchar(50) UNIQUE`. **status enum — 34 values** (see §6). `cargoType enum(17 values)`: `general, hazmat, refrigerated, oversized, liquid, gas, chemicals, petroleum, livestock, vehicles, timber, grain, dry_bulk, food_grade, water, intermodal, cryogenic`.

Hazmat: `hazmatClass varchar(10), unNumber varchar(10), properShippingName varchar(255), packingGroup enum('I','II','III'), technicalName varchar(255), emergencyResponseNumber varchar(10), emergencyPhone varchar(20), hazardClassNumber varchar(10), subsidiaryHazards json, specialPermit varchar(50)`.

Dimensions: `weight decimal(10,2), weightUnit default 'lbs', volume decimal(10,2), volumeUnit default 'gal', distance decimal(10,2), distanceUnit default 'miles'`.

Geo: `pickupLocation json, deliveryLocation json, currentLocation json, route json` (queryable via `JSON_EXTRACT`).

Dates: `pickupDate, deliveryDate, estimatedDeliveryDate, actualDeliveryDate` (timestamp).

Money: `rate decimal(10,2), currency varchar(3) default 'USD'`.

Cross-border: `originCountry enum('US','CA','MX') default 'US', destCountry enum('US','CA','MX') default 'US', isCrossBorder tinyint(1), originState varchar(10) MUL, destState varchar(10) MUL`.

Escort: `requiresEscort tinyint default 0, escortCount int default 0`.
Brokerage: `originalShipperId int, brokerChainDepth int default 0`.
Rail-mode: `originTerminalId int, destinationTerminalId int`.

Hold state (raw SQL hotfix, snake_case): `hold_reason text, held_by int, held_at timestamp, previous_state varchar(30)`.

Optimistic concurrency: `version int default 1`. Soft delete: `deletedAt`. Timestamps: `createdAt, updatedAt`.

Indexes: `status, cargoType, pickupDate, shipperId, catalystId, driverId, originState, destState`.

### 1.4 `payments`

`id int PK`, `loadId int MUL FK→loads.id`, `payerId int MUL FK→users.id`, `payeeId int MUL FK→users.id`, `amount decimal(10,2), currency varchar(3) default 'USD'`. `paymentType enum('load_payment','subscription','refund','payout','escrow','tip')`. `paymentMethod varchar(50)` (free-form mirror of `payment_methods.type`). Stripe: `stripePaymentIntentId varchar(255) MUL`, `stripeChargeId varchar(255)`. `status enum('pending','processing','succeeded','failed','cancelled','refunded') MUL default 'pending'`. `failureReason text, metadata json, isEncrypted tinyint default 0, documentUrl text`.

**No `companyId`** — tenancy inherited via `loadId → loads.shipperId.companyId`, a **tenancy trap** (requires join to filter).

### 1.5 `payment_methods`

`id int PK`, `userId int MUL FK→users.id` (user-scoped, not company-scoped), `stripePaymentMethodId varchar(100)`, `type enum('CARD','BANK_ACCOUNT','ACH','WIRE')`. PCI-safe only: `lastFour varchar(4), brand varchar(50), expiryMonth int, expiryYear int`. UX: `isDefault tinyint, isVerified tinyint, nickname varchar(50)`.

### 1.6 `hos_logs`

ELD-compliant Hours-of-Service event log. `id int PK`, `userId int MUL FK→users.id` (driver). `eventType enum('status_change','violation','break_start','break_end','reset','cycle_restart','edit','annotation') MUL`. Status transition: `fromStatus enum('off_duty','sleeper','driving','on_duty')`, `toStatus` same enum. Geo: `location varchar(255), locationLat decimal(10,6), locationLng decimal(10,6)`. Vehicle telemetry: `odometer decimal(10,1), engineHours decimal(10,1), vehicleId int, loadId int`. `source enum('driver','auto','eld','system','edit') default 'driver'`. Violations: `violationType varchar(50), violationCfr varchar(50)`. Rolling counters: `drivingMinutesAtEvent int, onDutyMinutesAtEvent int, cycleMinutesAtEvent int`. `timezone varchar(64) default 'America/Chicago'`, `annotation text`, `createdAt MUL`.

### 1.7 `tax_1099_records`

Annual US IRS tax form state. `id int PK`, `recordId varchar(100) UNIQUE` (external form ID), `taxYear int MUL`, `formType varchar(20) default '1099-NEC'`, `payeeId int MUL`, `payeeName, payeeEmail, payeeTIN varchar(11)`, `payerName default 'Eusorone Technologies Inc', payerTIN, payerAddress`. Money: `nonemployeeCompensation decimal(12,2), otherIncome decimal(12,2), federalTaxWithheld decimal(12,2), stateTaxWithheld decimal(12,2)`. `status enum('generated','reviewed','filed','corrected','voided') MUL default 'generated'`. Lifecycle: `generatedBy int, generatedAt, filedAt, correctedAt`.

### 1.8 `inspections`

DVIR/roadside/DOT master. `id int PK`, `vehicleId int MUL`, `driverId int MUL`, `companyId int`, `type enum('pre_trip','post_trip','dvir','roadside','annual','dot')`, `status enum('passed','failed','pending') default 'pending'`, `location varchar(255), defectsFound int default 0, oosViolation tinyint default 0`, `completedAt, createdAt`. Line items in `dvir_defect_items` / `dvir_reports`.

### 1.9 `messages` & `conversations`

`messages`: `id`, `conversationId int MUL`, `senderId int MUL`, `messageType enum('text','image','document','location','payment_request','payment_sent','payment_received','job_update','system_notification','voice_message','contact_card') default 'text'`, `content text, metadata json, isEncrypted tinyint, readBy json, createdAt MUL, updatedAt, deletedAt`.

`conversations`: `type enum('direct','group','job','channel','company','support') MUL`, `name, loadId MUL, companyId MUL, participants json, lastMessageAt`. Participant expansion denormalized via `conversation_participants` + `channel_members`.

### 1.10 `tenants`

Multi-tenancy root. `id int PK`, `plan varchar(20)`, `status varchar(20)`. Branding via `tenant_branding` (`tenantId UNIQUE`) and `tenant_data_isolation` (`tenantId MUL`). **Only 3 tables** carry `tenantId`: `tenant_branding`, `tenant_data_isolation`, `tenants` itself. All other tables rely on `companyId → tenantId` resolution in isolation middleware.

### 1.11 `vehicles`

`id int PK`, `companyId int MUL`, `vin varchar(17)`, `vehicleType enum(36 values)` covering every vertical: `tractor, trailer, tanker, flatbed, refrigerated, dry_van, lowboy, step_deck, hopper, pneumatic, end_dump, intermodal_chassis, curtain_side, pilot_car, escort_truck, height_pole_vehicle, route_survey_vehicle, reefer, auto_carrier, car_hauler, moving_van, log_trailer, livestock_trailer, grain_trailer, dump_trailer, container_chassis, conestoga, rgn, double_drop, roll_off, box_truck, specialized, oversize, chemical_tanker, stock_trailer, pole_trailer`. `status enum('available','in_use','maintenance','out_of_service')`. Trailers live in separate `vehicles` rows with `vehicleType='trailer'|<subtype>` **or** in `containers` / `railcars` / `vessels` for intermodal and rail/marine.

### 1.12 `factoring_invoices`

`id int PK`, `loadId int MUL`, `catalystUserId int MUL`, `shipperUserId int`, `factoringCompanyId int`. `invoiceNumber varchar(50) UNIQUE`, `invoiceAmount decimal(10,2)`. Fee model: `advanceRate decimal(5,2) default 97.00`, `factoringFeePercent decimal(5,2) default 3.00`, `factoringFeeAmount, advanceAmount, reserveAmount` all `decimal(10,2)`. `status enum('submitted','under_review','approved','funded','collection','collected','short_paid','disputed','chargedback','closed') MUL default 'submitted'`. Lifecycle: `submittedAt, approvedAt, fundedAt, collectedAt, collectedAmount, dueDate`. Docs: `supportingDocs json, notes text`.

### 1.13 `missions`, `badges`, `user_badges`, `gamification_profiles`

`badges`: `code varchar(100) UNIQUE, name, description, category enum('milestone','performance','specialty','seasonal','epic','legendary'), tier enum('bronze','silver','gold','platinum','diamond') default 'bronze', iconUrl, criteria json, xpValue int default 0, isRare tinyint, sortOrder int, isActive tinyint default 1`.

`gamification_profiles`: one row per user (`userId UNIQUE`). `level int default 1 MUL`, `currentXp, totalXp, xpToNextLevel default 1000`, `totalMilesEarned decimal(14,2), currentMiles decimal(14,2)`, `activeTitle varchar(100), rank int MUL, streakDays, longestStreak, lastActivityAt, seasonalRank, seasonalXp, stats json`.

Missions: progress in `mission_progress`. Badges: `user_badges (userId, badgeId, awardedAt, season)`.

### 1.14 `zeun_breakdowns` (physical: `zeun_breakdown_reports`)

Roadside repair workflow. `status enum('REPORTED','DIAGNOSED','ACKNOWLEDGED','EN_ROUTE_TO_SHOP','AT_SHOP','UNDER_REPAIR','WAITING_PARTS','RESOLVED','CANCELLED')`. Companion: `zeun_breakdown_status_history`, `zeun_diagnostic_results`, `zeun_repair_providers`, `zeun_maintenance_logs`, `zeun_fleet_maintenance_schedules`, `zeun_provider_reviews`, `zeun_vehicle_recalls`.

---

## 2. Multi-tenancy doctrine

**Two-axis model**: `tenantId` (white-label / reseller) and `companyId` (motor carrier / shipper / broker entity inside a tenant). Introspection: **98 tables carry `companyId`**, only **3 tables carry `tenantId`** (`tenants`, `tenant_branding`, `tenant_data_isolation`). Deliberate: `tenantId` resolved once per request by isolation middleware at edge, cached; downstream queries filter by `companyId IN (<companies_in_tenant>)`. `tenant_data_isolation` holds `tenantId → companyId[]` mapping.

### `isolationMiddleware` contract

1. Extract JWT claim `user.companyId` and `user.tenantId`.
2. If `/api/admin/*` → require `role IN ('SUPER_ADMIN')`, skip filtering.
3. For any ORM query on a `companyId` table, inject `WHERE companyId = :ctx.companyId`.
4. For tables without `companyId` (`payments`, `inspections`, `factoring_invoices`), apply join-based filter through foreign table (`loads.shipperId → users.companyId`).
5. For `messages`, filter via `conversations.companyId`.
6. Cross-tenant reads (marketplace loadboard) whitelist explicit `shared=true` flag and set `SET @allow_cross_tenant=1` for query duration.

**Data-leak risk tables** (no `companyId` AND no obvious join guard) — must be manually audited. Red flags: `hos_logs` (user-scoped, safe), `payments` (loads join), `tax_1099_records` (payeeId join), `gps_tracking` (check at query time), `gamification_profiles` (user-scoped, safe).

---

## 3. The 3-country data model

Every load carries `originCountry enum('US','CA','MX')` and `destCountry enum('US','CA','MX')` plus `isCrossBorder tinyint`. Rich data in satellite tables:

- **`carta_porte`** — Mexican SAT CFDI 4.0 Complemento Carta Porte 3.x. XML UUID, RFC of emisor/receptor, UN-code, peso bruto total, DG attributes. Required for any load where `originCountry='MX'` OR `destCountry='MX'` AND mode=TRUCK.
- **`pedimentos`** — Mexican customs entry/exit declarations with `agenteAduanalId FK→agentes_aduanales.id`.
- **`ace_manifests`** — US CBP ACE manifests (required US-bound from CA/MX).
- **`aci_manifests`** — Canada CBSA ACI (Canada-bound).
- **`customs_declarations`** — generic for USMCA Certification of Origin attestations. Carries `usmcaCertified tinyint, producerName, blanketPeriodFrom/To`.
- **`border_crossings`** + **`state_crossings`** — GPS-anchored events with port-of-entry code, FAST/SENTRI/C-TPAT trusted-program attribution.
- **`agentes_aduanales`** — Mexican customs broker roster.
- **`mexican_insurance_policies`** — required for trucks operating south of the border (Qualitas, HDI, Zurich, ANA, GNP).

**NOM (Normas Oficiales Mexicanas)** in `vehicles` supplementary JSON + `compliance_events` with `regulation='NOM-012-SCT-2'` (weights), `NOM-068-SCT-2` (physical inspection), `NOM-087-SCT-2` (placarding).

**VUCEM** connection state in `integration_connections` with `providerId → integration_providers.code='VUCEM'`; synced records in `integration_synced_records` and `integration_sync_logs`.

Currency: `exchange_rates` (daily FX USD/CAD/MXN), `cross_border_currency`, `cross_border_mx_taxes` (IVA/ISR withholding).

---

## 4. 9 verticals

1. **Hazmat** — `loads.hazmatClass, unNumber, properShippingName, packingGroup, technicalName, emergencyPhone, hazardClassNumber, subsidiaryHazards, specialPermit`. Reference: `erg_guides, erg_materials, erg_protective_distances`. Driver: `adr_driver_certifications, adr_compliance`. Placard runtime-derived from `hazmatClass + packingGroup`.

2. **Reefer** — `reefer_readings` (ambient/setpoint/return-air every N sec), `reefer_alerts`, `fsma_temp_logs` (FDA FSMA 21 CFR 1), `product_profiles` (temp-window per SKU), `usda_holds`. Alerts bubble to `notifications` + SMS.

3. **Flatbed** — tarp SKUs, strap/chain counts, securement photos in `loads.documents json` and `bills_of_lading`. `vehicles.vehicleType IN ('flatbed','step_deck','lowboy','rgn','double_drop','conestoga')`. Oversize/overweight permits in `permits_records`.

4. **Livestock** — `vehicles.vehicleType IN ('livestock_trailer','stock_trailer')`. HOS livestock exemption in `hos_logs.annotation`; welfare stops captured as `eventType='annotation'`. USDA VS Form 1-27 attestations in `documents` typed `type='vet_certificate'`.

5. **Auto-hauler** — `vehicles.vehicleType IN ('auto_carrier','car_hauler','moving_van')`. Per-unit VIN manifest in `bills_of_lading.lineItems json` with position and OEM routing codes.

6. **LTL** — `load_relay_legs` (multi-stop), `cross_dock_operations`. NMFC class + freight-class in `pricebook_entries`.

7. **Tanker** — `crude_oil_specs` (API gravity, sulfur, BS&W), `custody_transfers` (gauger tickets), `scada_transactions + scada_alarms` (SCADA/LACT meter), `run_tickets + run_ticket_expenses`. Tanker sub-states in `loads.previous_state` (lowercase, see §6.2).

8. **Intermodal** — `containers, intermodal_containers, intermodal_segments, intermodal_chassis_tracking, intermodal_shipments, intermodal_transfers, container_tracking`. Container ID = ISO 6346 owner code + 6-digit serial + check digit.

9. **General** — `cargoType='general'` with free-form dimensions; base `loads` columns only.

Cross-cutting: `inspections.type enum` + `defectsFound` counter. `dvir_defect_items.component enum` granular codes.

---

## 5. 3 Modes

### 5.1 TRUCK

Default. §1 and §4 assume TRUCK. Powered by `loads, hos_logs, vehicles, drivers, dvir_reports, fmcsa_*` (carrier-safety feeds), `geofences, gps_tracking, geotags`.

### 5.2 RAIL — 19-state lifecycle + FRA/PHMSA/STCC

Tables: `rail_shipments, rail_shipment_events, rail_waybills, rail_carriers, rail_yards, railcars, train_consists, rail_crew_assignments, rail_demurrage`.

**19-step lifecycle** in `rail_shipments.status`: `ORDERED, BILL_OF_LADING_ISSUED, CAR_ORDERED, EMPTY_CAR_PLACED, LOADING, LOADED, RELEASED_TO_CARRIER, IN_TRANSIT, INTERCHANGE, HUMPED, BLOCKED, BAD_ORDER, CONSTRUCTIVELY_PLACED, ACTUAL_PLACEMENT, HOLD, UNLOADED, RELEASED_EMPTY, RETURNED, CLOSED`.

Roles: `RAIL_SHIPPER, RAIL_CATALYST, RAIL_DISPATCHER, RAIL_ENGINEER, RAIL_CONDUCTOR, RAIL_BROKER`. FRA-reportable accidents → `safety_incidents` with `regulator='FRA'`. PHMSA hazmat rail → `hz_hazmat_incidents`. STCC (Standard Transportation Commodity Code) on `rail_waybills.stcc varchar(7)`; AAR-code on `railcars.aarCode`.

### 5.3 VESSEL — ISF 10+2, IMDG, VGM, SOLAS

Tables: `vessel_shipments, vessel_shipment_events, vessel_voyages, vessel_berth_assignments, vessel_demurrage, vessel_freight_rates, vessel_inspections, vessel_insurance, vessel_isps_records, vessel_port_charges, vessels, port_berths, ports`.

Compliance: **ISF 10+2** (CBP Importer Security Filing, 10 shipper + 2 carrier data elements) in `customs_declarations` flagged `type='ISF_10_2'`. **IMDG** in `imdg_compliance`. **VGM** (SOLAS May 2016) on `shipping_containers.vgmKg decimal(10,2)` + `vgmMethod enum('method_1','method_2')`. **SOLAS** inspection records in `vessel_inspections.type='SOLAS'`.

Roles: `VESSEL_SHIPPER, VESSEL_OPERATOR, PORT_MASTER, SHIP_CAPTAIN, VESSEL_BROKER, CUSTOMS_BROKER`.

`companies.supportedModes json` declares which modes a company is configured for; frontend hides unsupported-mode UI by reading this.

---

## 6. The load state machine

### 6.1 Primary `loads.status` — 34 physical + 3 derived = 37 states

**34 physical enum values**: `draft, posted, bidding, expired, awarded, declined, lapsed, accepted, assigned, confirmed, en_route_pickup, at_pickup, pickup_checkin, loading, loading_exception, loaded, in_transit, transit_hold, transit_exception, at_delivery, delivery_checkin, unloading, unloading_exception, unloaded, pod_pending, pod_rejected, delivered, invoiced, disputed, paid, complete, cancelled, on_hold`.

**3 derived states** (recognized by state machine, not physical): `QUEUED` (draft + scheduled-post timestamp future), `REBOOKED` (reassignment after cancelled), `ARCHIVED` (complete + retention-period elapsed).

Business logic uppercases for logs/events: `LOAD_STATUS_CHANGE from=IN_TRANSIT to=AT_DELIVERY`.

### 6.2 Tanker sub-states — 56 lowercase values

Tanker mode shards `in_transit` and `loading`/`unloading` macro-states into 56 sub-states stored in `loads.previous_state varchar(30)` (repurposed) and ticker-logged into `scada_transactions.sub_state`:

`prewash_requested, prewash_in_progress, prewash_complete, prewash_failed, wash_ticket_attached, residue_declared, vapor_recovered, vapor_failed, seal_applied, seal_verified, seal_broken, pre_load_gauge, pre_load_sample_taken, pre_load_sample_passed, pre_load_sample_failed, loading_start, loading_paused, loading_resumed, loading_overfill_alarm, loading_end, post_load_gauge, post_load_sample_taken, post_load_bol_issued, in_transit_normal, in_transit_temp_deviation, in_transit_pressure_deviation, in_transit_route_deviation, in_transit_agitation_required, in_transit_heating_on, in_transit_heating_off, in_transit_nitrogen_purge, in_transit_geofence_entry, in_transit_geofence_exit, at_terminal_queued, at_terminal_bay_assigned, at_terminal_gauge_pre, at_terminal_sample_pre, unloading_start, unloading_paused, unloading_resumed, unloading_end, unloading_overfill_alarm, post_unload_gauge, post_unload_sample, post_unload_dry, post_unload_heel_declared, postwash_requested, postwash_in_progress, postwash_complete, bol_signed_consignor, bol_signed_consignee, pod_uploaded, pod_verified, inspection_passed, inspection_failed, settlement_ready`.

Referenced by SCADA automation and LACT/custody-transfer workflows. Not primary status — supplemental.

---

## 7. ENUM registry

- `payment_type` (`payments.paymentType`): `load_payment, subscription, refund, payout, escrow, tip`.
- `payment_status` (`payments.status`): `pending, processing, succeeded, failed, cancelled, refunded`.
- `payment_method_type` (`payment_methods.type`): `CARD, BANK_ACCOUNT, ACH, WIRE`.
- `load_status`: see §6.1.
- `cargo_type` (`loads.cargoType`): 17 values, §1.3.
- `hos_event_type`: `status_change, violation, break_start, break_end, reset, cycle_restart, edit, annotation`.
- `hos_status` (from/to): `off_duty, sleeper, driving, on_duty`.
- `hos_source`: `driver, auto, eld, system, edit`.
- `dvir_result` (`inspections.status`): `passed, failed, pending`.
- `inspection_type`: `pre_trip, post_trip, dvir, roadside, annual, dot`.
- `user_role`: 24 values, §1.1.
- `company_category`: 15 values, §1.2.
- `supply_chain_role`: 7 values, §1.2.
- `country`: `US, CA, MX`.
- `packing_group`: `I, II, III`.
- `message_type`: 11 values, §1.9.
- `conversation_type`: `direct, group, job, channel, company, support`.
- `compliance_status`: `compliant, pending, expired, non_compliant`.
- `factoring_status`: 10 values, §1.12.
- `1099_status`: `generated, reviewed, filed, corrected, voided`.
- `badge_category`: `milestone, performance, specialty, seasonal, epic, legendary`.
- `badge_tier`: `bronze, silver, gold, platinum, diamond`.
- `vehicle_status`: `available, in_use, maintenance, out_of_service`.
- `vehicle_type`: 36 values, §1.11.
- `zeun_breakdown_status`: 9 values, §1.14.

---

## 8. Drizzle `schema.additions.wave4-8.ts` — prod gap

Drizzle repo declares additions split across `schema.ts, schema.additions.wave4.ts, wave5, wave6, wave7, wave8`. Wave-files hold emerging tables — `autonomous_vehicles, av_telemetry, convoys, swarm_proposals, swarm_surface_ownership, palace_meta_lessons, freight_ai_profiles, freight_ai_conversations, glasswing_scans, glasswing_findings, glasswing_certificates, catalyst_risk_scores, blockchain_audit_trail, experiments, experiment_results, variant_assignments, autopilot_*` (9 tables) — **declared in TS but not guaranteed present in every prod environment**.

Introspection confirms all physically present in primary MySQL, but edge replicas and staging UAT sometimes lag 1–2 waves. Manually tracked; no automated drift-detection job.

**Action**: before querying any `schema.additions.wave*` table, run preflight existence check in non-prod OR wrap in try/catch. Close by instrumenting nightly `schema_drift` MV comparing `information_schema.TABLES` to Drizzle declared-tables.

---

## 9. Raw-SQL tables (`haul_lobby_*`) bootstrapped at runtime

Three tables created lazily by chat module, NOT Drizzle migrations: `haul_lobby_messages, haul_lobby_moderation_log, haul_lobby_user_strikes`. `CREATE TABLE IF NOT EXISTS` in `server/chat/haul-lobby/bootstrap.ts` on first request.

**Risk profile:**
- **Drift risk**: columns added via raw `ALTER TABLE` don't flow into Drizzle `schema.ts`; TS types hand-maintained.
- **Migration-gap risk**: `pnpm db:push` won't see; drizzle-kit introspect ignores unless manually added.
- **Backup risk**: IS included in Azure PITR but logical dumps skip bootstrap unless first chat request fires.
- **Permission risk**: app DB user needs `CREATE TABLE` privilege at runtime — violates least-privilege.

**Mitigation**: fold into `schema.additions.wave9.ts`, remove runtime DDL, drop `CREATE` grants.

---

## 10. Indexing strategy

### 10.1 What IS indexed

- Every FK: `companyId, userId, loadId, vehicleId, driverId, conversationId, senderId, shipperId, catalystId, payerId, payeeId` — `MUL` index.
- High-cardinality enum status: `loads.status, loads.cargoType, payments.status, companies.complianceStatus, hos_logs.eventType, factoring_invoices.status, tax_1099_records.taxYear`.
- Time-range: `loads.pickupDate, messages.createdAt, hos_logs.createdAt`.
- Unique business keys: `users.email, users.openId, loads.loadNumber, factoring_invoices.invoiceNumber, tax_1099_records.recordId, payments.stripePaymentIntentId`.
- State composite for load board: `loads.originState, loads.destState` separately (no composite yet).

### 10.2 What SHOULD be indexed (mobile hot paths)

- Composite **`(driverId, status, pickupDate)`** on `loads` for "my upcoming loads."
- Composite **`(userId, createdAt DESC)`** on `hos_logs` for graph-grid render.
- Composite **`(conversationId, createdAt DESC)`** on `messages` (partial coverage causes filesort on pagination).
- Composite **`(companyId, status, updatedAt DESC)`** on `loads` for dispatcher board.
- Covering **`(vehicleId, completedAt DESC) INCLUDE (status, type)`** on `inspections` for DVIR history.
- Spatial / JSON on `loads.currentLocation->>'$.lat'/'$.lng'` for geo-radius queries.
- **`(payeeId, taxYear, status)`** on `tax_1099_records` for driver year-end portal.
- Partial index `WHERE deletedAt IS NULL` (MySQL 8 functional) on all soft-delete tables to avoid tombstone scans.

---

## 11. Partitioning

**Current state: no active partitioning detected** for `payments` or hot-write tables. Azure MySQL Flexible Server 8.0 supports RANGE partitioning; not enabled.

Recommendation:
- **`payments`** — monthly RANGE on `createdAt` once row count crosses ~20M (current <5M).
- **`orb_telemetry`** + `gps_tracking, reefer_readings, av_telemetry, location_breadcrumbs` — weekly/daily RANGE on `recordedAt`. Already exceed 100M rows in prod; un-partitioned forces full-table scans.
- **`hos_logs`** — yearly RANGE on `createdAt`, aligned with FMCSA 6-month + 6-month buffer.
- **`audit_logs`** — monthly RANGE on `createdAt`.

Partitioning enables `DROP PARTITION` for retention housekeeping — dramatically faster than DELETE.

---

## 12. Backup / Restore — Azure MySQL PITR

- **Backup retention**: 35 days (max for SKU). Binary log + automated full backup every 24h + log backup every 5 min.
- **Geo-redundant**: enabled; replica in paired region for DR.
- **RPO**: 5 min. **RTO**: ~15 min for same-region PITR to new server name.
- **Restore**: `az mysql flexible-server restore --source-server eusotrip-prod --restore-time <ISO8601> --name eusotrip-restore-<date>`, then DNS cutover via Azure Front Door.
- **Test cadence**: quarterly DR drill, logged in `audit_logs` with `event='DR_DRILL'`.
- **Long-term archival**: weekly `mysqldump --single-transaction --routines --triggers --events` to Azure Blob archive tier, retained 7 years (IRS + FMCSA-aligned).
- **Caveat**: bootstrapped tables (`haul_lobby_*`, §9) ARE in PITR but NOT logical dumps unless explicitly listed. Switch to `mysqldump --all-databases` or add to include-list.

---

## 13. Migration contract

Canonical flow via **drizzle-kit**:

- **`pnpm db:push`** — local dev + ephemeral previews. Directly reconciles `schema.ts + schema.additions.wave*.ts` against target. Fast but destructive-capable (DROPs columns). **Never against production.**
- **`pnpm db:generate`** — produces timestamped SQL migration file in `drizzle/migrations/`. PR-reviewed.
- **`pnpm db:migrate`** — applies pending migrations in order, state in `__drizzle_migrations`. Production path.

**Production rules:**
1. All prod changes: `db:generate` → PR → review → merge → `db:migrate` in deploy pipeline.
2. `db:push` gated by env check (`NODE_ENV !== 'production'`) in package script.
3. Destructive changes (DROP COLUMN, rename, type-narrow) require **two-phase migration**: first make column nullable / add new, dual-write for a release, then drop. State-machine tables (`loads.status`) never modified without full app freeze.
4. `__drizzle_migrations` is source of truth; drift detection compares hash against repo.
5. Raw-SQL hotfixes (`hold_reason/held_by/held_at/previous_state` on loads) discouraged — folded back into `schema.ts` next release cycle.
6. `schema.additions.wave*.ts` files merged into `schema.ts` once wave fully deployed everywhere; wave files become empty passthroughs or deleted.

**Verification checklist (before any migration PR merges):**

- [ ] Runs cleanly on restored PITR snapshot of prod (staging-mirror).
- [ ] Does not drop any column in use by currently-deployed app version.
- [ ] All added tables include `createdAt, updatedAt`, and either `companyId` (tenant-scoped) or documented tenancy-via-join path.
- [ ] All added ENUM values are additive only (never remove a value with existing rows).
- [ ] Any index added to a hot-write table (>10k inserts/day) validated via `EXPLAIN ANALYZE` first.
- [ ] `schema.ts` diff reviewed alongside `.sql` diff — they must agree.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
