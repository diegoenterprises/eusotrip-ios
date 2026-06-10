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
        // state_label — the live tanker sub-state chip (loads.
        // tanker_sub_state, migration 0100: FLOWING, SAMPLE_2_OF_4,
        // DETACH_ARM_CAPPED…) is FINER truth than the top-level
        // status, so it wins when present (Wave B, spec gap 3).
        if let sub = snapshot.load.tankerSubState?
            .trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
            b["state_label"] = sub.uppercased().replacingOccurrences(of: "_", with: " ")
        } else {
            b["state_label"] = snapshot.load.status.uppercased().replacingOccurrences(of: "_", with: " ")
        }
        b["equipment_label"]    = equipmentLabel(snapshot)
        b["equipment_subtitle"] = equipmentSubtitle(snapshot)
        b["dock_id"]            = dockId(snapshot, dockNumber: dockNumber)
        b["eta_minutes"]        = etaLabel(snapshot)
        b["commodity_label"]    = commodityLabel(snapshot)
        b["weight_label"]       = weightLabel(snapshot)
        b["progress_pct"]       = "\(Int(progressPercent(snapshot)))"

        // ─── Mode-specific layer ──────────────────────────────────
        // Wave B baked-sample kill (2026-06-10): the snapshot carries
        // no reporting marks / vessel identity / container BIC, and
        // "leave the key absent so the baked default shows" let the
        // SVG's authoring samples (EUSO 7142, MV EUSORONE ATLAS,
        // EUSO 884310) read as REAL data on live loads — exactly the
        // fabrication class the census's criterion (b) prohibits.
        // Until the snapshot wraps those records, the chips render the
        // honest em-dash. A real value, when it lands, overrides.
        if mode == "rail" {
            b["reporting_marks"] = "—"
        }
        if mode == "vessel" {
            b["vessel_name"] = "—"
            b["imo_number"]  = "—"
        }
        if mode == "vessel" || vert == "intermodal" {
            b["container_id"] = inferContainerId(from: snapshot) ?? "—"
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
    /// "ETA NN MIN" / "ETA NN HR" string. Returns the honest em-dash
    /// when the snapshot doesn't carry a future ETA — the SVG's baked
    /// "ETA 18 MIN" authoring sample must never read as live truth
    /// (Wave B baked-sample kill, 2026-06-10).
    private static func etaLabel(_ s: ShipperAPI.LifecycleSnapshot) -> String {
        let etaIso = s.load.estimatedDeliveryDate ?? s.load.deliveryDate
        guard let etaIso else { return "—" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = f.date(from: etaIso) ?? ISO8601DateFormatter().date(from: etaIso)
        guard let eta = parsed else { return "—" }
        let mins = Int(eta.timeIntervalSinceNow / 60)
        if mins < 0 { return "—" }                 // past — honest dash
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
    /// canonical "NN,NNN LBS" string. Renders the honest em-dash when
    /// the snapshot has no weight — the SVG's baked "45,000 LBS"
    /// authoring sample must never read as live truth (Wave B
    /// baked-sample kill, 2026-06-10).
    private static func weightLabel(_ s: ShipperAPI.LifecycleSnapshot) -> String {
        guard let w = s.load.weight, w > 0 else { return "—" }
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

    /// Progress percent — derived from the lifecycle status via the
    /// canonical 49-status ramp below.
    private static func progressPercent(_ s: ShipperAPI.LifecycleSnapshot) -> Double {
        percent(forStatus: s.load.status)
    }

    /// Wave B (2026-06-10) — THE canonical lifecycle-status → percent
    /// ramp. Covers all 49 TANKER_LOAD_STATUSES from the `loads.status`
    /// mysqlEnum (schema.additions.wave4-1.ts — original 32 + the 11
    /// Wave-4 tanker additions + 5 cargo-integrity exceptions + hold).
    /// The phantom `departed_pickup` (never a real enum member) is
    /// DEAD. Shared by the shipper strip, the driver equipment band,
    /// and ConvoyAnimationStrip so no two surfaces can disagree on a
    /// load's lifecycle percent.
    ///
    /// Exception states hold the percent of the procedure stage they
    /// wrap (a loading exception is still AT the rack at ~35%); hold/
    /// cancel/cargo-integrity states whose physical position is
    /// genuinely unknown report the honest floor 0 — never an estimate
    /// wearing telemetry's clothes.
    static func percent(forStatus status: String) -> Double {
        switch status.lowercased() {
        // ── pre-tender / tender (no freight movement yet) ──
        case "draft", "posted", "bidding", "expired",
             "awarded", "declined", "lapsed",
             "accepted", "assigned", "confirmed":
            return 0
        // ── rolling to the shipper ──
        case "en_route_pickup":
            return 10
        case "at_pickup", "pickup_checkin":
            return 25
        // ── Wave-4 pickup-side wizard (locked → loading_locked) ──
        case "locked":
            return 26
        case "backing_in":
            return 28
        case "brakes_set":
            return 30
        case "connecting":
            return 32
        case "loading_locked":
            return 34
        // ── loading block ──
        case "loading", "loading_exception":
            return 35
        case "loaded", "load_locked_filled":
            return 50
        // ── transit block (holds keep the transit stage — the trailer
        //    is on the road; the hold is administrative) ──
        case "in_transit", "transit_hold", "transit_exception":
            return 70
        // ── receiver side ──
        case "at_delivery", "delivery_checkin":
            return 85
        case "discharging":
            return 88
        case "unloading", "unloading_exception":
            return 90
        case "unloaded":
            return 95
        // ── Wave-4 detach wizard (cargo off, rig still connected) ──
        case "vapor_purging":
            return 96
        case "disconnecting":
            return 97
        case "detaching":
            return 98
        case "released":
            return 99
        // ── paperwork / financial / terminal ──
        case "pod_pending", "pod_rejected":
            return 95
        case "delivered", "invoiced", "disputed", "paid", "complete":
            return 100
        // ── terminal-cancel + holds with unknowable physical position:
        //    honest floor, never a fabricated mid-route bar ──
        case "cancelled", "on_hold":
            return 0
        // ── cargo-integrity exceptions can fire at ANY stage; with no
        //    stage signal on the row the honest answer is the floor ──
        case "temp_excursion", "reefer_breakdown", "contamination_reject",
             "seal_breach", "weight_violation":
            return 0
        // ── escort-assignment statuses (loads.getEscortAssignment rows
        //    ride the ConvoyAnimationStrip through this same ramp) ──
        case "pending":
            return 0
        case "en_route":
            return 10
        case "on_site":
            return 25
        case "escorting":
            return 70
        case "completed":
            return 100
        default:
            // Zero-fallback doctrine (E2E audit §4 · 2026-06-09): an
            // unmapped lifecycle status must not fabricate a half-done
            // progress bar. Surface the gap loudly in DEBUG; render an
            // honest 0 in release until the status is mapped above.
            assertionFailure("LoadAnimationContext.percent(forStatus:): unmapped load status '\(status)' — add it to the ramp")
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
    /// The snapshot doesn't carry a BIC today → nil, and the caller
    /// overrides the chip with the honest em-dash (the baked
    /// "EUSO 884310" sample is dead — Wave B baked-sample kill).
    private static func inferContainerId(from s: ShipperAPI.LifecycleSnapshot) -> String? {
        // No BIC field on snapshot — nil → "—" at the call site.
        nil
    }

    // MARK: - Wave B · driver-side builder (2026-06-10)

    /// Minimal honest fact set a DRIVER lifecycle screen can assemble
    /// from whatever load shape it hydrates (`Load` from
    /// `loads.getById`, `LoadsAPI.LoadDetail` from `loads.getDetail`).
    /// Every field is the real row value or nil — the builder below
    /// renders nil as the honest em-dash, never a sample.
    struct DriverLoadFacts {
        var status: String
        var tankerSubState: String?
        var cargoType: String?
        var hazmatClass: String?
        var unNumber: String?
        var commodityName: String?
        var equipmentType: String?
        var weightLbs: Double?
        var transportMode: String?
        var dockNumber: String?
        var facilityLabel: String?

        init(load: Load) {
            status         = load.status
            tankerSubState = load.tankerSubState
            cargoType      = load.cargoType
            hazmatClass    = load.hazmatClass
            unNumber       = load.unNumber
            commodityName  = load.commodityName
            equipmentType  = nil   // driver Load row carries no free-text equipment column
            weightLbs      = load.weightValue > 0 ? load.weightValue : nil
            transportMode  = load.transportMode
            dockNumber     = nil
            facilityLabel  = nil
        }

        init(detail: LoadsAPI.LoadDetail) {
            status         = detail.status
            tankerSubState = nil   // loads.getDetail projection omits the column
            cargoType      = detail.cargoType
            hazmatClass    = detail.hazmatClass
            unNumber       = detail.unNumber
            commodityName  = detail.commodityName ?? detail.commodity
            equipmentType  = detail.equipmentType
            weightLbs      = detail.weight.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
            transportMode  = detail.transportMode
            dockNumber     = nil
            facilityLabel  = nil
        }
    }

    /// Build the binding dictionary for the DRIVER equipment band —
    /// the same universal contract `from(snapshot:)` emits, assembled
    /// from the driver-side load row. The driver at the rack during
    /// 016/030 is the one user the 2,099-line petro-loading SVG was
    /// authored for; this is the context that finally feeds it.
    static func from(facts: DriverLoadFacts) -> LoadAnimationContext {
        var b: [String: String] = [:]

        // state_label — sub-state chip wins over the top-level status
        // (FLOWING beats LOADING for the driver mid-procedure).
        if let sub = facts.tankerSubState?
            .trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
            b["state_label"] = sub.uppercased().replacingOccurrences(of: "_", with: " ")
        } else {
            b["state_label"] = facts.status.uppercased().replacingOccurrences(of: "_", with: " ")
        }

        let mode = (facts.transportMode ?? "truck").lowercased()
        let kind = EquipmentKind.resolve(
            from: facts.equipmentType,
            hazmat: (facts.hazmatClass?.isEmpty == false)
        )
        let resolvedKind: EquipmentKind = facts.equipmentType == nil
            ? EquipmentKind.resolve(
                cargoType: facts.cargoType,
                hazmat: (facts.hazmatClass?.isEmpty == false),
                modality: mode == "rail" ? .rail : (mode == "vessel" ? .vessel : .truck))
            : kind
        b["equipment_label"] = resolvedKind.shortLabel

        // equipment_subtitle — cargo + regulatory hint (same composition
        // as the shipper builder).
        let cargo = (facts.cargoType ?? "").uppercased()
        if facts.hazmatClass?.isEmpty == false {
            b["equipment_subtitle"] = cargo.isEmpty
                ? "HAZMAT · CDL-X · 49 CFR 173"
                : "\(cargo) · HAZMAT · 49 CFR 173"
        } else {
            b["equipment_subtitle"] = cargo.isEmpty ? "GENERAL FREIGHT" : cargo
        }

        // dock chip — real assigned door → facility label → em-dash.
        if let d = facts.dockNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
           !d.isEmpty {
            let up = d.uppercased()
            b["dock_id"] = up.contains("DOCK") || up.contains("BAY") || up.contains("DOOR")
                ? up : "DOCK \(up)"
        } else if let f = facts.facilityLabel, !f.isEmpty {
            b["dock_id"] = f.uppercased()
        } else {
            b["dock_id"] = "—"
        }

        // No ETA source on the driver row shapes — honest dash (never
        // the SVG's baked "ETA 18 MIN" sample).
        b["eta_minutes"] = "—"

        let commodity = (facts.commodityName ?? facts.cargoType ?? "").uppercased()
        b["commodity_label"] = commodity.isEmpty ? "—" : commodity

        if let w = facts.weightLbs {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            let n = f.string(from: NSNumber(value: w)) ?? "\(Int(w))"
            b["weight_label"] = "\(n) LBS"
        } else {
            b["weight_label"] = "—"
        }

        b["progress_pct"] = "\(Int(percent(forStatus: facts.status)))"

        // Hazmat layer — real row values only.
        var placardId: String? = nil
        if let hazClass = facts.hazmatClass, !hazClass.isEmpty {
            b["hazmat_class"] = hazClass
            placardId = "class\(hazClass.replacingOccurrences(of: ".", with: "_"))Placard"
            if let un = facts.unNumber, !un.isEmpty {
                let normalized = un.uppercased().contains("UN")
                    ? un.uppercased().replacingOccurrences(of: " ", with: "")
                    : "UN\(un.replacingOccurrences(of: " ", with: ""))"
                b["un_number"] = normalized.replacingOccurrences(of: "UN", with: "UN ")
            }
            if let c = facts.commodityName ?? facts.cargoType, !c.isEmpty {
                b["commodity_stencil"] = c.uppercased()
            }
        }

        return LoadAnimationContext(
            bindings: b,
            placardSymbolId: placardId,
            modality: mode,
            vertical: "",
            region: "us"
        )
    }
}
