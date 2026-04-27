# 20 · Mode RAIL — Operator (Carrier)

**What this covers.** The `RAIL_OPERATOR` (CARRIER in rail parlance) role — screens 3120–3139, backend procedures consumed, FRA Hours-of-Service Act (49 USC Chapter 211, distinct from trucking HOS), crew-assignment flow, certifications expiry surface, per-diem tracking on foreign cars.

**When you need this.** When building 3120–3139. When wiring crew scheduling. When a rail operator (carrier) persona is primary.

**Cross-links.** Mode overview + state machine: [00_Overview.md](./00_Overview.md). Conductor view of same shipment: [06_Rail_Conductor.md](./06_Rail_Conductor.md). Lease management: [00_Overview.md §8](./00_Overview.md).

---

## 1. iOS screen range

**3120–3139** — Operator Home, Crew Assignments, Hours-of-Service Act Panel, Power Utilization, Fuel + MGA.

- **3120 Operator Home** — daily pipeline (shipments at each lifecycle stage), crew-on-duty count, certification expiry band.
- **3122 Crew Assignments** — weekly grid, NOT a "find available driver now" search. Assignments scheduled in advance against **assigned pool** or **extra board** systems.
- **3125 HOS Act Panel** — FRA 12/10/276 tracker per assigned crew member.
- **3127 Power Utilization** — locomotive assignments, active tractive effort vs commitment.
- **3130 Fuel + MGA** — per-train fuel draw, miles-per-gallon-adjusted against AAR standard.

---

## 2. Backend procedures consumed

- `rail.getRailShipments` with `carrierId` filter — operator sees only shipments their reporting marks are accountable for.
- `rail.acceptRailBid` — converts pending bid into carrier assignment. Flips shipment to `car_ordered`.
- `rail.updateRailShipmentStatus` — operator authorizes `car_ordered → car_placed`, `loading → loaded`, `loaded → in_consist`, `in_consist → departed`.
- `rail.getRailcars` with `carrierId` filter — equipment pool visibility.
- CloudMoyoCrewService (called server-side by crew-assignment procedures) — mobile operator panel reads back crew duty-hour status, certifications, cert-expiry warnings.
- `railLeaseMgmt.perDiemAccrual` — tracks per-diem for foreign-owned cars on operator's line (default $45/day).

---

## 3. FRA Hours-of-Service Act (49 USC Chapter 211)

Stricter and less forgiving than trucking's FMCSA HOS. Train crew member in "covered service" is limited to **12 consecutive hours on duty** followed by **10 hours off**, with a **276-hour monthly cap** for train and engine service employees.

There is **no 14-hour "clock" with breaks** like trucking — once 12-hour limit reached, crew is **dead on the law** (DOTL) and train stops where it stops.

**Mobile rule**: surface a **red-band banner** on Operator crew panel once any assigned crew member is within 90 minutes of DOTL.

---

## 4. Crew assignment UX

Scheduled in advance against **assigned pool** or **extra board** systems, not dispatched ad-hoc. Screen 3122 is a weekly grid. Operator assigns crew to board positions, tracks acceptances, manages sub-outs.

**Certifications expiry widget** integrated, pulling from `certifications` table filtered by rail roles:
- Air-brake certification — 3-year recurrence typical.
- Engineer certification — 3-year recurrence.
- Conductor certification — 3-year recurrence.

Each certification shown with 90-day warning band.

---

## 5. Unique UX considerations vs trucking

- Crew assignments scheduled in advance, not dispatched ad-hoc. Weekly grid, not real-time search.
- Operator panel integrates certification expiry widget — 90-day warning band per cert type.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
