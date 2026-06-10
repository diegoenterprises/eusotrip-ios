//
//  NativeSVGView.swift
//  EusoTrip — Native SVG renderer · public SwiftUI surface.
//
//  Drop-in replacement for the WKWebView SVG host: renders a bundled/inline SVG
//  natively via SwiftUI Canvas, driven by TimelineView for CSS @keyframes / SMIL
//  animation. Parsing+baking is cached per SVG string. Honors Reduce Motion
//  (renders the AUTHOR-designed calm pose from the prefers-reduced-motion CSS
//  bucket) and Dark Mode (@media (prefers-color-scheme: dark)).
//
//  Wave E (2026-06-10):
//    • country     — COUNTRY-GROUP TOGGLE: exactly one of .country-US/-MX/-CA
//                    renders per pass; nil = US default, never multiple.
//    • clockReference / crossfade — lifecycle continuity: state-variant swaps
//                    crossfade (~300ms) and the wheel/strobe phase carries
//                    across the swap instead of resetting.
//    • paused / minimumFrameInterval — clock hygiene for offscreen/settled
//                    strips; static documents never mount a TimelineView.
//    • cache key   — full SVG string (the old hashValue key could silently
//                    return the WRONG document on a collision).
//    • DEBUG       — one-shot diagnostic when bindings/cssVars are fed to a
//                    document with zero hooks (the silent-fail trap class).
//

import SwiftUI

/// Parsed+baked document cache so each unique SVG is compiled once, not per frame.
final class SVGDocumentCache {
    static let shared = SVGDocumentCache()
    private final class Box { let doc: SVGDocument; init(_ d: SVGDocument) { doc = d } }
    private let cache = NSCache<NSString, Box>()
    private init() { cache.countLimit = 256 }

    func document(for svg: String) -> SVGDocument? {
        // Key on the FULL string: `String(svg.hashValue)` could silently hand
        // back the wrong document on a hash collision (engine census, frame
        // pacing row). The NSString bridge cost is paid per body evaluation,
        // never per frame.
        let key = svg as NSString
        if let hit = cache.object(forKey: key) { return hit.doc }
        guard let doc = SVGParser.parse(string: svg) else { return nil }
        cache.setObject(Box(doc), forKey: key)
        return doc
    }
}

#if DEBUG
/// One-shot per-document warnings for the decode-shape silent-fail trap
/// analog: live data wired to a document that has no hooks for it renders
/// pixels that LOOK fine while every binding silently no-ops.
enum SVGBindingDiagnostics {
    private static var checked = Set<ObjectIdentifier>()
    private static let lock = NSLock()

    static func checkOnce(doc: SVGDocument, bindings: [String: String], cssVars: [String: String]) {
        guard !bindings.isEmpty || !cssVars.isEmpty else { return }
        let key = ObjectIdentifier(doc.root)
        lock.lock()
        defer { lock.unlock() }
        guard !checked.contains(key) else { return }
        checked.insert(key)

        var warnings: [String] = []
        if !bindings.isEmpty {
            if doc.bindKeys.isEmpty {
                warnings.append("\(bindings.count) binding(s) supplied but the document has ZERO data-bind hooks — every binding is a silent no-op (hero corpus fed to the bindable pipeline?)")
            } else {
                let dead = bindings.keys.filter { !doc.bindKeys.contains($0) }.sorted()
                if !dead.isEmpty {
                    warnings.append("binding key(s) with no data-bind hook in the document: \(dead.joined(separator: ", "))")
                }
            }
        }
        if !cssVars.isEmpty && !doc.usesCSSVars {
            warnings.append("\(cssVars.count) cssVar(s) supplied but the document has no var() consumers")
        }
        for w in warnings {
            print("[NativeSVG] ⚠️ \(w)")
        }
    }
}
#endif

struct NativeSVGView: View {
    let svgString: String
    /// Live `data-bind` key → value (e.g. carrier wordmark, ETA, commodity).
    var bindings: [String: String] = [:]
    /// Hazmat class symbol id to remap `<use href="#commodityPlacard">`.
    var placardId: String? = nil
    /// CSS custom properties resolved into `var(--name)` refs (e.g. --load-progress).
    var cssVars: [String: String] = [:]
    /// COUNTRY-GROUP TOGGLE — which of the authored `.country-US/-MX/-CA`
    /// regulatory groups renders. Exactly ONE country renders per pass;
    /// nil shows the US default (never multiple). Wave C wires the real
    /// load region through here.
    var country: SVGCountry? = nil
    /// Freeze the animation clock without unmounting (offscreen/settled strips).
    var paused: Bool = false
    /// Shared clock epoch so wheel/strobe phase carries across state-variant
    /// swaps AND view remounts (lifecycle continuity — key the clock to the
    /// strip's first appearance, not the SVG string). nil = per-view clock.
    var clockReference: Date? = nil
    /// Animation frame budget. Default 60fps — the corpus' slow operational
    /// beats gain nothing from 120Hz; callers can lower it further for dense
    /// boards or pass nil for the display's native cadence.
    var minimumFrameInterval: Double? = 1.0 / 60.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var start = Date()

    var body: some View {
        ZStack {
            if let doc = SVGDocumentCache.shared.document(for: svgString) {
                content(doc)
                    // Identity per parsed document → an svgString swap is an
                    // insert+remove pair, which the .opacity transition turns
                    // into a ~300ms crossfade instead of a hard cut.
                    .id(ObjectIdentifier(doc.root))
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .animation(.easeInOut(duration: 0.3), value: svgString)
    }

    @ViewBuilder
    private func content(_ doc: SVGDocument) -> some View {
        let dark = colorScheme == .dark
        #if DEBUG
        let _ = SVGBindingDiagnostics.checkOnce(doc: doc, bindings: bindings, cssVars: cssVars)
        #endif
        if reduceMotion || !doc.isAnimated {
            // Reduce Motion renders the AUTHORED calm pose: the baked cascade
            // includes the prefers-reduced-motion rule bucket, so dust wisps,
            // streams, and strobes land where the author parked them.
            // Static (animation-free) documents also take this path — no
            // TimelineView clock to begin with.
            Canvas { ctx, size in
                SVGRenderer.render(document: doc, into: ctx, size: size, time: 0,
                                   reduceMotion: reduceMotion, dark: dark,
                                   bindings: bindings, placardId: placardId,
                                   cssVars: cssVars, country: country)
            }
        } else {
            TimelineView(.animation(minimumInterval: minimumFrameInterval, paused: paused)) { timeline in
                Canvas { ctx, size in
                    let t = max(0, timeline.date.timeIntervalSince(clockReference ?? start))
                    SVGRenderer.render(document: doc, into: ctx, size: size, time: t,
                                       reduceMotion: false, dark: dark,
                                       bindings: bindings, placardId: placardId,
                                       cssVars: cssVars, country: country)
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
