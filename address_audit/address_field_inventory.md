# Address Field Inventory — EusoTrip iOS + watchOS

Scan date: 2026-04-22. Searched every `*.swift` in the repo for `TextField`, `GlassField`, `address`, `pickup|dropoff|destination|origin|waypoint|geofence|homeBase|terminal|rendezvous|truckStop|fuelStop|border`.

**Headline finding:** the app has **1 live user-typed address surface** (Carrier/Broker/Shipper registration company address, 4 sub-fields). Every other "address" in the codebase is hardcoded mock data in a `LoadLocation` struct, or a read-only label echoed from a backend payload. There is no create-load flow, no route planner, no fleet-edit, no favorites, no geofence-setup, no rendezvous picker in the shipping Swift UI — those flows are described in `_WAVE3_AUDIT` / `_WAVE4_BUILD` notes as "desktop/web" or "future v1.0+" only. The watch app has zero address inputs.

Sites below are ordered by priority for the upgrade. The top 5 are today's real TextField sites; the bottom 7 are known-planned or implied sites where an address field will be added in upcoming work and should use the new shared component from day one.

| # | File | Screen | Field label | Current impl | Notes |
|---|------|--------|-------------|--------------|-------|
| 1 | `EusoTrip/Views/Auth/002_CreateAccount.swift:761` | Create Account · Step 4 (carrier/broker/shipper addressBlock) | "Address" | `GlassField` (plain) binds `$vm.address:String` | Accompanied by separate City / State / ZIP fields. No geocoding, no validation. Writes to `RegistrationViewModel.address`. |
| 2 | `EusoTrip/Views/Auth/002_CreateAccount.swift:766` | Create Account · Step 4 | "City" | `GlassField` | Sibling of #1; would be auto-filled by the new component. |
| 3 | `EusoTrip/Views/Auth/002_CreateAccount.swift:769` | Create Account · Step 4 | "State" | `GlassField` (.characters cap) | Sibling of #1. |
| 4 | `EusoTrip/Views/Auth/002_CreateAccount.swift:772` | Create Account · Step 4 | "ZIP" | `GlassField` (.numberPad) | Sibling of #1. |
| 5 | `EusoTrip/Views/Driver/ProfileEditView.swift:311` | Profile Edit (Me) | — | Generic `fieldRow` TextField builder | **No address field today**, but the file is the one place where a driver-home-address row will drop in. |
| 6 | `EusoTrip/Views/Driver/MeDetailScreens.swift` MeFleetView (L2634+) | Me · Fleet Management | "Home base" | Read-only `Asset` mock: `Dallas · TX` | Planned edit flow will need an address picker for the vehicle's home terminal. |
| 7 | `EusoTrip/Models/Load.swift:20` / `LoadLocation` | Load model | pickup / delivery address | Hardcoded seed data (`"4800 Industrial Dr"`) | Consumer of the model. When a create-load surface ships, both pickup and delivery legs take the new component. |
| 8 | `EusoTrip/Views/Components/LoadDetailSheet.swift` | Load Detail · Pickup / Delivery stops | "Origin" / "Destination" | Read-only `Text(load.origin)` | Display-only today. Edit-load flow will need two address pickers here. |
| 9 | `EusoTrip/Services/GeofenceService.swift:96` | Geofence setup | (implicit pickup + delivery) | CLCircularRegion from existing `LoadLocation` lat/lng | No user-facing picker; geofence coords come from the load. When a manual "add custom geofence" lands (Me · Fleet · Geofences), it needs the new component. |
| 10 | `EusoTrip/Views/Driver/036_ESangSmartStop.swift` | ESANG Smart Stop | (implicit next stop) | ESANG picks; no text entry | A manual-override "type a stop" would use the new component. |
| 11 | `EusoTrip Watch App/Views/DispatchCallView.swift` | Watch · Dispatch | — | No TextField (watch has no keyboard paths) | Watch address entry uses Scribble/Dictation if ever added — same component via WKTextInputController, out of scope for this pass. |
| 12 | `EusoTrip/Views/Driver/DriverTabPanes.swift:932` | Search pill (Loads tab) | search query | `TextField` | Not an address field, but uses `LoadLocation.city` for filtering. Leave alone. |

**Confirmed non-sites** (searched, zero address input): `001_SignIn`, `003_ForgotPassword`, `004_ResetPassword`, `AddPaymentAccountSheet`, `SOSEmergencySheet`, `EmergencyView` (watch), `011_PretripDVIR`, `DriverConversationView`, all `0XX_*` active-trip screens, `HotZonesWidget`, `HereMapView`.

**Existing infra we can reuse:** `HereGeocodingClient` already wraps `/v1/geocode`, `/v1/revgeocode`, and `/v1/autosuggest` (see `EusoTrip/Services/HereMaps/HereGeocodingClient.swift`) — no new client code required. `HereGeocodeItem.asLoadLocation()` is already the bridge we need.
