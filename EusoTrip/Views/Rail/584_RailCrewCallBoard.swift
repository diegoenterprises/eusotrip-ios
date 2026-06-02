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
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Server returns totalAvailable/totalOnDuty/railroad; iOS uses callableNow/calledCount/yardRailroad.
        self.callableNow    = try (c.decodeIfPresent(Int.self, forKey: .callableNow) ?? c.decodeIfPresent(Int.self, forKey: .totalAvailable))
        self.calledCount    = try (c.decodeIfPresent(Int.self, forKey: .calledCount) ?? c.decodeIfPresent(Int.self, forKey: .totalOnDuty))
        self.extraBoardDepth = try c.decodeIfPresent(Int.self, forKey: .extraBoardDepth)
        self.avgTurnHours   = try c.decodeIfPresent(Double.self, forKey: .avgTurnHours)
        self.boardStatus    = try c.decodeIfPresent(String.self, forKey: .boardStatus)
        self.yardName       = try c.decodeIfPresent(String.self, forKey: .yardName)
        self.yardRailroad   = try (c.decodeIfPresent(String.self, forKey: .yardRailroad) ?? c.decodeIfPresent(String.self, forKey: .railroad))
    }
    
    enum CodingKeys: String, CodingKey {
        case callableNow, calledCount, extraBoardDepth, avgTurnHours, boardStatus, yardName, yardRailroad
        // Server's actual key names mapped above.
        case totalAvailable, totalOnDuty, railroad
    }
}

private struct CrewMember584: Decodable {
    let crewId: String?
    let craft: String?
    let boardPosition: String?
    let hosAvailableHours: Double?
    let status: String?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Server fields from railCrewAssignments table
        let userId = try container.decodeIfPresent(Int.self, forKey: .userId)
        let role = try container.decodeIfPresent(String.self, forKey: .role)
        let hoursOnDuty = try container.decodeIfPresent(String.self, forKey: .hoursOnDuty)
        let hoursOfServiceCompliant = try container.decodeIfPresent(Bool.self, forKey: .hoursOfServiceCompliant)
        
        // Map server fields to iOS struct fields
        self.crewId = userId.map { String($0) }
        self.craft = role
        self.boardPosition = nil
        self.hosAvailableHours = hoursOnDuty.flatMap { Double($0) }
        self.status = hoursOfServiceCompliant == true ? "callable" : "unavailable"
    }
    
    enum CodingKeys: String, CodingKey {
        case userId, role, hoursOnDuty, hoursOfServiceCompliant
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
    
    // Computed accessors for legacy iOS view code
    var trainSymbol: String? { nil }
    var consistLead: String? { nil }
    var onDutyInMinutes: Int? { hoursOnDuty.map { Int($0 * 60) } }
    var railId: String? { nil }
}

private struct YardIdIn584: Encodable { let yardId: String }

// MARK: - Body

private struct RailCrewCallBoardBody: View {
    @Environment(\.palette) private var palette
    let yardId: String

    @State private var availability: CrewAvailability584? = nil
    @State private var crew: [CrewMember584] = []
    @State private var nextCall: NextCall584? = nil
    @State private var isCalling = false

    // MARK: Derived

    private var yardLabel: String      { availability?.yardName?.uppercased() ?? yardId.uppercased() }
    private var callableNow: Int       { availability?.callableNow      ?? 0 }
    private var calledCount: Int       { availability?.calledCount       ?? 0 }
    private var boardSize: Int         { availability?.extraBoardDepth   ?? 0 }
    private var avgTurnLabel: String   {
        guard let t = availability?.avgTurnHours else { return "—" }
        return String(format: "%.1fh", t)
    }
    private var boardStatusLabel: String {
        switch (availability?.boardStatus ?? "open").lowercased() {
        case "closed":     return "BOARD CLOSED"
        case "restricted": return "RESTRICTED"
        default:           return "BOARD OPEN"
        }
    }
    private var boardStatusOpen: Bool {
        (availability?.boardStatus ?? "open").lowercased() == "open"
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
        .task { await loadAll() }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · CREW CALL")
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
                        .background(Capsule().fill((boardStatusOpen ? Brand.success : Brand.danger).opacity(0.14)))
                        .foregroundColor(boardStatusOpen ? Brand.success : Brand.danger)

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
                        Text("\(callableNow)")
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("callable now")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(palette.textSecondary)
                            Text("extra board depth \(boardSize) · turn \(avgTurnLabel)")
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
                        Text("\(calledCount)")
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
            MetricTile(label: "AVAILABLE", value: "\(callableNow)", accent: callableNow > 0 ? Brand.success : Brand.danger)
            MetricTile(label: "CALLED",    value: "\(calledCount)")
            MetricTile(label: "BOARD",     value: "\(boardSize)")
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
        let (chipColor, pillLabel, pillColor) = crewStatusInfo(member.status)
        let craftTitle = [member.craft, member.crewId].compactMap { $0 }.joined(separator: " · ")
        let hosHours   = member.hosAvailableHours.map { String(format: "%.1fh", $0) } ?? "—"
        let hosWord    = (member.status ?? "").lowercased() == "on_call" ? "left" : "avail"
        let subText    = "\(member.boardPosition ?? "—") · HOS \(hosHours) \(hosWord)"

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
                Text(craftTitle.isEmpty ? "—" : craftTitle)
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
        let trainLine   = nextCall.map { "Train \($0.trainSymbol ?? "—") · consist \($0.consistLead ?? "—") lead" } ?? "—"
        let dutyLine    = nextCall.map { nc -> String in
            let dutyStr = nc.onDutyInMinutes.map { formatOnDuty($0) } ?? "on-duty —"
            let rid     = nc.railId ?? "—"
            return "\(dutyStr) · \(rid)"
        } ?? "—"

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("NEXT CALL")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.8)
                    .foregroundColor(palette.textTertiary)
                Spacer()
            }
            Text(trainLine)
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

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: "Call crew",
                action: { isCalling = true; Task { await callCrew() } },
                leadingIcon: "plus",
                isLoading: isCalling
            )
            Button("HOS roster") {}
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Color.black.opacity(0.10), lineWidth: 1))
                )
        }
    }

    // MARK: Helpers

    private func crewStatusInfo(_ status: String?) -> (Color, String, Color) {
        switch (status ?? "callable").lowercased() {
        case "callable":   return (Brand.success, "CALLABLE", Brand.success)
        case "on_call":    return (Brand.warning,  "ON CALL",  Brand.warning)
        case "called":     return (Brand.info,     "CALLED",   Brand.info)
        case "unavailable":return (Brand.danger,   "UNAVAIL",  Brand.danger)
        default:           return (Brand.success,  "CALLABLE", Brand.success)
        }
    }

    private func formatOnDuty(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "on-duty in \(h)h \(m)m" }
        if h > 0           { return "on-duty in \(h)h" }
        return "on-duty in \(m)m"
    }

    // MARK: Data loading

    private func loadAll() async {
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

        availability = try? await availTask
        crew         = (try? await crewTask) ?? []
        nextCall     = try? await nextCallTask
    }

    private func callCrew() async {
        defer { isCalling = false }
        let result: [CrewMember584]? = try? await EusoTripAPI.shared.query(
            "railShipments.getRailCrew",
            input: YardIdIn584(yardId: yardId)
        )
        if let r = result { crew = r }
    }
}
