//
//  ES01_ConvoyComms.swift
//  EusoTrip — Escort · Convoy Comms (brick 603 · ES-01).
//
//  PTT-first MAP+BOARD hybrid for the active oversize move, built
//  verbatim from the ES-01 design-authority SVG pair
//  ("07 Escort/{Dark,Light}-SVG/ES-01 Convoy Comms.svg") and the
//  ES1_convoy_comms.md spec. One-thumb convoy control surface:
//  live role pins over the corridor, spacing overlay, the convoy
//  roster, the real safety-event feed, hazard quick-buttons, text
//  fallback, and the hold-to-talk bar.
//
//  Wiring truth (code-traced this firing):
//    REAL  escorts.getActiveConvoys   → the escort's live convoy
//          (id, load number, lane, spacing, speed cap, status).
//    REAL  convoy.getConvoy           → lead / haul / rear roster
//          (names + user ids), target + current spacing, speed cap.
//    REAL  convoy.getConvoyPositions  → live lat/lng per member,
//          freshness timestamps, computed lead/rear gaps.
//    REAL  convoy.getConvoyAlerts     → separation breaches, speed
//          violations, stale-GPS events (the system feed).
//    ABSENT (named gaps — see backendGaps in the firing report):
//          convoyComms.getChannel / getHistory / getMembers /
//          sendText / sendHazard / commitAudio / updateLocation /
//          subscribe + convoy_messages + convoy_members tables.
//          The hazard grid, text fallback, and hold-to-talk bar
//          therefore resolve to an HONEST "channel not connected"
//          notice — they never fake a send.
//
//  RBAC: registered role .escort only; every proc above resolves
//  the caller's own convoy membership server-side.
//
//  Pixel doctrine: palette tokens only, gradient-only accent,
//  tokenized spacing/radius/type, Dark + Light previews.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire projections (screen-local, private)

/// One row off `escorts.getActiveConvoys` — the escort's own live
/// convoy joined to its load. Spacing columns are integers (meters).
private struct EscortLiveConvoy: Decodable, Identifiable {
    let id: String
    let status: String?
    let maxSpeed: Int?
    let leadDistance: Int?
    let rearDistance: Int?
    let startedAt: String?
    let loadNumber: String?
    let loadStatus: String?
    let cargoType: String?
    let origin: String?
    let destination: String?
}

private struct EscortConvoySearchInput: Encodable { let search: String? }
private struct ConvoyIdInput: Encodable { let convoyId: Int }

// ES-01 comms send inputs (convoy.sendHazard / convoy.sendText / convoy.commitAudio).
private struct ConvoyHazardInput: Encodable { let convoyId: Int; let callout: String }
private struct ConvoyTextInput: Encodable { let convoyId: Int; let text: String }
private struct ConvoyAudioInput: Encodable { let convoyId: Int; let audioUrl: String; let durationS: Int }
private struct ConvoySendResult: Decodable { let success: Bool?; let id: Int? }

/// Roster member ref off `convoy.getConvoy`.
private struct ConvoyMemberRef: Decodable {
    let userId: Int?
    let name: String?
}

/// Envelope off `convoy.getConvoy` — roster + spacing targets.
private struct ConvoyDetailEnvelope: Decodable {
    let id: Int?
    let loadId: Int?
    let status: String?
    let lead: ConvoyMemberRef?
    let loadVehicle: ConvoyMemberRef?
    let rear: ConvoyMemberRef?
    let targetLeadDistance: Int?
    let targetRearDistance: Int?
    let currentLeadDistance: Int?
    let currentRearDistance: Int?
    let maxSpeedMph: Int?
    let startedAt: String?
}

/// One live position off `convoy.getConvoyPositions`.
private struct ConvoyPositionRow: Decodable, Identifiable {
    var id: String { "\(userId)-\(role)" }
    let userId: Int
    let role: String        // "lead" | "load" | "rear"
    let lat: Double
    let lng: Double
    let speed: Double?
    let heading: Double?
    let timestamp: String?
}

private struct ConvoyPositionsEnvelope: Decodable {
    let convoyId: Int?
    let positions: [ConvoyPositionRow]
    let leadDistance: Double?
    let rearDistance: Double?
    let status: String?
}

/// One system event off `convoy.getConvoyAlerts` — separation /
/// speed / signal. This is the REAL feed on this surface today.
private struct ConvoyAlertRow: Decodable, Identifiable {
    let id: String
    let type: String
    let severity: String
    let message: String
    let timestamp: String?
}

// MARK: - Screen body

struct EscortConvoyComms: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    /// Load phase for the convoy resolve (first fetch).
    private enum Phase {
        case loading
        case noConvoy
        case loaded
        case failed
    }

    @State private var phase: Phase = .loading
    @State private var convoy: EscortLiveConvoy? = nil
    @State private var detail: ConvoyDetailEnvelope? = nil
    @State private var positions: ConvoyPositionsEnvelope? = nil
    @State private var alerts: [ConvoyAlertRow] = []

    /// True after any broadcast affordance (hazard button, text
    /// fallback, hold-to-talk) is tapped while no channel spine is
    /// attached to the move. Shows the honest notice card — never a
    /// fake send.
    @State private var showChannelNotice: Bool = false
    /// Resolved once the active convoy loads — enables real broadcast on
    /// the hazard grid, text composer, and hold-to-talk bar.
    @State private var activeConvoyId: Int? = nil
    @State private var showComposer: Bool = false
    @State private var composedText: String = ""
    @State private var sendConfirmation: String? = nil

    private let hazardRows: [[HazardCallout]] = [
        [.oncoming, .clear, .comeAhead, .hold],
        [.behindYou, .lowClearance, .crossing, .policeHandoff],
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrowRow
                titleRow
                statusRow
                hairline
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .eusoRefreshable { await refreshAll() }
        .sheet(isPresented: $showComposer) { composerSheet }
        .overlay(alignment: .bottom) {
            if let msg = sendConfirmation {
                Text(msg)
                    .font(EType.caption).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Brand.success.opacity(0.92)))
                    .padding(.bottom, 108)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        await MainActor.run { withAnimation(.easeOut(duration: 0.2)) { sendConfirmation = nil } }
                    }
            }
        }
    }

    private var composerSheet: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Message the convoy")
                .font(EType.h2).foregroundStyle(palette.textPrimary)
            TextField("Type a callout…", text: $composedText, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .padding(Space.s3)
                .background(palette.bgCardSoft)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            CTAButton(title: "Send to convoy", action: {
                showComposer = false
                Task { await sendComposedText() }
            })
            .disabled(composedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer()
        }
        .padding(20)
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
        .background(palette.bgPage)
    }

    // MARK: - Header

    private var eyebrowRow: some View {
        HStack {
            EusoTripEyebrow(verbatim: "ESCORT · CONVOY COMMS")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text(companyCaps)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var companyCaps: String {
        if let cid = session.user?.companyId, !cid.isEmpty {
            return "COMPANY · \(cid)".uppercased()
        }
        return "ESCORT NETWORK"
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text("Convoy Comms")
                .font(.system(size: 28, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if let move = convoy?.loadNumber, !move.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(AnyShapeStyle(Brand.blue))
                        .frame(width: 6, height: 6)
                    Text(move)
                        .font(EType.mono(.caption)).tracking(0.6)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(palette.bgCardSoft)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: Space.s3) {
            if !myRoleLabel.isEmpty {
                Text(myRoleLabel)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.blue)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Brand.blue.opacity(0.14))
                    .clipShape(Capsule())
            }
            Text(statusLabel)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            if let online = onlineCount {
                HStack(spacing: 5) {
                    Circle()
                        .fill(AnyShapeStyle(Brand.success))
                        .frame(width: 6, height: 6)
                    Text("\(online) unit\(online == 1 ? "" : "s") reporting")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            Spacer(minLength: 0)
            Text(operatorCaps)
                .font(EType.mono(.micro)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    /// LEAD / CHASE / HAUL — resolved by matching the signed-in user
    /// id against the convoy roster. Empty until the roster resolves.
    private var myRoleLabel: String {
        guard let d = detail, let uid = sessionUserIdInt else { return "" }
        if d.lead?.userId == uid { return "LEAD" }
        if d.rear?.userId == uid { return "CHASE" }
        if d.loadVehicle?.userId == uid { return "HAUL" }
        return ""
    }

    private var sessionUserIdInt: Int? {
        guard let raw = session.user?.id else { return nil }
        return Int(String(describing: raw))
    }

    private var statusLabel: String {
        let s = (detail?.status ?? convoy?.status ?? "").lowercased()
        guard !s.isEmpty else { return "-" }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// Members with a GPS report inside the last 2 minutes — the
    /// honest "reporting" count (never a fabricated member total).
    private var onlineCount: Int? {
        guard let rows = positions?.positions, !rows.isEmpty else { return nil }
        return rows.filter { gpsAgeSeconds($0.timestamp).map { $0 < 120 } ?? false }.count
    }

    private var operatorCaps: String {
        let name = session.user?.name ?? ""
        guard !name.isEmpty else { return "" }
        let initials = name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }.joined().uppercased()
        return "\(name) · \(initials)"
    }

    private var hairline: some View {
        Rectangle()
            .fill(palette.iridescentHairline)
            .frame(height: 1)
            .padding(.horizontal, -14)
    }

    // MARK: - Content state machine

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingCard
        case .noConvoy:
            EusoEmptyState(
                systemImage: "dot.radiowaves.left.and.right",
                title: "No live convoy",
                subtitle: "This surface lights up the moment a convoy forms on one of your escort assignments. Pull to refresh once your move rolls."
            )
        case .failed:
            errorCard
        case .loaded:
            mapCard
            spacingStrip
            rosterCard
            eventsCard
            hazardSection
            if showChannelNotice { channelNoticeCard }
            textFallbackBar
            pttBar
        }
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionHeader("RESOLVING CONVOY", icon: "arrow.clockwise")
            Text("Pulling your live convoy, roster, and positions…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD THE CONVOY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text("EusoTrip couldn't reach your convoy record. Check your connection and retry — your assignment and corridor screens still work from the tabs below.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { Task { await refreshAll() } }) {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Map rail (live role pins)

    @ViewBuilder
    private var mapCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                sectionHeader("LIVE CONVOY MAP", icon: "map.fill")
                Spacer(minLength: 0)
                if let age = freshestGpsAge {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(AnyShapeStyle(age < 120 ? Brand.success : Brand.warning))
                            .frame(width: 6, height: 6)
                        Text("GPS \(gpsAgeLabel(age))")
                            .font(EType.mono(.micro)).tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            if let rows = positions?.positions, !rows.isEmpty {
                HereVectorMapView(
                    center: mapCenter(rows),
                    zoom: 12,
                    interactive: false,
                    layers: [.markers(markers(rows))]
                )
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
                .allowsHitTesting(false)
            } else {
                mapAwaiting
            }
            if let lane = laneLabel {
                Text(lane)
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var mapAwaiting: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Awaiting convoy GPS")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Role pins draw the moment convoy members report a position fix.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(Space.s3)
        .background(palette.tintNeutral.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var laneLabel: String? {
        guard let c = convoy else { return nil }
        let o = c.origin ?? ""
        let d = c.destination ?? ""
        guard !o.isEmpty || !d.isEmpty else { return nil }
        return "CORRIDOR · \(o) → \(d)".uppercased()
    }

    private func mapCenter(_ rows: [ConvoyPositionRow]) -> HereLatLng {
        let lat = rows.map(\.lat).reduce(0, +) / Double(rows.count)
        let lng = rows.map(\.lng).reduce(0, +) / Double(rows.count)
        return HereLatLng(lat, lng)
    }

    private func markers(_ rows: [ConvoyPositionRow]) -> [HereMarker] {
        rows.map { row in
            HereMarker(
                at: HereLatLng(row.lat, row.lng),
                kind: .truck,
                label: roleAbbrev(row.role)
            )
        }
    }

    private func roleAbbrev(_ role: String) -> String {
        switch role.lowercased() {
        case "lead": return "L"
        case "load": return "T"
        case "rear": return "C"
        default:     return role.prefix(1).uppercased()
        }
    }

    // MARK: - Spacing overlay strip

    private var spacingStrip: some View {
        HStack(spacing: Space.s2) {
            spacingTile(label: "LEAD GAP", value: metersLabel(liveLeadGap), target: detail?.targetLeadDistance)
            spacingTile(label: "REAR GAP", value: metersLabel(liveRearGap), target: detail?.targetRearDistance)
            spacingTile(label: "SPD CAP", value: detail?.maxSpeedMph.map { "\($0)" } ?? "-", target: nil)
        }
    }

    private var liveLeadGap: Double? {
        if let v = positions?.leadDistance { return v }
        if let v = detail?.currentLeadDistance { return Double(v) }
        if let v = convoy?.leadDistance { return Double(v) }
        return nil
    }

    private var liveRearGap: Double? {
        if let v = positions?.rearDistance { return v }
        if let v = detail?.currentRearDistance { return Double(v) }
        if let v = convoy?.rearDistance { return Double(v) }
        return nil
    }

    private func spacingTile(label: String, value: String, target: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let t = target {
                Text("target \(t) m")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            } else {
                Text("mph limit")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.lg)
    }

    private func metersLabel(_ v: Double?) -> String {
        guard let v, v > 0 else { return "-" }
        return "\(Int(v.rounded())) m"
    }

    // MARK: - Roster (convoy channel)

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                sectionHeader("CONVOY ROSTER", icon: "person.3.fill")
                Spacer(minLength: 0)
                Text("\(rosterRows.count) UNIT\(rosterRows.count == 1 ? "" : "S")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 6) {
                ForEach(rosterRows, id: \.roleLabel) { row in
                    rosterRow(row)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private struct RosterRow {
        let roleLabel: String
        let color: Color
        let name: String
        let isYou: Bool
        let gpsAge: TimeInterval?
    }

    private var rosterRows: [RosterRow] {
        guard let d = detail else { return [] }
        var rows: [RosterRow] = []
        let uid = sessionUserIdInt
        if let lead = d.lead {
            rows.append(RosterRow(
                roleLabel: "LEAD", color: Brand.blue,
                name: lead.name ?? "Lead escort",
                isYou: lead.userId != nil && lead.userId == uid,
                gpsAge: gpsAge(for: "lead")))
        }
        if let haul = d.loadVehicle {
            rows.append(RosterRow(
                roleLabel: "HAUL", color: Brand.success,
                name: haul.name ?? "Haul driver",
                isYou: haul.userId != nil && haul.userId == uid,
                gpsAge: gpsAge(for: "load")))
        }
        if let rear = d.rear {
            rows.append(RosterRow(
                roleLabel: "CHASE", color: Brand.escort,
                name: rear.name ?? "Chase escort",
                isYou: rear.userId != nil && rear.userId == uid,
                gpsAge: gpsAge(for: "rear")))
        }
        return rows
    }

    private func rosterRow(_ row: RosterRow) -> some View {
        HStack(spacing: Space.s3) {
            Circle()
                .fill(AnyShapeStyle(row.color))
                .frame(width: 8, height: 8)
            Text(row.roleLabel)
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textPrimary)
                .frame(width: 44, alignment: .leading)
            Text(row.isYou ? "You" : row.name)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let age = row.gpsAge {
                Text(age < 60 ? "live" : gpsAgeLabel(age))
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(age < 60 ? Brand.success : palette.textTertiary)
            } else {
                Text("no fix")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, Space.s3)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func gpsAge(for role: String) -> TimeInterval? {
        guard let row = positions?.positions.first(where: { $0.role.lowercased() == role }) else { return nil }
        return gpsAgeSeconds(row.timestamp)
    }

    private var freshestGpsAge: TimeInterval? {
        positions?.positions.compactMap { gpsAgeSeconds($0.timestamp) }.min()
    }

    private func gpsAgeSeconds(_ iso: String?) -> TimeInterval? {
        guard let iso, !iso.isEmpty else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = fmt.date(from: iso)
        if date == nil {
            fmt.formatOptions = [.withInternetDateTime]
            date = fmt.date(from: iso)
        }
        guard let d = date else { return nil }
        return max(0, Date().timeIntervalSince(d))
    }

    private func gpsAgeLabel(_ age: TimeInterval) -> String {
        if age < 60 { return "\(Int(age))s" }
        if age < 3600 { return "\(Int(age / 60))m" }
        return "\(Int(age / 3600))h"
    }

    // MARK: - Events feed (real system events)

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                sectionHeader("CONVOY EVENTS", icon: "waveform.path.ecg")
                Spacer(minLength: 0)
                if !alerts.isEmpty {
                    Text("\(alerts.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if alerts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Brand.success)
                    Text("All quiet — no separation, speed, or signal events on this move.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(alerts) { alertEventRow($0) }
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func alertEventRow(_ row: ConvoyAlertRow) -> some View {
        let tint: Color = {
            switch row.severity.lowercased() {
            case "critical": return Brand.danger
            case "warning":  return Brand.warning
            default:         return palette.textTertiary
            }
        }()
        return HStack(alignment: .top, spacing: Space.s3) {
            Circle()
                .fill(AnyShapeStyle(tint))
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.type.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6).padding(.horizontal, Space.s3)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: - Hazard quick-buttons

    /// The eight standard oversize-corridor radio callouts. HOLD and
    /// LOW CLEARANCE carry the danger register (safety-critical stop
    /// calls); everything else rides the neutral card surface.
    private enum HazardCallout: String, CaseIterable {
        case oncoming = "ONCOMING"
        case clear = "CLEAR"
        case comeAhead = "COME AHEAD"
        case hold = "HOLD"
        case behindYou = "BEHIND YOU"
        case lowClearance = "LOW CLEARANCE"
        case crossing = "CROSSING"
        case policeHandoff = "POLICE HANDOFF"

        var isDanger: Bool { self == .hold || self == .lowClearance }
        var isGo: Bool { self == .clear }
    }

    private var hazardSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                sectionHeader("HAZARD CALLOUT", icon: "bolt.fill")
                Spacer(minLength: 0)
                Text(activeConvoyId != nil ? "CHANNEL LIVE" : "CHANNEL NOT CONNECTED")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(activeConvoyId != nil ? Brand.success : palette.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(activeConvoyId != nil ? Brand.success.opacity(0.5) : palette.borderSoft, lineWidth: 1))
            }
            ForEach(0..<hazardRows.count, id: \.self) { i in
                HStack(spacing: Space.s2) {
                    ForEach(hazardRows[i], id: \.rawValue) { callout in
                        hazardButton(callout)
                    }
                }
            }
        }
    }

    private func hazardButton(_ callout: HazardCallout) -> some View {
        Button {
            if activeConvoyId != nil {
                Task { await sendHazard(callout) }
            } else {
                // No convoy is attached to this move — honest notice, no fake send.
                withAnimation(.easeOut(duration: 0.12)) { showChannelNotice = true }
            }
        } label: {
            Text(callout.rawValue)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(hazardForeground(callout))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(hazardBackground(callout))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(hazardBorder(callout), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func hazardForeground(_ c: HazardCallout) -> Color {
        if c.isDanger { return .white }
        if c.isGo { return Brand.success }
        return palette.textPrimary
    }

    private func hazardBackground(_ c: HazardCallout) -> AnyShapeStyle {
        if c.isDanger { return AnyShapeStyle(Brand.danger) }
        if c.isGo { return AnyShapeStyle(palette.tintSuccess) }
        return AnyShapeStyle(palette.bgCard)
    }

    private func hazardBorder(_ c: HazardCallout) -> AnyShapeStyle {
        if c.isDanger { return AnyShapeStyle(Brand.danger.opacity(0.5)) }
        if c.isGo { return AnyShapeStyle(Brand.success.opacity(0.5)) }
        return AnyShapeStyle(palette.borderFaint)
    }

    /// The honest broadcast-unavailable notice. No channel record is
    /// attached to this move, so nothing on this surface can reach
    /// the convoy — say so plainly and hand the operator the real
    /// fallback (CB + phone). Never a fake send, never a fake queue.
    private var channelNoticeCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Convoy broadcast isn't connected")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("No live voice or message channel is attached to this move, so callouts from this screen can't reach the convoy. Positions, spacing, and safety events above stay live. Call out on CB channel 17 and phone dispatch for anything urgent.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintWarning)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Text fallback + hold-to-talk

    private var textFallbackBar: some View {
        Button {
            if activeConvoyId != nil {
                showComposer = true
            } else {
                withAnimation(.easeOut(duration: 0.12)) { showChannelNotice = true }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text("Type a message to the convoy")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var pttBar: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { showChannelNotice = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                Text("HOLD TO TALK")
                    .font(.system(size: 14, weight: .heavy)).tracking(1.2)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared

    private func sectionHeader(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(text)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
        }
    }

    // MARK: - Data plumbing

    private func refreshAll() async {
        if convoy == nil { phase = .loading }
        do {
            let rows: [EscortLiveConvoy] = try await EusoTripAPI.shared.query(
                "escorts.getActiveConvoys",
                input: EscortConvoySearchInput(search: nil)
            )
            guard let first = rows.first else {
                convoy = nil; detail = nil; positions = nil; alerts = []
                phase = .noConvoy
                return
            }
            convoy = first
            if let convoyId = Int(first.id) {
                activeConvoyId = convoyId
                async let d: ConvoyDetailEnvelope? = fetchDetail(convoyId)
                async let p: ConvoyPositionsEnvelope? = fetchPositions(convoyId)
                async let a: [ConvoyAlertRow] = fetchAlerts(convoyId)
                detail = await d
                positions = await p
                alerts = await a
            }
            phase = .loaded
        } catch {
            if convoy == nil { phase = .failed }
        }
    }

    private func fetchDetail(_ convoyId: Int) async -> ConvoyDetailEnvelope? {
        try? await EusoTripAPI.shared.query(
            "convoy.getConvoy", input: ConvoyIdInput(convoyId: convoyId))
    }

    private func fetchPositions(_ convoyId: Int) async -> ConvoyPositionsEnvelope? {
        try? await EusoTripAPI.shared.query(
            "convoy.getConvoyPositions", input: ConvoyIdInput(convoyId: convoyId))
    }

    private func fetchAlerts(_ convoyId: Int) async -> [ConvoyAlertRow] {
        (try? await EusoTripAPI.shared.query(
            "convoy.getConvoyAlerts", input: ConvoyIdInput(convoyId: convoyId))) ?? []
    }

    // MARK: - Real broadcast (convoy comms spine)

    /// Fire a hazard callout to the convoy. Server enum uses underscores
    /// ("COME_AHEAD"); the on-screen label carries spaces.
    private func sendHazard(_ callout: HazardCallout) async {
        guard let cid = activeConvoyId else { showChannelNotice = true; return }
        let wire = callout.rawValue.replacingOccurrences(of: " ", with: "_")
        do {
            let _: ConvoySendResult = try await EusoTripAPI.shared.mutation(
                "convoy.sendHazard", input: ConvoyHazardInput(convoyId: cid, callout: wire))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.12)) { sendConfirmation = "\(callout.rawValue) sent to convoy" }
            }
            await fetchAlertsIntoState(cid)
        } catch {
            await MainActor.run { sendConfirmation = "Callout didn't send — check signal and retry" }
        }
    }

    private func sendComposedText() async {
        let text = composedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let cid = activeConvoyId else { return }
        do {
            let _: ConvoySendResult = try await EusoTripAPI.shared.mutation(
                "convoy.sendText", input: ConvoyTextInput(convoyId: cid, text: text))
            await MainActor.run { composedText = ""; sendConfirmation = "Message sent to convoy" }
        } catch {
            await MainActor.run { sendConfirmation = "Message didn't send — check signal and retry" }
        }
    }

    private func fetchAlertsIntoState(_ cid: Int) async {
        let a = await fetchAlerts(cid)
        await MainActor.run { alerts = a }
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct EscortConvoyCommsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortConvoyComms()
        } nav: {
            BottomNav(
                leading: escortNavLeading_603(),
                trailing: escortNavTrailing_603(),
                orbState: .idle
            )
        }
    }
}

private func escortNavLeading_603() -> [NavSlot] {
    EscortNavRoute.leading(current: .assignments)
}

private func escortNavTrailing_603() -> [NavSlot] {
    EscortNavRoute.trailing(current: .assignments)
}

// MARK: - Previews
//
// Previews don't run `.task`, so the surface stays in its loading
// register — both variants render without touching the network.

#Preview("603 · Escort · Convoy Comms · Dark") {
    EscortConvoyCommsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("603 · Escort · Convoy Comms · Light") {
    EscortConvoyCommsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
