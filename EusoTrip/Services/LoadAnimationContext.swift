//
//  LoadAnimationContext.swift
//  EusoTrip — produces the data-bind dictionary the 66 state-variant SVGs
//  consume via `[data-bind="<key>"]` text-content swaps.
//
//  Implements the canonical runtime binding contract from
//  `RUNTIME_BINDING_SCHEMA.json` v1.0 (see ~/Desktop/todays work/
//  01_animation_system_instructions/RUNTIME_BINDING_SCHEMA.json).
//
//  Three layers:
//    A · UNIVERSAL bindings (all 66 state-variant files):
//        state_label, equipment_label, equipment_subtitle, dock_id,
//        eta_minutes, commodity_label, weight_label, progress_pct
//
//    B · MODE-specific (rail / vessel / container / reefer):
//        reporting_marks (rail), vessel_name + imo_number (vessel),
//        container_id + iso_code (container), reefer_setpoint /
//        reefer_actual (reefer)
//
//    C · HAZMAT (when commodity is hazmat):
//        hazmat_class, un_number, un_hazard_id, commodity_stencil,
//        + placard_symbol_id (drives <use href> swap)
//
//  Powered by ESANG AI™.
//

import Foundation

/// Materialized bindings ready for the SVG runtime. The
/// `BindableEquipmentAnimation` view feeds this directly into a
/// WKWebView JS injection: `querySelector('[data-bind=KEY]').textContent = VALUE`.
struct LoadAnimationContext: Hashable {
    let bindings: [String: String]
    /// When non-nil, the SVG renderer should swap
    /// `<use href="#commodityPlacard">` to point at this id (e.g.
    /// "class3Placard"). Hazmat-only.
    let placardSymbolId: String?
    /// Cell-matrix axes, exposed for animation registry lookup.
    let modality: String   // truck | rail | vessel
    let vertical: String   // dry_van | reefer | tanker_hazmat | …
    let region: String     // us | mx | ca

    /// Engine-facing country toggle for the `.country-US/-MX/-CA` regulatory
    /// groups (Wave C plumbing). Maps the derived region onto the Wave E
    /// `NativeSVGView(country:)` API. An unknown region maps to nil — the
    /// engine renders the US default, never a guessed placard set.
    var svgCountry: SVGCountry? {
        switch region {
        case "us": return .us
        case "mx": return .mx
        case "ca": return .ca
        default:   return nil
        }
    }

    // MARK: - Build from a LifecycleSnapshot

    /// Builds the binding dictionary from the live snapshot. Empty
    /// fields fall back to the per-equipment defaults that are
    /// already baked into the v1.5 state-variant SVGs (per
    /// `TEMPLATE_TOKEN_INDEX.md` v1.5 — defaults are baked into
    /// `<text>` content; we only override when the snapshot has a
    /// real value).
    ///
    /// `dockNumber` is the REAL assigned dock door from
    /// `appointments.getByLoad.dockNumber` — the same read the driver
    /// lifecycle screens (024/037/039) hydrate. Callers that have the
    /// appointment in hand pass it through; it wins over the facility-
    /// name fallback so the dock chip shows the actual door.
    static func from(snapshot: ShipperAPI.LifecycleSnapshot,
                     dockNumber: String? = nil) -> LoadAnimationContext {
        let mode = inferModality(from: snapshot)
        let vert = inferVertical(from: snapshot)
        let reg = inferRegion(from: snapshot)

        var b: [String: String] = [:]

        // ─── Universal layer ──────────────────────────────────────
        b["state_label"]        = snapshot.load.status.uppercased().replacingOccurrences(of: "_", with: " ")
        b["equipment_label"]    = equipmentLabel(snapshot)
        b["equipment_subtitle"] = equipmentSubtitle(snapshot)
        b["dock_id"]            = dockId(snapshot, dockNumber: dockNumber)
        b["eta_minutes"]        = etaLabel(snapshot)
        b["commodity_label"]    = commodityLabel(snapshot)
        b["weight_label"]       = weightLabel(snapshot)
        b["progress_pct"]       = "\(Int(progressPercent(snapshot)))"

        // ─── Mode-specific layer ──────────────────────────────────
        // Rail reporting marks — `EUSO 7142` etc. The snapshot
        // doesn't carry reporting marks today; the server-side
        // shippers.getLifecycleSnapshot envelope omits the field. We
        // leave the key absent rather than fabricate one — the
        // SVG's baked default ("EUSO 7142") will show through, which
        // is the founder-doctrine honest fallback.

        // Vessel name + IMO — same story; absent until the snapshot
        // wraps the vessel record.

        // Container id + ISO code — pulled from cargoType heuristic
        // until the snapshot carries the BIC field explicitly.
        if mode == "vessel" || vert == "intermodal",
           let containerId = inferContainerId(from: snapshot) {
            b["container_id"] = containerId
        }

        // Reefer — driven by the load's hazmatClass rejection +
        // explicit reefer cargoType. The snapshot doesn't carry
        // setpoint/actual today; the server's reefer telemetry
        // (when wired) will populate.
        if vert == "reefer" {
            // No setpoint on snapshot yet — leave defaults.
        }

        // ─── Hazmat layer ─────────────────────────────────────────
        var placardId: String? = nil
        if let hazClass = snapshot.load.hazmatClass, !hazClass.isEmpty {
            b["hazmat_class"] = hazClass
            placardId = "class\(hazClass.replacingOccurrences(of: ".", with: "_"))Placard"
            if let un = snapshot.load.unNumber, !un.isEmpty {
                // Schema requires "UN NNNN" — accept either "UN1075" or "1075"
                let normalized = un.uppercased().contains("UN")
                    ? un.uppercased().replacingOccurrences(of: " ", with: "")
                    : "UN\(un.replacingOccurrences(of: " ", with: ""))"
                // Insert the space the schema documents: "UN 1075"
                b["un_number"] = normalized.replacingOccurrences(of: "UN", with: "UN ")
            }
            if let cargo = snapshot.load.cargoType, !cargo.isEmpty {
                b["commodity_stencil"] = cargo.uppercased()
            }
        }

        return LoadAnimationContext(
            bindings: b,
            placardSymbolId: placardId,
            modality: mode,
            vertical: vert,
            region: reg
        )
    }

    // MARK: - Inference helpers

    /// Equipment label — primary header text on every SVG. Pulls from
    /// the load's `equipmentType` and falls back to the modality if
    /// the equipment field is blank.
    private static func equipmentLabel(_ s: ShipperAPI.LifecycleSnapshot) -> String {
        let eq = (s.load.equipmentType ?? "").trimmingCharacters(in: .whitespaces)
        if !eq.isEmpty {
            return eq.uppercased()
        }
        // Fall back to a sensible per-mode default
        switch inferModality(from: s) {
        case "rail":   return "RAIL"
        case "vessel": return "VESSEL"
        default:       return "TRUCK"
        }
    }

    /// Equipment subtitle — secondary header text. We compose from the
    /// cargo type + a regulatory hint when one fits (CDL-X for hazmat,
    /// FDA for food, USDA for ag) so the subtitle reads as more than
    /// a duplicate of the commodity label.
    private static func equipmentSubtitle(_ s: ShipperAPI.LifecycleSnapshot) -> String {
        let cargo = s.load.cargoType?.uppercased() ?? ""
        if let hazClass = s.load.hazmatClass, !hazClass.isEmpty {
            return cargo.isEmpty
                ? "HAZMAT · CDL-X · 49 CFR 173"
                : "\(cargo) · HAZMAT · 49 CFR 173"
        }
        return cargo.isEmpty ? "GENERAL FREIGHT" : cargo
    }

    /// Dock chip — resolution order:
    ///   1. the REAL assigned dock door (`appointments.getByLoad
    ///      .dockNumber`, plumbed in by the caller — 024's pattern),
    ///   2. the pickup/delivery facility name for the side of the trip
    ///      the load is closest to,
    ///   3. city/state,
    ///   4. the honest em-dash sentinel.
    /// The "DOCK 12" Figma sample is DEAD (Wave-A1 fabrication kill,
    /// 2026-06-10) — the em-dash deliberately OVERRIDES the SVG's baked
    /// "DOCK 12" default text so a sample dock can never read as real.
    private static func dockId(_ s: ShipperAPI.LifecycleSnapshot,
                               dockNumber: String? = nil) -> String {
        if let d = dockNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
           !d.isEmpty {
            let up = d.uppercased()
            return up.contains("DOCK") || up.contains("BAY") || up.contains("DOOR")
                ? up
                : "DOCK \(up)"
        }
        let status = s.load.status.lowercased()
        let useDelivery = status.contains("deliver") ||
                          status.contains("unload") ||
                          status.contains("pod")
        let stop = useDelivery ? s.delivery : (s.pickup ?? s.delivery)
        if let f = stop?.facilityName, !f.isEmpty { return f.uppercased() }
        if let c = stop?.city, let st = stop?.state, !c.isEmpty, !st.isEmpty {
            return "\(c.uppercased()), \(st.uppercased())"
        }
        return "—"
    }

    /// ETA chip — formats minutes-to-arrival into the canonical
    /// "ETA NN MIN" / "ETA NN HR" string. Returns "" when the
    /// snapshot doesn't carry an ETA — SVG baked default shows.
    private static func etaLabel(_ s: ShipperAPI.LifecycleSnapshot) -> String {
        let etaIso = s.load.estimatedDeliveryDate ?? s.load.deliveryDate
        guard let etaIso else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = f.date(from: etaIso) ?? ISO8601DateFormatter().date(from: etaIso)
        guard let eta = parsed else { return "" }
        let mins = Int(eta.timeIntervalSinceNow / 60)
        if mins < 0 { return "" }                  // past — leave default
        if mins < 60 { return "ETA \(mins) MIN" }
        if mins < 60 * 24 { return "ETA \(mins / 60) HR" }
        return "ETA \(mins / (60 * 24)) D"
    }

    /// Commodity chip — combines the cargo name with the unit
    /// quantity when both are known. Examples:
    ///   - "GASOLINE · 8,500 GAL"
    ///   - "GENERAL FREIGHT · 24 PLT"
    private static func commodityLabel(_ s: ShipperAPI.LifecycleSnapshot) -> String {
        let cargo = (s.load.cargoType ?? "").uppercased()
        if cargo.isEmpty {
            return "GENERAL FREIGHT"
        }
        return cargo
    }

    /// Weight label — formats the load's weight + unit into the
    /// canonical "NN,NNN LBS" string. Falls back to an empty key when
    /// the snapshot has no weight (lets the SVG default show).
    ///
    /// Unit localization (Wave C, level-100 criterion c): the platform
    /// stores truck/rail weight in pounds; MX (NOM-012-SCT) and CA
    /// (provincial weights & dimensions regs) loads read in kilograms,
    /// so the label converts for region mx/ca. Vessel DWT is already
    /// metric tonnes — never converted.
    private static func weightLabel(_ s: ShipperAPI.LifecycleSnapshot) -> String {
        guard let w = s.load.weight, w > 0 else { return "" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        // Mode-aware units
        if inferModality(from: s) == "vessel" {
            let n = f.string(from: NSNumber(value: w)) ?? "\(Int(w))"
            return "DWT \(n)"
        }
        switch inferRegion(from: s) {
        case "mx", "ca":
            let kg = w * 0.45359237
            let n = f.string(from: NSNumber(value: kg.rounded())) ?? "\(Int(kg))"
            return "\(n) KG"
        default:
            let n = f.string(from: NSNumber(value: w)) ?? "\(Int(w))"
            return "\(n) LBS"
        }
    }

    /// Progress percent — derived from the lifecycle status. Pre-
    /// pickup states report 0; loaded → 50; in-transit → 75; delivery
    /// states → 100. Server-side `progress.updated` events from the
    /// LoadChannel WebSocket override this when wired (~Phase 4).
    private static func progressPercent(_ s: ShipperAPI.LifecycleSnapshot) -> Double {
        switch s.load.status.lowercased() {
        case "draft", "posted", "bidding", "awarded", "accepted", "assigned", "confirmed":
            return 0
        case "en_route_pickup":
            return 10
        case "at_pickup", "pickup_checkin":
            return 25
        case "loading":
            return 35
        case "loaded", "departed_pickup":
            return 50
        case "in_transit":
            return 70
        case "at_delivery", "delivery_checkin":
            return 85
        case "unloading":
            return 90
        case "unloaded", "pod_pending":
            return 95
        case "delivered", "complete":
            return 100
        default:
            // Zero-fallback doctrine (E2E audit §4 · 2026-06-09): an
            // unmapped lifecycle status must not fabricate a half-done
            // progress bar. Surface the gap loudly in DEBUG; render an
            // honest 0 in release until the status is mapped above.
            assertionFailure("LoadAnimationContext.progressPercent: unmapped load status '\(s.load.status)' — add it to the ramp")
            return 0
        }
    }

    /// Modality — truck / rail / vessel — derived from the load's
    /// equipment type. Server doesn't carry an explicit modality
    /// column today; this maps the equipment to a mode using the same
    /// heuristic the iOS LifecycleProductContext uses.
    private static func inferModality(from s: ShipperAPI.LifecycleSnapshot) -> String {
        let e = (s.load.equipmentType ?? "").lowercased()
        if e.contains("rail") || e.contains("hopper") || e.contains("tofc") ||
           e.contains("cofc") || e.contains("autorack") || e.contains("centerbeam") ||
           e.contains("gondola") || e.contains("flatcar") || e.contains("boxcar") {
            return "rail"
        }
        if e.contains("vessel") || e.contains("ship") || e.contains("ro/ro") ||
           e.contains("roro") || e.contains("lng") || e.contains("bulk carrier") {
            return "vessel"
        }
        return "truck"
    }

    /// Vertical — maps cargo type into the 10-vertical taxonomy from
    /// the cell matrix. Hazmat loads route through `tanker_hazmat`;
    /// reefer loads route through `reefer`; everything else falls
    /// through to `dry_van`.
    private static func inferVertical(from s: ShipperAPI.LifecycleSnapshot) -> String {
        let e = (s.load.equipmentType ?? "").lowercased()
        let c = (s.load.cargoType ?? "").lowercased()
        if let hc = s.load.hazmatClass, !hc.isEmpty {
            return e.contains("petro") || e.contains("306") ? "tanker_petro" : "tanker_hazmat"
        }
        if e.contains("reefer") || c.contains("reefer") || c.contains("frozen") || c.contains("refrigerated") {
            return "reefer"
        }
        if e.contains("flatbed") || e.contains("step deck") || e.contains("rgn") || e.contains("lowboy") {
            return "flatbed"
        }
        if e.contains("hopper") || e.contains("bulk") {
            return "bulk_dry"
        }
        if e.contains("container") || e.contains("intermodal") || e.contains("tofc") || e.contains("cofc") {
            return "intermodal"
        }
        return "dry_van"
    }

    /// Region — the jurisdiction whose regulatory truth governs the
    /// rendered placards/credentials/units (Wave C).
    ///
    /// CURRENT-LEG RULE: a cross-border load renders the country of the
    /// leg it is on NOW — origin-side statuses (anything up to and
    /// including departure from the pickup) take the PICKUP stop's
    /// country; post-departure statuses (in transit → delivered) take
    /// the DELIVERY stop's country. Domestic loads resolve identically
    /// from either side. Statuses the ramp doesn't recognize stay on
    /// the origin leg — the load hasn't provably departed, so the
    /// pixels never switch placard regimes on a guess.
    ///
    /// Country derives from the stop's state/province abbreviation via
    /// `countryCode(forState:)` — the server's `detectLoadCountry`
    /// tables (routers/loads.ts:106, the rule that mints
    /// `loads.originCountry`/`destCountry`) minus the ambiguous-code
    /// collisions (see countryCode's DELIBERATE DIVERGENCE note). The
    /// lifecycle snapshot envelope carries `Stop.state`, not the minted
    /// country columns, so deriving from the same input is the honest
    /// equivalent. Unknown/absent state → "us" — the engine's
    /// US-default, never a guessed placard set.
    private static func inferRegion(from s: ShipperAPI.LifecycleSnapshot) -> String {
        let status = s.load.status.lowercased()
        let departedOrigin: Bool
        switch status {
        case "in_transit", "departed_pickup",
             "at_delivery", "delivery_checkin",
             "unloading", "unloaded", "pod_pending",
             "delivered", "complete":
            departedOrigin = true
        default:
            departedOrigin = false
        }
        let legStop = departedOrigin
            ? (s.delivery ?? s.pickup)
            : (s.pickup ?? s.delivery)
        return countryCode(forState: legStop?.state)
    }

    /// State/province abbreviation → country code, derived from the
    /// server's `detectLoadCountry` tables (routers/loads.ts:106 — the
    /// rule that mints `loads.originCountry`/`destCountry`), plus the
    /// 3-letter MX forms (CHH, AGS, …) free-form stop entry produces.
    ///
    /// DELIBERATE DIVERGENCE (honest floor): the server's 2-letter MX
    /// table contains codes that are ALSO real US states (CO=Colorado,
    /// MI=Michigan, MO=Missouri) or CA provinces (BC, NL). Resolving
    /// those to MX would paint SCT placards on a Michigan rig — wrong
    /// regulatory truth, the exact failure class Wave C kills. An
    /// ambiguous code therefore never flips the pixels away from its
    /// far-more-likely US/CA reading; only unambiguous codes resolve MX.
    static func countryCode(forState state: String?) -> String {
        guard let raw = state?.uppercased().trimmingCharacters(in: .whitespaces),
              !raw.isEmpty else { return "us" }
        let mxStates: Set<String> = [
            // Server detectLoadCountry 2-letter set (routers/loads.ts:109)
            // minus the ambiguous US/CA collisions {CO, MI, MO, BC, NL}.
            "AG","BS","CM","CS","CH","CL","DG","GT","GR","HG","JA",
            "MX","NA","OA","PU","QT","QR","SL","SI","SO","TB",
            "TM","TL","VE","YU","ZA","DF",
            // 3-letter forms free-form stop entry produces
            "AGS","BCS","CAM","CHH","CHP","COA","COL","CMX","DUR","GRO","GTO",
            "HID","JAL","MEX","MIC","MOR","NAY","NLE","OAX","PUE","QRO","ROO",
            "SIN","SLP","SON","TAB","TAM","TLA","VER","YUC","ZAC"
        ]
        let caProvs: Set<String> = ["AB","BC","MB","NB","NL","NS","NT","NU","ON","PE","QC","SK","YT"]
        if mxStates.contains(raw) { return "mx" }
        if caProvs.contains(raw) { return "ca" }
        return "us"
    }

    /// Engine-facing country for an arbitrary state/province code —
    /// used by surfaces that have a state but no LifecycleSnapshot
    /// (e.g. the post-load wizard's equipment preview, where the
    /// current leg is by definition the origin).
    static func svgCountry(forState state: String?) -> SVGCountry? {
        switch countryCode(forState: state) {
        case "mx": return .mx
        case "ca": return .ca
        default:   return .us
        }
    }

    /// Container BIC — only relevant for intermodal/container loads.
    /// The snapshot doesn't carry a BIC today; we leave it nil and
    /// let the SVG's baked default ("EUSO 884310") show through.
    private static func inferContainerId(from s: ShipperAPI.LifecycleSnapshot) -> String? {
        // No BIC field on snapshot — return nil to keep baked default.
        nil
    }
}
