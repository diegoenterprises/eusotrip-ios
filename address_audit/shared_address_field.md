# EusoAddressField — Component Design

A single SwiftUI view that replaces every plain `GlassField` / `TextField` wired to an address string. Lives at `EusoTrip/Views/Components/EusoAddressField.swift`. Uses existing `HereGeocodingClient` — no new network code.

## Public surface

```swift
struct ResolvedAddress: Equatable {
    enum Source: Equatable { case typed, coord, autocomplete }
    var display: String                 // what we show in the field
    var coordinate: CLLocationCoordinate2D?
    var loadLocation: LoadLocation?     // populated once resolved
    var source: Source
}

struct EusoAddressField: View {
    let label: String                   // e.g. "Pickup"
    let placeholder: String             // e.g. "Street address or lat, lng"
    @Binding var value: ResolvedAddress
    var nearHint: CLLocationCoordinate2D? = nil   // bias for autosuggest
    var accessibilityHint: String? = nil
}
```

Binds through a single `ResolvedAddress` struct so the caller (e.g. `RegistrationViewModel`, future `CreateLoadViewModel`) gets everything — display string, geo, source — without synchronizing three `@Published` vars.

## Behavior

1. **Typing path.** On every change to `value.display`:
   - Run `CoordinateParser.parse(value.display)` first.
   - If it parses: hide suggestion list, call `HereGeocodingClient.reverseGeocode(at:)`, and write `ResolvedAddress(display: canonical, coordinate: parsed, loadLocation: reverse.first?.asLoadLocation(), source: .coord)`. Show the reverse-geocoded street line beneath the field as a secondary label ("Resolved: 1 World Trade Center, New York").
   - Else debounce 350 ms, call `HereGeocodingClient.autosuggest(query:, near: nearHint ?? CoreLocationBroker.shared.lastKnown ?? Dallas)` with `limit: 5`. Drop results if the query has changed since issue (via `Task` id cancellation / `@State var currentTask: Task<Void,Never>?`).

2. **Suggestion tap.** On tap, cancel any in-flight task, call `HereGeocodingClient.geocode(query: suggestion.title, limit: 1)` (HERE's autosuggest does not always include coords for non-`address` result types), write `ResolvedAddress(display: hit.title, coordinate: hit.position.cl, loadLocation: hit.asLoadLocation(), source: .autocomplete)`, collapse suggestion list.

3. **Clear.** Trailing "x.circle.fill" button → resets `value = ResolvedAddress(display:"", coord:nil, loc:nil, source: .typed)` and re-focuses the field.

4. **Blur without tap.** If the user leaves the field while `source == .typed`, run a one-shot forward geocode (`HereGeocodingClient.geocode`) to try to resolve what they typed. Silent failure is OK — we keep the raw string in `display`, `coordinate` stays nil, downstream validation can decide whether to require resolution.

## Layout (mirrors `GlassField`)

```
┌───────────────────────────────────────────────────┐
│  LABEL                                            │
│  ┌─────────────────────────────────────────────┐  │
│  │ 📍  523 W Adams Blvd, Los Angeles…     ✕   │  │  ← 50 pt, palette.bgCardSoft, Radius.md
│  └─────────────────────────────────────────────┘  │
│  Resolved: 40.7128, -74.0060 · New York, NY       │  ← EType.caption, textTertiary, only if resolved
│  ┌─────────────────────────────────────────────┐  │
│  │ 523 W Adams Blvd · Los Angeles, CA 90007   │  │  ← suggestion rows, max 5
│  │ 523 Adams St    · Chicago, IL 60607        │  │
│  │ …                                           │  │
│  └─────────────────────────────────────────────┘  │
```

Suggestion row: title (street + number) in `EType.bodyStrong`, subtitle (`city, state`) in `EType.caption textSecondary`. 44 pt min height. Leading `mappin` icon in `textTertiary`.

## Accessibility

- `accessibilityLabel(label)` on the field.
- `accessibilityHint("Type a street address, or paste a latitude and longitude")`.
- Suggestion rows: `accessibilityLabel("\(title), \(subtitle)")`, `accessibilityAddTraits(.isButton)`.
- Clear button: `accessibilityLabel("Clear address")`.
- Resolved-label line: `accessibilityLabel("Resolved to \(display)")`.

## Edge cases

- **Offline**: autosuggest throws → show inline "Offline — we'll save what you type" under the field; blur-time geocode is skipped.
- **No HERE key**: `HereMapsError.missingAPIKey` → component degrades to a pure `GlassField` with the same binding (coord stays nil).
- **Paste of multi-line**: strip newlines before parse/suggest.
- **nearHint nil**: use `CLLocationManager`'s last known location if authorized, else fall back to the app's default center (Dallas 32.78, -96.80 — matches the existing load seed data).
