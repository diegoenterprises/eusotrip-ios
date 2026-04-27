# Wave-3 Agent 09 — Bucket 09 Audit (Navigation / Route Overview / Traffic / Fuel Stops)

Screens audited: `116 Navigation.png`, `117 Route Overview.png`, `118 Traffic.png`, `119 Fuel Stops.png`
Light + Dark reads from `/Users/diegousoro/Desktop/EusoTrip 2027 UI Wireframes/01 Driver/{Light,Dark}/`.
Backend base: `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/`.
Swift port base: `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip/Views/Driver/`.

---

## 116 Navigation.png
**Swift port:** NONE. `Views/Driver/` only contains `010_DriverHome..022_DockAssigned`. No `Navigation.swift`, no `016_*` beyond pickup screens. Closest analogue is `013_ActiveEnroute.swift` (en-route map shell) which already consumes HERE Routing.
**Purpose:** Full-screen live turn-by-turn navigation. Light register = live driving (14:57, "Live Nav to Marcus Hook", GPS Lock, 0.3 mi to "Right onto Pulaski Hwy / US-40", lane guide, slowdown/construction cards, Mute voice / Reroute around). Dark register = post-drive replay (22:57, "Last Route · Paused", drop reached, events log with fuel stop, AI summary, Replay route / Plan tomorrow).

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Status chip `LIVE NAV to <destination>` / `LAST ROUTE · PAUSED` | Current route status + destination | `navigation.getRoute` (loadId) — `/frontend/server/routers/navigation.ts:81` + `routes.status` enum schema.ts:2919 | Works if route row exists |
| `GPS LOCK` indicator | GPS fix quality | GAP — no procedure for GPS signal/accuracy; Swift layer only |
| Next maneuver `0.3 mi — Right onto Pulaski Hwy / US-40` | Turn-by-turn step | GAP — `navigation.calculateRoute` stores `polyline` but no turn-by-turn steps/maneuver table. HERE `actions` return field is requested in Swift `HereRoutingClient.swift:57` but no backend persistence or relay procedure | Swift can hit HERE directly; no server fallback |
| "Then 18.2 mi to dock 4 · stay right 2 lanes" subtext | Subsequent maneuver / lane instruction | GAP — no lane guidance / next-next maneuver procedure |
| Lane guide arrows (`↑ ↑ ↑ ↗`) | Lane-level guidance | GAP — requires HERE `advanceNotice`/`laneInfo` actions; no backend proc |
| Map polyline with current position (live dot) | Route geometry + current lat/lng | `navigation.getRoute` returns polyline navigation.ts:102; `navigation.updateETA` consumes current lat/lng navigation.ts:144 | Polyline is 2-point (origin;dest), not real-road geometry |
| "I-95 N · 63 MPH" speed + speed-limit sign | Current speed, posted speed limit | GAP — no procedure for speed limit by segment; HERE spans request it (HereRoutingClient.swift:59) but nothing server-side |
| Progress pill `Dock 4 · 16:32 ETA` | ETA to next waypoint | `navigation.getETA` navigation.ts:123 |
| `ETA 16:30` / `REPLAY 16:18` | Predicted ETA | `navigation.getETA` navigation.ts:123 |
| `18.5 mi REMAINING` / `47.2 mi TOTAL` | Remaining miles | `navigation.getETA.remainingMiles` navigation.ts:134 |
| `+12 min` / `+0 min MM 81 SLOW` change-vs-prior | ETA delta + reason | `navigation.getETA.changeMinutes`+`changeReason` navigation.ts:137–138 |
| ON THE ROUTE section header with `2 AHEAD` count | Incidents ahead counter | GAP — `traffic.getIncidents` returns `[]` (traffic.ts:19); no ahead-only filter |
| `Slowdown — I-95 N MM 81 · in 7.4 mi` incident card | Traffic slowdown | GAP — `traffic.getDelays` stub (traffic.ts:33) returns `{avgDelay:0,routes:[]}`; `routes.getConditions` pulls NWS weather only (routes.ts:303), not traffic |
| `Construction zone — MM 86–88 · 45 mph speed limit · no shoulder · in 9.1 mi` | Construction zone | GAP — `traffic.getConstruction` stub returns `[]` (traffic.ts:24). `hz_road_conditions` table queried by `trafficNerve` service (autopilot/agents/sensory/trafficNerve.ts:79) but no router exposes it |
| AI coach card `"MM 81 slowdown adds ~12 min but holds 16:30 ETA…"` | AI-generated rerouting suggestion with trade-off | GAP — no esangAI/autopilot procedure returning route-level suggestion text (trafficNerve publishes events but no query) |
| `Mute voice` button | Toggle TTS | GAP — no voice pref procedure (no `driverMobile.muteVoice` / `userPrefs.*`) |
| `Reroute around` button | Request alternate route avoiding incident | GAP — no `reroute` / `avoidIncident` mutation. `routing.calculateRoute` (routing.ts:70) recomputes cold but can't take "avoid MM 81" input |
| (Dark) `Drop reached` pill at 16:18 | Waypoint status | `navigation.updateWaypointStatus` (status=arrived) navigation.ts:216 |
| (Dark) Events log entries `Reached drop on time`, `Fuel — Pilot Carlisle · +42 gal · saved $14` | Post-trip events + savings | PARTIAL — fuel events stored via `fuel.reportPurchase` fuel.ts:255; arrival via waypoint status; but no unified "trip events log" query. GAP — savings calculation ("saved $14") has no backend |
| (Dark) `Today's log · 2 routes, both within 1 min of ETA…` AI summary | Daily AI trip recap | GAP — no procedure (autopilot `narrator.ts` generates narrative but no router surface for driver-daily) |
| (Dark) `Replay route` button | Load stored route for scrub | `navigation.getRoute` (loadId/routeId) navigation.ts:81 | No polyline history playback; only current polyline |
| (Dark) `Plan tomorrow` button | Open next-day planner | GAP — no "plan tomorrow" procedure; navigation to planner screen only |
| Tab bar HOME · TRIPS · (center) · WALLET · ME | Navigation | Out-of-scope shell |

### Backend GAPS (numbered)
1. Turn-by-turn maneuver persistence/feed (HERE actions not relayed server-side).
2. Lane guidance feed.
3. Posted-speed-limit feed.
4. Real-road polyline (current stores 2-point `lat,lng;lat,lng`, navigation.ts:46).
5. `traffic.getIncidents`, `getConstruction`, `getDelays` are stubs returning empty (`traffic.ts:15–38`).
6. No router exposes `hz_road_conditions` (used only by `trafficNerve` autopilot agent).
7. "Ahead on route" spatial filter (distance-along-route) nonexistent.
8. `reroute around` mutation absent — no way to apply an avoid-incident replan.
9. Mute / voice-preference procedure absent.
10. AI coach card (route-level trade-off text) has no router surface.
11. Savings attribution ("saved $14") has no procedure.
12. `Replay route` has no historical polyline; only latest route row is kept per load.
13. `Plan tomorrow` action unwired.
14. No "trip events log" aggregate query (events spread across waypoints/fuelTx/etaHistory).
15. GPS lock status not surfaced.

### User-journey entry points
- From `013_ActiveEnroute` (Swift) → Start Nav CTA triggers route activation (`navigation.activateRoute` navigation.ts:237) and transitions to this screen.
- From `117 Route Overview` → `Start nav` button (requires planned `routes.status='planned'` row).
- Deep-link on load-accept in `010_DriverHome` if active load has `routes.status='active'`.
- Required backend state: `routes` row for load, `routeWaypoints` entries, recent `etaHistory` row, active GPS ingress via `navigation.updateETA` loop, optional `fuelTransactions` for dark-mode replay.

---

## 117 Route Overview.png
**Swift port:** NONE. Closest is `013_ActiveEnroute.swift` but it's already in-motion; no pre-trip overview screen in current port.
**Purpose:** Pre-drive route summary + alternates. Light = planning ("Active Route · Departing 18:00", corridor map w/ current vs alternate, origin/destination cards, waypoint list 3-of-3, 2 ranked alternates, AI rationale, `Compare alts` / `Start nav`). Dark = post-drive retrospective ("Day Arc · Fri Apr 17 · Closed · −4 min vs ETA", realized path vs alternate, alternates considered, AI recap, `Trip details` / `Plan tomorrow`).

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header pill `ACTIVE ROUTE · DEPARTING 18:00` / `DAY ARC · FRI APR 17 · CLOSED · −4 MIN VS ETA` | Departure time / final variance | `routes.status` schema.ts:2919 + `etaHistory.changeMinutes`; partial — departure timestamp exists on `loads`/`routeWaypoints.plannedDeparture` |
| Corridor map w/ active + alternate polylines | Multiple route geometries | `navigation.getRoute` returns single polyline; `routing.calculateRoute` (routing.ts:70) and `routeOptimization.*` compute candidates but no storage of alternates | GAP — no `routeAlternates` table |
| Origin card `Marcus Hook PA` / `Lakeland FL` | Origin | `routeWaypoints` type='origin' schema.ts:2938 |
| Destination card `Plant City FL` / `Marcus Hook PA` | Destination | `routeWaypoints` type='destination' |
| Summary stats row `1,054 TOTAL` / `17h 04m DRIVE` / `3 STOPS` / `2×30m BREAKS` | Miles, drive hrs, stops, break count | `navigation.getRoute` (distance/duration) navigation.ts:97; `routing.calculateRoute` returns `requiredBreaks` array routing.ts:132; GAP — break count not persisted on `routes` row (schema `requiredBreaks` json exists:2915 but unwritten) |
| WAYPOINTS list `3 OF 3 · PLANNED` (Marcus Hook hook 18:00, Petro Smithfield NC break 02:14, Plant City Yara A-08 drop 11:04) | Ordered waypoints + planned times | `navigation.getRoute.waypoints` navigation.ts:107 |
| Waypoint colored dot + status | Waypoint.status enum | `routeWaypoints.status` schema.ts:2948 |
| (Dark) Wawa Lancaster — drop 12:14 (actual time) | Actual arrival | `routeWaypoints.actualArrival` schema.ts:2945 |
| ALTERNATES RANKED (`2 OPTIONS` / `TODAY`) header | Alternates list count | GAP — no `routing.getAlternates`; `routing.optimizeRoute` (routing.ts:276) only returns one optimal |
| Alt card `1 I-95 S corridor (recommended) · 17h 2m · −2 min · 1,069 mi · 6h · weekend forecast` | Ranked alternate routes | GAP — no router returns ranked alternates w/ weather/cost delta |
| Alt card `2 I-81 → I-77 → I-26 inland · 17h 4m · +37 min · 1,100 mi · 4h · cleanest forecast` | Second alternate w/ ETA delta | GAP |
| (Dark) Alt `I-77 → I-81 inland reroute · +36 min · 1,090 mi` + `2 toll plazas` | Considered-but-not-taken alts | GAP |
| AI rationale card `"I-95 S wins on time, fuel, and weather — pre-precip in the 18:00–11:04 corridor. Inland alt saves $14 toll but burns extra 7 gal ($21). Net: stay coastal. ETA Plant City Sun 11:04."` | AI route-comparison narrative | GAP — autopilot agents can produce but no driver-facing router surface |
| (Dark) AI recap `"You picked the right corridor — I-95 N saved 36 min and skipped 2 toll plazas vs the inland alt. Tomorrow's Marcus Hook → Plant City run will reuse this template; preview ready to view."` | Post-trip rationale + template reuse | GAP |
| `Compare alts` button | Open comparison view | GAP — no procedure; UI-only drill-down |
| `Start nav` button | Activate route | `navigation.activateRoute` navigation.ts:237 |
| (Dark) `Trip details` button | Load trip log | GAP — no "trip details" aggregated procedure |
| (Dark) `Plan tomorrow` | Kick off tomorrow's plan | GAP — no `planTomorrow` mutation (autopilot `dispatchPlanner` exists but not wired to driver) |

### Backend GAPS (numbered)
1. No storage/query for ranked alternate routes (only a single optimized result).
2. `routes.requiredBreaks`/`fuelStops` JSON columns exist but `navigation.calculateRoute` never writes them (navigation.ts:48–57).
3. AI route-comparison rationale has no router surface.
4. `Compare alts` drill-down has no procedure.
5. Post-trip recap + "template for tomorrow" unsupported.
6. Toll-plaza count / cost per alternate not persisted.
7. Weather-per-corridor forecast for alternates not exposed (weatherNerve exists but no per-route correlate).
8. `Plan tomorrow` action unwired.
9. Break-count summary not denormalized on route.

### User-journey entry points
- From `010_DriverHome` load card → "View route" CTA (after dispatch accept and before `activateRoute`).
- From `117` → `Start nav` pushes `116 Navigation`.
- From `116 Navigation` dark-mode `Replay route` → `117` in retrospective mode.
- Required backend state: `routes` row `status='planned'` w/ waypoints; ideally `alternate_routes` (missing); `etaHistory` seed row.

---

## 118 Traffic.png
**Swift port:** NONE.
**Purpose:** Incident detail + reroute decision support. Light = live incident ahead ("I-95 N MM 81 — lane 2 closure", in 7.4 mi, +12 min hold, PennDOT est. clear 15:30, side-by-side Stay/Reroute table, AI recommendation "Recommend stay 95", `Stay on 95` / `Take Pulaski`). Dark = post-incident decision log ("Closed earlier today — saved 4 min", held in slowdown details, AI closed-loop summary, `Decision log` / `Replay route`).

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header `AHEAD ON YOUR ROUTE / IN 7.4 MI` or `CLOSED EARLIER TODAY · SAVED 4 MIN` | Distance-ahead / resolution outcome | GAP — no ahead-of-route spatial query; `traffic.getIncidents` returns `[]` traffic.ts:15 |
| Incident primary card `I-95 N MM 81 — lane 2 closure · PennDOT · est. clear 15:30 · +12 min hold · lanes 2 of 3 · cause maint` | Full incident detail (source, eta-to-clear, severity, cause) | GAP — `hz_road_conditions` table consumed only by `trafficNerve` (autopilot/agents/sensory/trafficNerve.ts:79); no router exposes it. `traffic.getConstruction` stub traffic.ts:24 |
| (Dark) `RESOLVED · CLEARED 15:30 · 1h 18m total span` + `WAS AT 7.4 mi · LASTED 5h 18m · DECISION: rerouted` | Resolution metadata + driver decision record | GAP — no `reroute_decisions` / `incident_resolutions` table |
| `FLOW ON I-95 N · MM 75–96 · LIVE / CLOSED` horizontal flow strip (free/slow/stopped gradient) | Traffic flow by segment | GAP — no flow-strip procedure; HERE `flow` API not wrapped |
| Legend `Free · Slow · Stopped` | Static | — |
| Two-column decision table `Reroute on I-95 / Reroute Pulaski Hwy` with `+12 min hold / -4 min net`, ETA `16:42 / 16:38`, distance `18.5 / 26.6 mi`, fuel `idle 8 min / +1.1 gal`, surface `smooth / rough` | Per-option comparison (time, fuel, surface) | GAP — no `traffic.compareRoutes` / `routing.rerouteOptions`; `routing.calculateRoute` would need to be called twice w/ different `avoid` inputs (not supported — only `isHazmat` flag) |
| AI rec card `"Reroute saves 4 min but Pulaski has rough surface for 6 mi (NH₃ trailer slosh risk). Recommend stay 95 — the 12-min hold sits inside Yara's 30-min grace, no reload penalty."` | Commodity-aware recommendation | GAP — no commodity-aware reroute AI (trafficNerve publishes events only) |
| `Stay on 95` button | Record stay decision (no-op route-wise) | GAP — no "log decision" mutation; only `routes.reportCondition` routes.ts:284 (for new condition reports, not for decisions) |
| `Take Pulaski` button | Apply alternate route | GAP — no apply-reroute mutation |
| (Dark) `Decision log` button | View past decisions | GAP — no decision log table/procedure |
| (Dark) `Replay route` | Return to post-trip view | `navigation.getRoute` partial (no time scrub) |
| (Dark) AI closed-loop `"Closed loop · Pulaski reroute paid off by 4 min and 1.2 gal of idle fuel. The MM 81 lane stayed put for 5h 18m total. Logged to today's decision history; pattern templated for future PA runs."` | Outcome learning narrative | GAP — no driver-facing learning/template procedure |

### Backend GAPS (numbered)
1. Traffic router is three stubs (`getIncidents`, `getConstruction`, `getDelays`) — none read `hz_road_conditions`.
2. Ahead-on-route spatial filter missing.
3. Incident-clear-time, lanes-affected, cause fields not exposed via router (they exist in `hz_road_conditions` schema per trafficNerve.ts:77–78).
4. Traffic flow (segment-level free/slow/stopped) not wrapped.
5. Reroute decision comparison (side-by-side ETA/fuel/surface) unsupported.
6. Road-surface quality data not surfaced (`lidarRoadIntelligence.ts` service exists but no router).
7. Apply-reroute / stay-route mutation absent — no decision log persisted.
8. Commodity-aware AI recommendation (NH₃ slosh risk) not connected.
9. Post-trip "closed loop" learning recap not emitted to driver router.
10. `hz_road_conditions` table itself may not exist in schema.ts (only referenced via `sql.raw`) — schema gap.

### User-journey entry points
- Triggered from `116 Navigation` when incident is within N miles of route (currently unwired — `getIncidents` returns empty).
- Deep-link from safety alert push notification.
- Required backend state: active `routes` row + current position, `hz_road_conditions` entry within route buffer, commodity tag on load, optional `road_surface_index`.

---

## 119 Fuel Stops.png
**Swift port:** NONE.
**Purpose:** Fuel-stop recommendation + price lock. Light = live tank snapshot ("Tank · Live · 76% · 612 mi range · 612 mi range left · $214 est cost · $112 save vs avg"), recommended stop `Pilot #428 Carlisle PA · ETA 15:54 · 45 min dwell · NH₃ hi-flow OK`, amenities chips, 3 alternates ranked, AI rationale, `Compare all` / `Lock $2.74`. Dark = locked/logged view ("Tank · Closed Shift · 76% post Marcus Hook", Today's Fuel · Logged · Locked $2.74, alternates considered, AI summary, `Fuel history` / `Plan tomorrow`).

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Tank widget `TANK · LIVE · 76% · 612 mi range` | Fuel level + computed range | GAP — no procedure returning current tank %; ELD router may have but not wired. `vehicles` table likely has `fuelLevel` (not verified here); no `fuel.getTankStatus` |
| `612 mi RANGE LEFT` / `$214 EST COST` / `$112 SAVE VS AVG` | Range, estimated cost, savings | PARTIAL — `fuel.getSummary` fuel.ts:20 computes avg MPG; estimated-cost & savings-vs-avg have no procedure |
| Recommended stop card `Pilot #428 Carlisle PA` | Best station pick w/ score | `fuel.getNearbyStations` fuel.ts:351 (+ `routing.getFuelStops` routing.ts:328) returns nearest by Haversine; GAP on "recommended" ranking/scoring logic |
| `LOCK $2.74` chip (price lock badge) | Promised price from station | GAP — no price-lock / reservation API (no `pilot_flying_j.lockPrice` in integration) |
| Stop price row `$2.74 PRICE · 142 MI DIST · 45 MIN DWELL · +520 MI RANGE` | Price, distance, dwell, post-refuel range | PARTIAL — price via `fuelPriceService.findNearbyStations` (service line 335); distance yes; dwell + post-refuel range GAP |
| Amenity chips `NH₃ OK · HI-FLOW · SHOWERS · SUBWAY · PARKING` | Station amenities incl. hazmat compatibility | PARTIAL — `TRUCK_STOPS[].amenities` returned via findNearbyStations (fuelPriceService.ts:366); GAP on NH₃/hi-flow specifically (schema has generic `amenities: string[]`, no hazmat-lane flags) |
| ALTERNATES CONSIDERED `3 VISIBLE` header | Alt stops count | `fuel.getNearbyStations` returns list | OK-ish |
| Alt card `Pilot #428 Carlisle BEST $2.74` / `Love's #392 Hagerstown +$0.18 $2.92` / `Petro Smithfield NC $2.68 (tomorrow's leg)` | Alt stops ranked w/ price delta | PARTIAL — list returned but delta/ranking-by-trip-leg GAP |
| AI rationale `"Pilot Carlisle wins on price, route, and NH₃ lane availability — Love's is $0.18 cheaper per gallon but the 47-mi detour adds $1.44 net cost and 18 min. Recommend lock $2.74 now; price has drifted +$0.04 in last 6h."` | AI trade-off + price-drift note | GAP — no `fuel.getRecommendation` returning narrative; price-drift history unexposed |
| `Compare all` button | Open full comparison | GAP — no procedure |
| `Lock $2.74` button | Commit to station + lock price | GAP — no `fuel.lockPrice` / `fuel.reserveStop` mutation |
| (Dark) `LOCKED $2.74` / `STOPPED 23:12 · 78 gal · 47 min dwell` / `PRICE $2.74 · GALLONS 78.0 · TOTAL $213.72 · RANGE +520 MI` | Completed purchase record | `fuel.reportPurchase` fuel.ts:255 writes `fuelTransactions`; dwell/range GAP |
| (Dark) Best-alt comparison `Pilot #428 Carlisle (chosen) best $2.74` / `Love's #392 Hagerstown $2.92` / `TA Mechanicsburg · on corridor · CV lane closed for maint · $2.85` | Post-hoc alternatives w/ facility-status note | GAP — facility closure/advisory not in router |
| (Dark) AI summary `"Closed loop · Pilot #428 Carlisle saved $112 vs TA and $68 vs Love's. NH₃ hi-flow lane was the deciding factor (TA's was down for maint). Logged to fuel history; pattern templated for tomorrow's southbound run."` | Post-trip savings narrative | GAP |
| `Fuel history` button | Open transactions list | `fuel.getTransactions` fuel.ts:116 |
| `Plan tomorrow` button | Push next-day fuel plan | GAP |

### Backend GAPS (numbered)
1. Tank status (live % / range) — no procedure (likely needs ELD-router integration).
2. "Save vs avg" and "estimated cost for next leg" derived metrics absent.
3. Recommended-stop scoring (combines price + detour + amenity + commodity compatibility) absent.
4. Price-lock / reservation API missing (no `pilot_flying_j.lockPrice`, no `fuelRouter.lockPrice`).
5. Dwell-time estimate per stop absent.
6. Post-refuel range recomputation absent.
7. Hazmat-lane / NH₃ hi-flow amenity flag not modeled (generic `amenities: string[]`).
8. Facility-status advisories (lane closed for maint) not persisted.
9. Price-drift history per station not exposed.
10. AI rationale narrative for fuel decisions not exposed via router.
11. "Plan tomorrow" fuel preview unwired.
12. Commodity-aware stop filtering (NH₃ trailer) absent.

### User-journey entry points
- Autotriggered from `116 Navigation` when tank % drops below threshold along route.
- From `117 Route Overview` waypoint card tap on a fuel waypoint (type=fuel in `routeWaypoints`).
- From `010_DriverHome` "Fuel" quick-action tile.
- From dispatch-injected required fuel stop in HOS plan (`routing.calculateRoute.fuelStops` routing.ts:154–170).
- Required backend state: current `vehicles.fuelLevel` + odometer, active `routes` row w/ corridor polyline, `TRUCK_STOPS` lookup data, load commodity tag (for hazmat-lane filter), optional `fuelTransactions` history for savings comparison.

---

## Summary
- **Screens audited:** 4
- **Swift ports present:** 0 / 4 (0%). None of 116/117/118/119 have a dedicated Swift file in `Views/Driver/`. HERE client scaffolding (`HereRoutingClient`, `HereGeocodingClient`, `HereMatrixClient`, `HereTileOverlay`) exists; `013_ActiveEnroute.swift` is the closest behavioral neighbor.
- **UI element → backend map totals (counted across all 4):** ~64 distinct elements. Fully backed ≈ 9 (ETA / waypoint status / route status / polyline / favorites / nearby stations / report purchase / transactions / activateRoute). Partially backed ≈ 8. GAPs ≈ 47. **Backed rate: ~14% fully, ~27% including partials.**
- **Aggregate router coverage:**
  - `navigation.ts` — solid CRUD for route/waypoint/ETA but nothing route-geometry-real (polyline is 2-point string).
  - `routes.ts` — partial planning + `getConditions` pulls weather (not traffic).
  - `routing.ts` — strong HOS/fuel-stop compute-on-demand; no persistence for alternates.
  - `traffic.ts` — three empty stubs; the consuming data source (`hz_road_conditions`) is only read by autopilot `trafficNerve`, not by any driver-facing router.
  - `fuel.ts` — price discovery + purchase reporting OK; no tank status, no price lock, no commodity-aware recommendation.
  - No HERE Maps server-side wrapper — HERE is only on the Swift client.

### Top-3 gaps (priority order)
1. **Traffic data pipe is disconnected.** `traffic.*` router returns empty; `hz_road_conditions` (populated by `trafficNerve`) is never queried by a driver-facing procedure. Every card on 118, plus the "2 ahead" and AI coach on 116, depend on this.
2. **No "reroute / decision" mutation + no alternate-route persistence.** 116 `Reroute around`, 117 `Compare alts` / ranked alternates, 118 `Stay / Take Pulaski` + decision log — all demand `routing.compareAlternatives`, `routing.applyReroute`, and a `reroute_decisions` table. Currently non-existent.
3. **Fuel price-lock + tank-status procedures missing.** 119's `Lock $2.74`, tank %, range-left, and post-refuel range cannot be satisfied by any existing procedure. `fuel.lockPrice` and ELD-sourced `fuel.getTankStatus` are the two net-new surfaces needed.
