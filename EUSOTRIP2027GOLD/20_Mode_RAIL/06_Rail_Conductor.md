# 20 · Mode RAIL — Conductor

**What this covers.** The `RAIL_CONDUCTOR` role — screens 3200–3219, backend procedures, train manifest (must be downloadable for offline), air brake test (FRA 49 CFR 232), radio log, track warrant. Device assumed **mounted in the cab**, bridge mode uses large-text high-contrast rendering legible under direct sunlight through laminated glass.

**When you need this.** When building 3200–3219. When implementing the air-brake test workflow. When wiring offline manifest download for canyon sections (Winslow–Flagstaff, Feather River Canyon, Marias Pass).

**Cross-links.** Mode overview + state machine: [00_Overview.md](./00_Overview.md). Dispatcher (who coordinates via OT messages): [02_Rail_Dispatcher.md](./02_Rail_Dispatcher.md). Yard Master (who builds the consist): [03_Rail_Yard_Master.md](./03_Rail_Yard_Master.md). Offline doctrine (canyon sections, satellite fallback): [../60_Offline_First_and_Pulse_Watch.md](./../60_Offline_First_and_Pulse_Watch.md).

---

## 1. iOS screen range

**3200–3219** — Conductor Home, Train Manifest, Air Brake Test, Radio Log, Track Warrant.

- **3200 Conductor Home** — bridge mode, large-text high-contrast.
- **3201 Train Manifest** — railcar-by-railcar, offline-downloadable. Hazmat placard summary at top, in red, with UN numbers and ERG page references.
- **3202 Air Brake Test** — structured checklist that times the test (Class I is 60 minutes minimum for inspection), records pressure readings (typically 90 psi brake pipe with 15 psi reduction for initial set). Each entry writes to `railInspections` via status procedure with `eventType: "air_brake_test"` and inspector's certificate number.
- **3204 Radio Log** — append-only journal with timestamps for incoming train orders, slow orders, track warrants.
- **3208 Track Warrant** — current warrant display with boundaries, speed restriction, expiration.

---

## 2. Backend procedures consumed

- `rail.getRailShipmentDetail` scoped by consist membership via `consistCars` table.
- `rail.updateRailShipmentStatus` — conductor authorizes `departed → in_transit`, `in_transit → at_interchange` in coordination with dispatcher.
- `rail.getRailTracking` — event timeline as viewed from head-end.
- `rail_compliance_status` (MCP) — pre-departure check of FRA inspection currency.

---

## 3. Train manifest

Real-time railcar-by-railcar listing. **Must be downloadable for offline access** — train will lose LTE in canyon sections (Winslow → Flagstaff, Feather River Canyon, over Marias Pass).

Mobile app must:
- **Pre-cache the full manifest** at the last point of good connectivity.
- **Allow conductor to mark cars as bad order offline**, syncing mark on reconnect.
- **Render hazmat placard summary at top, in red, with UN numbers and ERG page references.**

---

## 4. Air brake test (FRA 49 CFR 232)

FRA 49 CFR 232 requires Class I, II, IA air brake tests at specific intervals. Mobile Air Brake Test screen (3202) is a **structured checklist that**:
- Times the test (Class I is 60 minutes minimum).
- Records pressure readings (typically 90 psi brake pipe with 15 psi reduction for initial set).
- Each entry writes to `railInspections` via status procedure with `eventType: "air_brake_test"` and the inspector's certificate number.

This is a legal-grade workflow. The app cannot skip steps; all pressure readings must be captured; inspector certificate must be verified.

---

## 5. Bridge mode UX

Device assumed mounted in cab. Conductor cannot leave the train unattended except under specific DOT exceptions. Bridge mode:
- Large text, high-contrast.
- Legible under direct sunlight through laminated glass.
- Touch targets oversized for gloved fingers.
- No swipe gestures for destructive actions.

No "chat with customer" workflow — inbound communication is radio-mediated via dispatcher. Radio-log screen (3204) is append-only journal.

---

## 6. Unique UX considerations vs trucking

- Mobile app assumes device mounted in cab, not in hand.
- Large-text, high-contrast "bridge mode."
- Radio-mediated communication (no direct chat with customer or dispatcher outside OT messaging).
- Offline manifest is a first-class requirement.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
