# 40 · Intermodal and Cross-Border

**What this covers.** Intermodal (coordinated hand-off across two or more modes — truck, rail, vessel, occasionally barge or air — under a single shipment identifier) and the cross-border components that govern US ↔ MX ↔ CA flows: USMCA, VUCEM, Carta Porte digital stamping, ACE + ACI advanced filings, NOM-087 + NOM-086 (Mexico hazmat), TDG (Canada Transport Dangerous Goods). Covers ocean → rail → truck journey hand-offs, drayage chassis per-diem, warehouse-to-rail ramp logistics, chassis pool coordination, FROB. Source: wave-1 shard `team_RAIL_VESSEL_intermodal` Section 3.

**When you need this.** When a load crosses modes. When a load crosses borders. When scoping any tri-country flow. When the trip involves a chassis pool, a steamship line, a rail carrier, AND a drayage carrier.

**Cross-links.** Rail mode detail: [20_Mode_RAIL/00_Overview.md](./20_Mode_RAIL/00_Overview.md). Vessel mode detail: [30_Mode_VESSEL/00_Overview.md](./30_Mode_VESSEL/00_Overview.md). Truck driver cross-border specifics: [10_Mode_TRUCK/01_Driver.md §9](./10_Mode_TRUCK/01_Driver.md). Backend routers: [03_Backend_API_Contract.md](./03_Backend_API_Contract.md). Third-party integrations (CBP, CBSA, SAT, PHMSA): [06_Third_Party_Integrations.md](./06_Third_Party_Integrations.md).

---

## 1. Mode charter

Intermodal is coordinated hand-off of a single freight journey across two or more modes under a single shipment identifier. Backend exposes via `intermodalShipments, intermodalSegments, intermodalTransfers, intermodalContainers, intermodalChassisTracking` tables, `intermodal.ts` router (8 procedures), legacy `multiModal.ts` router for aggregated dashboards and per-mode operations.

Intermodal uses `protectedProcedure` (not mode-specific) because intermodal operator is cross-mode by definition. Parent `IM-#####` shipment ID; child rail `RS-#####` + vessel `VS-#####` records auto-created by `createIntermodalShipment` based on segment modes.

**iOS screen range: 3500–3599** — Intermodal Home, Journey Builder, Segment Timeline, Transfer Point Map, Chassis Coordination, Cross-Border Docs, Cost Breakdown.

---

## 2. Ocean → Rail → Truck journey hand-offs

Classic trans-Pacific intermodal journey:

1. **Ocean segment (leg 1)**: Shanghai → Los Angeles/Long Beach. Container loaded in Shanghai with master + house BOLs. 14-day transit. Ends at LA/LB terminal with `discharged` status on vessel shipment.
2. **Transfer point 1**: Vessel-to-rail at Pier T (LBCT) or APMT (LA). Container leaves terminal on bomb cart, crosses to on-dock rail facility, stacks on doublestack well car. `intermodalTransfers` record of type `vessel_to_rail`.
3. **Rail segment (leg 2)**: LAXT → Chicago Logistics Park (CHIR) on BNSF's Q-LBCCHC train. 4–5 day transit. Child `railShipments` record tracks rail leg.
4. **Transfer point 2**: Rail-to-truck at Chicago intermodal ramp. Container grounded, chassis mounted, drayage assigned.
5. **Drayage segment (leg 3)**: Ramp to consignee DC. Hours-to-days depending on distance.

Each transfer is a **discrete workflow with handoff of liability, chassis, and demurrage clocks.** Mobile Intermodal Journey screen (3502) renders all three segments on vertical timeline with transfer points as "handshake" nodes.

Backend procedure `intermodal.advanceSegment` handles chain logic: when segment's `completedSegmentId` marked complete, next segment (by `legNumber`) moves from `pending` to `booked`, `intermodalTransfers` record created, parent `intermodalShipments.status` advances through `first_leg_active → at_transfer → second_leg_active → third_leg_active → delivered`.

---

## 3. Drayage leg specifics

**Chassis.** Wheeled frame under the container. Container shipped ocean or rail arrives without a chassis; drayage requires chassis mount. In US post-2009, chassis pools (IEP, DCLI, TRAC, FlexiVan, Milestone) replaced carrier-provided chassis.

Flow: driver picks up chassis from pool, mounts container, delivers, returns chassis (or drops at depot). `intermodalChassisTracking` captures chassis ID, mount location, mount time, return location, return time, per-diem.

**Per-diem.** Chassis rental accrues at $25–$60/day after free time. Mobile Drayage screen (3550) shows live per-diem on every active chassis.

**Free time.** Terminal free time for container before demurrage begins (typically 4 days at LA/LB, 5 days at NY/NJ, 2 days at MX ports). App surfaces as countdown on each active container.

---

## 4. Cross-border — US ↔ MX ↔ CA

### 4.1 USMCA

United States-Mexico-Canada Agreement (in force July 2020, replacing NAFTA). Tariff treatment for North American-origin goods. `cross_border_usmca` MCP tool returns origin rules + duty rates.

Mobile screen **3560 USMCA Certificate Builder** walks shipper through:
- Certifier type (exporter, producer, or importer).
- Origin criteria (A through D).
- Generates USMCA origin certificate PDF.

### 4.2 VUCEM

Ventanilla Única de Comercio Exterior Mexicano — Mexico's Single Window for Foreign Trade. All Mexican customs filings route through VUCEM. `cross_border_vucem` MCP tool + `cross_border_mx_compliance` surfaced in cross-border flow.

### 4.3 Carta Porte digital stamping

Mexican SAT requires all domestic freight movements to carry **Carta Porte (CFDI 4.0 with Complemento Carta Porte 3.0)** with digital stamp (**timbre fiscal digital**).

Mobile Cross-Border Docs screen (3561) captures:
- Origin, destination, distance.
- Commodity by SCFI code.
- Vehicle tag.
- Driver's licencia federal.

Submits to SAT PAC (Proveedor Autorizado de Certificación) for stamping. Returned UUID stored, printable as PDF with CFDI QR code.

### 4.4 ACE and ACI advanced filings

- **ACE (Automated Commercial Environment)** — US CBP's single window for imports + exports. e-Manifest for trucks crossing northbound transmitted **1 hour before arrival**. ACE AMS (Automated Manifest System) handles rail + ocean.
- **ACI (Advanced Commercial Information)** — CBSA equivalent for northbound (into Canada) truck + rail. eManifest mandatory **1 hour before arrival**.

Both consumed via Descartes integration, surfaced at **3562 Cross-Border Manifest**.

---

## 5. NOM-087 + NOM-086 — Mexican hazmat

- **NOM-087-SCT-2/2017** — transportation of hazardous waste. Placarding, manifesto, transporter licensing requirements.
- **NOM-086-SCT2/2004** — lists of hazardous substances + materials for transport regulatory classification.

Mobile cross-border hazmat screen (3563) surfaces applicable NOM references based on UN number, forces Carta Porte hazmat complement when required. `cross_border_nom` MCP tool returns full requirement set.

---

## 6. TDG — Canada Transport Dangerous Goods

Transport Dangerous Goods Regulations (SOR/2001-286) govern hazmat in Canada. TDG requires shipping document with:
- UN number.
- Proper shipping name.
- Class.
- Packing group.
- 24-hour emergency response phone number.

Mobile TDG form (3564) mirrors required fields, retains ERP (Emergency Response Plan) reference for Class 1, 2, 6.1, 6.2, or 7 shipments.

---

## 7. Warehouse-to-rail ramp logistics

A shipper loading a container at their DC for rail origination must coordinate:
(a) Pickup of empty container + chassis from rail-line's yard.
(b) Live load or drop-and-pick at DC.
(c) Return to ramp within ramp's receiving window (typically 48h before cutoff).
(d) Ramp-side gate in.
(e) Consist assignment.

Mobile **Warehouse-to-Ramp** screen (3570) is Gantt of these five sub-steps with cutoff deadlines.

---

## 8. Chassis pool coordination

Three major US pools (IEP, DCLI, TRAC) + regional cooperatives. A driver may pick a chassis from Pool A at origin and return to Pool B at destination **if there's an interop agreement** — otherwise a re-position move is required.

Mobile **Chassis Pool** screen (3571) surfaces pool of origin, destination compatibility, re-position cost if mismatched.

---

## 9. FROB — Freight Remaining On Board

FROB is cargo that remains on a vessel through a US port call because vessel is only calling (not discharging that cargo). Under CBP 19 CFR 4, FROB must be manifested but is exempt from certain import formalities.

Mobile port agent screen (3343) surfaces FROB as distinct list separate from discharge list to prevent accidental gate-in attempts. See [30_Mode_VESSEL/03_Vessel_Port_Agent.md §5](./30_Mode_VESSEL/03_Vessel_Port_Agent.md).

---

## 10. Intermodal mobile UX differences vs trucking

- Trucking dispatch screens are single-segment. Intermodal is inherently multi-segment; primary visualization is **segmented timeline**, not map polyline.
- Mode switches are **named events** (`vessel_to_rail, rail_to_truck`) with required documentation handoffs, not silent continuations. Mobile app treats each as punctuation point with own confirm/complete action.
- **Per-container visibility** necessary; per-load visibility (as in trucking) insufficient — single intermodal shipment may contain multiple containers with independent movement histories.
- Cost breakdowns are multi-party (steamship line + rail carrier + drayage carrier + chassis pool + customs broker). Screen **3580 Cost Breakdown** surfaces full stack via `intermodal.getIntermodalCostBreakdown`.

---

## 11. Doctrine gaps tracked

| Gap | Severity | Owner |
|---|---|---|
| Carta Porte CFDI UUID not stored as structured field | P2 | Cross-border team |
| Chassis pool interop table not seeded | P3 | Drayage team |

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
