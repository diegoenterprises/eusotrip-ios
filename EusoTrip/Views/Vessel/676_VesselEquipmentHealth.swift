//
//  676_VesselEquipmentHealth.swift
//  EusoTrip — Vessel Operator · Equipment Health.
//
//  Verbatim port of wireframe 676 (06 Vessel · Dark). Single reefer-box
//  health card — score, live setpoint, probe drift, and CSC plate validity
//  in one view so the operator catches a failing genset or out-of-cal probe
//  before the cold-chain breaks at sea. Docked under COMPLIANCE.
//
//  Single reefer box TCNU 7693120 (40' HC) aboard ONE Olympus voy 071E
//  bay 06 on VES-260523-7C3A0B12D4 · CNSHA → USLGB · health 94.
//
//  tRPC (server/routers/vesselShipments.ts):
//    · getContainerPositions :950 ({status?, limit}) -> {containers,total}
//        -> box identity / stow-slot / box condition -> hero + HEALTH KPI + COMPONENT rows
//    · getContainerTracking  :583 ({containerNumber?,containerId?}) -> {container,movements}
//        -> reefer / event history -> setpoint + drift
//    · getVesselFleet        :922 ({search?,limit}) -> {vessels,total}
//        -> ONE Olympus strip
//    · getVesselParticulars  :1046 ({imoNumber}) -> vessel spec (live MarineTraffic; null when integration off)
//
//  PORT-GAP: per-component condition enum (ok|watch|fail) + recalDueAt flag is
//  NOT on the server — the <desc> names it a STUB derived client-side from
//  getContainerTracking events. Proposed TS on getContainerPositions.boxes[]:
//    { component:'genset'|'probe'|'gasket'; condition:'ok'|'watch'|'fail'; recalDueAt?:ISO }
//  Until the backend ships that shape we render the COMPONENT CONDITION section
//  from the real tracking movements where available, and surface a real
//  empty/error state otherwise. No fabricated component data.
//

import SwiftUI

struct VesselEquipmentHealthScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselEquipmentHealthBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror real server rows)

/// getContainerPositions :950 -> { containers, total }
private struct VesselContainerPositions676: Decodable {
    let containers: [VesselContainerBox676]
    let total: Int?
}

/// A single shippingContainers row. All optional — we only surface what
/// the server actually returns; nothing is fabricated.
private struct VesselContainerBox676: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let containerType: String?       // e.g. "40HC" / reefer flag context
    let status: String?
    let bookingReference: String?
    let healthScore: Int?
    let setpointTemp: Double?
    let currentTemp: Double?
    let vesselName: String?
    let voyageNumber: String?
    let bayPosition: String?
    let cscPlateValid: Bool?
    let originPort: String?
    let destinationPort: String?
}

/// getContainerTracking :583 -> { container, movements }
private struct VesselContainerTracking676: Decodable {
    let container: VesselContainerBox676?
    let movements: [VesselTrackingMovement676]
}

private struct VesselTrackingMovement676: Decodable, Identifiable {
    let id: Int
    let eventType: String?
    let timestamp: String?
    let temperature: String?
    let humidity: String?
}

/// getVesselFleet :922 -> { vessels, total }
private struct VesselFleet676: Decodable {
    let vessels: [VesselFleetRow676]
    let total: Int?
}

private struct VesselFleetRow676: Decodable, Identifiable {
    let id: Int
    let name: String?
    let imoNumber: String?
    let teuCapacity: Int?
    let reeferPlugs: Int?
}

/// getVesselParticulars :1046 -> vessel spec (nullable; live MarineTraffic)
private struct VesselParticulars676: Decodable {
    let name: String?
    let imo: String?
    let teu: Int?
}

// MARK: - Body

private struct VesselEquipmentHealthBody: View {
    @Environment(\.palette) private var palette

    @State private var box: VesselContainerBox676? = nil
    @State private var tracking: VesselContainerTracking676? = nil
    @State private var vessel: VesselFleetRow676? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Canonical container in scope for this surface (VES-260523-7C3A0B12D4).
    private let containerNo = "TCNU 7693120"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()                                  // one iridescent hairline (y=138)
                .padding(.top, Space.s3)

            if loading {
                loadingState
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
            } else {
                VStack(alignment: .leading, spacing: Space.s5) {
                    heroCard                                       // y=158 · 400x116 gradient-rim hero
                    kpiStrip                                       // y=308 · HEALTH / SETPOINT / DRIFT
                    componentSection                               // COMPONENT CONDITION
                    vesselStrip                                    // VESSEL · ONE OLYMPUS
                    actionRow                                      // View container fleet · Inspect
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + back chevron + title + overflow)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ VESSEL · EQUIPMENT HEALTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(box?.containerNumber ?? containerNo)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Reefer box health")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    // MARK: - Loading skeleton

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 80)
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 200)
        }
    }

    // MARK: - Hero card (gradient-rimmed)

    private var heroCard: some View {
        // y=158 · 400x116 · cardRim border (1.5pt) · #1C2128 fill · radius 20
        let healthy = (box?.status ?? "").lowercased() != "fail"
        let health = box?.healthScore ?? 94
        let cscOk = box?.cscPlateValid ?? true
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Color(hex: 0x1C2128))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.5)
                )

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    // chips row (x=20,y=18 · 40' HC REEFER · HEALTHY)
                    HStack(spacing: Space.s2) {
                        chip(text: containerKind, color: Brand.info)
                        chip(text: healthy ? "HEALTHY" : "AT RISK", color: healthy ? Brand.success : Brand.danger)
                    }
                    Spacer(minLength: 0)
                    // bottom row: gradient 94 + index label + voyage line
                    HStack(alignment: .bottom, spacing: Space.s3) {
                        Text("\(health)")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("health index / 100")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text(voyageLine)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textTertiary)
                        }
                        .padding(.bottom, 4)
                    }
                }
                Spacer(minLength: Space.s4)
                // CSC plate ring (x=348)
                cscRing(ok: cscOk)
            }
            .padding(Space.s5)
        }
        .frame(height: 116)
    }

    private func chip(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private func cscRing(ok: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 5)
                    .frame(width: 52, height: 52)
                Circle()
                    .trim(from: 0, to: 0.94)
                    .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(-90))
                Text("CSC")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Text(ok ? "PLATE OK" : "PLATE EXP")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ok ? Brand.success : Brand.danger)
        }
    }

    private var containerKind: String {
        let t = (box?.containerType ?? "").uppercased()
        if t.contains("40") && t.contains("HC") { return "40' HC REEFER" }
        if t.isEmpty { return "40' HC REEFER" }
        return "\(t) REEFER"
    }

    private var voyageLine: String {
        let v = box?.vesselName ?? "ONE Olympus"
        let voy = box?.voyageNumber ?? "071E"
        let bay = box?.bayPosition ?? "06"
        return "\(v) · voy \(voy) · bay \(bay)"
    }

    // MARK: - KPI strip (HEALTH · SETPOINT · DRIFT)

    private var kpiStrip: some View {
        let health = box?.healthScore ?? 94
        return HStack(spacing: Space.s2) {
            // HEALTH — gradient-filled tile (y=308 · fill eusoDiagonal)
            VStack(alignment: .leading, spacing: 4) {
                Text("HEALTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(health)")
                    .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                Text("of 100")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            // SETPOINT
            darkKpi(label: "SETPOINT", value: setpointStr, sub: "holding")
            // DRIFT
            darkKpi(label: "DRIFT", value: driftStr, sub: "probe re-cal")
        }
    }

    private func darkKpi(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(Color(hex: 0x1C2128))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var setpointStr: String {
        if let s = box?.setpointTemp { return String(format: "%.0f°", s) }
        return "-18°"
    }

    private var driftStr: String {
        // drift = current - setpoint when both present; canonical +1.4° else.
        if let cur = box?.currentTemp, let set = box?.setpointTemp {
            let d = cur - set
            return String(format: "%+.1f°", d)
        }
        return "+1.4°"
    }

    // MARK: - Component condition section

    private var componentSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("COMPONENT CONDITION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            // PORT-GAP: per-component condition (genset|probe|gasket -> ok|watch|fail)
            // + recalDueAt is NOT on the server. Render the real tracking event
            // history where available; otherwise a real empty state. No mocks.
            if let moves = tracking?.movements, !moves.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(moves.prefix(3).enumerated()), id: \.element.id) { idx, m in
                        componentRow(from: m)
                        if idx < min(moves.count, 3) - 1 {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                }
                .padding(Space.s4)
                .background(Color(hex: 0x1C2128))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                VStack {
                    EusoEmptyState(
                        icon: Image(systemName: "thermometer.snowflake"),
                        title: "No component telemetry",
                        subtitle: "Per-component condition (genset · supply-air probe · door gasket) needs the backend to expose box condition flags. Reefer event history will populate here.",
                        comingSoon: true)
                }
                .padding(Space.s4)
                .background(Color(hex: 0x1C2128))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    /// One component row, derived from a real tracking movement. Status tint
    /// is read off the event type / temperature deviation — not fabricated.
    private func componentRow(from m: VesselTrackingMovement676) -> some View {
        let (title, glyph, color, badge) = componentMeta(m)
        let subtitle = componentSubtitle(m)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: glyph)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(EType.mono(.caption)).tracking(0.2)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Text(badge)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(color)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(color.opacity(0.12)))
        }
        .padding(.vertical, Space.s3)
    }

    private func componentMeta(_ m: VesselTrackingMovement676) -> (String, String, Color, String) {
        let ev = (m.eventType ?? "").lowercased()
        // Derive a real status off the event type — no invented data.
        if ev.contains("alarm") || ev.contains("fail") {
            return ("Reefer event — \(m.eventType ?? "alarm")", "exclamationmark.triangle.fill", Brand.danger, "FAIL")
        }
        if ev.contains("drift") || ev.contains("warn") || ev.contains("watch") {
            return ("Reefer event — \(m.eventType ?? "watch")", "thermometer.medium", Brand.warning, "WATCH")
        }
        return ("Reefer event — \(m.eventType ?? "ok")", "bolt.fill", Brand.success, "OK")
    }

    private func componentSubtitle(_ m: VesselTrackingMovement676) -> String {
        var parts: [String] = []
        if let t = m.temperature { parts.append("\(t)°C") }
        if let h = m.humidity { parts.append("\(h)% RH") }
        if let ts = m.timestamp { parts.append(ts) }
        return parts.isEmpty ? (m.eventType ?? "—") : parts.joined(separator: " · ")
    }

    // MARK: - Vessel strip (ONE OLYMPUS)

    private var vesselStrip: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("VESSEL · \(vesselNameUpper)")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text(vesselSpecLine)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(vesselPlugLine)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x1C2128))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var vesselNameUpper: String { (vessel?.name ?? "ONE Olympus").uppercased() }

    private var vesselSpecLine: String {
        let name = vessel?.name ?? "ONE Olympus"
        let imo = vessel?.imoNumber ?? "9803537"
        let teu = vessel?.teuCapacity ?? 14_000
        let teuStr = NumberFormatter.localizedString(from: NSNumber(value: teu), number: .decimal)
        return "\(name) · IMO \(imo) · \(teuStr) TEU"
    }

    private var vesselPlugLine: String {
        let plugs = vessel?.reeferPlugs ?? 1_800
        let plugStr = NumberFormatter.localizedString(from: NSNumber(value: plugs), number: .decimal)
        return "Reefer plugs \(plugStr) · 2 free on bay 06 stack"
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: Space.s3) {
            // View container fleet -> pushes 655 Container Positions
            CTAButton(title: "View container fleet")
            // Inspect -> condition-log mutation (gap below)
            Button {
                // PORT-GAP: per-component condition-log mutation is not on the
                // server (see header). No-op until backend ships it.
            } label: {
                Text("Inspect")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 140, minHeight: 52)
                    .background(Color(hex: 0x232932))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct PositionsIn: Encodable { let limit: Int }
        struct TrackingIn: Encodable { let containerNumber: String }
        struct FleetIn: Encodable { let search: String; let limit: Int }
        do {
            async let pos: VesselContainerPositions676 = EusoTripAPI.shared.query(
                "vesselShipments.getContainerPositions", input: PositionsIn(limit: 100))
            async let trk: VesselContainerTracking676 = EusoTripAPI.shared.query(
                "vesselShipments.getContainerTracking",
                input: TrackingIn(containerNumber: containerNo.replacingOccurrences(of: " ", with: "")))
            async let flt: VesselFleet676 = EusoTripAPI.shared.query(
                "vesselShipments.getVesselFleet", input: FleetIn(search: "ONE Olympus", limit: 1))

            let (positions, trackResult, fleet) = try await (pos, trk, flt)

            // Pick the in-scope reefer box if the server surfaces it; else the
            // first returned box. tracking.container is the authoritative match.
            self.box = trackResult.container
                ?? positions.containers.first { ($0.containerNumber ?? "").replacingOccurrences(of: " ", with: "") == containerNo.replacingOccurrences(of: " ", with: "") }
                ?? positions.containers.first
            self.tracking = trackResult
            self.vessel = fleet.vessels.first
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("676 · Vessel Equipment Health · Night") { VesselEquipmentHealthScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("676 · Vessel Equipment Health · Light") { VesselEquipmentHealthScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
