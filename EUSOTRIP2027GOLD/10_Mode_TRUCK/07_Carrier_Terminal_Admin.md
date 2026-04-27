# 10 · Mode TRUCK — Carrier, Terminal, Admin

**What this covers.** The TRUCK carrier-administration cluster — owner-operator carrier, fleet-manager carrier, terminal operator / yard jockey, compliance officer, safety officer, accountant, executive, and admin role definitions. Screen ranges 700–899. Synthesized from the wave-1 shards alongside Driver, Dispatch, Catalyst, Broker, Shipper, Escort. This file is the aggregation of supporting personas that keep the trucking operation running without being the load-handler themselves.

**When you need this.** When a non-driver / non-dispatcher stakeholder role is in play. When wiring fleet management, terminal ops, safety dashboards, or compliance officer surfaces. When a fleet-owner or terminal manager asks what their app looks like.

**Cross-links.** Driver: [01_Driver.md](./01_Driver.md). Dispatch: [02_Dispatch.md](./02_Dispatch.md). Security posture (which these roles enforce): [05_Auth_Security_Compliance.md](./../05_Auth_Security_Compliance.md). Integrations (ELD/FMCSA they watch): [06_Third_Party_Integrations.md](./../06_Third_Party_Integrations.md).

---

## 1. Owner-operator carrier

**Screens: 800–809.** The solo owner-operator is modeled as a `DRIVER` role with `ownerOperator: true` flag and a `companies` record they own. Inherits the 010–099 Driver screen set (see [01_Driver.md](./01_Driver.md)) PLUS 800-series for business-side surfaces:

- **800 Owner-Op Home** — revenue dashboard, tax withholdings YTD, insurance expirations, authority status (MC/DOT).
- **801 IFTA Quarterly** — auto-compiled from `gpsTracking` + `fuelTransactions`.
- **802 Business Expenses** — fuel, tolls, maintenance, meals, per-diem, equipment lease.
- **803 Stripe Connect Dashboard** — linked debit, payout methods, transfer history.
- **804 1099-NEC Vault** — annual tax documents.
- **805 Authority Monitor** — FMCSA CSA, BASIC, insurance expiry, BOC-3, UCR.
- **806 Factoring Relationship** — linked factor, advance history, reserves.
- **807 Truck Financials** — lease-to-own calculator, maintenance cost-per-mile.

Unlike company driver, owner-op sees margin, not just line-haul, on rate-cons. Settlement runs against their Connect account directly. Wallet adds Business tab.

---

## 2. Fleet manager / carrier admin

**Screens: 810–829.** Fleet manager at small-to-mid carrier. Authority scoped by `ADMIN` role within a `companyId`.

- **810 Fleet Dashboard** — live map of all trucks, HOS status per driver, loads in-flight, exceptions queue.
- **811 Driver Roster** — hire, terminate, reassign; CDL/medical/drug-test compliance per driver.
- **812 Vehicle Inventory** — VIN, plate, inspection expirations, maintenance schedule.
- **813 Carrier Authority** — MC/DOT/UCR, BOC-3, insurance certs, bond.
- **814 CSA / BASIC Tracker** — per-BASIC percentile, alert thresholds, intervention plans.
- **815 Settlement Batch Review** — approve weekly batches; driver disputes.
- **816 Fuel Card Admin** — EFS/ComCheck/Wex card management, driver assignments.
- **817 Maintenance Schedule** — PM intervals, Zeun integration, shop network.
- **818 Safety Incidents** — accidents, near-misses, dashcam events.
- **819 Training Programs** — assigned modules, completion rates, expiry monitor.

Heavy web bias — admin actions live on web; mobile surfaces alerts + urgent approvals.

---

## 3. Safety officer

**Screens: 830–849.** `SAFETY_MANAGER` role. Watches fleet-wide safety metrics + regulatory exposure.

- **830 Safety Dashboard** — CSA score trend, crash-free days, HOS violations, inspection outcomes.
- **831 Inspection Archive** — all `inspections` rows for the company, filterable by driver/vehicle/type.
- **832 Roadside Inspection Alerts** — real-time push when DOT officer runs a driver.
- **833 DVIR Reviews** — defect categorization, OOS tracking, repair verification.
- **834 Drug & Alcohol Program** — Clearinghouse queries, random selection audit, refusals.
- **835 Accident Investigation** — incident report intake, preventability determination, root cause.
- **836 Dashcam Event Review** — harsh-event clips, coaching workflow.
- **837 Safety Scorecard Per Driver** — composite safety score, coaching plan.

Safety officer is the point-of-contact when FMCSA audits hit. Every screen captures evidence that survives litigation.

---

## 4. Compliance officer

**Screens: 850–869.** `COMPLIANCE_OFFICER` role. Owns regulatory reporting, not safety.

- **850 Compliance Dashboard** — authority status, insurance, bond, BOC-3, UCR, IRP, IFTA.
- **851 IFTA Filing Workstation** — per-jurisdiction mileage + fuel, quarterly preparation.
- **852 IRP Fleet Registration** — per-state apportionment.
- **853 UCR Annual Filing** — fee calculation by fleet size.
- **854 BOC-3 Roster** — process agent per state.
- **855 HazMat Registration** — PHMSA annual registration, HM-232 security plans.
- **856 FSMA Records** — food-grade carrier attestations, temp-log archives.
- **857 Audit Artifacts** — everything needed for a DOT compliance review, organized by CFR cite.

---

## 5. Terminal manager / yard jockey

**Screens: 700–729.** `TERMINAL_MANAGER` role. Runs a physical terminal (distribution center, cross-dock, rail-served yard).

- **700 Terminal Dashboard** — gate-in queue, dock occupancy, inbound/outbound split.
- **701 Gate Kiosk Companion** — guard-shack tablet view: driver arrivals, appointment lookup, seal verification, PARS/ACI label scan (cross-border).
- **702 Dock Door Board** — which door each load is assigned, dwell time, live loading progress.
- **703 Yard Inventory** — trailers on yard, drop-and-hook pool, spots assigned.
- **704 Yard Jockey Move Queue** — ordered list of spot-to-spot moves; one per line, haptic confirmation.
- **705 Appointment Calendar** — dock-door-level schedule, drag-to-reschedule.
- **706 Seal Verification** — BOL seal number lookup, photograph and log seal at gate-in / gate-out.
- **707 Cross-Dock Assignments** — inbound trailer → outbound lane mapping.
- **708 Terminal Scorecard (driver-facing)** — facility wait times, appointment honor rate, dock courtesy score (what drivers see about this terminal).
- **709 Lumper Authorization** — approve lumper-fee receipts before driver can file accessorial.

**Yard Jockey View (additional, 710–719).** Targeted at the driver moving trailers inside the yard. Dense ops view: spot map, move queue, driver assignments. Voice commands and haptic feedback mandatory (gloves + winter).

---

## 6. Accountant

**Screens: 870–879.** Not a distinct role enum — admins with a finance scope. A/R, A/P, GL posting, payroll.

- **870 Financial Dashboard** — AR aging, AP schedule, monthly cash flow.
- **871 Settlement Approval** — batch approval above threshold.
- **872 Invoice Generation** — shipper invoices, corrections.
- **873 GL Export** — QuickBooks / NetSuite / Dynamics sync.
- **874 Payroll** — W-2 payroll (company drivers), 1099 (owner-ops + Catalysts).
- **875 Tax Documents Vault** — 1099-NEC, 1099-K, 941, W-9s on file.

Mobile-light. Web-primary.

---

## 7. Executive

**Screens: 880–889.** C-suite / general manager. High-level dashboards, not operational.

- **880 Executive Dashboard** — revenue, margin, fleet utilization, safety score, all rolled up.
- **881 Lane Profitability** — per-lane, per-customer margin analytics.
- **882 Carrier Scorecard Rollup** — aggregate vendor performance.
- **883 Customer Scorecard Rollup** — aggregate customer performance.
- **884 Board Report Generator** — quarterly pack template.

Read-only. No mutations from exec mobile surface.

---

## 8. Admin / super-admin

**Screens: 890–899.** `ADMIN` and `SUPER_ADMIN` roles. Platform-side concerns, not individual tenant ops.

- **890 Tenant Admin** — tenant roster, branding config, data isolation verification.
- **891 User Management** — create/suspend/role-change users within tenant.
- **892 Feature Flag Console** — per-tenant, per-user flag evaluation.
- **893 Impersonation (super-admin only)** — audit-logged, time-limited.
- **894 Platform Metrics** — crash-free sessions, API latency, DAU/WAU/MAU.
- **895 Integration Connections** — per-tenant Samsara/Motive/Geotab/ELD tokens.

Super-admin is gated to internal Eusorone staff only. See [05_Auth_Security_Compliance.md §18](./../05_Auth_Security_Compliance.md) for known vulnerabilities + mitigation plan including the hardcoded super-admin email P1 that must be resolved before GA.

---

## 9. Cross-cutting rules for these roles

1. **RBAC-gated.** Every screen in this file is gated by `roleProcedure(...)` — see [03_Backend_API_Contract.md §6](./../03_Backend_API_Contract.md).
2. **Isolation-gated.** Every read is scoped by `ctx.isolation.companyId` (or `linkedCompanies` for broker/factoring) unless explicitly `superAdminProcedure`.
3. **Audit-logged.** Every mutation flows through `autoAudit` — see [05_Auth_Security_Compliance.md §13](./../05_Auth_Security_Compliance.md).
4. **Web-primary.** Mobile is triage-grade. Deep work lives on web. See [91_Web_Mobile_Parity.md](./../91_Web_Mobile_Parity.md).
5. **No mock data.** If backend isn't wired, use `EusoEmptyState(comingSoon:)` rather than fake a screen.
6. **Mode-gated.** TRUCK roles see TRUCK-only data. Rail/Vessel variants of these admin roles exist with `RAIL_*` / `VESSEL_*` enum counterparts where applicable — see [20_Mode_RAIL/00_Overview.md](./../20_Mode_RAIL/00_Overview.md) and [30_Mode_VESSEL/00_Overview.md](./../30_Mode_VESSEL/00_Overview.md).

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
