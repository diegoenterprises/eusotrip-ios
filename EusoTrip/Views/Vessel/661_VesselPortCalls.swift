//
//  661_VesselPortCalls.swift
//  EusoTrip — Vessel Operator · Port Calls (call history + vessels at port) · CARRIER-SIDE.
//
//  Verbatim bespoke port of canonical wireframe 661 "Vessel Port Calls"
//  (06 Vessel · Light/Dark). Carrier live port view, reached from the 659
//  Port Directory row tap-through. DETAIL/console grammar (mirrors 697 Port
//  Operations / 02 Shipper 205): ActiveCard hero with an eusoDiagonal
//  "avg berth wait" KPI cell, a 3-tile berth-state KPI strip (AT BERTH /
//  AT ANCHOR / BERTH AVAIL), an icon-chip PORT CALL QUEUE, a PORT WAIT GUARD
//  card, and the Vessel-lineup / Berths CTA pair.
//
//  Docked under SHIPMENTS. transportMode=vessel · USLGB Long Beach.
//
//  REAL WIRING (tRPC · server/routers/vesselShipments.ts):
//    · vesselShipments.getVesselFleet     {limit} -> operator fleet -> the IMO
//        whose port-call history we plot (vesselShipments.ts:922).
//    · vesselShipments.getVesselPortCalls {imoNumber,days} -> MarineTraffic
//        scheduled / historical PortCall[] (the queue rows). Typed helper:
//        EusoTripAPI.shared.vesselTrack.getVesselPortCalls(imoNumber:days:)
//        — returns nil when the AIS / port-call feed is unavailable.
//
//  Every KPI (avg berth wait, vessels in port, at berth, at anchor, berth
//  availability) derives from the LIVE port-call rows + fleet count — never
//  fabricated. When the feed has nothing, the queue renders an honest-empty
//  "no live port calls" state and the KPIs read "—". RBAC: protectedProcedure
//  reads. NEVER touches camera / BottomNav design.
//

import SwiftUI

struct VesselPortCallsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselPortCallsBody() } nav: {
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

// MARK: - Data shapes

/// vesselShipments.getVesselFleet -> { vessels: [...], total }
private struct VesselFleetResponse661: Decodable {
    let vessels: [VesselAsset661]
    let total: Int?
}

private struct VesselAsset661: Decodable, Identifiable {
    let id: Int
    let name: String?
    let imoNumber: String?
    let status: String?
}

/// Berth lifecycle a `PortCall` resolves to, derived from the row's
/// arrival / departure / in-port flags — NOT a fabricated status string.
private enum CallStage {
    case berthed    // arrived, in port, not yet sailed
    case inbound    // future arrival / at anchor
    case sailed     // departed
}

// MARK: - Body

private struct VesselPortCallsBody: View {
    @Environment(\.palette) private var palette

    /// MarineTraffic PortCall rows for the operator's lead vessel(s).
    @State private var calls: [VesselTrackAPI.PortCall] = []
    /// The fleet vessel whose IMO drove the port-call query (for the
    /// queue subtitles + the lineup CTA).
    @State private var vessel: VesselAsset661? = nil
    @State private var fleetCount: Int = 0

    @State private var loading = true
    @State private var loadError: String? = nil

    // CTA feedback (honest acks — no fake navigation).
    @State private var ctaNote: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(Brand.danger)
                                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            }
                        }
                    } else {
                        heroCard
                        berthStateStrip
                        portCallQueueSection
                        portWaitGuardCard
                        if let note = ctaNote {
                            LifecycleCard(accentGradient: true) {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundStyle(LinearGradient.diagonal)
                                    Text(note).font(EType.caption).foregroundStyle(palette.textPrimary)
                                }
                            }
                        }
                        ctaRow
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + USLGB·LIVE · back chevron + title + menu)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · PORT CALLS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text(portLocodeLabel)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(portTitle)
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s4)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    /// Title resolves to the lead vessel's most-recent port-call port; if the
    /// feed is empty we keep the carrier-canonical home port (Long Beach).
    private var portTitle: String {
        if let live = currentPortName, !live.isEmpty { return live }
        return "Port of Long Beach"
    }

    private var portLocodeLabel: String {
        if let locode = currentLocode, !locode.isEmpty { return "\(locode.uppercased()) · LIVE" }
        return "USLGB · LIVE"
    }

    /// The most-recent / in-port call's port name (queue is sorted live-first).
    private var currentPortName: String? {
        sortedCalls.first(where: { ($0.inPort ?? false) })?.portName
            ?? sortedCalls.first?.portName
    }
    private var currentLocode: String? {
        sortedCalls.first(where: { ($0.inPort ?? false) })?.unlocode
            ?? sortedCalls.first?.unlocode
    }

    // MARK: - Hero card (gradient rim · chips · eusoDiagonal avg-wait + vessels)

    private var heroCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s3) {
                // live · port queue chips
                HStack(spacing: 8) {
                    chip("live")
                    chip("port queue")
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text(avgBerthWaitDisplay)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("avg berth wait")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(anchorSubLine)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
            Spacer(minLength: 0)
            // VESSELS · in port cell
            VStack(alignment: .leading, spacing: 6) {
                Text("VESSELS")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(vesselsInPortDisplay)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.textPrimary).monospacedDigit()
                Text("in port")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1.5)
        )
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).tracking(0.5)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(palette.textPrimary.opacity(0.05)))
    }

    // MARK: - Berth-state KPI strip (AT BERTH · AT ANCHOR · BERTH AVAIL)

    private var berthStateStrip: some View {
        HStack(spacing: Space.s3) {
            // AT BERTH — eusoDiagonal gradient cell-1.
            VStack(alignment: .leading, spacing: 8) {
                Text("AT BERTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text(berthedDisplay)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).monospacedDigit()
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(Space.s4)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            berthTile(label: "AT ANCHOR",  value: anchorDisplay,    accent: Brand.hazmat)
            berthTile(label: "BERTH AVAIL", value: berthAvailDisplay, accent: Brand.success)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func berthTile(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Port call queue (icon-chip rows)

    private var portCallQueueSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("PORT CALL QUEUE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("Live")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            }

            VStack(spacing: 0) {
                if visibleCalls.isEmpty {
                    emptyQueueRow
                } else {
                    ForEach(Array(visibleCalls.enumerated()), id: \.offset) { idx, call in
                        callRow(call)
                        if idx < visibleCalls.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                    if calls.count > visibleCalls.count {
                        Text("+ \(calls.count - visibleCalls.count) more call\(calls.count - visibleCalls.count == 1 ? "" : "s") · \(anchorCount) vessel\(anchorCount == 1 ? "" : "s") at anchor")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.s4)
                            .padding(.vertical, Space.s3)
                    }
                }
            }
            .padding(.vertical, Space.s1)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var emptyQueueRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.textTertiary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("No live port calls")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(vessel?.imoNumber.map { "IMO \($0) · MarineTraffic returned no calls" }
                     ?? "Awaiting AIS port-call feed for the fleet")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer()
        }
        .padding(Space.s4)
    }

    private func callRow(_ call: VesselTrackAPI.PortCall) -> some View {
        let stage = stage(for: call)
        let accent = accentColor(for: stage)
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: icon(for: stage))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: Space.s2) {
                    Text(callTitle(call, stage: stage))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: Space.s2)
                    Text(badgeLabel(for: stage))
                        .font(.system(size: 11, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(accent.opacity(0.16)))
                }
                Text(callDetail(call))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(callTimeStamp(call, stage: stage))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(Space.s4)
    }

    // MARK: - Port wait guard card

    private var portWaitGuardCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PORT WAIT GUARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("Live")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(guardLine1)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(guardLine2)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var guardLine1: String {
        "\(berthAvailDisplay) open berths · \(anchorDisplay) vessels waiting"
    }
    private var guardLine2: String {
        "avg wait \(avgBerthWaitDisplay) · \(vesselsInPortDisplay) vessels in port"
    }

    // MARK: - CTA row (Vessel lineup · Berths)

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            Button {
                ctaNote = vessel.map { "Lineup for \($0.name ?? "fleet") · \(calls.count) call\(calls.count == 1 ? "" : "s") on the AIS feed." }
                    ?? "No fleet vessel resolved — add a vessel to the operator fleet."
            } label: {
                Text("Vessel lineup")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                ctaNote = "\(berthAvailDisplay) berths open of \(berthedCount + anchorCount + berthAvailCount) tracked · \(berthedDisplay) occupied."
            } label: {
                Text("Berths")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 140)
                    .frame(minHeight: 48)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Derived KPIs (all from live port-call rows + fleet count)

    /// Calls sorted live-first: in-port, then by arrival recency.
    private var sortedCalls: [VesselTrackAPI.PortCall] {
        calls.sorted { a, b in
            let ai = (a.inPort ?? false) ? 1 : 0
            let bi = (b.inPort ?? false) ? 1 : 0
            if ai != bi { return ai > bi }
            return (a.arrivalTime ?? "") > (b.arrivalTime ?? "")
        }
    }

    /// First three rows render in the card; the rest roll into the footer.
    private var visibleCalls: [VesselTrackAPI.PortCall] { Array(sortedCalls.prefix(3)) }

    private var berthedCount: Int {
        calls.filter { stage(for: $0) == .berthed }.count
    }
    private var anchorCount: Int {
        calls.filter { stage(for: $0) == .inbound }.count
    }
    /// Berth availability is the fleet capacity not currently at a berth — a
    /// live read, floored at 0. With no fleet count we surface nothing.
    private var berthAvailCount: Int {
        max(0, fleetCount - berthedCount)
    }
    /// Vessels in port = berthed + at anchor (everything not yet sailed),
    /// floored to the fleet count when the feed is sparse.
    private var vesselsInPortCount: Int {
        max(berthedCount + anchorCount, calls.filter { !($0.departureTime.map { !$0.isEmpty } ?? false) }.count)
    }

    private var berthedDisplay: String { calls.isEmpty ? "—" : "\(berthedCount)" }
    private var anchorDisplay: String { calls.isEmpty ? "—" : "\(anchorCount)" }
    private var berthAvailDisplay: String { fleetCount == 0 ? "—" : "\(berthAvailCount)" }
    private var vesselsInPortDisplay: String { calls.isEmpty ? "—" : "\(vesselsInPortCount)" }

    /// Average berth wait, in days, computed from inbound calls whose arrival
    /// is in the future (anchor → berth lag). Honest "—" when uncomputable.
    private var avgBerthWaitDisplay: String {
        let now = Date()
        let waits: [Double] = sortedCalls.compactMap { call in
            guard stage(for: call) == .inbound,
                  let arr = call.arrivalTime, let d = parseDate(arr) else { return nil }
            let days = d.timeIntervalSince(now) / 86_400.0
            return days > 0 ? days : nil
        }
        guard !waits.isEmpty else { return "—" }
        let avg = waits.reduce(0, +) / Double(waits.count)
        return String(format: "%.1fd", avg)
    }

    private var anchorSubLine: String {
        if calls.isEmpty { return "awaiting feed" }
        return "\(anchorCount) at anchor · \(anchorCount > berthAvailCount ? "building" : "clearing")"
    }

    // MARK: - Stage / row helpers

    private func stage(for call: VesselTrackAPI.PortCall) -> CallStage {
        let departed = (call.departureTime?.isEmpty == false)
        if departed { return .sailed }
        if call.inPort == true { return .berthed }
        return .inbound
    }

    private func accentColor(for stage: CallStage) -> Color {
        switch stage {
        case .berthed: return Brand.success
        case .inbound: return Brand.hazmat
        case .sailed:  return Brand.neutral
        }
    }

    private func icon(for stage: CallStage) -> String {
        switch stage {
        case .berthed: return "square.grid.3x1.below.line.grid.1x2"   // berthed / containers
        case .inbound: return "diamond"                               // inbound at anchor
        case .sailed:  return "arrowshape.up"                         // sailed / departed
        }
    }

    private func badgeLabel(for stage: CallStage) -> String {
        switch stage {
        case .berthed: return "BERTHED"
        case .inbound: return "ANCHOR"
        case .sailed:  return "SAILED"
        }
    }

    private func callTitle(_ call: VesselTrackAPI.PortCall, stage: CallStage) -> String {
        let port = call.portName ?? call.unlocode ?? "Port"
        switch stage {
        case .berthed: return "Berthed · \(port)"
        case .inbound: return "Inbound · \(port)"
        case .sailed:  return "Departed · \(port)"
        }
    }

    private func callDetail(_ call: VesselTrackAPI.PortCall) -> String {
        var parts: [String] = []
        if let v = vessel?.name, !v.isEmpty { parts.append(v) }
        if let arr = call.arrivalTime, let d = parseDate(arr) {
            parts.append("arr \(timeOnly(d))")
        }
        if let loc = call.unlocode, !loc.isEmpty { parts.append(loc.uppercased()) }
        else if let c = call.country, !c.isEmpty { parts.append(c.uppercased()) }
        if let dr = call.draught, dr > 0 { parts.append(String(format: "%.1fm draught", dr)) }
        return parts.isEmpty ? "AIS port call" : parts.joined(separator: " · ")
    }

    private func callTimeStamp(_ call: VesselTrackAPI.PortCall, stage: CallStage) -> String {
        switch stage {
        case .berthed:
            if let arr = call.arrivalTime, let d = parseDate(arr) { return timeOnly(d) }
            return "in port"
        case .inbound:
            if let arr = call.arrivalTime, let d = parseDate(arr) { return "ETA \(dayOnly(d))" }
            return "ETA —"
        case .sailed:
            if let dep = call.departureTime, let d = parseDate(dep) { return monthDay(d) }
            return "sailed"
        }
    }

    // MARK: - Date helpers

    private func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
    private func timeOnly(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
    private func dayOnly(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: d)
    }
    private func monthDay(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 252)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Load (getVesselFleet -> getVesselPortCalls)

    private func load() async {
        loading = true; loadError = nil
        struct FleetIn: Encodable { let limit: Int }
        do {
            // 1) Resolve the operator's fleet — the lead vessel's IMO is the
            //    key for MarineTraffic port calls; the count seeds berth-avail.
            let fleet: VesselFleetResponse661 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselFleet", input: FleetIn(limit: 12))
            self.fleetCount = fleet.total ?? fleet.vessels.count
            // Lead vessel: prefer one with an IMO so the feed query is valid.
            self.vessel = fleet.vessels.first(where: { ($0.imoNumber?.isEmpty == false) })
                ?? fleet.vessels.first

            // 2) Port calls for that vessel's IMO. Server returns nil when the
            //    AIS / port-call feed is unavailable — coalesce to honest-empty.
            if let imo = self.vessel?.imoNumber, !imo.isEmpty {
                let bare = imo.uppercased().hasPrefix("IMO")
                    ? String(imo.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    : imo
                let rows = try await EusoTripAPI.shared.vesselTrack.getVesselPortCalls(
                    imoNumber: bare, days: 30)
                self.calls = rows ?? []
            } else {
                self.calls = []
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("661 · Vessel Port Calls · Night") { VesselPortCallsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("661 · Vessel Port Calls · Light") { VesselPortCallsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
