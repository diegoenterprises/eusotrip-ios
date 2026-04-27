# Lat/Long Parser Spec

Purpose: detect when the user pastes or types a coordinate into any address field and short-circuit autocomplete.

## Accepted shapes

1. Decimal degrees, comma-separated:              `40.7128, -74.0060`
2. Decimal degrees, space-separated:              `40.7128 -74.0060`
3. Parenthesized:                                  `(40.7128, -74.0060)` / `[40.7128,-74.0060]`
4. Hemisphere suffix:                              `40.7128N 74.0060W` / `40.7128° N, 74.0060° W`
5. Hemisphere prefix:                              `N40.7128 W74.0060`
6. Trailing degree glyph, no hemisphere:           `40.7128°, -74.0060°`
7. Semicolon or slash separators:                  `40.7128; -74.0060` / `40.7128/-74.0060`
8. Signed with leading `+`:                        `+40.7128, -74.0060`

Rejected (fall through to autocomplete): anything with a letter that isn't `N/S/E/W`, lat out of `[-90, 90]`, lng out of `[-180, 180]`, missing second number.

## Regex (Swift, `.caseInsensitive`)

```
^\s*                                   # leading ws
[\(\[]?\s*                             # optional open paren/bracket
(?<latHemiPrefix>[NS])?\s*             # optional N/S prefix
(?<lat>[+\-]?\d{1,3}(?:\.\d+)?)        # latitude number
\s*°?\s*                               # optional degree + ws
(?<latHemiSuffix>[NS])?                # optional N/S suffix
\s*[,;/\s]\s*                          # separator
(?<lngHemiPrefix>[EW])?\s*
(?<lng>[+\-]?\d{1,3}(?:\.\d+)?)
\s*°?\s*
(?<lngHemiSuffix>[EW])?
\s*[\)\]]?\s*$
```

Post-parse validation: if `lat` has a hemisphere, reject if the numeric sign disagrees (`-40.0N` fails). Same for lng. Then check `abs(lat) <= 90` and `abs(lng) <= 180`.

## Swift signature

```swift
struct ParsedCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
    /// The exact substring the parser matched, for "label under the field"
    /// echo ("40.7128, -74.0060" stays "40.7128, -74.0060" in the UI).
    let canonical: String
}

enum CoordinateParser {
    /// Returns nil if the input isn't a coordinate pair.
    /// Whitespace-tolerant. Rejects out-of-range values.
    static func parse(_ input: String) -> ParsedCoordinate?
}
```

Owner: ship in `EusoTrip/Services/HereMaps/CoordinateParser.swift` (it's reverse-geocoding adjacent).

## Test matrix

| # | Input | Expected |
|---|-------|----------|
| 1  | `40.7128, -74.0060`       | `(40.7128, -74.0060)` |
| 2  | `40.7128 -74.0060`        | `(40.7128, -74.0060)` |
| 3  | `(40.7128, -74.0060)`     | `(40.7128, -74.0060)` |
| 4  | `40.7128N 74.0060W`       | `(40.7128, -74.0060)` |
| 5  | `40.7128° N, 74.0060° W`  | `(40.7128, -74.0060)` |
| 6  | `N40.7128 W74.0060`       | `(40.7128, -74.0060)` |
| 7  | `-33.8688, 151.2093`      | `(-33.8688, 151.2093)` (Sydney, tests signed lat + positive lng) |
| 8  | `40.7128; -74.0060`       | `(40.7128, -74.0060)` |
| 9  | `  +40.7128,-74.0060  `   | `(40.7128, -74.0060)` (trim + sign) |
| 10 | `91.0, 0.0`               | `nil` (lat > 90) |
| 11 | `40.0, 200.0`             | `nil` (lng > 180) |
| 12 | `-40.7128N 74.0060W`      | `nil` (sign disagrees with hemisphere) |
| 13 | `523 W Adams`             | `nil` (letters, fall through to autocomplete) |
| 14 | `40.7128`                 | `nil` (single number) |
