# Patch Plan — Migrating to `EusoAddressField`

All work lands in one PR. The underlying HERE client (`HereGeocodingClient`) already exists and requires no changes. Net new code: one parser + one view + call-site edits.

## Ordered work

| # | Task | File(s) | Effort | Risk |
|---|------|---------|--------|------|
| 1 | Add `CoordinateParser` + unit tests (14 cases from `lat_long_parser.md`) | `EusoTrip/Services/HereMaps/CoordinateParser.swift` (new); test target | **S** | Low — pure function. |
| 2 | Add `ResolvedAddress` struct | `EusoTrip/Models/ResolvedAddress.swift` (new) | **S** | Low. |
| 3 | Build `EusoAddressField` SwiftUI view | `EusoTrip/Views/Components/EusoAddressField.swift` (new) | **M** | Medium — debounce, task-cancellation, keyboard dismissal, offline state. Budget 1 day. |
| 4 | Swap `GlassField(label: "Address", …)` at Create Account | `EusoTrip/Views/Auth/002_CreateAccount.swift:761-775` (address block, ~15 lines) | **S** | Low. Extend `RegistrationViewModel` with a `companyAddress: ResolvedAddress` field; the new component can fan out to the existing `address / city / state / zip` `@Published`s on resolve (keeps backend payload identical). |
| 5 | Keep existing `city / state / zip` `GlassField`s as read-only echoes for one release (show what was resolved), with an "edit manually" disclosure that flips them back to inputs | same file | **S** | Low — hedge in case HERE misses a detail the user needs to correct. |
| 6 | Wire one mini-screen preview in `ContentView`'s dev gallery so QA can hit it without signing in | `EusoTrip/ContentView.swift` (optional, gated to `#if DEBUG`) | **S** | Zero. |
| 7 | Regression tests for Create Account happy path + coord-paste + offline | UITest target | **M** | Medium — network-mockable via URLSession's `URLProtocol`. |

**Total:** ~2 engineer-days for a one-pass ship.

## Future sites (not in this PR — adopt the component when the screen gets built)

These are the sites from the inventory marked "planned" but not currently live in the Swift code. They should use `EusoAddressField` from day one; no retrofit will be needed:

- Create/Edit Load flow → pickup + delivery + multi-stop (2 pickers minimum, n for stops).
- Me · Fleet Management · Home base edit.
- Me · Fleet Management · Geofence setup ("add custom geofence" center point).
- Route planner manual override (origin / destination / intermediate waypoints).
- ESANG Smart Stop manual override (rare, but listed in design).
- Cross-border crossing picker (if it ever becomes text-typed vs. a fixed list).
- Watch companion — skip. Watch address entry uses Siri dictation; the component is phone-only.

## Phased alternative (not recommended)

Phase 1 could ship the parser + component without any call-site swaps, as dead code, so the PR is reviewable in isolation. Phase 2 swaps the Create Account site. I don't recommend splitting — the only current call site is one screen, and shipping an unused component drifts out of sync with its first real consumer. One pass is cleaner.

## Backend / payload impact

None. `RegistrationViewModel` already sends `address: String, city: String, state: String, zip: String` to the API. The new component just fills those four strings from a single user interaction. If the backend later wants lat/lng on the Company record, add two optional fields — non-breaking.
