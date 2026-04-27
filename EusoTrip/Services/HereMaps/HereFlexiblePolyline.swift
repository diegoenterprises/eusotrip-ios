//
//  HereFlexiblePolyline.swift
//  EusoTrip — Decode HERE's flexible polyline format into CLLocationCoordinate2D
//
//  Spec: https://github.com/heremaps/flexible-polyline
//
//  HERE encodes polylines with variable precision (5/6/7 decimals) and an
//  optional 3D elevation channel. This pure-Swift decoder covers the 2D case
//  (lat/lng only) which is all we need for rendering route overlays.
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

enum HereFlexiblePolyline {

    static let decodingTable: [Int] = {
        // Reverse lookup for the URL-safe base64 alphabet HERE uses.
        var t = [Int](repeating: -1, count: 128)
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for (i, c) in alphabet.enumerated() { t[Int(c.asciiValue!)] = i }
        return t
    }()

    /// Decode a flexible polyline into an array of `CLLocationCoordinate2D`.
    /// Returns an empty array on malformed input (silent failure is fine —
    /// the map will just not show a route overlay).
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        guard !encoded.isEmpty else { return [] }
        let bytes = [UInt8](encoded.utf8)

        var index = 0

        // Header: version (5 bits), precision (4 bits), thirdDimType (3 bits), thirdDimPrec (4 bits)
        guard let header = decodeUnsigned(bytes, &index) else { return [] }
        let precision = Int(header & 0x0F)
        let thirdDimType = Int((header >> 4) & 0x07)
        let thirdDimPrec = Int((header >> 7) & 0x0F)

        let factor = pow(10.0, Double(precision))
        _ = thirdDimPrec
        let has3D = thirdDimType != 0

        var lastLat: Int64 = 0
        var lastLng: Int64 = 0
        var out: [CLLocationCoordinate2D] = []

        while index < bytes.count {
            guard let dLat = decodeSigned(bytes, &index) else { break }
            guard let dLng = decodeSigned(bytes, &index) else { break }
            if has3D {
                _ = decodeSigned(bytes, &index)   // drop elevation
            }
            lastLat &+= dLat
            lastLng &+= dLng
            out.append(CLLocationCoordinate2D(
                latitude:  Double(lastLat) / factor,
                longitude: Double(lastLng) / factor
            ))
        }
        return out
    }

    // MARK: - Varint decode

    private static func decodeUnsigned(_ bytes: [UInt8], _ i: inout Int) -> UInt64? {
        var shift: UInt64 = 0
        var result: UInt64 = 0
        while i < bytes.count {
            let b = bytes[i]; i += 1
            let code = Int(b) < decodingTable.count ? decodingTable[Int(b)] : -1
            guard code >= 0 else { return nil }
            result |= UInt64(code & 0x1F) << shift
            if code & 0x20 == 0 { return result }
            shift += 5
            if shift > 63 { return nil }
        }
        return nil
    }

    private static func decodeSigned(_ bytes: [UInt8], _ i: inout Int) -> Int64? {
        guard let u = decodeUnsigned(bytes, &i) else { return nil }
        let signBit = (u & 1) != 0
        let magnitude = Int64(u >> 1)
        return signBit ? -(magnitude + 1) : magnitude
    }
}
