# 30 · Mode VESSEL — Overview

**What this covers.** The top-level map of the VESSEL mode on EusoTrip — 19-state ocean lifecycle, ISF 10+2 filing gate (enforced in state-transition validator), IMDG Code for hazmat at sea, SOLAS VGM doctrine gap, blank sailings, demurrage, AIS vessel tracking, port pair directory (US, MX, CA), the 6 vessel roles (screens 3300–3419). Source: wave-1 shard `team_RAIL_VESSEL_intermodal`.

**When you need this.** When starting any vessel story, when scoping ISF or VGM, when a vessel PM asks "what's in scope."

**Cross-links.** Per-role files: [01_Vessel_Captain.md](./01_Vessel_Captain.md), [02_Vessel_First_Officer.md](./02_Vessel_First_Officer.md), [03_Vessel_Port_Agent.md](./03_Vessel_Port_Agent.md), [04_Vessel_Shipping_Line_Ops.md](./04_Vessel_Shipping_Line_Ops.md), [05_Vessel_Terminal_Operator.md](./05_Vessel_Terminal_Operator.md), [06_Vessel_NVOCC_Forwarder.md](./06_Vessel_NVOCC_Forwarder.md). Intermodal + vessel-to-rail / vessel-to-truck handoffs: [40_Intermodal_and_Cross_Border.md](./../40_Intermodal_and_Cross_Border.md). Schema: [04_Database_and_Schema.md §5.3](./../04_Database_and_Schema.md).

---

## 1. Mode charter

Vessel mode covers container (FCL + LCL), bulk (dry + liquid), breakbulk, ro-ro, reefer, and project cargo ocean freight. Backend revolves around:

- `vessel_shipments, vessels, ports, port_berths, vessel_voyages, bills_of_lading, customs_declarations`
- `shipping_containers, container_tracking, vessel_freight_rates, vessel_demurrage`
- `vessel_inspections, vessel_insurance, vessel_isps_records, vessel_port_charges`

Integrations: **MarineTraffic** (AIS), **INTTRA** (booking gateway), **Descartes ABI** (US customs), **DTN Marine Weather**, **Avalara HTS** (duty classification), **Oil Price Marine** (bunker fuel indexing).

`vesselShipments.ts` router exposes **30+ procedures** covering creation, status transitions, BOL issuance, customs filings, container movement, ISF 10+2 status, USCG port entry validation, compliance overviews.

---

## 2. 6 vessel roles

| Role | Screen range | File |
|---|---|---|
| `SHIP_CAPTAIN` | 3300–3319 | [01_Vessel_Captain.md](./01_Vessel_Captain.md) |
| `VESSEL_FIRST_OFFICER` (maps to `VESSEL_OPERATOR`) | 3320–3339 | [02_Vessel_First_Officer.md](./02_Vessel_First_Officer.md) |
| `VESSEL_PORT_AGENT` (maps to `PORT_MASTER`) | 3340–3359 | [03_Vessel_Port_Agent.md](./03_Vessel_Port_Agent.md) |
| `VESSEL_SHIPPING_LINE` | 3360–3379 | [04_Vessel_Shipping_Line_Ops.md](./04_Vessel_Shipping_Line_Ops.md) |
| `VESSEL_TERMINAL_OPERATOR` | 3380–3399 | [05_Vessel_Terminal_Operator.md](./05_Vessel_Terminal_Operator.md) |
| `VESSEL_BROKER` / `VESSEL_FORWARDER` (NVOCC) | 3400–3419 | [06_Vessel_NVOCC_Forwarder.md](./06_Vessel_NVOCC_Forwarder.md) |

---

## 3. 19-state vessel lifecycle

Canonical state machine in `vesselShipments.ts` lines 206–224 as `VALID_VESSEL_TRANSITIONS`. Mapping to SKILL §16 slice 04 nomenclature:

1. **`pending`** (API: `booking_requested`) — booking inquiry received.
2. **`confirmed`** (API: `booking_confirmed`) — carrier confirmed slot + equipment.
3. **`documentation`** — BOL draft, ISF draft, export clearance in preparation.
4. **`container_released`** — empty container assigned to shipper, pickup authorized.
5. **`gate_in`** — loaded container passed terminal gate. **ISF 10+2 enforcement gate** (see §4).
6. **`loaded`** (API: `loaded_on_vessel`) — container placed on vessel.
7. **`departed`** — vessel cleared load port.
8. **`in_transit`** — vessel at sea or transiting between ports.
9. **`transshipment`** — container offloaded at intermediate port for relay onto second vessel (common at Singapore, Algeciras, Salalah, Colombo).
10. **`arrived`** — vessel berthed at discharge port.
11. **`discharged`** — container offloaded to terminal yard.
12. **`customs_hold`** — CBP (or foreign customs) placed hold on release.
13. **`customs_cleared`** — cargo cleared for release.
14. **`gate_out`** — container passed outbound gate on drayage chassis.
15. **`delivered`** — container arrived at consignee facility.
16. **`cancelled`** — terminal cancellation.
17. **`rolled`** — booking pushed to later sailing due to blank sailing, capacity constraint, missed CY cutoff. Allowed from `booking_requested, booking_confirmed, container_released, loaded_on_vessel` (if bumped last-minute), `in_transit` (transshipment failure), returns to `booking_confirmed` on replacement sailing.
18. **`invoiced`** — carrier invoice issued.
19. **`settled`** — payment cleared.

---

## 4. ISF 10+2 filing (Importer Security Filing)

Under 19 CFR 149, US importers must file ISF 24 hours before cargo is loaded on vessel at foreign port. The 10 importer-filed elements plus 2 carrier-filed elements give the program its "10+2" name.

**Enforcement encoded directly in state transition validator** at `vesselShipments.ts` lines 232–251: the transition `container_released → gate_in` or `gate_in → loaded_on_vessel` throws `TRPCError PRECONDITION_FAILED` with message:

> "ISF 10+2 filing required before vessel loading. Filing deadline was 24 hours before ETD. CBP penalty risk: $5,000 per violation."

If no matching `customsDeclarations` record of type `import` exists AND the 24h-before-ETD deadline has passed.

Mobile app mirrors on screen 3340 (Port Agent) and NVOCC Booking Detail (3400). Prominent **ISF Status badge** pulls from `vessel.getISFStatus`, renders one of four states:
- `not_filed` — grey badge with "ISF Required" label.
- `filed` — amber badge.
- `cleared` — green badge.
- `overdue` — red badge with warning icon and CBP penalty amount.

---

## 5. IMDG Code — hazmat at sea

IMO's IMDG Code (International Maritime Dangerous Goods Code) governs hazmat stowage, segregation, documentation at sea.

- **Dangerous Goods Declaration (DGD)** mandatory for any hazmat container. `vesselShipments.imdgCode` + `vesselShipments.hazmatClass` fields drive required DGD form at booking time.
- **Segregation table** — IMDG Class 1 (explosives) cannot be stowed near Class 5 (oxidizers), etc. First Officer cargo plan must enforce segregation before marking bay as loaded. Screen 3322 highlights any stowage conflict in red.
- **Placards and labels** — same visual identification regime as rail PHMSA placarding.

---

## 6. SOLAS VGM — Verified Gross Mass — the doctrine gap

SOLAS Chapter VI Regulation 2 (effective July 2016) requires every packed export container have Verified Gross Mass declared by shipper to carrier + terminal before loading. VGM by Method 1 (weigh loaded container) or Method 2 (weigh all contents plus tare). Container without VGM cannot be loaded.

**SKILL §16 GAP — Schema field missing.** The current `vesselShipments` schema does NOT have a `verifiedGrossMassKg` field nor `vgmMethod` nor `vgmSignatoryId`. **Known doctrine gap** identified in this wave.

Until schema extended, VGM capture is **temporarily held in `customsDeclarations.notes`** (unstructured) which is not auditable + not enforceable in state-transition validator.

**Remediation:**
1. Add `vgmKg DECIMAL(10,2)`, `vgmMethod ENUM('method_1','method_2')`, `vgmSignatoryId INT`, `vgmTimestamp DATETIME` to `vesselShipments` table (or child `vesselVGM` 1:1 table).
2. Add VGM-present check to `container_released → gate_in` transition alongside ISF check.
3. Add VGM capture step to screens 3400 (NVOCC) and 3383 (Terminal) writing to new field(s).

**Gap must be resolved before 2027 release. Tracking as P1 in doctrine backlog.**

---

## 7. Blank sailing dashboard and demurrage alerts

- **Blank sailing dashboard** — aggregated from carrier service schedules + industry feeds. `blank_sailing_dashboard` MCP tool surfaced at screen 3361 + alert badge on NVOCC Home when blank affects any active booking.
- **Demurrage alerts** — `vessel.getVesselDemurrage` returns per-shipment charges. Free time at US ports typically 4–5 days; after free time, demurrage escalates at tiered rates ($100–$400/day/container). Mobile alert fires at 24h before free-time expiry with clear action path (schedule drayage, request free-time extension, escalate to customs broker if held).

---

## 8. Container tracking — MarineTraffic, VesselFinder, AIS

Vessel tracking and container tracking are two different problems.
- **Vessel tracking** uses AIS (Automatic Identification System) transponder data aggregated by MarineTraffic, VesselFinder, and commercial providers.
- **Container tracking** requires carrier EDI (IFTMIN/IFTMCS/COPARN/CODECO) or a visibility provider (Project44, FourKites for ocean, Vizion).

Mobile map (3301 captain, 3370 port agent) renders vessel positions as AIS icons + container positions as CY/terminal markers.

---

## 9. Port pair directory

`PORTS` catalog in `multiModal.ts` lines 44–53 is the seed for mobile port picker:

- **USLAX** — Port of Los Angeles
- **USLGB** — Port of Long Beach
- **USNYC/USNWK** — NY/NJ (Port Newark)
- **USSAV** — Savannah
- **USHOU** — Houston
- **USCHA** — Charleston
- **USSEA** — Seattle-Tacoma
- **USOAK** — Oakland

**Mexican gateway ports extension** (added this doctrine cycle):
- **MXVER** — Veracruz
- **MXZLO** — Manzanillo (Pacific hub for Asia imports)
- **MXLZC** — Lazaro Cardenas (primary Pacific intermodal gateway to FXE/CPKCM rail)

**Canadian ports**: **CAVAN** — Vancouver (Pacific gateway), **CAHAL** — Halifax (Atlantic gateway).

Port picker must be searchable by UN/LOCODE, city name, or state/province. Pre-selected default retained in user preferences.

---

## 10. Cross-cutting mobile doctrine (applies to all vessel roles)

- **Offline-first**: render from cached state with visible sync timestamp; queue mutations with optimistic UI; surface sync-pending badge when writes in-flight.
- **Compliance visibility**: for every regulated action (ISF, VGM, placarding, customs), compliance state must be visible BEFORE action commit button. Backend validators are safety nets — mobile UI should never let user reach a server-side rejection.
- **Gamification hooks**: status transitions fire `load_created, load_completed, route_completed, earnings_received` gamification events. Surfaced as achievement toasts after successful transition.
- **WebSocket real-time**: routers emit socket events to `vessel:booking:<id>` rooms on every status change. Mobile subscribes on detail screens, refreshes automatically without pull-to-refresh.

---

## 11. Doctrine gaps tracked to resolution (VESSEL-specific)

| Gap | Severity | Owner |
|---|---|---|
| SOLAS VGM field missing from `vesselShipments` schema | P1 | Platform schema team |
| FROB (Freight Remaining On Board) handling not a distinct state in vessel lifecycle | P2 | Vessel router team |

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
