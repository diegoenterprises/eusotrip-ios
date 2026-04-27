//
//  LatLongParser.swift
//  EusoTrip — Pure-Swift coordinate string parser.
//
//  Recognises the common "paste a coordinate" shapes users reach for when
//  filling address fields:
//
//      40.7128, -74.0060        → (40.7128, -74.0060)
//      40.7128,-74.0060         → (40.7128, -74.0060)
//      (40.7128, -74.0060)      → (40.7128, -74.0060)
//      40.7128N 74.0060W        → (40.7128, -74.0060)
//      40.7128° N, 74.0060° W   → (40.7128, -74.0060)
//      N40.7128 W74.0060        → (40.7128, -74.0060)
//      -33.8688, 151.2093       → (-33.8688, 151.2093)  (Sydney)
//      40.7128; -74.0060        → (40.7128, -74.0060)
//      ` +40.7128,-74.0060 `    → (40.7128, -74.0060)  (trim + sign)
//      40.7128 -74.0060         → (40.7128, -74.0060)  (space separated)
//
//  Rejected (returns nil so autosuggest keeps running):
//      91.0, 0.0                → nil (lat out of ±90)
//      40.0, 200.0              → nil (lng out of ±180)
//      -40.7128N 74.0060W       → nil (sign disagrees with hemisphere)
//      523 W Adams              → nil (letters — fall through to autocomplete)
//      40.7128                  → nil (single number)
//
//  No dependencies beyond Foundation + CoreLocation.
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

/// Pure-Swift parser that detects when a string is a lat/lng pair so the
/// address picker can short-circuit autocomplete and drop a pin directly.
///
/// All public API is `static` — there's no state to hold. Callers should
/// invoke `LatLongParser.parse(_:)` on every keystroke and treat a `nil`
/// return as "this isn't a coordinate, run the normal autosuggest flow."
enum LatLongParser {

    // MARK: Public API

    /// Returns a `CLLocationCoordinate2D` if `text` parses as a coordinate
    /// pair; otherwise `nil`. Whitespace-tolerant, sign-aware, hemisphere-
    /// aware, and range-validating (|lat| ≤ 90, |lng| ≤ 180).
    ///
    /// Example: `40.7128, -74.0060` → CLLocationCoordinate2D(40.7128, -74.0060)
    /// Example: `40.7128,-74.0060` → CLLocationCoordinate2D(40.7128, -74.0060)
    /// Example: `(40.7128, -74.0060)` → CLLocationCoordinate2D(40.7128, -74.0060)
    /// Example: `40.7128N 74.0060W` → CLLocationCoordinate2D(40.7128, -74.0060)
    /// Example: `40.7128° N, 74.0060° W` → CLLocationCoordinate2D(40.7128, -74.0060)
    /// Example: `N40.7128 W74.0060` → CLLocationCoordinate2D(40.7128, -74.0060)
    /// Example: `-33.8688, 151.2093` → CLLocationCoordinate2D(-33.8688, 151.2093)
    /// Example: `40.7128; -74.0060` → CLLocationCoordinate2D(40.7128, -74.0060)
    /// Example: `  +40.7128,-74.0060  ` → CLLocationCoordinate2D(40.7128, -74.0060)
    /// Example: `91.0, 0.0` → nil (lat > 90)
    static func parse(_ text: String) -> CLLocationCoordinate2D? {
        // Normalise: strip newlines, convert unicode minus (U+2212) to ASCII
        // hyphen-minus, collapse internal whitespace into a single space.
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return nil }

        // Run the shared regex. All captures are optional — we validate
        // agreement + range below.
        guard let match = Self.regex.firstMatch(
            in: normalized,
            options: [],
            range: NSRange(normalized.startIndex..., in: normalized)
        ) else {
            return nil
        }

        func captured(_ name: String) -> String? {
            let r = match.range(withName: name)
            guard r.location != NSNotFound, let range = Range(r, in: normalized) else { return nil }
            return String(normalized[range])
        }

        guard let latString = captured("lat"), let lngString = captured("lng"),
              var lat = Double(latString), var lng = Double(lngString) else {
            return nil
        }

        let latHemiPrefix = captured("latHemiPrefix")?.uppercased()
        let latHemiSuffix = captured("latHemiSuffix")?.uppercased()
        let lngHemiPrefix = captured("lngHemiPrefix")?.uppercased()
        let lngHemiSuffix = captured("lngHemiSuffix")?.uppercased()

        // A hemisphere cannot appear on both sides at once. If both showed
        // up we bail — ambiguous input is better treated as "not a coord."
        if latHemiPrefix != nil && latHemiSuffix != nil { return nil }
        if lngHemiPrefix != nil && lngHemiSuffix != nil { return nil }

        let latHemi = latHemiPrefix ?? latHemiSuffix
        let lngHemi = lngHemiPrefix ?? lngHemiSuffix

        // Hemisphere/sign reconciliation.
        // If the user wrote e.g. "-40N", that's self-contradictory → reject.
        if let h = latHemi {
            switch h {
            case "N":
                if lat < 0 { return nil }
            case "S":
                if lat > 0 { return nil }
                lat = -abs(lat)
            default:
                return nil
            }
        }
        if let h = lngHemi {
            switch h {
            case "E":
                if lng < 0 { return nil }
            case "W":
                if lng > 0 { return nil }
                lng = -abs(lng)
            default:
                return nil
            }
        }

        // Range gate.
        guard abs(lat) <= 90.0, abs(lng) <= 180.0 else { return nil }

        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    // MARK: Internals

    /// Swap Unicode minus (U+2212), en-dash, em-dash, and non-breaking space
    /// for their ASCII equivalents; trim ends; collapse whitespace runs.
    private static func normalize(_ input: String) -> String {
        var s = input
        // Unicode minus → ASCII hyphen-minus
        s = s.replacingOccurrences(of: "\u{2212}", with: "-")
        s = s.replacingOccurrences(of: "\u{2013}", with: "-")   // en-dash
        s = s.replacingOccurrences(of: "\u{2014}", with: "-")   // em-dash
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")   // nbsp
        // Kill newlines entirely (paste from multi-line sources).
        s = s.replacingOccurrences(of: "\r", with: " ")
        s = s.replacingOccurrences(of: "\n", with: " ")
        // Trim.
        s = s.trimmingCharacters(in: .whitespaces)
        return s
    }

    /// Regex built once and cached. See `lat_long_parser.md` for the spec.
    /// Named groups: latHemiPrefix, lat, latHemiSuffix, lngHemiPrefix, lng,
    /// lngHemiSuffix. All hemispheres are optional; at most one side shows.
    private static let regex: NSRegularExpression = {
        // Whitespace in the pattern is literal because we are NOT using
        // .allowCommentsAndWhitespace; the pattern is compact-escaped.
        let pattern =
            #"^"# +                                                  // anchor
            #"\s*[\(\[]?\s*"# +                                      // optional ( or [
            #"(?:(?<latHemiPrefix>[NSns])\s*)?"# +                   // optional N/S prefix
            #"(?<lat>[+\-]?\d{1,3}(?:\.\d+)?)"# +                    // latitude
            #"\s*°?\s*"# +                                           // optional °
            #"(?<latHemiSuffix>[NSns])?"# +                          // optional N/S suffix
            #"\s*[,;/\s]\s*"# +                                      // separator
            #"(?:(?<lngHemiPrefix>[EWew])\s*)?"# +                   // optional E/W prefix
            #"(?<lng>[+\-]?\d{1,3}(?:\.\d+)?)"# +                    // longitude
            #"\s*°?\s*"# +                                           // optional °
            #"(?<lngHemiSuffix>[EWew])?"# +                          // optional E/W suffix
            #"\s*[\)\]]?\s*"# +                                      // optional ) or ]
            #"$"#                                                    // end

        // swiftlint:disable:next force_try — pattern is a compile-time constant.
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()
}
