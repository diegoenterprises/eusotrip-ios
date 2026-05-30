//
//  BespokeMapProjection.swift
//  EusoTrip — native map projection + viewport math.
//
//  This is the pure-math core under the in-house SwiftUI map renderer that
//  drop-in replaces the WKWebView `HereMapWebViewRepresentable`. It owns the
//  one thing every map surface needs and historically got wrong: turning a
//  `HereLatLng` into a `CGPoint` in the view's coordinate space (and back),
//  given either a fixed (center, zoom) camera OR a fit-to-coords request.
//
//  Projection: standard spherical **Web Mercator** (EPSG:3857), the exact
//  projection HERE's OMV vector tiles, Google, Mapbox and MapKit all use. We
//  work in a normalized "world unit square" [0,1] × [0,1] where (0,0) is the
//  north-west corner (lng −180, lat ~+85.0511°) and (1,1) is the south-east
//  corner (lng +180, lat ~−85.0511°). That square scales by `worldPx =
//  256 · 2^zoom` to give absolute world pixels, matching the slippy-tile
//  convention (256 px tiles, one tile at zoom 0). The viewport then offsets
//  world pixels by the camera's world-pixel origin to land in screen space.
//
//  DESIGN INVARIANTS
//   • Pure + deterministic. No `Date`, no RNG, no global mutable state. Same
//     inputs → byte-identical outputs. Safe to call from layout, gestures,
//     and snapshot tests.
//   • No UIKit / WebKit. SwiftUI (CGPoint/CGSize), CoreLocation, Foundation
//     only — so it compiles on every platform the app targets, watchOS and
//     visionOS included.
//   • Reuses the canonical `HereLatLng` data contract verbatim
//     (Services/HereMaps/HereMapWebView.swift). It does NOT redeclare it.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation
import Foundation

// MARK: - Web Mercator projection (EPSG:3857)

/// Stateless forward/inverse Web Mercator projection into the normalized
/// world unit square `[0,1] × [0,1]` (NW origin, Y grows southward).
///
/// Forward (per the slippy-map standard, with `rad = lat · π/180`):
/// ```
/// x = (lng + 180) / 360
/// y = (1 − ln( tan(rad) + 1/cos(rad) ) / π) / 2
/// ```
/// Mercator cannot represent the true poles (Y → ±∞), so latitude is clamped
/// to ±`maxLatitude` (the value at which the projected world becomes square),
/// exactly as every web map does.
public enum BespokeMapProjection {

    /// Maximum latitude representable in Web Mercator before the projection
    /// blows up: `atan(sinh(π)) · 180/π ≈ 85.05112878°`. Beyond this the world
    /// square would no longer be square.
    public static let maxLatitude: Double = 85.05112877980659

    /// Tile size in pixels at integer zoom. One 256 px tile covers the whole
    /// world at zoom 0; `worldPx(at:) = tileSize · 2^zoom`.
    public static let tileSize: Double = 256.0

    /// Forward projection: geographic coordinate → normalized world point.
    /// Result components are in `[0,1]` (X always; Y within the clamped
    /// latitude band). `(0,0)` = NW corner, `(1,1)` = SE corner.
    public static func project(_ coord: HereLatLng) -> CGPoint {
        let lat = clampLatitude(coord.lat)
        let lng = coord.lng

        let x = (lng + 180.0) / 360.0

        let radLat = lat * .pi / 180.0
        // tan(rad) + 1/cos(rad) == tan(π/4 + rad/2); the explicit form matches
        // the documented data contract and is numerically equivalent.
        let y = (1.0 - log(tan(radLat) + 1.0 / cos(radLat)) / .pi) / 2.0

        return CGPoint(x: x, y: y)
    }

    /// Inverse projection: normalized world point → geographic coordinate.
    /// The exact analytic inverse of `project(_:)`.
    public static func unproject(_ world: CGPoint) -> HereLatLng {
        let nx = Double(world.x)
        let ny = Double(world.y)

        let lng = nx * 360.0 - 180.0

        // Invert y = (1 − ln(tan + sec)/π)/2  ⇒  lat = atan(sinh(π(1 − 2y)))
        let n = Double.pi * (1.0 - 2.0 * ny)
        let lat = atan(sinh(n)) * 180.0 / .pi

        return HereLatLng(clampLatitude(lat), lng)
    }

    /// Absolute world size in pixels at a (possibly fractional) zoom level:
    /// `tileSize · 2^zoom`.
    public static func worldPixels(at zoom: Double) -> Double {
        tileSize * pow(2.0, zoom)
    }

    /// Clamp latitude to the Mercator-valid band `[−maxLatitude, +maxLatitude]`.
    public static func clampLatitude(_ lat: Double) -> Double {
        Swift.min(Swift.max(lat, -maxLatitude), maxLatitude)
    }

    // MARK: Great-circle distance (deterministic helper)

    /// Haversine great-circle distance between two coordinates, in meters.
    /// Pure helper for callers that need to size symbols / radii in real-world
    /// units without pulling in `CLLocation` (which is `Date`-tainted on init).
    public static func haversineMeters(_ a: HereLatLng, _ b: HereLatLng) -> Double {
        let earthRadius = 6_371_008.8 // mean Earth radius (meters), IUGG
        let dLat = (b.lat - a.lat) * .pi / 180.0
        let dLng = (b.lng - a.lng) * .pi / 180.0
        let lat1 = a.lat * .pi / 180.0
        let lat2 = b.lat * .pi / 180.0
        let h = sin(dLat / 2) * sin(dLat / 2)
              + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
        return 2.0 * earthRadius * asin(Swift.min(1.0, sqrt(h)))
    }

    // MARK: Great-circle interpolation (slerp on the unit sphere)

    /// Spherical-linear-interpolate (slerp) a single point a fraction `t`
    /// (`0…1`) along the great-circle arc from `a` to `b`. At `t == 0` returns
    /// `a`, at `t == 1` returns `b`. The interpolation is exact on the sphere,
    /// so when the result is fed back through `project(_:)` it traces the
    /// curved Mercator arc an ocean leg actually follows — NOT the straight
    /// rhumb line a naïve lng/lat lerp would draw.
    ///
    /// Pure + deterministic (no `Date`, no RNG). Antimeridian-safe: it works in
    /// 3-D Cartesian space, so a Shanghai→Long Beach leg that crosses 180°
    /// interpolates correctly without longitude wraparound artefacts.
    public static func slerp(_ a: HereLatLng, _ b: HereLatLng, t: Double) -> HereLatLng {
        let tt = Swift.min(1.0, Swift.max(0.0, t))
        // Geographic → unit Cartesian (right-handed, +Z = north pole).
        let aLat = a.lat * .pi / 180.0, aLng = a.lng * .pi / 180.0
        let bLat = b.lat * .pi / 180.0, bLng = b.lng * .pi / 180.0
        let ax = cos(aLat) * cos(aLng), ay = cos(aLat) * sin(aLng), az = sin(aLat)
        let bx = cos(bLat) * cos(bLng), by = cos(bLat) * sin(bLng), bz = sin(bLat)

        // Angular distance between the two unit vectors.
        let dot = Swift.min(1.0, Swift.max(-1.0, ax * bx + ay * by + az * bz))
        let omega = acos(dot)
        // Coincident / antipodal endpoints: no unique arc → fall back to the
        // endpoint nearest `tt` (avoids a 0/0 in the sin(omega) divisor).
        guard omega > 1e-9, sin(omega) > 1e-9 else {
            return tt < 0.5 ? a : b
        }
        let s0 = sin((1.0 - tt) * omega) / sin(omega)
        let s1 = sin(tt * omega) / sin(omega)
        let x = s0 * ax + s1 * bx
        let y = s0 * ay + s1 * by
        let z = s0 * az + s1 * bz

        let lat = atan2(z, sqrt(x * x + y * y)) * 180.0 / .pi
        let lng = atan2(y, x) * 180.0 / .pi
        return HereLatLng(clampLatitude(lat), lng)
    }

    /// Interpolate `count` points (inclusive of both endpoints, so
    /// `count >= 2`) evenly along the great-circle arc from `origin` to `dest`.
    /// The returned polyline curves correctly under Web Mercator and is the
    /// ocean-route geometry the bespoke canvas paints (solid traveled →
    /// dashed remaining, split at the live-position fraction).
    public static func greatCircle(
        from origin: HereLatLng,
        to dest: HereLatLng,
        count: Int = 48
    ) -> [HereLatLng] {
        let n = Swift.max(2, count)
        var out: [HereLatLng] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            out.append(slerp(origin, dest, t: t))
        }
        return out
    }
}

// MARK: - Viewport

/// A deterministic map camera over a `CGSize` canvas. Converts between
/// geographic coordinates (`HereLatLng`) and view-local screen points
/// (`CGPoint`, origin top-left, Y down — SwiftUI's convention).
///
/// Construct it one of two ways:
///   • **Fixed camera** — `init(center:zoom:size:)`: you supply the center
///     coordinate and an integer (slippy) zoom; the canvas is centered on it.
///   • **Fit-to-coords** — `init(fitting:size:padding:minZoom:maxZoom:)`: you
///     supply a bag of coordinates and the viewport solves for the
///     highest (fractional) zoom + center that fits them all inside the
///     padded canvas. Empty / degenerate inputs fall back to a world view.
///
/// Both paths are pure: identical inputs yield an identical viewport, and
/// every `screenPoint` / `coordinate` round-trips exactly (within FP).
public struct BespokeMapViewport: Equatable {

    /// Camera center.
    public let center: HereLatLng
    /// Fractional zoom (integer for the fixed-camera initializer; solved value
    /// for the fit initializer). `worldPx = 256 · 2^zoom`.
    public let zoom: Double
    /// Canvas size in points the camera renders into.
    public let size: CGSize

    // Cached world-pixel frame so screenPoint / coordinate are O(1).
    private let worldPx: Double
    private let centerWorld: CGPoint   // center projected → world pixels

    // MARK: Fixed camera

    /// Center + integer zoom over a canvas. This matches the HERE renderer
    /// entry-point contract `(center:HereLatLng, zoom:Int, …)`.
    public init(center: HereLatLng, zoom: Int, size: CGSize) {
        self.init(center: center, fractionalZoom: Double(zoom), size: size)
    }

    /// Center + fractional zoom over a canvas (used internally by `fitting`,
    /// and available for smooth pinch-zoom where zoom is continuous).
    public init(center: HereLatLng, fractionalZoom: Double, size: CGSize) {
        let safeSize = BespokeMapViewport.sanitize(size)
        let z = fractionalZoom.isFinite ? fractionalZoom : 0
        self.center = center
        self.zoom = z
        self.size = safeSize
        self.worldPx = BespokeMapProjection.worldPixels(at: z)
        let cw = BespokeMapProjection.project(center)
        self.centerWorld = CGPoint(x: cw.x * worldPx, y: cw.y * worldPx)
    }

    // MARK: Fit-to-coords

    /// Solve for the camera that fits every coordinate inside the canvas,
    /// inset by `padding` points on all sides.
    ///
    /// - The center is the mid-point of the coords' projected bounding box.
    /// - The zoom is the largest value at which the box's world-pixel span
    ///   still fits the padded canvas on both axes, clamped to
    ///   `[minZoom, maxZoom]`.
    /// - A single coordinate (or a zero-extent box) can't imply a scale, so it
    ///   is centered at `maxZoom`. An empty set falls back to the whole world
    ///   (center 0,0 at `minZoom`).
    public init(
        fitting coords: [HereLatLng],
        size: CGSize,
        padding: CGFloat = 24,
        minZoom: Double = 0,
        maxZoom: Double = 20
    ) {
        let safeSize = BespokeMapViewport.sanitize(size)
        let pad = Swift.max(0, Double(padding))

        // Usable canvas after symmetric padding (never below 1px to avoid /0).
        let usableW = Swift.max(1.0, Double(safeSize.width) - 2 * pad)
        let usableH = Swift.max(1.0, Double(safeSize.height) - 2 * pad)

        // Project every coord into the normalized world square and bound it.
        guard !coords.isEmpty else {
            self.init(center: HereLatLng(0, 0), fractionalZoom: minZoom, size: safeSize)
            return
        }

        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for c in coords {
            let p = BespokeMapProjection.project(c)
            minX = Swift.min(minX, Double(p.x)); maxX = Swift.max(maxX, Double(p.x))
            minY = Swift.min(minY, Double(p.y)); maxY = Swift.max(maxY, Double(p.y))
        }

        // Center = midpoint of the normalized box, unprojected back to geo.
        let midWorld = CGPoint(x: (minX + maxX) / 2.0, y: (minY + maxY) / 2.0)
        let fitCenter = BespokeMapProjection.unproject(midWorld)

        // Normalized box extent (fraction of the whole world, [0,1]).
        let spanX = maxX - minX
        let spanY = maxY - minY

        let loZoom = Swift.min(minZoom, maxZoom)
        let hiZoom = Swift.max(minZoom, maxZoom)

        // Degenerate box (single point / colinear on an axis): no scale info,
        // so zoom in as far as allowed and just center on it.
        guard spanX > 1e-12 || spanY > 1e-12 else {
            self.init(center: fitCenter, fractionalZoom: hiZoom, size: safeSize)
            return
        }

        // Required world-pixel size on each axis = usable / normalizedSpan.
        // zoom = log2(requiredWorldPx / tileSize). Take the tighter axis so
        // BOTH fit; guard zero spans so a thin box only constrains its real axis.
        let t = BespokeMapProjection.tileSize
        var candidate = hiZoom
        if spanX > 1e-12 {
            candidate = Swift.min(candidate, log2(usableW / (spanX * t)))
        }
        if spanY > 1e-12 {
            candidate = Swift.min(candidate, log2(usableH / (spanY * t)))
        }
        let solvedZoom = Swift.min(hiZoom, Swift.max(loZoom, candidate))

        self.init(center: fitCenter, fractionalZoom: solvedZoom, size: safeSize)
    }

    // MARK: Forward / inverse mapping

    /// Project a geographic coordinate to a view-local screen point.
    /// Origin top-left, +X right, +Y down (SwiftUI). Points outside the canvas
    /// are returned too (negative / overflow) so callers can cull or draw
    /// off-screen leader lines — this method never clamps.
    public func screenPoint(_ coord: HereLatLng) -> CGPoint {
        let w = BespokeMapProjection.project(coord)
        let worldX = Double(w.x) * worldPx
        let worldY = Double(w.y) * worldPx
        return CGPoint(
            x: worldX - Double(centerWorld.x) + Double(size.width) / 2.0,
            y: worldY - Double(centerWorld.y) + Double(size.height) / 2.0
        )
    }

    /// Inverse of `screenPoint(_:)` — a view-local point back to geo.
    public func coordinate(_ point: CGPoint) -> HereLatLng {
        let worldX = Double(point.x) - Double(size.width) / 2.0 + Double(centerWorld.x)
        let worldY = Double(point.y) - Double(size.height) / 2.0 + Double(centerWorld.y)
        // Wrap X into the valid world span so a point dragged past the
        // antimeridian still inverts to a real longitude; Y is clamped by
        // unproject's latitude clamp.
        let nxRaw = worldX / worldPx
        let nx = nxRaw - floor(nxRaw)               // wrap into [0,1) for longitude
        let ny = Swift.min(1.0, Swift.max(0.0, worldY / worldPx))
        return BespokeMapProjection.unproject(CGPoint(x: nx, y: ny))
    }

    /// `true` iff every coordinate currently projects inside the canvas
    /// (with an optional inset `margin`, in points — positive shrinks the
    /// accepted area, modeling the same padding used when fitting). An empty
    /// set vacuously fits.
    public func fits(_ coords: [HereLatLng], margin: CGFloat = 0) -> Bool {
        let m = Double(margin)
        let minX = m, minY = m
        let maxX = Double(size.width) - m
        let maxY = Double(size.height) - m
        for c in coords {
            let p = screenPoint(c)
            if Double(p.x) < minX || Double(p.x) > maxX ||
               Double(p.y) < minY || Double(p.y) > maxY {
                return false
            }
        }
        return true
    }

    /// The geographic bounding box currently visible in the canvas, as
    /// `(northWest, southEast)` corners. Useful for tile/marker culling.
    public var visibleBounds: (northWest: HereLatLng, southEast: HereLatLng) {
        let nw = coordinate(CGPoint(x: 0, y: 0))
        let se = coordinate(CGPoint(x: size.width, y: size.height))
        return (nw, se)
    }

    /// Meters represented by one screen point at the viewport center
    /// (Web Mercator's latitude-dependent ground resolution). Lets symbol/
    /// stroke sizing track real-world scale deterministically.
    public var metersPerPoint: Double {
        let circumference = 2.0 * Double.pi * 6_378_137.0 // equatorial, meters
        let latRad = BespokeMapProjection.clampLatitude(center.lat) * .pi / 180.0
        return circumference * cos(latRad) / worldPx
    }

    // MARK: Utilities

    /// Guard against NaN / non-positive canvas sizes from early layout passes.
    private static func sanitize(_ size: CGSize) -> CGSize {
        let w = (size.width.isFinite && size.width > 0) ? size.width : 1
        let h = (size.height.isFinite && size.height > 0) ? size.height : 1
        return CGSize(width: w, height: h)
    }
}
