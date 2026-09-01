//
//  584_RailCrewCallBoard.swift
//  EusoTrip — Rail 584 · Crew Call Board
//

import SwiftUI

// MARK: - Outer shell

struct RailCrewCallBoardScreen: View {
    let theme: Theme.Palette
    let yardId: String

    var body: some View {
        Shell(theme: theme) {
            RailCrewCallBoardBody(yardId: yardId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct CrewAvailability584: Decodable {
    let callableNow: Int?
    let calledCount: Int?
    let extraBoardDepth: Int?
    let avgTurnHours: Double?
    let boardStatus: String?
    let yardName: String?
    let yardRailroad: String?
    let tracked: Bool?
    let trackingState: HOSTrackingState?
    let source: String?
    let freshness: String?

    var hasCurrentEvidence: Bool {
        tracked == true
            && trackingState == .tracked
            && source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && HOSObservationClock.freshness(freshness).isCurrent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Server returns totalAvailable/totalOnDuty/railroad; iOS uses callableNow/calledCount/yardRailroad.
        self.callableNow = Self.decodeInt(c, .callableNow) ?? Self.decodeInt(c, .totalAvailable)
        self.calledCount = Self.decodeInt(c, .calledCount) ?? Self.decodeInt(c, .totalOnDuty)
        self.extraBoardDepth = Self.decodeInt(c, .extraBoardDepth)
        self.avgTurnHours = Self.decodeDouble(c, .avgTurnHours)
        self.boardStatus    = try c.decodeIfPresent(String.self, forKey: .boardStatus)
        self.yardName       = try c.decodeIfPresent(String.self, forKey: .yardName)
        self.yardRailroad   = try (c.decodeIfPresent(String.self, forKey: .yardRailroad) ?? c.decodeIfPresent(String.self, forKey: .railroad))
        self.tracked = try c.decodeIfPresent(Bool.self, forKey: .tracked)
        self.trackingState = try c.decodeIfPresent(HOSTrackingState.self, forKey: .trackingState)
        self.source = try (c.decodeIfPresent(String.self, forKey: .source)
            ?? c.decodeIfPresent(String.self, forKey: .provider))
        self.freshness = try (c.decodeIfPresent(String.self, forKey: .freshness)
            ?? c.decodeIfPresent(String.self, forKey: .asOf))
    }

    enum CodingKeys: String, CodingKey {
        case callableNow, calledCount, extraBoardDepth, avgTurnHours, boardStatus, yardName, yardRailroad
        case totalAvailable, totalOnDuty, railroad, tracked, trackingState, source, provider, freshness, asOf
    }

    private static func decodeInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(Double.self, forKey: key), value.isFinite {
            return Int(value)
        }
        if let raw = try? container.decode(String.self, forKey: key) { return Int(raw) }
        return nil
    }

    private static func decodeDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key), value.isFinite { return value }
        if let raw = try? container.decode(String.self, forKey: key),
           let value = Double(raw), value.isFinite { return value }
        return nil
    }
}

private struct CrewMember584: Decodable {
    let crewId: String?
    let craft: String?
    let boardPosition: String?
    let hoursOnDuty: Double?
    let hoursOfServiceCompliant: Bool?
    let status: String?
    let tracked: Bool?
    let trackingState: HOSTrackingState?
    let source: String?
    let freshness: String?

    var hasCurrentHOSEvidence: Bool {
        tracked == true
            && trackingState == .tracked
            && source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && HOSObservationClock.freshness(freshness).isCurrent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.crewId = Self.decodeIdentifier(c, .crewId)
            ?? Self.decodeIdentifier(c, .userId)
            ?? Self.decodeIdentifier(c, .id)
        self.craft = try c.decodeIfPresent(String.self, forKey: .role)
        self.boardPosition = try c.decodeIfPresent(String.self, forKey: .boardPosition)
        self.hoursOnDuty = Self.decodeDouble(c, .hoursOnDuty)
        self.hoursOfServiceCompliant = try c.decodeIfPresent(Bool.self, forKey: .hoursOfServiceCompliant)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        self.tracked = try c.decodeIfPresent(Bool.self, forKey: .tracked)
        self.trackingState = try c.decodeIfPresent(HOSTrackingState.self, forKey: .trackingState)
        self.source = try (c.decodeIfPresent(String.self, forKey: .source)
            ?? c.decodeIfPresent(String.self, forKey: .provider))
        self.freshness = try (c.decodeIfPresent(String.self, forKey: .freshness)
            ?? c.decodeIfPresent(String.self, forKey: .observedAt)
            ?? c.decodeIfPresent(String.self, forKey: .updatedAt))
    }

    enum CodingKeys: String, CodingKey {
        case id, crewId, userId, role, boardPosition, hoursOnDuty, hoursOfServiceCompliant, status
        case tracked, trackingState, source, provider, freshness, observedAt, updatedAt
    }

    private static func decodeIdentifier(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> String? {
        if let raw = try? container.decode(String.self, forKey: key), !raw.isEmpty { return raw }
        if let value = try? container.decode(Int.self, forKey: key) { return String(value) }
        return nil
    }

    private static func decodeDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key), value.isFinite { return value }
        if let raw = try? container.decode(String.self, forKey: key),
           let value = Double(raw), value.isFinite { return value }
        return nil
    }
}

private struct NextCall584: Decodable {
    let crewMemberId: String?
    let crewMemberName: String?
    let role: String?
    let currentStatus: String?
    let hoursOnDuty: Double?
    let hoursAvailable: Double?
    let restRequired: Double?
    let lastReportTime: String?
    let shiftStart: String?
    let maxAllowedHours: Double?
    let fraComplianceStatus: String?
    let consecutiveDaysWorked: Int?
    let tracked: Bool?
    let trackingState: HOSTrackingState?
    let source: String?
    let freshness: String?

    var hasCurrentEvidence: Bool {
        tracked == true
            && trackingState == .tracked
            && source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && HOSObservationClock.freshness(freshness ?? lastReportTime).isCurrent
    }
}

private struct YardIdIn584: Encodable { let yardId: String }

// MARK: - Body

private struct RailCrewCallBoardBody: View {
    @Environment(\.palette) private var palette
    let yardId: String

    @State private var availability: CrewAvailability584? = nil
    @State private var crew: [CrewMember584] = []
    @State private var nextCall: NextCall584? = nil
    @State private var isLoading = true
    @State private var boardLoadError: String? = nil
    @State private var crewLoadError: String? = nil
    @State private var hosLoadError: String? = nil

    // MARK: Derived

    private var yardLabel: String { availability?.yardName?.uppercased() ?? yardId.uppercased() }
    private var currentBoard: CrewAvailability584? {
        availability?.hasCurrentEvidence == true ? availability : nil
    }
    private var callableNow: Int? { currentBoard?.callableNow }
    private var calledCount: Int? { currentBoard?.calledCount }
    private var boardSize: Int? { currentBoard?.extraBoardDepth }
    private var callableNowLabel: String { callableNow.map(String.init) ?? "—" }
    private var calledCountLabel: String { calledCount.map(String.init) ?? "—" }
    private var boardSizeLabel: String { boardSize.map(String.init) ?? "—" }
    private var avgTurnLabel: String   {
        guard let t = currentBoard?.avgTurnHours else { return "—" }
        return String(format: "%.1fh", t)
    }
    private var boardStatusLabel: String {
        guard let status = currentBoard?.boardStatus?.lowercased() else { return "BOARD UNVERIFIED" }
        switch status {
        case "open":       return "BOARD OPEN"
        case "closed":     return "BOARD CLOSED"
        case "restricted": return "RESTRICTED"
        default:           return "STATUS UNKNOWN"
        }
    }
    private var boardStatusOpen: Bool {
        currentBoard?.boardStatus?.lowercased() == "open"
    }
    private var boardStatusColor: Color {
        guard currentBoard != nil else { return Brand.warning }
        return boardStatusOpen ? Brand.success : Brand.danger
    }
    private var yardNamePill: String {
        let name = availability?.yardName ?? yardId
        let rr   = availability?.yardRailroad ?? ""
        return rr.isEmpty ? name : "\(name) \(rr)"
    }

    // MARK: View

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrow
                headline
                IridescentHairline()
                if isLoading {
                    LifecycleCard {
                        Text("Loading crew and HOS evidence…")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                if !evidenceIssues.isEmpty {
                    LifecycleCard(accentDanger: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(evidenceIssues, id: \.self) { issue in
                                Text(issue)
                                    .font(EType.caption)
                                    .foregroundStyle(Brand.warning)
                            }
                        }
                    }
                }
                heroCard
                kpiStrip
                crewSection
                nextCallStrip
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .eusoRefreshTask { await loadAll() }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            EusoTripEyebrow(verbatim: "RAIL ENGINEER · CREW CALL")
                .font(.system(size: 9, weight: .black))
                .kerning(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(yardLabel)
                .font(.system(size: 9, weight: .heavy).monospaced())
                .kerning(0.6)
                .foregroundColor(palette.textTertiary)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Crew call board")
                .font(.system(size: 28, weight: .heavy))
                .kerning(-0.4)
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: Hero card

    private var heroCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            VStack(alignment: .leading, spacing: Space.s3) {
                // Status + yard pills
                HStack(spacing: Space.s2) {
                    Text(boardStatusLabel)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(boardStatusColor.opacity(0.14)))
                        .foregroundColor(boardStatusColor)

                    Text(yardNamePill)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.05)))
                        .foregroundColor(palette.textPrimary)
                }

                // Callable figure + called right
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: Space.s2) {
                        Text(callableNowLabel)
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("callable now")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(palette.textSecondary)
                            Text("extra board depth \(boardSizeLabel) · turn \(avgTurnLabel)")
                                .font(.system(size: 11))
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CALLED")
                            .font(.system(size: 10, weight: .black))
                            .kerning(0.6)
                            .foregroundColor(palette.textTertiary)
                        Text(calledCountLabel)
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundColor(palette.textPrimary)
                        Text("on assignment")
                            .font(.system(size: 11))
                            .foregroundColor(palette.textSecondary)
                    }
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 116)
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(
                label: "AVAILABLE",
                value: callableNowLabel,
                accent: callableNow.map { $0 > 0 ? Brand.success : Brand.danger } ?? Brand.warning
            )
            MetricTile(label: "CALLED", value: calledCountLabel)
            MetricTile(label: "BOARD", value: boardSizeLabel)
        }
    }

    // MARK: Crew list

    private var crewSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CREW")
                .font(.system(size: 9, weight: .black))
                .kerning(1.0)
                .foregroundColor(palette.textTertiary)

            VStack(spacing: 0) {
                if crew.isEmpty {
                    Text(crewLoadError == nil ? "No crew rows were returned." : "Crew roster unavailable.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.s4)
                }
                ForEach(Array(crew.enumerated()), id: \.offset) { idx, member in
                    if idx > 0 {
                        Divider()
                            .overlay(Color.black.opacity(0.06))
                            .padding(.horizontal, Space.s4)
                    }
                    crewRow(member)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func crewRow(_ member: CrewMember584) -> some View {
        let (chipColor, pillLabel, pillColor) = crewStatusInfo(member)
        let craftTitle = [member.craft, member.crewId].compactMap { $0 }.joined(separator: " · ")
        let hosHours = member.hasCurrentHOSEvidence
            ? member.hoursOnDuty.map { String(format: "%.1fh", $0) } ?? "—"
            : "—"
        let subText = "\(member.boardPosition ?? "—") · on duty \(hosHours)"

        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(chipColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(chipColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(craftTitle.isEmpty ? "-" : craftTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                Text(subText)
                    .font(.system(size: 11).monospaced())
                    .kerning(0.4)
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
            Text(pillLabel)
                .font(.system(size: 11, weight: .bold))
                .kerning(0.5)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(pillColor.opacity(0.14)))
                .foregroundColor(pillColor)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
    }

    // MARK: Next call strip

    private var nextCallStrip: some View {
        let nextCallLine = nextCall.flatMap { row -> String? in
            guard row.hasCurrentEvidence else { return nil }
            guard let identity = row.crewMemberName ?? row.crewMemberId else { return nil }
            return [identity, row.role].compactMap { $0 }.joined(separator: " · ")
        } ?? "No current next-call evidence"
        let dutyLine = nextCall.flatMap { row -> String? in
            guard row.hasCurrentEvidence else { return nil }
            let onDuty = row.hoursOnDuty.map { "on duty " + HOSStatus.formatHours($0) }
            let available = row.hoursAvailable.map { "available " + HOSStatus.formatHours($0) }
            return [onDuty, available].compactMap { $0 }.joined(separator: " · ")
        }.flatMap { $0.isEmpty ? nil : $0 } ?? "HOS counters unavailable"

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("NEXT CALL")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.8)
                    .foregroundColor(palette.textTertiary)
                Spacer()
            }
            Text(nextCallLine)
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
            Text(dutyLine)
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: CTA pair

    private var hosRosterLines: [String] {
        var lines = [
            "Yard: \(yardLabel)",
            "Railroad: \(availability?.yardRailroad ?? "-")",
            "Callable now: \(callableNowLabel)",
            "Called count: \(calledCountLabel)",
            "Extra board depth: \(boardSizeLabel)",
            "Average turn: \(avgTurnLabel)"
        ]
        if let nextCall {
            lines.append("Next call: \(nextCall.crewMemberName ?? nextCall.crewMemberId ?? "-")")
            lines.append("FRA status: \(nextCall.hasCurrentEvidence ? nextCall.fraComplianceStatus ?? "unavailable" : "unverified")")
            lines.append("HOS source: \(nextCall.source ?? "unavailable")")
        }
        for member in crew.prefix(4) {
            lines.append("\(member.crewId ?? "unavailable") - \(member.craft ?? "crew") - \(crewStatusInfo(member).1)")
        }
        return lines
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: "Call channel unavailable",
                action: {},
                leadingIcon: "exclamationmark.shield"
            )
            .disabled(true)
            .opacity(0.55)
            RailSecondaryActionButton(
                title: "HOS roster",
                sheetTitle: "Crew HOS roster",
                lines: hosRosterLines,
                fillWidth: true,
                systemImage: "person.3.sequence"
            )
        }
    }

    // MARK: Helpers

    private func crewStatusInfo(_ member: CrewMember584) -> (Color, String, Color) {
        guard member.hasCurrentHOSEvidence else {
            return (Brand.warning, "UNVERIFIED", Brand.warning)
        }
        switch member.hoursOfServiceCompliant {
        case true:  return (Brand.success, "HOS VERIFIED", Brand.success)
        case false: return (Brand.danger, "HOS HOLD", Brand.danger)
        case nil:   return (Brand.warning, "UNVERIFIED", Brand.warning)
        }
    }

    // MARK: Data loading

    private func loadAll() async {
        isLoading = true
        boardLoadError = nil
        crewLoadError = nil
        hosLoadError = nil
        availability = nil
        crew = []
        nextCall = nil

        async let availTask: CrewAvailability584 = EusoTripAPI.shared.query(
            "railShipments.getCrewAvailability",
            input: YardIdIn584(yardId: yardId)
        )
        async let crewTask: [CrewMember584] = EusoTripAPI.shared.query(
            "railShipments.getRailCrew",
            input: YardIdIn584(yardId: yardId)
        )
        async let nextCallTask: NextCall584 = EusoTripAPI.shared.query(
            "railShipments.getCrewHOS",
            input: YardIdIn584(yardId: yardId)
        )

        do { availability = try await availTask }
        catch { boardLoadError = "Crew board source unavailable: \(error.eusoUserCopy)" }

        do { crew = try await crewTask }
        catch { crewLoadError = "Crew roster source unavailable: \(error.eusoUserCopy)" }

        do { nextCall = try await nextCallTask }
        catch { hosLoadError = "Crew HOS source unavailable: \(error.eusoUserCopy)" }

        isLoading = false
    }

    private var evidenceIssues: [String] {
        var issues = [boardLoadError, crewLoadError, hosLoadError].compactMap { $0 }
        if !isLoading, availability != nil, currentBoard == nil {
            issues.append("Crew board evidence is untracked, stale, or missing provenance.")
        }
        if !isLoading, nextCall != nil, nextCall?.hasCurrentEvidence != true {
            issues.append("Next-call HOS evidence is untracked, stale, or missing provenance.")
        }
        issues.append("No authorized crew-call write channel is configured; no call was sent.")
        return issues
    }
}
