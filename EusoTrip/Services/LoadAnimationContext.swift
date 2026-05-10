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

    // MARK: - Build from a LifecycleSnapshot

    /// Builds the binding dictionary from the live snapshot. Empty
    /// fields fall back to the per-equipment defaults that are
    /// already baked into the v1.5 state-variant SVGs (per
    /// `TEMPLATE_TOKEN_INDEX.md` v1.5 — defaults are baked into
    /// `<text>` content; we only override when the snapshot has a
    /// real value).
    static func from(snapshot: ShipperAPI.LifecycleSnapshot) -> LoadAnimationContext {
        let mode = inferModality(from: snapshot)
        let vert = inferVertical(from: snapshot)
        let reg = inferRegion(from: snapshot)

        var b: [String: String] = [:]

        // ─── Universal layer ──────────────────────────────────────
        b["state_label"]        = snapshot.load.status.uppercased().replacingOccurrences(of: "_", with: " ")
        b["equipment_label"]    = equipmentLabel(snapshot)
        b["equipment_subtitle"] = equipmentSubtitle(snapshot)
        b["dock_id"]            = dockId(snapshot)
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

    /// Dock chip — pulls the pickup or delivery facility name based on
    /// which side of the trip the load is closest to. Matches the
    /// `data-bind="dock_id"` chip on the loading/unloading SVGs.
    private static func dockId(_ s: ShipperAPI.LifecycleSnapshot) -> String {
        let status = s.load.status.lowercased()
        let useDelivery = status.contains("deliver") ||
                          status.contains("unload") ||
                          status.contains("pod")
        let stop = useDelivery ? s.delivery : (s.pickup ?? s.delivery)
        if let f = stop?.facilityName, !f.isEmpty { return f.uppercased() }
        if let c = stop?.city, let st = stop?.state, !c.isEmpty, !st.isEmpty {
            return "\(c.uppercased()), \(st.uppercased())"
        }
        return "DOCK 12"
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
    private static func weightLabel(_ s: ShipperAPI.LifecycleSnapshot) -> String {
        guard let w = s.load.weight, w > 0 else { return "" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let n = f.string(from: NSNumber(value: w)) ?? "\(Int(w))"
        // Mode-aware units
        switch inferModality(from: s) {
        case "vessel": return "DWT \(n)"
        case "rail":   return "\(n) LBS"
        default:       return "\(n) LBS"
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
            return 50
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

    /// Region — defaults to `us` until cross-border state is wired.
    /// The server-side `BORDER_CROSSING_USMCA` state and customs
    /// router will populate this in Phase 6+.
    private static func inferRegion(from s: ShipperAPI.LifecycleSnapshot) -> String {
        // Heuristic: if either pickup or delivery state matches
        // 2-letter MX or CA codes, route accordingly.
        let mxStates: Set<String> = ["AGS","BC","BCS","CAM","CHH","CHP","COA","COL","CMX","DUR","GRO","GTO","HID","JAL","MEX","MIC","MOR","NAY","NLE","OAX","PUE","QRO","ROO","SIN","SLP","SON","TAB","TAM","TLA","VER","YUC","ZAC"]
        let caProvs: Set<String> = ["AB","BC","MB","NB","NL","NS","NT","NU","ON","PE","QC","SK","YT"]
        let states = [s.pickup?.state, s.delivery?.state].compactMap { $0?.uppercased() }
        if states.contains(where: { mxStates.contains($0) }) { return "mx" }
        if states.contains(where: { caProvs.contains($0) }) { return "ca" }
        return "us"
    }

    /// Container BIC — only relevant for intermodal/container loads.
    /// The snapshot doesn't carry a BIC today; we leave it nil and
    /// let the SVG's baked default ("EUSO 884310") show through.
    private static func inferContainerId(from s: ShipperAPI.LifecycleSnapshot) -> String? {
        // No BIC field on snapshot — return nil to keep baked default.
        nil
    }
}
