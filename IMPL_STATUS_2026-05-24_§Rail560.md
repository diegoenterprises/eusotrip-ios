# IMPL_STATUS · 2026-05-24 · §Rail560

## Brick Ported
**560 Rail Live Tracking** — `EusoTrip/Views/Rail/560_RailLiveTracking.swift`  
Rail Engineer · carrier-side live position view for an in-transit shipment.  
Faithful port of `05 Rail/Light-SVG/560 Rail Live Tracking.svg` (Light + Dark).  
CERTIFIED: `_CADENCE_QA_2026-05-24_§rail-recon-634.md` (560–616 verified bar).

---

## Endpoints (CODE ANCHOR)

| Procedure | File:Line | Status | Notes |
|---|---|---|---|
| `railShipments.getRailShipmentDetail` | `railShipments.ts:140` | **EXISTS** | Returns `{...shipment, waybills, events, demurrage, originYard, destinationYard}` |
| `railShipments.getRailTracking` | `railShipments.ts:485` | **EXISTS** | Returns `{events: RailShipmentEvent[], currentLocation: {lat,lng,description}?}` |
| `railShipments.liveTrackShipment` | `railShipments.ts:734` | **EXISTS** | External Class I AEI feed (BNSF/UP/NS/CSX/CPKC/CN); returns `null` if unavailable — bound best-effort, non-blocking |

---

## Registration

- **File written**: `EusoTrip/Views/Rail/560_RailLiveTracking.swift` (425 lines, 17 433 bytes)  
- **Registered via**: `mcp__xcode-tools__XcodeWrite` (auto-adds to project structure)  
- **ContentView.swift**: Added `Rail560` entry to `ProductionScreen.all` at line ~1959  
  `{ p in AnyView(RailLiveTrackingScreen(theme: p, shipmentId: 0)) }`  
- **RailEngineerNavController.swift**: Added `"live_tracking": "Rail560"` to route map  

---

## Build Gate

```
xcodebuild -project EusoTrip.xcodeproj -scheme EusoTrip -destination 'generic/platform=iOS' build
** BUILD SUCCEEDED **   elapsed: ~103 s   errors: 0
```

---

## Screen Summary

- **Header**: back-chevron · tram.fill eyebrow · `IridescentHairline` · shipment number H1 · `StatusPill(.info)` · origin→dest caption
- **Route Arc Card**: `GeometryReader` Bézier canvas — solid gradient arc (origin→live), dashed arc (live→dest), live dot + halo, origin/dest pins; "LIVE · {location}" chip + ETA chip overlay
- **KPI Strip**: 3× `MetricTile` — SPEED / ETA DEST (gradient) / DWELL RISK (semantic color)
- **Events**: `LifecycleCard` with 40×40 icon badge per `RailShipmentEvent` row (type → SF Symbol, description, location, timestamp)
- **Actions**: `CTAButton("Share tracking", leadingIcon: "square.and.arrow.up")` + `CTAButton("Waybill", leadingIcon: "doc.text")`
- **Theme**: Both `Theme.dark` + `Theme.light` #Previews compile; palette tokens only

---

## Data Shape Decisions

- `liveTrackShipment` keyed by `(originRailroad, waybillNumber)` from detail — called `try?` (best-effort; external Class I API returns nil when no EDI feed configured).  
- `RailLocation560` mirrors `railShipmentEvents.location` schema: `{lat, lng, description}`.  
- `shortDate()` handles both `withFractionalSeconds` and plain ISO8601 for server timestamp variance.

---

## Next Backlog Target

**Rail 561** — next certified screen in the 560–616 range.  
Check `~/Desktop/EusoTrip 2027 UI Wireframes/05 Rail/Code/561_*.swift` for triplet + wiring manifest.  
Alternatively escalate to **Vessel 659** per FIRING_STATUS §472 directive.

---

## git status (relevant)

```
?? EusoTrip/Views/Rail/560_RailLiveTracking.swift  (new)
 M EusoTrip/ContentView.swift
 M EusoTrip/Views/Rail/RailEngineerNavController.swift
 M IMPL_STATUS_2026-05-24_§Rail560.md  (new)
```
