//
//  LatLongParser.swift
//  EusoTrip
//
//  Canonical coordinate parser for native address, location, and map inputs.
//  Parsing is local and deterministic: HERE may enrich a parsed coordinate
//  with an address, but it never changes or gates the coordinate itself.
//

import Foundation
import CoreLocation

enum LatLongParser {

    struct ParsedCoordinate {
        let coordinate: CLLocationCoordinate2D
        /// Trimmed user input, retained so a caller never has to replace a
        /// pasted coordinate or map URL with a geocoder's formatted address.
        let originalText: String
    }

    // MARK: - Public API

    /// Parses decimal/signed/hemisphere coordinates, DMS and degree-minute
    /// coordinates, RFC 5870-style `geo:` URIs, and coordinate-bearing links
    /// from Apple Maps, Google Maps, HERE, OpenStreetMap, and Bing Maps.
    static func parse(_ text: String) -> CLLocationCoordinate2D? {
        parseDetailed(text)?.coordinate
    }

    static func parseDetailed(_ text: String) -> ParsedCoordinate? {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalize(text)
        guard !original.isEmpty, !normalized.isEmpty else { return nil }

        let parsed = parseGeoURI(normalized)
            ?? parseKnownMapURL(normalized)
            ?? parseDMSPair(normalized)
            ?? parseDecimalPair(normalized)

        guard let parsed, isValid(parsed) else { return nil }
        return ParsedCoordinate(coordinate: parsed, originalText: original)
    }

    /// Distinguishes malformed coordinate-shaped input from an ordinary
    /// address or landmark. Callers can preserve free text for geocoding while
    /// rejecting an out-of-range pair, incomplete geo URI, or broken map link.
    static func hasCoordinateIntent(_ text: String) -> Bool {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return false }
        if parseDetailed(normalized) != nil { return true }
        if normalized.lowercased().hasPrefix("geo:") { return true }

        let urlText = normalized.replacingOccurrences(of: " ", with: "%20")
        if let components = URLComponents(string: urlText), isKnownMapLocation(components) {
            let coordinateKeys: Set<String> = [
                "ll", "q", "query", "center", "destination", "daddr", "saddr", "map", "cp"
            ]
            if components.queryItems?.contains(where: {
                coordinateKeys.contains($0.name.lowercased())
                    && ($0.value.map(isCoordinateShaped) ?? false)
            }) == true {
                return true
            }
            let itemNames = Set((components.queryItems ?? []).map { $0.name.lowercased() })
            if itemNames.contains("mlat") || itemNames.contains("mlon") { return true }
            let path = components.percentEncodedPath.removingPercentEncoding ?? components.path
            if path.contains("/@") || (components.fragment?.lowercased().contains("map=") == true) {
                return true
            }
            return false
        }

        return isCoordinateShaped(normalized)
    }

    /// Shared gate for API records and optional provider coordinates. Missing
    /// values stay missing, while every finite WGS-84 pair remains valid,
    /// including either zero axis and the real coordinate `(0,0)`.
    static func validatedCoordinate(
        latitude: Double?,
        longitude: Double?
    ) -> CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return isValid(coordinate) ? coordinate : nil
    }

    static func isValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        return latitude.isFinite
            && longitude.isFinite
            && (-90.0...90.0).contains(latitude)
            && (-180.0...180.0).contains(longitude)
    }

    /// Uses Swift's round-trippable Double representation rather than a
    /// fixed decimal format that would visually truncate a precise fix.
    static func displayString(_ coordinate: CLLocationCoordinate2D) -> String {
        "\(coordinate.latitude), \(coordinate.longitude)"
    }

    // MARK: - Decimal and hemisphere pairs

    private static func parseDecimalPair(_ text: String) -> CLLocationCoordinate2D? {
        guard let match = decimalPairRegex.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ) else { return nil }

        guard let latitude = decimalComponent(
            match: match,
            text: text,
            valueName: "lat",
            prefixName: "latHemiPrefix",
            suffixName: "latHemiSuffix",
            positiveHemisphere: "N",
            negativeHemisphere: "S"
        ), let longitude = decimalComponent(
            match: match,
            text: text,
            valueName: "lng",
            prefixName: "lngHemiPrefix",
            suffixName: "lngHemiSuffix",
            positiveHemisphere: "E",
            negativeHemisphere: "W"
        ) else { return nil }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return isValid(coordinate) ? coordinate : nil
    }

    private static func decimalComponent(
        match: NSTextCheckingResult,
        text: String,
        valueName: String,
        prefixName: String,
        suffixName: String,
        positiveHemisphere: String,
        negativeHemisphere: String
    ) -> Double? {
        guard let raw = capture(valueName, match: match, text: text),
              let value = Double(raw) else { return nil }
        let prefix = capture(prefixName, match: match, text: text)?.uppercased()
        let suffix = capture(suffixName, match: match, text: text)?.uppercased()
        guard prefix == nil || suffix == nil else { return nil }
        return applyHemisphere(
            rawValue: raw,
            magnitude: abs(value),
            hemisphere: prefix ?? suffix,
            positiveHemisphere: positiveHemisphere,
            negativeHemisphere: negativeHemisphere
        )
    }

    // MARK: - DMS and degree-minute pairs

    private static func parseDMSPair(_ text: String) -> CLLocationCoordinate2D? {
        guard let match = dmsPairRegex.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ) else { return nil }

        guard let latitude = dmsComponent(
            match: match,
            text: text,
            stem: "lat",
            positiveHemisphere: "N",
            negativeHemisphere: "S"
        ), let longitude = dmsComponent(
            match: match,
            text: text,
            stem: "lng",
            positiveHemisphere: "E",
            negativeHemisphere: "W"
        ) else { return nil }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return isValid(coordinate) ? coordinate : nil
    }

    private static func dmsComponent(
        match: NSTextCheckingResult,
        text: String,
        stem: String,
        positiveHemisphere: String,
        negativeHemisphere: String
    ) -> Double? {
        guard let rawDegrees = capture("\(stem)Deg", match: match, text: text),
              let degrees = Double(rawDegrees),
              let rawMinutes = capture("\(stem)Min", match: match, text: text),
              let minutes = Double(rawMinutes) else { return nil }
        let seconds = capture("\(stem)Sec", match: match, text: text).flatMap(Double.init) ?? 0
        guard minutes >= 0, minutes < 60, seconds >= 0, seconds < 60 else { return nil }

        let prefix = capture("\(stem)HemiPrefix", match: match, text: text)?.uppercased()
        let suffix = capture("\(stem)HemiSuffix", match: match, text: text)?.uppercased()
        guard prefix == nil || suffix == nil else { return nil }

        let magnitude = abs(degrees) + minutes / 60 + seconds / 3_600
        return applyHemisphere(
            rawValue: rawDegrees,
            magnitude: magnitude,
            hemisphere: prefix ?? suffix,
            positiveHemisphere: positiveHemisphere,
            negativeHemisphere: negativeHemisphere
        )
    }

    private static func applyHemisphere(
        rawValue: String,
        magnitude: Double,
        hemisphere: String?,
        positiveHemisphere: String,
        negativeHemisphere: String
    ) -> Double? {
        guard let hemisphere else {
            return rawValue.hasPrefix("-") ? -magnitude : magnitude
        }

        if hemisphere == positiveHemisphere {
            guard !rawValue.hasPrefix("-") else { return nil }
            return magnitude
        }
        if hemisphere == negativeHemisphere {
            guard !rawValue.hasPrefix("+") else { return nil }
            return -magnitude
        }
        return nil
    }

    // MARK: - geo URI and map links

    private static func parseGeoURI(_ text: String) -> CLLocationCoordinate2D? {
        guard text.lowercased().hasPrefix("geo:") else { return nil }
        let body = String(text.dropFirst(4))

        // A geo URI may use `geo:0,0?q=lat,lng(Label)`. The query location
        // is the intended coordinate and therefore takes precedence.
        if let queryStart = body.firstIndex(of: "?") {
            let query = String(body[body.index(after: queryStart)...])
            if let coordinate = coordinateFromQuery(query, keys: ["q", "query"]) {
                return coordinate
            }
        }

        let path = body.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let coordinatePart = path.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
        return parseCoordinateBearingValue(String(coordinatePart), allowsTrailingFields: false)
    }

    private static func parseKnownMapURL(_ text: String) -> CLLocationCoordinate2D? {
        let urlText = text.replacingOccurrences(of: " ", with: "%20")
        guard let components = URLComponents(string: urlText), isKnownMapLocation(components) else { return nil }

        if let coordinate = coordinateFromItems(
            components.queryItems ?? [],
            keys: ["ll", "q", "query", "center", "destination", "daddr", "saddr", "map", "cp"]
        ) {
            return coordinate
        }

        if let latitude = components.queryItems?.first(where: { $0.name.lowercased() == "mlat" })?.value.flatMap(Double.init),
           let longitude = components.queryItems?.first(where: { $0.name.lowercased() == "mlon" })?.value.flatMap(Double.init) {
            return validatedCoordinate(latitude: latitude, longitude: longitude)
        }

        let decodedPath = components.percentEncodedPath.removingPercentEncoding ?? components.path
        if let coordinate = coordinateFromGooglePath(decodedPath) {
            return coordinate
        }
        if let fragment = components.fragment,
           let coordinate = coordinateFromMapFragment(fragment.removingPercentEncoding ?? fragment) {
            return coordinate
        }
        return nil
    }

    private static func isKnownMapLocation(_ components: URLComponents) -> Bool {
        guard let scheme = components.scheme?.lowercased() else { return false }
        let host = components.host?.lowercased() ?? ""
        let isKnownWebHost = [
            "apple.com", "google.com", "here.com", "openstreetmap.org", "bing.com"
        ].contains { host == $0 || host.hasSuffix(".\($0)") }
        let isKnownMapScheme = ["maps", "comgooglemaps"].contains(scheme)
        return ((scheme == "http" || scheme == "https") && isKnownWebHost) || isKnownMapScheme
    }

    private static func isCoordinateShaped(_ text: String) -> Bool {
        let decoded = text.removingPercentEncoding ?? text
        let range = NSRange(decoded.startIndex..., in: decoded)
        guard coordinateIntentRegex.firstMatch(in: decoded, range: range) != nil else { return false }
        let numberCount = coordinateNumberRegex.numberOfMatches(in: decoded, range: range)
        if numberCount >= 2 { return true }
        return numberCount == 1
            && singleCoordinateIntentRegex.firstMatch(in: decoded, range: range) != nil
    }

    private static func coordinateFromQuery(_ query: String, keys: Set<String>) -> CLLocationCoordinate2D? {
        let synthetic = URLComponents(string: "https://coordinates.invalid/?\(query.replacingOccurrences(of: " ", with: "%20"))")
        return coordinateFromItems(synthetic?.queryItems ?? [], keys: keys)
    }

    private static func coordinateFromItems(
        _ items: [URLQueryItem],
        keys: Set<String>
    ) -> CLLocationCoordinate2D? {
        for item in items where keys.contains(item.name.lowercased()) {
            guard let value = item.value else { continue }
            if let coordinate = parseCoordinateBearingValue(value, allowsTrailingFields: true) {
                return coordinate
            }
        }
        return nil
    }

    private static func parseCoordinateBearingValue(
        _ value: String,
        allowsTrailingFields: Bool
    ) -> CLLocationCoordinate2D? {
        let decoded = (value.removingPercentEncoding ?? value)
            .replacingOccurrences(of: "loc:", with: "", options: [.caseInsensitive, .anchored])
        let regex = allowsTrailingFields ? leadingCoordinatePairRegex : exactCoordinatePairRegex
        guard let match = regex.firstMatch(
            in: decoded,
            range: NSRange(decoded.startIndex..., in: decoded)
        ), let rawLatitude = capture("lat", match: match, text: decoded),
           let rawLongitude = capture("lng", match: match, text: decoded),
           let latitude = Double(rawLatitude), let longitude = Double(rawLongitude) else { return nil }
        return validatedCoordinate(latitude: latitude, longitude: longitude)
    }

    private static func coordinateFromGooglePath(_ path: String) -> CLLocationCoordinate2D? {
        guard let match = googlePathRegex.firstMatch(
            in: path,
            range: NSRange(path.startIndex..., in: path)
        ), let rawLatitude = capture("lat", match: match, text: path),
           let rawLongitude = capture("lng", match: match, text: path),
           let latitude = Double(rawLatitude), let longitude = Double(rawLongitude) else { return nil }
        return validatedCoordinate(latitude: latitude, longitude: longitude)
    }

    private static func coordinateFromMapFragment(_ fragment: String) -> CLLocationCoordinate2D? {
        guard let match = mapFragmentRegex.firstMatch(
            in: fragment,
            range: NSRange(fragment.startIndex..., in: fragment)
        ), let rawLatitude = capture("lat", match: match, text: fragment),
           let rawLongitude = capture("lng", match: match, text: fragment),
           let latitude = Double(rawLatitude), let longitude = Double(rawLongitude) else { return nil }
        return validatedCoordinate(latitude: latitude, longitude: longitude)
    }

    // MARK: - Normalization and regular expressions

    private static func normalize(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capture(
        _ name: String,
        match: NSTextCheckingResult,
        text: String
    ) -> String? {
        let range = match.range(withName: name)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func regularExpression(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try -- all patterns are compile-time constants.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let decimalPairRegex = regularExpression(
        #"^\s*[\(\[]?\s*(?:(?<latHemiPrefix>[NS])\s*)?(?<lat>[+\-]?\d{1,3}(?:\.\d+)?)\s*°?\s*(?<latHemiSuffix>[NS])?\s*[,;/\s]\s*(?:(?<lngHemiPrefix>[EW])\s*)?(?<lng>[+\-]?\d{1,3}(?:\.\d+)?)\s*°?\s*(?<lngHemiSuffix>[EW])?\s*[\)\]]?\s*$"#
    )

    private static let dmsPairRegex = regularExpression(
        #"^\s*[\(\[]?\s*(?:(?<latHemiPrefix>[NS])\s*)?(?<latDeg>[+\-]?\d{1,3})\s*[°º]\s*(?<latMin>\d{1,2}(?:\.\d+)?)\s*['′’]\s*(?:(?<latSec>\d{1,2}(?:\.\d+)?)\s*[\"″]\s*)?(?<latHemiSuffix>[NS])?\s*[,;/\s]\s*(?:(?<lngHemiPrefix>[EW])\s*)?(?<lngDeg>[+\-]?\d{1,3})\s*[°º]\s*(?<lngMin>\d{1,2}(?:\.\d+)?)\s*['′’]\s*(?:(?<lngSec>\d{1,2}(?:\.\d+)?)\s*[\"″]\s*)?(?<lngHemiSuffix>[EW])?\s*[\)\]]?\s*$"#
    )

    private static let exactCoordinatePairRegex = regularExpression(
        #"^\s*[\(\[]?\s*(?<lat>[+\-]?\d{1,3}(?:\.\d+)?)\s*[,~]\s*(?<lng>[+\-]?\d{1,3}(?:\.\d+)?)\s*[\)\]]?\s*$"#
    )

    private static let leadingCoordinatePairRegex = regularExpression(
        #"^\s*[\(\[]?\s*(?<lat>[+\-]?\d{1,3}(?:\.\d+)?)\s*[,~]\s*(?<lng>[+\-]?\d{1,3}(?:\.\d+)?)(?:\s*[\(\),/].*)?$"#
    )

    private static let googlePathRegex = regularExpression(
        #"/@(?<lat>[+\-]?\d{1,3}(?:\.\d+)?),(?<lng>[+\-]?\d{1,3}(?:\.\d+)?)(?:,|/|$)"#
    )

    private static let mapFragmentRegex = regularExpression(
        #"(?:^|&)map=\d+(?:\.\d+)?/(?<lat>[+\-]?\d{1,3}(?:\.\d+)?)/(?<lng>[+\-]?\d{1,3}(?:\.\d+)?)(?:&|$)"#
    )

    private static let coordinateIntentRegex = regularExpression(
        #"^\s*[\(\[\{]?[NSEW+\-\d.,;/~°º'′’\"″\s]+[\)\]\}]?\s*$"#
    )

    private static let coordinateNumberRegex = regularExpression(
        #"[+\-]?\d+(?:\.\d+)?"#
    )

    private static let singleCoordinateIntentRegex = regularExpression(
        #"^\s*[NSEW]?\s*[+\-]?\d{1,3}(?:\.\d+)?\s*°?\s*[NSEW]?\s*$"#
    )
}
