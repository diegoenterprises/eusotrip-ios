# 20 · Mode RAIL — Dispatcher

**What this covers.** The `RAIL_DISPATCHER` role — screens 3100–3119, backend procedures consumed, interchange coordination workflow, consist-comb UI (different from trucking load cards), crew-board + train-order messaging. NOT a trucking-dispatch UI in different colors.

**When you need this.** When building 3100–3119. When wiring interchange maps. When scoping any rail dispatcher feature.

**Cross-links.** Mode overview + state machine: [00_Overview.md](./00_Overview.md). Operator (who receives tenders): [01_Rail_Operator.md](./01_Rail_Operator.md). Yard Master (who builds consists the dispatcher plans): [03_Rail_Yard_Master.md](./03_Rail_Yard_Master.md).

---

## 1. iOS screen range

**3100–3119** — Dispatcher Home, Schedule Board, Interchange Map, Consist Builder, Power-Assignment Picker.

- **3100 Dispatcher Home** — consist comb (120 micro-rows collapsing into interchange blocks), not load cards grid.
- **3104 Interchange Map** — near-real-time view of which railroad hands off to which at Chicago Gateway, Memphis Jct, East St Louis, Kansas City, New Orleans Gateway. Each node tappable → mini-tender sheet.
- **3106 Consist Builder** — build/amend consists, order cars, assign blocks.
- **3110 Power-Assignment Picker** — match locomotives to consists.
- **3115 Crew Board & OT Messages** — train-order messages, crew-board events.

---

## 2. Backend procedures consumed

- `rail.getTrainConsists` — list of active consists with status filter (building, departed, in_transit, at_interchange).
- `rail.createConsist` — build new consist by passing `trainId, carrierId, originYardId, destinationYardId`, and ordered `railcarIds[]` (insertion order becomes physical position in consist table).
- `rail.getRailYards` — directory lookup with filters `railroadId, state, country, yardType, hasIntermodal`.
- `rail.getRailTracking` — pulls all events for a shipment, returns last event with `location` payload as current known position.
- `multiModal.getRailSchedules` — aggregated schedule query with railroad + date filters. Reads `railShipments.originRailroad` and `destinationRailroad` to surface interchange railroads.
- `rail.updateRailShipmentStatus` — dispatcher authorized to push `in_transit → at_interchange`, `at_interchange → in_yard`, trigger `interchange_delay` exception holds.

---

## 3. Unique UX considerations vs trucking

**Consist comb, not load cards.** Trucking dispatchers see one driver per load, single polyline. Rail dispatchers see **60–180 railcars per consist** and must visualize block groups (cars destined for same interchange). Dispatcher home uses vertical stack of 120 micro-rows collapsing into interchange blocks — the "consist comb" layout — not load cards grid.

**Interchange coordination is blocking workflow.** Screen 3104 must display in near-real-time which railroad hands off to which at each gateway. Each interchange node tappable, opens mini-tender sheet.

**No direct driver chat equivalent.** Rail conductors dispatched through crew board systems, not SMS. Message tab filters to **crew-board events** and **OT (train-order) messages** rather than direct-to-driver chat.

---

## 4. Message surface

Rail-dispatcher messaging is **NOT** the trucking chat-with-driver model. It is crew-board + train-order (OT) messaging. The conductor receives operating instructions through a canonical radio + signed train-order paper, not through ad-hoc SMS.

EusoTrip's `messages.*` router still handles internal coordination between dispatcher, yard master, broker, shipper — but NOT direct conductor messaging in flight. See [70_Messaging_and_ESANG_AI.md](./../70_Messaging_and_ESANG_AI.md).

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
