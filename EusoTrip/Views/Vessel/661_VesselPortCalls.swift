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
//    vesselShipments.getVesselFleet (EXISTS vesselShipments.ts:1377 · {limit,offset} ->
//      {vessels:[raw vessels rows incl. name + imoNumber], total}) resolves the operator's REAL
//      lead vessel when no IMO is threaded — the rotation identity (loop label + IMO) is live
//      data or an honest empty state, never a hardcoded string.
//
//  ZERO-FALLBACK (2026-06-09 · C1 fix): the fabricated RotationTick (6.2 nm / "14:30" / hardcoded
//  ESang line), its fake-distance countdown stream, and the hardcoded loop "EUS-TPEB-07" / IMO
//  "9839430" are DELETED. The hero's next-call ETA derives from the next upcoming call's REAL
//  arrivalTime; there is no live-distance source today so no nm figure renders. The ESang card
//  renders only when a real advisory exists (none today ⇒ hidden). The status flip write
//  (updateVesselShipmentStatus:289) is NOT fired here (read-only board); "Full rotation" /
//  "Berths" are navigation CTAs, no backing mutation. PortCall_661 / IridescentHairline_661
//  are file-scoped bespoke helpers suffixed 661 to avoid cross-file private collisions.
//
//  — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc. · 2026-06-02 EDT.
//

import SwiftUI

private enum CallState661 { case departed, alongside, next, scheduled }

private struct PortCall_661: Identifiable {
    let id = UUID()
    let port: String
    let unlocode: String           // raw UN/LOCODE for the catalog lookup
    let codeLine: String
    let pill: String
    let offset: String
    let state: CallState661
    /// Real catalog coordinate (PortDirectory.find(unlocode:)) — nil when the
    /// call's UN/LOCODE is not in the NGA Pub 150 directory; such calls stay in
    /// the schedule list but are SKIPPED from the map (no fabricated point).
    let coord: HereLatLng?
}

@MainActor
private final class RotationVM_661: ObservableObject {
    @Published var loading = true
    @Published var loadError: String? = nil
    @Published var hasVessel = false
    @Published var hasCalls = false

    /// Live rotation identity — the resolved vessel's name + IMO (getVesselFleet),
    /// nil until a real vessel resolves. No hardcoded loop/IMO.
    @Published var loop: String? = nil
    @Published var imo: String? = nil
    @Published var rotation: [String] = []
    @Published var nextPort = "-"
    @Published var nextCode = "-"
    /// REAL next-call ETA derived from the next upcoming call's arrivalTime — "-" when none.
    @Published var nextEta = "-"
    @Published var calls: [PortCall_661] = []
    /// Real advisory line only (no feed today ⇒ the ESang card stays hidden).
    @Published var esangLine: String? = nil
    /// Channel marine conditions at the NEXT call's port (getPortConditions).
    /// nil until the next call resolves to a catalog coordinate AND the marine
    /// feed answers — enterprise-gated today ⇒ stays nil, advisory hidden.
    @Published var portConditions: PortConditions661? = nil

    /// The catalog coordinate of the NEXT call's port — the channel the
    /// inbound transit is approaching, so the pilotage-hold advisory reads off
    /// the port we're about to enter. nil ⇒ no conditions fetch (honest).
    var nextCallCoord: HereLatLng? {
        if let next = calls.first(where: { $0.state == .next })?.coord { return next }
        return calls.first(where: { $0.state == .scheduled })?.coord
    }

    // MARK: derived map state — port pins + call sequence (real catalog coords)

    /// Calls that resolved to a real PortDirectory coordinate, IN ROTATION ORDER.
    /// Calls whose UN/LOCODE is not in the catalog are dropped here (skipped from
    /// the map) but stay in `calls` for the schedule list.
    var mappableCalls: [PortCall_661] { calls.filter { $0.coord != nil } }

    /// True when at least one port call resolved to a catalog coordinate.
    var hasMappablePorts: Bool { mappableCalls.contains { $0.coord != nil } }

    /// Map camera center = mean of the resolved port coordinates (the rotation's
    /// geographic centroid). nil ⇒ nothing to frame.
    var mapCenter: HereLatLng? {
        let pts = mappableCalls.compactMap { $0.coord }
        guard !pts.isEmpty else { return nil }
        let lat = pts.map(\.lat).reduce(0, +) / Double(pts.count)
        let lng = pts.map(\.lng).reduce(0, +) / Double(pts.count)
        return HereLatLng(lat, lng)
    }

    /// Ocean-register zoom from the resolved-port coordinate spread. Wider spread
    /// ⇒ lower zoom. Coarse buckets matched to the great-circle register.
    var mapZoom: Int {
        let pts = mappableCalls.compactMap { $0.coord }
        guard pts.count > 1,
              let minimumLatitude = pts.map(\.lat).min(),
              let maximumLatitude = pts.map(\.lat).max(),
              let minimumLongitude = pts.map(\.lng).min(),
              let maximumLongitude = pts.map(\.lng).max() else { return 6 }
        let latSpan = maximumLatitude - minimumLatitude
        let lngSpan = maximumLongitude - minimumLongitude
        let span = max(latSpan, lngSpan)
        switch span {
        case ..<2:    return 7
        case ..<6:    return 6
        case ..<14:   return 5
        case ..<30:   return 4
        default:      return 3
        }
    }

    // MARK: load — resolve the REAL vessel, then vesselShipments.getVesselPortCalls
    func load(threadedImo: String?) async {
        loading = true; loadError = nil; portConditions = nil
        do {
            // 1. Rotation identity: threaded IMO wins; otherwise the operator's real
            //    lead vessel from getVesselFleet. No vessel ⇒ honest empty state.
            var imoNumber = threadedImo
            if imoNumber == nil || imoNumber?.isEmpty == true {
                struct FleetIn661: Encodable { let limit: Int; let offset: Int }
                struct VesselRow661: Decodable { let name: String?; let imoNumber: String? }
                struct FleetEnv661: Decodable { let vessels: [VesselRow661] }
                let fleet: FleetEnv661 = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselFleet", input: FleetIn661(limit: 1, offset: 0))
                imoNumber = fleet.vessels.first?.imoNumber
                loop = fleet.vessels.first?.name
            }
            guard let imoNumber, !imoNumber.isEmpty else {
                hasVessel = false; calls = []; rotation = []; hasCalls = false; loading = false
                return
            }
            hasVessel = true
            imo = imoNumber

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
                input: PortCallsInput661(imoNumber: imoNumber, days: 30))

            guard let raw = r, !raw.isEmpty else {
                calls = []; rotation = []; hasCalls = false; loading = false
                return
            }

            // departed = has a departure timestamp; alongside = inPort; otherwise upcoming.
            // First upcoming call is the NEXT call (drives the hero + nm countdown).
            var mapped: [PortCall_661] = []
            var firstUpcoming: Int? = nil
            for (idx, c) in raw.enumerated() {
                let code = (c.unlocode ?? c.portId ?? "-").uppercased()
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

                // Resolve UN/LOCODE → real coordinate via the SAME catalog
                // Vessel 660/003 use (PortDirectory.find(unlocode:) — NGA Pub 150).
                // Calls whose code is not in the directory carry coord == nil and
                // are skipped from the map below; they remain in the schedule list.
                let geo: HereLatLng? = (c.unlocode.flatMap { uc in
                    PortDirectory.find(unlocode: uc.uppercased())
                }).flatMap { port in
                    guard let coordinate = LatLongParser.validatedCoordinate(
                        latitude: port.lat,
                        longitude: port.lng
                    ) else { return nil }
                    return HereLatLng(coordinate)
                }

                mapped.append(PortCall_661(
                    port: port,
                    unlocode: code,
                    codeLine: timeLine,
                    pill: pill,
                    offset: Self.dayOffset(arrival: c.arrivalTime, departure: c.departureTime),
                    state: state,
                    coord: geo))
            }

            calls = mapped
            rotation = raw.map { ($0.unlocode ?? $0.portId ?? "-").uppercased() }
            if let ni = firstUpcoming {
                nextPort = raw[ni].portName ?? rotation[ni]
                nextCode = rotation[ni]
                nextEta = Self.shortTime(raw[ni].arrivalTime)
            } else if let last = raw.last {
                nextPort = last.portName ?? (last.unlocode ?? "-").uppercased()
                nextCode = (last.unlocode ?? last.portId ?? "-").uppercased()
                nextEta = "-"
            }
            hasCalls = true

            // Channel marine conditions at the NEXT call's port (getPortConditions)
            // → the channel-fog PILOTAGE-HOLD advisory in the ESang · ROTATION
            // slot. NON-FATAL + enterprise-gated: keyed off the next call's
            // catalog coordinate (PortDirectory · NGA Pub 150 — the SAME lookup
            // the schedule + map use); a feed error or `available:false` leaves
            // `portConditions` nil so the advisory stays honestly hidden, and it
            // never breaks the rotation board.
            if let next = nextCallCoord {
                portConditions = try? await EusoTripAPI.shared.query(
                    "vesselShipments.getPortConditions",
                    input: PortConditionsInput661(lat: next.lat, lng: next.lng))
            } else {
                portConditions = nil
            }
        } catch {
            loadError = error.eusoUserCopy
            hasCalls = false
        }
        loading = false
    }

    private static func shortTime(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "-" }
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
        guard let ref, !ref.isEmpty, let d = f.date(from: ref) else { return "-" }
        let days = Int((d.timeIntervalSinceNow / 86400).rounded())
        if days == 0 { return "today" }
        return days < 0 ? "\(days)d" : "+\(days)d"
    }
}

private struct PortCallsInput661: Encodable {
    let imoNumber: String
    let days: Int
}

/// `getPortConditions` — channel marine conditions at the NEXT call's port
/// (Wave-4 server #85). Drives the channel-fog PILOTAGE-HOLD advisory that
/// fills 661's ESang · ROTATION slot. Every field decodes optionally: the
/// marine feed is enterprise-gated today (`available:false` → null readings),
/// so a partial/unavailable payload degrades to the honest hidden state, never
/// a thrown decode. `craneWindLimitKt` / the pilotage `visibilityMinimumNm`
/// are PUBLISHED operating standards the server measures against — each carries
/// a `basis` citation so the advisory never reads as a fabricated verdict.
private struct PortConditions661: Decodable {
    let available: Bool?
    let pilotageHold: Bool?
    let berthingSafety: String?
    let visibility: Double?
    let visibilityMinimumNm: Double?
    let waveSignificantHeight: Double?
    let windGust: Double?
    let forecastGustKt: Double?
    let basis: String?
    let pilotageBasis: String?

    private enum CodingKeys: String, CodingKey {
        case available, pilotageHold, berthingSafety, visibility, visibilityMinimumNm
        case waveSignificantHeight, windGust, forecastGustKt, basis, pilotageBasis
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available             = try? c.decode(Bool.self, forKey: .available)
        pilotageHold          = try? c.decode(Bool.self, forKey: .pilotageHold)
        berthingSafety        = try? c.decode(String.self, forKey: .berthingSafety)
        visibility            = try? c.decode(Double.self, forKey: .visibility)
        visibilityMinimumNm   = try? c.decode(Double.self, forKey: .visibilityMinimumNm)
        waveSignificantHeight = try? c.decode(Double.self, forKey: .waveSignificantHeight)
        windGust              = try? c.decode(Double.self, forKey: .windGust)
        forecastGustKt        = try? c.decode(Double.self, forKey: .forecastGustKt)
        basis                 = try? c.decode(String.self, forKey: .basis)
        pilotageBasis         = try? c.decode(String.self, forKey: .pilotageBasis)
    }

    /// The published pilotage visibility minimum (nm) — server value wins; the
    /// fallback is the doctrine floor (≈0.5 nm) used only to decide the trip.
    var pilotageMinimumNm: Double { visibilityMinimumNm ?? 0.5 }

    /// Channel visibility is below the published pilot-boarding minimum.
    var visibilityBelowMinimum: Bool {
        guard let v = visibility else { return false }
        return v < pilotageMinimumNm
    }

    /// Trip ONLY on a real signal — an explicit pilotage hold or measured
    /// visibility below the minimum. nil/empty (enterprise-gated) never trips.
    var pilotageHoldTripped: Bool {
        if available == false { return false }
        if pilotageHold == true { return true }
        return visibilityBelowMinimum
    }
}

private struct PortConditionsInput661: Encodable {
    let lat: Double
    let lng: Double
}

// MARK: - Wrapper (Shell + real Vessel Operator nav · SHIPMENTS inked)

struct VesselPortCallsScreen: View {
    let theme: Theme.Palette
    /// IMO threaded from the journey hub; nil resolves the operator's lead vessel live.
    var imoNumber: String? = nil
    init(theme: Theme.Palette, imoNumber: String? = nil) { self.theme = theme; self.imoNumber = imoNumber }
    var body: some View {
        Shell(theme: theme) {
            VesselPortCallsBody(imoNumber: imoNumber)
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
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm = RotationVM_661()
    let imoNumber: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                IridescentHairline_661()

                if vm.loading {
                    LifecycleCard { Text("Loading rotation…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = vm.loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !vm.hasVessel {
                    EusoEmptyState(systemImage: "ferry",
                                   title: "No vessel resolved",
                                   subtitle: "No vessel was resolved for this operator and no IMO was carried into this screen. There is nothing to plot, and no rotation is invented to fill the gap.")
                } else if !vm.hasCalls {
                    EusoEmptyState(systemImage: "ferry",
                                   title: "No port calls in range",
                                   subtitle: "AIS returned no port-call history for this rotation. There is nothing to plot, and no calls are invented to fill the gap.")
                } else {
                    rotationHero
                    rotationMap
                    scheduleList
                    // ESANG · ROTATION slot — the channel-fog PILOTAGE-HOLD
                    // advisory fills it when getPortConditions trips on the next
                    // call's channel; otherwise a real ESang line; else hidden.
                    if let c = vm.portConditions, c.pilotageHoldTripped {
                        pilotageHoldCard(c)
                    } else if vm.esangLine != nil {
                        esangCard
                    }
                    ctaRow
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await vm.load(threadedImo: imoNumber) }
        .eusoRefreshable { await vm.load(threadedImo: imoNumber) }
    }

    // MARK: header
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("VESSEL OPERATOR · PORT CALLS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                // Live rotation identity (vessel name · IMO) — em-dash until resolved.
                Text(vm.loop ?? vm.imo.map { "IMO \($0)" } ?? "—").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 10) {
                Text("Port calls").font(.system(size: 28, weight: .bold)).kerning(-0.4).foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: NEXT-CALL rotation hero (real next-call ETA — no fabricated nm countdown)
    private var rotationHero: some View {
        let doneIdx = vm.rotation.firstIndex(of: vm.nextCode) ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NEXT CALL · ROTATION \(vm.loop ?? "—")").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                    Text("AIS HISTORY").font(.system(size: 8.5, weight: .heavy)).tracking(0.6).foregroundStyle(Brand.success)
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
                    // Real next-call ETA from the AIS port-call row — em-dash when none.
                    Text(vm.nextEta == "-" ? "—" : "ETA \(vm.nextEta)")
                        .font(.system(size: 16, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text("Port calls · by arrival time").font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: ROTATION MAP · UN/LOCODE → catalog coordinate (ocean register)
    //
    // Each port call's UN/LOCODE is resolved to a REAL coordinate via
    // PortDirectory.find(unlocode:) (NGA Pub 150, the SAME catalog Vessel 660/003
    // use). Resolved ports plot as hollow port pins on the .ocean great-circle
    // register, joined IN ROTATION ORDER by a call-sequence polyline. Calls whose
    // code is not in the directory are skipped from the map (no fabricated point);
    // they still appear in the schedule list below. If NONE resolve, an honest
    // "no catalog coordinates" note replaces the canvas — never a blank/faked map.
    @ViewBuilder private var rotationMap: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("ROTATION MAP · UN/LOCODE → PORT DIRECTORY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text("\(vm.mappableCalls.count)/\(vm.calls.count) plotted")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, 10)

            if let center = vm.mapCenter, vm.hasMappablePorts {
                HereVectorMapView(
                    center: center,
                    zoom: vm.mapZoom,
                    interactive: true,
                    tilt: 0,
                    layers: rotationLayers,
                    styleHint: .ocean,
                    mapModeContext: .primary(.vessel),
                    onSelectMarker: { _ in }     // informational pins — no handler nav
                )
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            } else {
                // Every call's UN/LOCODE missing from the catalog — honest note.
                VStack(spacing: 6) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Text("No catalog coordinates")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("None of these UN/LOCODEs are in the PortDirectory catalog — nothing to plot, no fabricated pins.")
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28).padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    /// Ocean-register layers: real port-call pins only. Call order is not
    /// navigational route geometry. Departed calls render as the grey
    /// `.delivery` ring; active / upcoming calls as the primary `.pickup` ring.
    private var rotationLayers: [HereMapLayer] {
        [.markers(vm.mappableCalls.compactMap { call in
            guard let at = call.coord else { return nil }
            let kind: HereMarker.Kind = (call.state == .departed) ? .delivery : .pickup
            return HereMarker(at: at, kind: kind, label: call.port, id: call.unlocode)
        })]
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
        let pillText: String = c.pill
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

    // MARK: ESANG · ROTATION — channel-fog PILOTAGE-HOLD advisory
    //
    // Fills the ESang · ROTATION slot when getPortConditions reports a pilotage
    // hold OR channel visibility below the published pilot-boarding minimum at
    // the NEXT call's port. Bespoke: the WeatherIcons .eye / .fog glyph (ZERO
    // SF Symbols on the weather element) + the ESang orb + the berthingSafety
    // state pill. HONEST: only rendered when the advisory actually trips on real
    // marine data — the empty / clear / enterprise-gated case leaves it hidden.
    // The basis line cites the operating standard so it never reads as a
    // fabricated EusoTrip verdict.
    private func pilotageHoldCard(_ c: PortConditions661) -> some View {
        let safety = berthingSafety661(c.berthingSafety)
        return HStack(alignment: .top, spacing: 0) {
            // The ESang orb identifies the advisory voice; the fog/eye glyph
            // overlays the channel-visibility signal.
            ZStack {
                orbMini
                if c.visibilityBelowMinimum {
                    WeatherIcons.symbolView(for: 2000, size: 18)   // #i-fog
                        .offset(x: 9, y: 9)
                }
            }
            .padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("ESANG · PILOTAGE HOLD")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(safety.tint)
                    Text(safety.badge)
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(safety.tint)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(safety.tint.opacity(0.16)))
                }
                Text(c.visibilityBelowMinimum
                     ? "\(vm.nextPort) channel · fog below pilot-boarding minimum"
                     : "\(vm.nextPort) channel · pilotage hold in effect")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(pilotageDetail661(c))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let basis = c.pilotageBasis ?? c.basis, !basis.isEmpty {
                    HStack(spacing: 5) {
                        WeatherIcons.utility(.alert, size: 10, tint: palette.textTertiary)
                        Text(basis)
                            .font(.system(size: 9.5))
                            .foregroundStyle(palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(safety.tint.opacity(0.55), lineWidth: 1.2))
    }

    /// Mono detail — measured visibility vs. the published minimum + sea-state.
    /// Honest em-dash collapse: only fields the feed returned are shown.
    private func pilotageDetail661(_ c: PortConditions661) -> String {
        var parts: [String] = []
        if let v = c.visibility { parts.append(String(format: "vis %.1f nm", v)) }
        if let m = c.visibilityMinimumNm { parts.append(String(format: "min %.1f nm", m)) }
        if let w = c.waveSignificantHeight { parts.append(String(format: "swell %.1f m", w)) }
        if let g = c.windGust ?? c.forecastGustKt { parts.append(String(format: "gust %.0f kt", g)) }
        return parts.isEmpty ? "Awaiting channel telemetry" : parts.joined(separator: " · ")
    }

    private struct BerthingSafety661 { let badge: String; let tint: Color }

    /// Map the server berthingSafety enum onto the schedule's tint grammar.
    /// Unknown / nil ⇒ the warning treatment (a pilotage hold is never benign).
    private func berthingSafety661(_ raw: String?) -> BerthingSafety661 {
        switch (raw ?? "").lowercased() {
        case "unsafe", "restricted", "closed":
            return BerthingSafety661(badge: "BERTHING UNSAFE", tint: Brand.danger)
        case "caution", "marginal":
            return BerthingSafety661(badge: "BERTHING CAUTION", tint: Brand.warning)
        case "safe", "open", "clear":
            return BerthingSafety661(badge: "BERTHING SAFE", tint: Brand.warning)
        default:
            return BerthingSafety661(badge: "BERTHING HOLD", tint: Brand.warning)
        }
    }

    // MARK: ESANG · ROTATION (renders only when a REAL advisory exists — hidden today)
    private var esangCard: some View {
        HStack(alignment: .top, spacing: 0) {
            orbMini.padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · ROTATION").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(vm.esangLine ?? "—").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
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
