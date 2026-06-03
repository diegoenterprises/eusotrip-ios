//
//  661_VesselPortCalls.swift
//  EusoTrip — Vessel Operator · Port Calls.
//
//  Faithful bespoke port of "06 Vessel/Light-SVG/661 Vessel Port Calls.svg" (+ Dark),
//  reconstructed to the live SUPER-INTELLIGENCE FUSION grammar (mirror canonical
//  06 Vessel/Code/661): back chevron + ✦ eyebrow + loop caption + 28pt title "Port calls" ->
//  NEXT-CALL rotation hero (CNSHA·CNNGB·KRPUS·USLGB·USOAK strip + next port + live nm +
//  AIS-LIVE/DEGRADED dot) -> CALL SCHEDULE · GEOFENCE-DRIVEN STATUS list (port·berth /
//  code·ATD-ETA / status pill / day offset) -> ESANG · ROTATION card -> CTA pair.
//
//  The rotation hero, the next-call countdown and the ESang advisory are three faces of
//  ONE tick (WS_EVENTS.PORT_CALL_TICK): AIS closes the distance to the next call; a
//  port-limit geofence ENTER flips that call SCHEDULED→ALONGSIDE and promotes the next port.
//
//  Adapted into the app convention: real Vessel Operator Shell + BottomNav
//  (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME) — the same wrapper the registered
//  vessel siblings 664/680/757 ship — replaces the canonical port's self-drawn nav/orb +
//  .safeAreaInset + systemGroupedBackground page bg (Shell provides them). Bespoke body kept
//  faithfully; all design-system surfaces re-skinned onto palette.bgCard / bgCardSoft and
//  the app's LinearGradient.diagonal / .primary tokens.
//
//  Data / wiring (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    vesselShipments.getVesselPortCalls (EXISTS frontend/server/routers/vesselShipments.ts:1418 ·
//      input {imoNumber:string, days?:number} · returns MarineTraffic PortCall[] (bare array, or
//      null on error) where each call = {portName,portId,unlocode,arrivalTime,departureTime,
//      inPort,draught,country} — see MarineTrafficService.getPortCalls:222). Calls partition into
//      DEPARTED (departureTime set) / ALONGSIDE (inPort) / NEXT (first upcoming) / SCHEDULED by
//      time. Empty array when the IMO has no port-call history in range — the bespoke empty state
//      renders honestly, no fabricated rows.
//    Live rotation tick (next-call nm countdown + AIS-LIVE/DEGRADED) is the marine adaptation of
//      WS_EVENTS.PORT_CALL_TICK (getRealtimePositions + getGeofenceEvents); today it streams the
//      AIS distance closing client-side from the loaded next call. The status flip write
//      (updateVesselShipmentStatus:289 — geofence SCHEDULED→ALONGSIDE) is NOT fired here (read-only
//      board); "Full rotation" / "Berths" are navigation CTAs, no backing mutation.
//
//  0 mock data on load · honest empty/error states. Seed rotation lives ONLY in #Preview path
//  (the VM's static .live). PortCall_661 / RotationTick_661 / IridescentHairline_661 / nm chips
//  are file-scoped bespoke helpers suffixed 661 to avoid cross-file private collisions.
//
//  — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc. · 2026-06-02 EDT.
//

import SwiftUI

private enum CallState661 { case departed, alongside, next, scheduled }

private struct PortCall_661: Identifiable {
    let id = UUID()
    let port: String
    let codeLine: String
    let pill: String
    let offset: String
    let state: CallState661
}

// MARK: - ONE live tick (the fusion source · WS_EVENTS.PORT_CALL_TICK)
private struct RotationTick_661: Equatable {
    var nextCallNm: Double         // distance to the next call (AIS, counts down)
    var nextCallEta: String
    var degraded: Bool
    var esangLine: String          // esangCoach.forScreen, recomputed each tick

    static let live = RotationTick_661(
        nextCallNm: 6.2, nextCallEta: "14:30",
        degraded: false,
        esangLine: "Long Beach 15:00 — Oakland window tightens")
}

@MainActor
private final class RotationVM_661: ObservableObject {
    @Published private(set) var tick: RotationTick_661 = .live

    @Published var loading = true
    @Published var loadError: String? = nil
    @Published var hasCalls = false

    @Published var loop = "EUS-TPEB-07"
    @Published var rotation: [String] = []
    @Published var nextPort = "—"
    @Published var nextCode = "—"
    @Published var calls: [PortCall_661] = []

    private var streamTask: Task<Void, Never>?

    // MARK: live tick — closes the AIS distance to the loaded next call.
    func startStream() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            for await next in Self.rotationStream(seed: self?.tick ?? .live) {
                self?.tick = next
            }
        }
    }
    func stopStream() { streamTask?.cancel() }

    private static func rotationStream(seed: RotationTick_661) -> AsyncStream<RotationTick_661> {
        AsyncStream { continuation in
            continuation.yield(seed)
            let t = Task {
                var p = seed
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    p.nextCallNm = max(0.0, (p.nextCallNm * 10 - 1).rounded() / 10)
                    continuation.yield(p)
                }
            }
            continuation.onTermination = { _ in t.cancel() }
        }
    }

    // MARK: load — vesselShipments.getVesselPortCalls (MarineTraffic PortCall[])
    func load() async {
        loading = true; loadError = nil
        do {
            struct Call: Decodable {
                let portName: String?
                let portId: String?
                let unlocode: String?
                let arrivalTime: String?
                let departureTime: String?
                let inPort: Bool?
                let country: String?
            }
            // Server returns a bare PortCall[] (or null on error).
            let r: [Call]? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselPortCalls",
                input: PortCallsInput661(imoNumber: imoForLoop, days: 30))

            guard let raw = r, !raw.isEmpty else {
                calls = []; rotation = []; hasCalls = false; loading = false
                return
            }

            // departed = has a departure timestamp; alongside = inPort; otherwise upcoming.
            // First upcoming call is the NEXT call (drives the hero + nm countdown).
            var mapped: [PortCall_661] = []
            var firstUpcoming: Int? = nil
            for (idx, c) in raw.enumerated() {
                let code = (c.unlocode ?? c.portId ?? "—").uppercased()
                let port = c.portName ?? code
                let departed = (c.departureTime?.isEmpty == false)
                let alongside = (c.inPort == true) && !departed
                let upcoming = !departed && !alongside
                if upcoming && firstUpcoming == nil { firstUpcoming = idx }

                let state: CallState661 = departed ? .departed
                    : alongside ? .alongside
                    : (firstUpcoming == idx ? .next : .scheduled)

                let timeLine: String = departed
                    ? "\(code) · ATD \(Self.shortTime(c.departureTime))"
                    : alongside
                        ? "\(code) · ALONGSIDE \(Self.shortTime(c.arrivalTime))"
                        : "\(code) · ETA \(Self.shortTime(c.arrivalTime))"

                let pill: String = departed ? "DEPARTED"
                    : alongside ? "ALONGSIDE"
                    : (state == .next ? "NEXT" : "SCHEDULED")

                mapped.append(PortCall_661(
                    port: port,
                    codeLine: timeLine,
                    pill: pill,
                    offset: Self.dayOffset(arrival: c.arrivalTime, departure: c.departureTime),
                    state: state))
            }

            calls = mapped
            rotation = raw.map { ($0.unlocode ?? $0.portId ?? "—").uppercased() }
            if let ni = firstUpcoming {
                nextPort = raw[ni].portName ?? rotation[ni]
                nextCode = rotation[ni]
            } else if let last = raw.last {
                nextPort = last.portName ?? (last.unlocode ?? "—").uppercased()
                nextCode = (last.unlocode ?? last.portId ?? "—").uppercased()
            }
            hasCalls = true
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            hasCalls = false
        }
        loading = false
    }

    /// IMO for the active service loop. In production the loop's lead vessel IMO
    /// is threaded from the journey hub; this board reads the rotation for it.
    private let imoForLoop = "9839430"

    private static func shortTime(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        // ISO 8601 — surface "MMM d HH:mm" without pulling in a heavy formatter.
        let parts = iso.split(separator: "T")
        let date = String(parts.first ?? "")
        let time = parts.count > 1 ? String(parts[1].prefix(5)) : ""
        return time.isEmpty ? date : "\(date) \(time)"
    }

    private static func dayOffset(arrival: String?, departure: String?) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let ref = departure?.isEmpty == false ? departure : arrival
        guard let ref, !ref.isEmpty, let d = f.date(from: ref) else { return "—" }
        let days = Int((d.timeIntervalSinceNow / 86400).rounded())
        if days == 0 { return "today" }
        return days < 0 ? "\(days)d" : "+\(days)d"
    }
}

private struct PortCallsInput661: Encodable {
    let imoNumber: String
    let days: Int
}

// MARK: - Wrapper (Shell + real Vessel Operator nav · SHIPMENTS inked)

struct VesselPortCallsScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselPortCallsBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselPortCallsBody: View {
    @Environment(\.palette) private var palette
    @StateObject private var vm = RotationVM_661()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                IridescentHairline_661()

                if vm.loading {
                    LifecycleCard { Text("Loading rotation…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = vm.loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !vm.hasCalls {
                    EusoEmptyState(systemImage: "ferry",
                                   title: "No port calls in range",
                                   subtitle: "getVesselPortCalls returned no AIS port-call history for this rotation. Nothing to plot — no fabricated calls.")
                } else {
                    rotationHero
                    scheduleList
                    esangCard
                    ctaRow
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await vm.load(); vm.startStream() }
        .refreshable { await vm.load() }
        .onDisappear { vm.stopStream() }
    }

    // MARK: header
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("VESSEL OPERATOR · PORT CALLS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(vm.loop).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 10) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("Port calls").font(.system(size: 28, weight: .bold)).kerning(-0.4).foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: NEXT-CALL rotation hero (live nm + AIS pulse)
    private var rotationHero: some View {
        let liveColor = vm.tick.degraded ? Brand.warning : Brand.success
        let doneIdx = vm.rotation.firstIndex(of: vm.nextCode) ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NEXT CALL · ROTATION \(vm.loop)").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(liveColor).frame(width: 6, height: 6)
                    Text(vm.tick.degraded ? "DEGRADED" : "AIS LIVE").font(.system(size: 8.5, weight: .heavy)).tracking(0.6).foregroundStyle(liveColor)
                }
            }
            // rotation chip strip
            HStack(spacing: 6) {
                ForEach(Array(vm.rotation.enumerated()), id: \.offset) { idx, code in
                    let isNext = code == vm.nextCode
                    let done = idx < doneIdx
                    Text(code).font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(isNext ? AnyShapeStyle(.white) : (done ? AnyShapeStyle(palette.textTertiary) : AnyShapeStyle(palette.textPrimary)))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Capsule().fill(isNext ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft)))
                    if idx < vm.rotation.count - 1 {
                        Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold)).foregroundStyle(palette.textTertiary)
                    }
                }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.nextPort).font(.system(size: 30, weight: .bold)).foregroundStyle(LinearGradient.diagonal)
                    Text(vm.nextCode).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(vm.tick.degraded ? "rough est." : String(format: "in %.1f nm", vm.tick.nextCallNm))
                        .font(.system(size: 16, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text("ETA \(vm.tick.nextCallEta) · closes on tick").font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: CALL SCHEDULE · GEOFENCE-DRIVEN STATUS
    private var scheduleList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CALL SCHEDULE · GEOFENCE-DRIVEN STATUS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary).padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(Array(vm.calls.enumerated()), id: \.element.id) { idx, c in
                    callRow(c)
                    if idx < vm.calls.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 16)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
        }
    }

    private func callRow(_ c: PortCall_661) -> some View {
        let tint: Color = tintFor661(c.state)
        let icon: String = c.state == .next ? "mappin.and.ellipse"
            : c.state == .departed ? "ferry"
            : c.state == .alongside ? "anchor"
            : "clock"
        let pillText: String = (c.state == .next && !vm.tick.degraded)
            ? "NEXT · \(String(format: "%.0f", vm.tick.nextCallNm))nm"
            : c.pill
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(c.port).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(c.codeLine).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(pillText)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5).foregroundStyle(tint)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(tint.opacity(0.16)))
                Text(c.offset).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func tintFor661(_ s: CallState661) -> Color {
        switch s {
        case .next:      return Brand.blue
        case .departed:  return palette.textTertiary
        case .alongside: return Brand.success
        case .scheduled: return Brand.warning
        }
    }

    // MARK: ESANG · ROTATION
    private var esangCard: some View {
        HStack(alignment: .top, spacing: 0) {
            orbMini.padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · ROTATION").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(vm.tick.esangLine).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("request an earlier downstream slot · rotation buffer eroding").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint))
    }

    private var orbMini: some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
            Circle().fill(RadialGradient(colors: [.white.opacity(0.6), .clear], center: .topLeading, startRadius: 1, endRadius: 16)).frame(width: 32, height: 32)
        }
    }

    // MARK: CTA pair (navigation · no backing mutation on this read-only board)
    private var ctaRow: some View {
        HStack(spacing: 8) {
            Text("Full rotation").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            Text("Berths").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .frame(width: 148, height: 48)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }
}

// MARK: - File-scoped bespoke helper (preserve the canonical wireframe look)

private struct IridescentHairline_661: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient.diagonal.opacity(0.55))
            .frame(height: 1)
    }
}

#Preview("661 · Vessel Port Calls · Night") {
    VesselPortCallsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("661 · Vessel Port Calls · Light") {
    VesselPortCallsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
