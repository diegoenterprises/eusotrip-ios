//
//  NativeSVGView.swift
//  EusoTrip — Native SVG renderer · public SwiftUI surface.
//
//  Drop-in replacement for the WKWebView SVG host: renders a bundled/inline SVG
//  natively via SwiftUI Canvas, driven by TimelineView for CSS @keyframes / SMIL
//  animation. Parsing is cached per SVG string. Honors Reduce Motion (freezes to
//  the first frame) and Dark Mode (applies @media (prefers-color-scheme: dark)).
//

import SwiftUI

/// Parsed-document cache so each unique SVG is parsed once, not per frame.
final class SVGDocumentCache {
    static let shared = SVGDocumentCache()
    private final class Box { let doc: SVGDocument; init(_ d: SVGDocument) { doc = d } }
    private let cache = NSCache<NSString, Box>()
    private init() { cache.countLimit = 256 }

    func document(for svg: String) -> SVGDocument? {
        let key = String(svg.hashValue) as NSString
        if let hit = cache.object(forKey: key) { return hit.doc }
        guard let doc = SVGParser.parse(string: svg) else { return nil }
        cache.setObject(Box(doc), forKey: key)
        return doc
    }
}

struct NativeSVGView: View {
    let svgString: String
    /// Live `data-bind` key → value (e.g. carrier wordmark, ETA, commodity).
    var bindings: [String: String] = [:]
    /// Hazmat class symbol id to remap `<use href="#commodityPlacard">`.
    var placardId: String? = nil
    /// CSS custom properties resolved into `var(--name)` refs (e.g. --load-progress).
    var cssVars: [String: String] = [:]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var start = Date()

    var body: some View {
        if let doc = SVGDocumentCache.shared.document(for: svgString) {
            content(doc)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func content(_ doc: SVGDocument) -> some View {
        let dark = colorScheme == .dark
        if reduceMotion {
            Canvas { ctx, size in
                SVGRenderer.render(document: doc, into: ctx, size: size, time: 0,
                                   reduceMotion: true, dark: dark,
                                   bindings: bindings, placardId: placardId, cssVars: cssVars)
            }
        } else {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let t = max(0, timeline.date.timeIntervalSince(start))
                    SVGRenderer.render(document: doc, into: ctx, size: size, time: t,
                                       reduceMotion: false, dark: dark,
                                       bindings: bindings, placardId: placardId, cssVars: cssVars)
                }
            }
        }
    }
}

extension NativeSVGView {
    /// Load by bundle resource name (e.g. "01_dry_van_anim"), searching the
    /// Equipment animation subdirectories. Returns an empty view on miss.
    init?(bundleName: String, subdirectory: String? = nil) {
        let candidates: [String?] = subdirectory != nil
            ? [subdirectory]
            : [nil, "Animations/Equipment", "Animations/Equipment/01_Truck",
               "Animations/Equipment/02_Rail", "Animations/Equipment/03_Vessel"]
        var found: String? = nil
        for sub in candidates {
            if let url = Bundle.main.url(forResource: bundleName, withExtension: "svg", subdirectory: sub),
               let s = try? String(contentsOf: url, encoding: .utf8) {
                found = s; break
            }
        }
        guard let svg = found else { return nil }
        self.svgString = svg
    }
}
