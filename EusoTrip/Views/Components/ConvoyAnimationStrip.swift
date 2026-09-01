//
//  ConvoyAnimationStrip.swift
//  EusoTrip — Multi-vehicle parent shipment view.
//
//  Renders one card per child Vehicle in a Shipment, with adaptive
//  layout per device class:
//    - iPhone (compact): TabView carousel, swipe between vehicles
//    - iPad / Mac (regular): horizontal scroll, all vehicles visible
//
//  Each card shows:
//    - Leg sequence number + role badge ("YOUR VEHICLE" highlight
//      when the current driver is on this leg)
//    - The matching equipment SVG with full data-binding (via
//      LifecycleAnimationStrip's underlying BindableEquipmentAnimation)
//    - Equipment label + child state
//
//  Below the cards, project cargo (≥ 3 vehicles) and intermodal
//  multi-leg shipments get a horizontal sequence timeline showing
//  each leg as a colored dot — green=delivered, cyan=in-transit,
//  red=exception, gray=upcoming.
//
//  Founder doctrine 2026-05-10:
//    "EusoTrip should own the unified data model where one Shipment
//     is the parent and N Vehicles are typed children that
//     participate in a single lifecycle, with regulatory + animation
//     + role-aware parity from web to wrist." — MULTI_VEHICLE_LOAD_ARCHITECTURE.md
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct ConvoyAnimationStrip: View {
    let shipment: Shipment
    /// When the viewer is a driver, pass their vehicle id so that
    /// card highlights with a "YOUR VEHICLE" badge + purple border.
    var ownVehicleId: String? = nil
    /// Tap callback so callers can open a per-vehicle detail sheet.
    var onVehicleTap: ((String) -> Void)? = nil

    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedVehicleIdx: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if sizeClass == .compact {
                carousel
            } else {
                horizontalScroll
            }

            if shipment.isProjectCargo || shipment.vehicles.count > 2 {
                sequenceTimeline
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.connected.to.line.below")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPMENT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(shipment.id)
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Text(shipment.parentBolNumber)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                ParentStateBadge(state: shipment.parentState)
                Text("\(shipment.vehicles.count) vehicle\(shipment.vehicles.count == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: - Carousel (iPhone)

    private var carousel: some View {
        TabView(selection: $selectedVehicleIdx) {
            ForEach(Array(orderedVehicles.enumerated()), id: \.offset) { idx, vehicle in
                ConvoyVehicleCard(
                    vehicle: vehicle,
                    isOwn: vehicle.id == ownVehicleId,
                    onTap: onVehicleTap
                )
                .tag(idx)
                .padding(.horizontal, 4)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 320)
    }

    // MARK: - Horizontal scroll (iPad / Mac)

    private var horizontalScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(orderedVehicles) { vehicle in
                    ConvoyVehicleCard(
                        vehicle: vehicle,
                        isOwn: vehicle.id == ownVehicleId,
                        onTap: onVehicleTap
                    )
                    .frame(width: 320)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Sequence timeline

    private var sequenceTimeline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LEG SEQUENCE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(orderedVehicles.enumerated()), id: \.offset) { idx, vehicle in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(legColor(vehicle))
                                .frame(width: 12, height: 12)
                            Text("L\(vehicle.leg.sequenceNumber)")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(palette.textPrimary)
                            Text(vehicle.modality.rawValue.uppercased())
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(palette.textTertiary)
                        }
                        .frame(width: 44)
                        if idx < orderedVehicles.count - 1 {
                            Rectangle()
                                .fill(palette.borderFaint)
                                .frame(width: 24, height: 2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var orderedVehicles: [Vehicle] {
        shipment.vehicles.sorted { $0.leg.sequenceNumber < $1.leg.sequenceNumber }
    }

    private func legColor(_ v: Vehicle) -> Color {
        if ChildLifecycleSet.blocking.contains(v.childState) { return Brand.danger }
        if v.childState.hasSuffix("_EXCEPTION") { return Brand.warning }
        if ChildLifecycleSet.delivered.contains(v.childState) { return Brand.success }
        if ChildLifecycleSet.inTransit.contains(v.childState) { return Brand.info }
        return Brand.neutral
    }
}

// MARK: - Parent state badge

struct ParentStateBadge: View {
    let state: ParentShipmentState
    @Environment(\.palette) private var palette

    var body: some View {
        Text(state.rawValue.replacingOccurrences(of: "_", with: " "))
            .font(.system(size: 9, weight: .heavy)).tracking(0.7)
            .foregroundStyle(stateColor)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(stateColor.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(stateColor.opacity(0.4), lineWidth: 1))
    }

    private var stateColor: Color {
        switch state {
        case .exceptionBlocking:
            return Brand.danger
        case .exceptionAny:
            return Brand.warning
        case .complete, .delivered, .podFull:
            return Brand.success
        case .inTransitFull, .inProgress, .atHandoff:
            return Brand.info
        case .cancelled:
            return Brand.neutral
        default:
            return Brand.magenta
        }
    }
}

// MARK: - Per-vehicle card

private struct ConvoyVehicleCard: View {
    let vehicle: Vehicle
    let isOwn: Bool
    let onTap: ((String) -> Void)?

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row — leg # + role + own-vehicle badge
            HStack(spacing: 6) {
                Text("LEG \(vehicle.leg.sequenceNumber)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                Text(roleLabel(vehicle.role))
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(palette.bgCardSoft)
                    .clipShape(Capsule())
                Spacer(minLength: 0)
                if isOwn {
                    Text("YOUR VEHICLE")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                }
            }

            // The animated equipment surface — uses the same
            // BindableEquipmentAnimation pipeline as
            // LifecycleAnimationStrip but takes a Vehicle directly.
            ConvoyVehicleAnimation(vehicle: vehicle)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )

            // Footer row — equipment label + state
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(vehicle.equipment.label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if let sub = vehicle.equipment.subtitle {
                        Text(sub)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Text(vehicle.childState.replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(palette.bgCardSoft)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(isOwn ? Brand.magenta.opacity(0.05) : palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isOwn ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                    lineWidth: isOwn ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { onTap?(vehicle.id) }
    }

    private func roleLabel(_ role: VehicleRole) -> String {
        switch role {
        case .primary: return "PRIMARY"
        case .secondary: return "SECONDARY"
        case .escortLead: return "ESCORT LEAD"
        case .escortChase: return "ESCORT CHASE"
        case .escortStateTrooper: return "STATE ESCORT"
        case .teamDriver: return "TEAM"
        case .relay: return "RELAY"
        case .av: return "AUTONOMOUS"
        case .avHandoffHuman: return "AV HANDOFF"
        }
    }
}

// MARK: - Vehicle-keyed animation

/// Small adapter that pulls the right EquipmentKind for a Vehicle's
/// equipment.type and renders it via BindableEquipmentAnimation
/// with vehicle-scoped bindings (equipment_label / subtitle / state /
/// reporting_marks / etc.).
private struct ConvoyVehicleAnimation: View {
    let vehicle: Vehicle
    @Environment(\.palette) private var palette

    /// Escort pilot/chase cars have NO canonical equipment model in
    /// the 40-model catalog — painting a dry van for a pilot car would
    /// be a wrong-shape fabrication (canonical-models doctrine). They
    /// render the bespoke beacon card instead.
    private var isEscort: Bool {
        switch vehicle.role {
        case .escortLead, .escortChase, .escortStateTrooper: return true
        default: return false
        }
    }

    var body: some View {
        if isEscort {
            VStack(spacing: 6) {
                Image(systemName: "light.beacon.max.fill")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text(vehicle.equipment.label)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(vehicle.childState.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.bgCardSoft)
        } else if let svg = EquipmentAnimationCache.shared.svg(
            for: equipmentKind,
            // Wave B (2026-06-10) — the convoy card renders the
            // lifecycle STATE VARIANT for its child state, same
            // selection contract as the shipper strip.
            state: AnimationState(loadStatus: vehicle.childState)
        ) {
            BindableEquipmentAnimation(
                svgString: svg,
                context: vehicleContext()
            )
        } else {
            VStack(spacing: 6) {
                Image(systemName: equipmentKind.iconName)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text(vehicle.equipment.label)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.bgCardSoft)
        }
    }

    /// Wave B (2026-06-10) — rides the ONE shared resolver
    /// (`EquipmentKind.resolve(from:)`, normalizes underscore/space
    /// tokens) instead of a private matcher that missed the T-030 six
    /// + auto-carrier. Modality floor stays honest per mode.
    private var equipmentKind: EquipmentKind {
        EquipmentKind.resolve(
            from: vehicle.equipment.type,
            hazmat: vehicle.hazmatChain?.entries.isEmpty == false,
            modality: {
                switch vehicle.modality {
                case .truck:  return .truck
                case .rail:   return .rail
                case .vessel: return .vessel
                }
            }()
        )
    }

    /// Build the binding dictionary from the Vehicle. Only fields we
    /// can populate honestly from the snapshot — empty strings drop
    /// out so the SVG's baked default text content shows through.
    private func vehicleContext() -> LoadAnimationContext {
        var b: [String: String] = [
            "state_label":     vehicle.childState.replacingOccurrences(of: "_", with: " "),
            "equipment_label": vehicle.equipment.label,
        ]
        if let sub = vehicle.equipment.subtitle { b["equipment_subtitle"] = sub }
        if let r = vehicle.equipment.reportingMarks, !r.isEmpty { b["reporting_marks"] = r }
        if let v = vehicle.equipment.vesselName, !v.isEmpty { b["vessel_name"] = v }
        if let i = vehicle.equipment.imoNumber, !i.isEmpty { b["imo_number"] = i.hasPrefix("IMO") ? i : "IMO \(i)" }
        if let c = vehicle.equipment.containerBicCode, !c.isEmpty { b["container_id"] = c }
        if let iso = vehicle.equipment.containerIsoCode, !iso.isEmpty { b["iso_code"] = iso }

        // Hazmat — pull from the most recent placard chain entry if
        // available; otherwise leave keys absent so the SVG's baked
        // default shows.
        var placardId: String? = nil
        if let chain = vehicle.hazmatChain, let recent = chain.entries.last {
            b["hazmat_class"] = recent.hazmatClass
            b["un_number"] = recent.unNumber.hasPrefix("UN ") ? recent.unNumber : "UN \(recent.unNumber.replacingOccurrences(of: "UN", with: ""))"
            placardId = recent.placardSymbolId
        }

        // Progress — derive from the child state via the same ramp
        // LoadAnimationContext uses for shipper lifecycle.
        let pct = progressFromChildState(vehicle.childState)
        b["progress_pct"] = "\(Int(pct))"

        return LoadAnimationContext(
            bindings: b,
            placardSymbolId: placardId,
            modality: vehicle.modality.rawValue,
            vertical: "",
            region: "us"
        )
    }

    /// Wave B (2026-06-10) — child-state progress now rides THE
    /// canonical 49-status ramp (`LoadAnimationContext.percent
    /// (forStatus:)`), so the convoy cards and the shipper strip can
    /// never disagree on a load's lifecycle percent. The handful of
    /// multi-vehicle-only child states (relay / AV / rail-ramp / vessel
    /// vocabulary from the 55-state taxonomy) are mapped here BEFORE
    /// delegating; everything else — including all 11 Wave-4 tanker
    /// statuses — resolves centrally.
    private func progressFromChildState(_ state: String) -> Double {
        switch state.uppercased() {
        case "EN_ROUTE_DELIVERY", "IN_TRANSIT_AUTONOMOUS",
             "RAIL_LINEHAUL", "VESSEL_LOADED":
            return 70
        case "AV_HUMAN_HANDOFF", "RAIL_RAMP_IN", "VESSEL_GATE_IN":
            return 60
        case "RAIL_RAMP_OUT", "VESSEL_DISCHARGED":
            return 95
        // Pre-departure compliance overlays — booked, not rolling.
        case "EQUIPMENT_VERIFIED", "HAZMAT_CLASS_VALIDATED",
             "BRIDGE_CLEARANCE_CHECKED":
            return 0
        // Blocking exceptions with unknowable physical position —
        // honest floor, never a fabricated mid-route bar.
        case "HAZMAT_INCIDENT", "CUSTOMS_HOLD",
             "IDENTITY_RE_VERIFICATION_REQUIRED":
            return 0
        default:
            return LoadAnimationContext.percent(forStatus: state)
        }
    }
}

// ============================================================================
// MARK: - Wave B · real-data Shipment composer (2026-06-10)
// ============================================================================

/// Composes a `Shipment` from the REAL rows the escort surface already
/// hydrates: the load detail (`loads.getDetail`) + its escort
/// assignments (`loads.getEscortAssignment`). This is what finally
/// mounts ConvoyAnimationStrip — fully built since 2026-05-10, ZERO
/// call sites until now (LEVEL100 census, bindings row "Convoy
/// AnimationStrip": 15) — on the escorted-load detail per
/// MULTI_VEHICLE_LOAD_ARCHITECTURE doctrine ("one Shipment, N typed
/// Vehicles … one tractor + two pilot cars is ONE Shipment").
///
/// Every populated field is a real row value; structurally required
/// fields with no honest source (BOL, audit anchor, customs filings)
/// stay empty/zero — the strip renders the em-dash, never a sample.
extension Shipment {

    static func composed(
        fromLoad detail: LoadsAPI.LoadDetail,
        escorts: [LoadsAPI.EscortAssignment]
    ) -> Shipment? {
        guard !escorts.isEmpty,
              let pickupCoordinate = LatLongParser.validatedCoordinate(
                  latitude: detail.pickupLocation?.lat,
                  longitude: detail.pickupLocation?.lng
              ),
              let deliveryCoordinate = LatLongParser.validatedCoordinate(
                  latitude: detail.deliveryLocation?.lat,
                  longitude: detail.deliveryLocation?.lng
              ) else { return nil }

        let loadRef = detail.loadNumber
        let weight = detail.weight.flatMap(Double.init) ?? 0
        let hazmat = (detail.hazmatClass?.isEmpty == false)
        let modality: VehicleModality = {
            switch (detail.transportMode ?? "truck").lowercased() {
            case "rail":   return .rail
            case "vessel": return .vessel
            default:       return .truck
            }
        }()
        let originPoint = GeoPoint(
            lat: pickupCoordinate.latitude,
            lng: pickupCoordinate.longitude,
            label: detail.pickupLocation?.cityState
        )
        let destPoint = GeoPoint(
            lat: deliveryCoordinate.latitude,
            lng: deliveryCoordinate.longitude,
            label: detail.deliveryLocation?.cityState
        )

        let primaryKind = EquipmentKind.resolve(
            from: detail.equipmentType ?? detail.cargoType,
            hazmat: hazmat,
            modality: modality == .rail ? .rail : (modality == .vessel ? .vessel : .truck)
        )

        func leg(_ seq: Int) -> LegSpec {
            LegSpec(
                sequenceNumber: seq,
                origin: originPoint,
                destination: destPoint,
                plannedDepartTs: nil, plannedArriveTs: nil,
                actualDepartTs: nil, actualArriveTs: nil,
                modeTransition: .origin,
                predecessorVehicleId: nil, successorVehicleId: nil
            )
        }

        // Convoy order: lead escorts ahead of the primary, chase
        // behind — sequence numbers encode the CONVOY position (Swift
        // sort isn't stable, so equal keys would shuffle the cards).
        var vehicles: [Vehicle] = []
        var seq = 1
        for e in escorts where e.position.lowercased() != "chase" {
            vehicles.append(escortVehicle(e, shipmentId: loadRef, role: .escortLead, seq: seq, leg: leg(seq)))
            seq += 1
        }
        vehicles.append(Vehicle(
            id: "\(loadRef)-PRIMARY",
            shipmentId: loadRef,
            role: .primary,
            modality: modality,
            equipment: EquipmentSpec(
                type: detail.equipmentType ?? detail.cargoType ?? "",
                label: primaryKind.shortLabel,
                subtitle: detail.commodityName ?? detail.commodity,
                trailerId: nil, licensePlate: nil, reportingMarks: nil,
                containerBicCode: nil, containerIsoCode: nil,
                vesselName: nil, imoNumber: nil, mmsi: nil
            ),
            driverIds: detail.driverId.map { [String($0)] } ?? [],
            carrierId: detail.catalystId.map(String.init) ?? "",
            leg: leg(seq),
            cargoSplit: CargoSplit(
                weightAllocated: weight, unitsAllocated: 0,
                itemRangeStart: nil, itemRangeEnd: nil,
                hazmatProportionAllocated: hazmat ? 1.0 : nil
            ),
            childState: detail.status.uppercased(),
            animationManifestId: primaryKind.rawValue,
            geofenceEvents: []
        ))
        seq += 1
        for e in escorts where e.position.lowercased() == "chase" {
            vehicles.append(escortVehicle(e, shipmentId: loadRef, role: .escortChase, seq: seq, leg: leg(seq)))
            seq += 1
        }

        return Shipment(
            id: loadRef,
            parentBolNumber: "—",                 // no BOL on the detail row — honest dash
            shipperOrgId: detail.shipperId.map(String.init) ?? "",
            consigneeOrgId: "",
            vertical: (detail.cargoType ?? "general").lowercased(),
            region: "us",
            totalWeight: weight,
            totalValue: 0,
            hazmatPresent: hazmat,
            customsRequired: false,
            parentState: parentState(fromLoadStatus: detail.status),
            vehicles: vehicles,
            stops: [],
            handoffs: [],
            syncWindows: [],
            customsFilings: [],
            parentRate: Money(
                amount: Decimal(string: detail.rate ?? "0") ?? 0,
                currency: detail.currency ?? "USD"
            ),
            vehicleRates: [],
            parentInvoiceId: nil,
            hashChainAnchor: ""
        )
    }

    private static func escortVehicle(
        _ e: LoadsAPI.EscortAssignment,
        shipmentId: String,
        role: VehicleRole,
        seq: Int,
        leg: LegSpec
    ) -> Vehicle {
        let who = [e.escortName, e.companyName]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .first ?? "PILOT CAR"
        return Vehicle(
            id: "\(shipmentId)-ESC-\(e.id)",
            shipmentId: shipmentId,
            role: role,
            modality: .truck,
            equipment: EquipmentSpec(
                type: "escort_vehicle",
                label: who.uppercased(),
                subtitle: role == .escortLead ? "LEAD PILOT CAR" : "CHASE PILOT CAR",
                trailerId: nil, licensePlate: nil, reportingMarks: nil,
                containerBicCode: nil, containerIsoCode: nil,
                vesselName: nil, imoNumber: nil, mmsi: nil
            ),
            driverIds: [String(e.escortUserId)],
            carrierId: e.companyDot ?? "",
            leg: leg,
            cargoSplit: CargoSplit(
                weightAllocated: 0, unitsAllocated: 0,   // escorts carry no cargo
                itemRangeStart: nil, itemRangeEnd: nil,
                hazmatProportionAllocated: nil
            ),
            childState: e.status.uppercased(),
            animationManifestId: "escort",
            geofenceEvents: []
        )
    }

    /// Roll a single load status up to the parent-shipment vocabulary.
    private static func parentState(fromLoadStatus status: String) -> ParentShipmentState {
        switch status.lowercased() {
        case "draft":                                            return .draft
        case "posted", "bidding", "expired", "declined", "lapsed": return .posted
        case "awarded", "accepted", "assigned", "confirmed":     return .bookedFull
        case "en_route_pickup", "at_pickup", "pickup_checkin",
             "locked", "backing_in", "brakes_set", "connecting",
             "loading_locked", "loading", "loaded",
             "load_locked_filled":                               return .inProgress
        case "in_transit":                                       return .inTransitFull
        case "transit_hold", "transit_exception",
             "loading_exception", "unloading_exception",
             "on_hold", "temp_excursion":                        return .exceptionAny
        case "reefer_breakdown", "contamination_reject",
             "seal_breach", "weight_violation":                  return .exceptionBlocking
        case "at_delivery", "delivery_checkin", "discharging",
             "unloading", "vapor_purging", "disconnecting",
             "detaching":                                        return .inProgress
        case "unloaded", "released", "delivered":                return .delivered
        case "pod_pending", "pod_rejected":                      return .podPartial
        case "invoiced", "disputed", "paid", "complete":         return .complete
        case "cancelled":                                        return .cancelled
        default:                                                 return .inProgress
        }
    }
}
