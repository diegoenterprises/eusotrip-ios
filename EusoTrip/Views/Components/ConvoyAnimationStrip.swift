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

    var body: some View {
        if let svg = EquipmentAnimationCache.shared.svg(for: equipmentKind) {
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

    private var equipmentKind: EquipmentKind {
        let t = vehicle.equipment.type.lowercased()
        // Truck
        if t.contains("dry_van") || t.contains("dry van") { return .dryVan }
        if t.contains("reefer") && !t.contains("rail") && !t.contains("vessel") { return .reefer }
        if t.contains("flatbed") { return .flatbed }
        if t.contains("step_deck") || t.contains("step deck") { return .stepDeck }
        if t.contains("conestoga") { return .conestoga }
        if t.contains("container") && !t.contains("ship") { return .container }
        if t.contains("mc_331") || t.contains("hazmat_tanker") { return .tankerHazmat }
        if t.contains("mc_306") || t.contains("dot_406") || t.contains("petro") { return .tankerPetro }
        if t.contains("dot_407") || t.contains("liquid_tanker") { return .tankerLiquid }
        if t.contains("mc_338") || t.contains("gas_tanker") { return .tankerGas }
        if t.contains("power") { return .powerOnly }
        if t.contains("oversize") || t.contains("rgn") { return .oversized }
        if t.contains("lowboy") { return .lowboy }
        if t.contains("hot_shot") || t.contains("hotshot") { return .hotShot }
        // Rail
        if t.contains("rail_tofc") || t.contains("tofc") { return .railTOFC }
        if t.contains("rail_cofc") || t.contains("cofc") { return .railCOFC }
        if t.contains("rail_intermodal") || t.contains("well_car") { return .railIntermodal }
        if t.contains("dot_105") || t.contains("rail_tank_gas") { return .railTankGas }
        if t.contains("dot_117") || t.contains("dot_111") || t.contains("rail_tank") { return .railTankLiquid }
        if t.contains("rail_boxcar") || t.contains("boxcar") { return .railBoxcar }
        if t.contains("rail_hopper") || t.contains("hopper") { return .railHopper }
        if t.contains("centerbeam") { return .railCenterbeam }
        if t.contains("gondola") { return .railGondola }
        if t.contains("auto_rack") || t.contains("autorack") { return .railAutoRack }
        if t.contains("rail_reefer") { return .railReeferBoxcar }
        if t.contains("flatcar") { return .railFlatcar }
        // Vessel
        if t.contains("vessel_reefer") || t.contains("reefer_container") { return .vesselReeferContainer }
        if t.contains("iso_tank") { return .vesselISOTank }
        if t.contains("container_ship") || t.contains("vessel_container") { return .vesselContainer }
        if t.contains("bulk_carrier") || t.contains("vessel_bulk") { return .vesselBulk }
        if t.contains("vessel_tanker") || t.contains("vlcc") { return .vesselTanker }
        if t.contains("ro_ro") || t.contains("roro") { return .vesselRoRo }
        if t.contains("lng") { return .vesselLNG }

        // Modality fallback
        switch vehicle.modality {
        case .truck:  return .dryVan
        case .rail:   return .railBoxcar
        case .vessel: return .vesselContainer
        }
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

    private func progressFromChildState(_ state: String) -> Double {
        switch state {
        case "DRAFT", "POSTED", "BIDDING", "AWARDED", "ACCEPTED", "ASSIGNED", "CONFIRMED":
            return 0
        case "EN_ROUTE_PICKUP", "EN_ROUTE_DELIVERY":
            return 15
        case "AT_PICKUP", "PICKUP_CHECKIN":
            return 25
        case "LOADING":
            return 35
        case "LOADED", "DEPARTED_PICKUP":
            return 50
        case "IN_TRANSIT", "IN_TRANSIT_AUTONOMOUS", "RAIL_LINEHAUL", "VESSEL_LOADED":
            return 70
        case "AT_DELIVERY", "DELIVERY_CHECKIN":
            return 85
        case "UNLOADING":
            return 90
        case "UNLOADED", "POD_PENDING":
            return 95
        case "DELIVERED", "VESSEL_DISCHARGED", "RAIL_RAMP_OUT", "COMPLETE":
            return 100
        default:
            return 50
        }
    }
}
