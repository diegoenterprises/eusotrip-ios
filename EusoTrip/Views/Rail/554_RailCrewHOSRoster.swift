//
//  554_RailCrewHOSRoster.swift
//  EusoTrip — Rail Engineer · Crew HOS Roster (carrier vantage).
//
//  Visual identity: 49 CFR §228 hours-of-service compliance dashboard.
//  Team HOS ring shows collective duty-quota consumption at a glance.
//  Per-member inline arcs encode individual remaining-hours at a glance;
//  role-specific avatar colors (engineer=gradient, conductor=blue, helper=info).
//

import SwiftUI

struct RailCrewHOSRosterScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailCrewHOSRosterBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shape (mirror railCrewAssignments row)

private struct RailCrewMember: Decodable, Identifiable {
    let id: Int
    let role: String?
    let crewId: String?
    let onDutyHours: Double?
    let remainingHours: Double?
    let dutyStatus: String?     // on_duty | off_duty | near_limit
    let endorsement: String?

    enum CodingKeys: String, CodingKey {
        case id, role, crewId, onDutyHours, remainingHours, dutyStatus, endorsement
        case hoursOnDuty
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.role = try c.decodeIfPresent(String.self, forKey: .role)
        self.crewId = try c.decodeIfPresent(String.self, forKey: .crewId)
        
        // Server sends hoursOnDuty as decimal string, iOS expects Double
        if let hoursStr = try c.decodeIfPresent(String.self, forKey: .hoursOnDuty),
           let hours = Double(hoursStr) {
            self.onDutyHours = hours
        } else if let hours = try c.decodeIfPresent(Double.self, forKey: .hoursOnDuty) {
            self.onDutyHours = hours
        } else {
            self.onDutyHours = nil
        }
        
        self.remainingHours = try c.decodeIfPresent(Double.self, forKey: .remainingHours)
        self.dutyStatus = try c.decodeIfPresent(String.self, forKey: .dutyStatus)
        self.endorsement = try c.decodeIfPresent(String.self, forKey: .endorsement)
    }
}

// MARK: - Body

private struct RailCrewHOSRosterBody: View {
    @Environment(\.palette) private var palette
    @State private var crew: [RailCrewMember] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    private let hosQuota: Double = 12.0   // 49 CFR §228 shift limit (hours)

    private var onDuty: Int    { crew.filter { ($0.dutyStatus ?? "") == "on_duty" }.count }
    private var offDuty: Int   { crew.filter { ($0.dutyStatus ?? "") == "off_duty" }.count }
    private var nearLimit: Int { crew.filter { ($0.dutyStatus ?? "") == "near_limit" }.count }

    // Team-average fraction of quota consumed
    private var teamQuotaFraction: Double {
        guard !crew.isEmpty else { return 0 }
        let avg = crew.map { min(($0.onDutyHours ?? 0) / hosQuota, 1.0) }.reduce(0, +) / Double(crew.count)
        return avg
    }
    private var teamRingColor: Color {
        teamQuotaFraction > 0.85 ? Brand.danger : (teamQuotaFraction > 0.70 ? Brand.warning : Brand.success)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading crew…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    teamHeroCard
                    summaryTiles
                    crewHeader
                    crewList
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("RAIL ENGINEER · CREW HOS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Crew roster")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Team HOS hero card

    private var teamHeroCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            HStack(spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 8) {
                    // Regulatory badge
                    Text("49 CFR §228")
                        .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(palette.textTertiary.opacity(0.12)))
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(crew.count)")
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("crew assigned")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text(nearLimit > 0 ? "\(nearLimit) near HOS limit" : "all hours clear")
                                .font(EType.caption)
                                .foregroundStyle(nearLimit > 0 ? Brand.warning : Brand.success)
                        }
                    }
                }
                Spacer()
                teamHOSRing
            }
            .padding(Space.s4)
        }
        .frame(height: 120)
    }

    private var teamHOSRing: some View {
        ZStack {
            Circle()
                .stroke(teamRingColor.opacity(0.18), lineWidth: 7)
                .frame(width: 68, height: 68)
            Circle()
                .trim(from: 0, to: teamQuotaFraction)
                .stroke(teamRingColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 68, height: 68)
            VStack(spacing: 1) {
                Text("\(Int(teamQuotaFraction * 100))%")
                    .font(.system(size: 14, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(teamRingColor)
                Text("USED")
                    .font(.system(size: 7, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Summary tiles

    private var summaryTiles: some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "ON DUTY",    value: "\(onDuty)",    icon: "checkmark.circle")
            LifecycleStatTile(label: "OFF DUTY",   value: "\(offDuty)",   icon: "moon.fill")
            LifecycleStatTile(label: "NEAR LIMIT", value: "\(nearLimit)", icon: "exclamationmark.circle", danger: nearLimit > 0)
        }
    }

    // MARK: Crew list

    private var crewHeader: some View {
        Text("ASSIGNED CREW · getRailCrewHOS")
            .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }

    private var crewList: some View {
        VStack(spacing: Space.s2) {
            ForEach(crew) { crewRow($0) }
        }
    }

    private func crewRow(_ m: RailCrewMember) -> some View {
        let (statusLabel, statusColor): (String, Color) = {
            switch (m.dutyStatus ?? "") {
            case "on_duty":    return ("ON DUTY",    Brand.success)
            case "near_limit": return ("NEAR LIMIT", Brand.warning)
            default:           return ("OFF DUTY",   palette.textTertiary)
            }
        }()
        let remaining = m.remainingHours ?? hosQuota
        let used = max(0, hosQuota - remaining)
        let frac = min(used / hosQuota, 1.0)
        let arcColor: Color = frac > 0.85 ? Brand.danger : (frac > 0.70 ? Brand.warning : Brand.success)

        return HStack(spacing: Space.s3) {
            roleAvatar(m)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(m.role?.capitalized ?? "Crew") · \(m.crewId ?? "—")")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("\(String(format: "%.1f", m.onDutyHours ?? 0))h on duty\(m.endorsement.map { " · \($0)" } ?? "")")
                    .font(.system(size: 11)).monospaced().foregroundStyle(palette.textSecondary)
            }
            Spacer()
            // Inline HOS arc
            hosArc(fraction: frac, color: arcColor, remaining: remaining)
            Text(statusLabel)
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(statusColor.opacity(0.14)).clipShape(Capsule())
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func roleAvatar(_ m: RailCrewMember) -> some View {
        ZStack {
            Circle()
                .fill(roleGradient(m.role))
                .frame(width: 36, height: 36)
            Image(systemName: "person.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func roleGradient(_ role: String?) -> AnyShapeStyle {
        switch (role ?? "").lowercased() {
        case "engineer":  return AnyShapeStyle(LinearGradient.diagonal)
        case "conductor": return AnyShapeStyle(Brand.blue)
        case "helper":    return AnyShapeStyle(Brand.info)
        default:          return AnyShapeStyle(palette.textTertiary.opacity(0.8))
        }
    }

    private func hosArc(fraction: Double, color: Color, remaining: Double) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 4)
                .frame(width: 30, height: 30)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 30, height: 30)
            Text(remaining <= 0 ? "0h" : "\(Int(remaining))h")
                .font(.system(size: 7.5, weight: .heavy)).monospacedDigit()
                .foregroundStyle(color)
        }
    }

    // MARK: Data

    private func load() async {
        loading = true; loadError = nil
        do {
            let result: [RailCrewMember] = try await EusoTripAPI.shared.queryNoInput("railShipments.getRailCrewHOS")
            self.crew = result
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("554 · Rail Crew HOS · Night") { RailCrewHOSRosterScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("554 · Rail Crew HOS · Light") { RailCrewHOSRosterScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
