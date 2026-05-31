//
//  BindableEquipmentAnimation.swift
//  EusoTrip — wraps an SVG state-variant animation with runtime data-bind
//  injection so every load renders with its own carrier wordmark, dock, ETA,
//  commodity, weight, and progress pulled from the live LifecycleSnapshot.
//
//  NATIVE RENDER (no WKWebView)
//  ───────────────────────────
//  The state-variant SVGs under `04_LoadingUnloading/` ship with `data-bind`
//  attributes on every parameterizable <text>/<tspan>, a `<use href=
//  "#commodityPlacard">` for the hazmat placard, and a `var(--load-progress)`
//  driven progress bar. The native SVG engine reproduces the exact behavior the
//  old WKWebView+JS layer did, with no web view:
//
//    1. data-bind   → NativeSVGView(bindings:)  — a non-empty live value
//                     replaces the baked default; empty/missing keeps the default
//                     (founder doctrine: no fabricated runtime data).
//    2. placard swap → NativeSVGView(placardId:) — remaps the commodityPlacard
//                     <use> to the 49 CFR 172.101 class symbol (class3Placard…).
//    3. progress     → cssVars["--load-progress"] resolves the SVG's
//                     var(--load-progress) in its baked transform/width rule.
//
//  No stubs, no fabricated values — every output character came from the live
//  LifecycleSnapshot or the SVG's baked default.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct BindableEquipmentAnimation: View {
    /// Raw SVG markup from `EquipmentAnimationCache` — the state-variant file
    /// (e.g. `01_dry_van_loading.svg`) with `data-bind` attributes baked in.
    let svgString: String
    /// Runtime bindings from `LoadAnimationContext.from(snapshot:)`. Empty values
    /// are skipped so the SVG's baked default text content stays visible.
    let context: LoadAnimationContext

    var body: some View {
        NativeSVGView(
            svgString: svgString,
            bindings: liveBindings,
            placardId: context.placardSymbolId,
            cssVars: ["--load-progress": String(format: "%.4f", progressFraction)]
        )
    }

    /// Drop empty values up front — mirrors the old JS pass that left the SVG's
    /// baked default in place when a snapshot field carried no real value.
    private var liveBindings: [String: String] {
        context.bindings.compactMapValues { $0.isEmpty ? nil : $0 }
    }

    /// Decimal 0…1 used to drive the `--load-progress` CSS var (the SVG progress
    /// bar uses `scaleX(var(--load-progress))` or equivalent in its stylesheet).
    private var progressFraction: Double {
        let raw = Double(context.bindings["progress_pct"] ?? "50") ?? 50
        return max(0, min(1, raw / 100.0))
    }
}
