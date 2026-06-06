//
//  BespokeMapBasemap.swift
//  EusoTrip — the in-house abstract basemap geometry for `BespokeMapCanvas`.
//
//  WHY THIS EXISTS
//  The bespoke SwiftUI Canvas renderer historically painted ONLY a backdrop
//  gradient + a ~6%-opacity graticule + a couple of decorative horizon
//  ribbons. With no route/markers handed in (e.g. Shipper Control Tower /
//  Live Tracking framing CONUS before per-load coords land), that reads as a
//  near-blank panel — the "maps blank" P0. The web platform never has this
//  problem because it always mounts an OMV tile basemap UNDER whatever data
//  a screen draws.
//
//  This file is the parity fix: a small, deterministic set of *abstract*
//  continental coastline rings (simplified — NOT real streets, matching the
//  bespoke-cartography doctrine) that the canvas projects through the SAME
//  Web-Mercator `BespokeMapViewport` as the route/markers. The land reads as
//  a real basemap, pans/zooms with the camera, and is painted in the
//  register's own land/coast hue so it never fights the brand cartography.
//  No WKWebView, no MapKit, no tiles, no network — pure geometry.
//
//  The rings are intentionally coarse (a few dozen vertices per continent).
//  At a continental / world camera they read as recognizable landmasses; the
//  route + endpoints + live puck remain the focal layer on top.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Abstract continental geometry (lng/lat rings)

/// Deterministic, coarse coastline rings for the abstract basemap. Each ring
/// is an ordered list of `(lng, lat)` vertices in degrees, closed implicitly
/// by the renderer. These are stylized silhouettes — enough fidelity to read
/// as "North America", "South America", etc. at a board/world camera, never a
/// surveyed boundary.
enum BespokeMapBasemap {

    /// All continental rings the canvas paints as the abstract land layer.
    /// Ordered largest-first so smaller landmasses overpaint cleanly.
    static let continents: [[(lng: Double, lat: Double)]] = [
        northAmerica,
        southAmerica,
        eurasia,
        africa,
        oceania,
    ]

    // North America (incl. a coarse Gulf/Mexico taper) — the primary truck/
    // rail theatre, so it carries the most vertices of the set.
    static let northAmerica: [(lng: Double, lat: Double)] = [
        (-168, 65), (-160, 71), (-141, 70), (-128, 70), (-115, 69),
        (-101, 69), (-95, 72), (-83, 73), (-73, 68), (-64, 60),
        (-56, 53), (-52, 47), (-66, 44), (-70, 41), (-76, 37),
        (-81, 31), (-80, 26), (-82, 25), (-83, 29), (-90, 29),
        (-94, 29), (-97, 26), (-97, 22), (-105, 20), (-106, 23),
        (-110, 24), (-112, 29), (-117, 32), (-122, 37), (-124, 42),
        (-124, 48), (-130, 54), (-135, 58), (-148, 60), (-158, 56),
        (-165, 60), (-168, 65),
    ]

    static let southAmerica: [(lng: Double, lat: Double)] = [
        (-81, 6), (-77, 8), (-72, 11), (-64, 10), (-60, 5),
        (-51, 0), (-44, -2), (-40, -8), (-39, -13), (-41, -22),
        (-48, -25), (-54, -34), (-58, -38), (-63, -41), (-66, -45),
        (-69, -52), (-74, -52), (-73, -45), (-72, -38), (-71, -30),
        (-70, -23), (-71, -18), (-75, -14), (-79, -8), (-81, -3),
        (-80, 2), (-81, 6),
    ]

    // Eurasia — Europe + Asia as one coarse landmass (the bulk of the
    // Eastern hemisphere); kept low-vertex on purpose.
    static let eurasia: [(lng: Double, lat: Double)] = [
        (-10, 36), (-9, 43), (-2, 48), (4, 52), (8, 57),
        (12, 56), (20, 55), (28, 60), (24, 66), (33, 71),
        (50, 70), (70, 73), (90, 76), (110, 74), (130, 72),
        (150, 70), (160, 66), (170, 62), (162, 58), (150, 53),
        (140, 46), (130, 42), (122, 38), (121, 30), (110, 21),
        (105, 10), (100, 6), (98, 12), (90, 22), (80, 14),
        (72, 20), (60, 25), (50, 30), (43, 38), (36, 36),
        (28, 36), (18, 40), (10, 37), (-10, 36),
    ]

    static let africa: [(lng: Double, lat: Double)] = [
        (-17, 21), (-16, 28), (-6, 36), (10, 37), (20, 32),
        (25, 32), (33, 31), (43, 12), (51, 12), (43, -1),
        (40, -15), (35, -22), (26, -34), (18, -34), (12, -17),
        (9, -1), (9, 4), (-4, 5), (-12, 8), (-17, 15),
        (-17, 21),
    ]

    static let oceania: [(lng: Double, lat: Double)] = [
        (113, -22), (122, -18), (130, -12), (137, -12), (142, -11),
        (146, -19), (153, -25), (150, -38), (141, -38), (134, -32),
        (126, -32), (115, -34), (113, -27), (113, -22),
    ]
}
