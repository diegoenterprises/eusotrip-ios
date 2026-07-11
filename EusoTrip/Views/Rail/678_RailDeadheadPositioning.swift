//
//  678_RailDeadheadPositioning.swift
//  EusoTrip — Rail Engineer · Deadhead Positioning (crew repositioning).
//
//  Bespoke port of "05 Rail/Dark-SVG/678 Rail Deadhead Positioning.svg".
//  ARCHETYPE = SUPPLY/DEMAND FLOW LEDGER — a crew-balance verdict hero
//  (available vs near-limit, a split bar) over a stack of reposition-
//  candidate rows (crew initials disc, craft, HOS remaining, HOS-impact
//  pill). Not a roster of clock bars, not 674's threshold gate.
//
//  Role: RAIL_ENGINEER (carrier family). transportMode = rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getRailCrewHOS EXISTS:2125 (queryNoInput) →
//        [railCrewAssignments row {id,role,crewId,onDutyHours,
//        remainingHours,dutyStatus,endorsement}]. The crew balance + the
//        reposition-candidate list are the REAL crew HOS rows; each
//        candidate's HOS-ok / HOS-tight pill is derived from its real
//        remaining-hours against the 49 CFR Part 228 ceiling.
//    HONEST GAP: the deadhead move MATCH (from-yard → to-yard), miles,
//    mode, and cost have no backing procedure (getDeadheadMoves /
//    dispatchDeadhead — STUB); those render as a pending band, never a
//    fabricated $/route. Deadhead time counts conservatively as on-duty
//    (Part 228 limbo).
//

import SwiftUI

private struct CrewHOS678: Decodable, Identifiable {
    let id: Int
    let role: String?
    let crewId: String?
    let onDutyHours: Double?
    let remainingHours: Double?
    let dutyStatus: String?
    let endorsement: String?

    enum CodingKeys: String, CodingKey { case id, role, crewId, remainingHours, dutyStatus, endorsement, hoursOnDuty }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.role = try c.decodeIfPresent(String.self, forKey: .role)
        self.crewId = try c.decodeIfPresent(String.self, forKey: .crewId)
        if let s = try c.decodeIfPresent(String.self, forKey: .hoursOnDuty), let h = Double(s) { self.onDutyHours = h }
        else { self.onDutyHours = try c.decodeIfPresent(Double.self, forKey: .hoursOnDuty) }
        self.remainingHours = try c.decodeIfPresent(Double.self, forKey: .remainingHours)
        self.dutyStatus = try c.decodeIfPresent(String.self, forKey: .dutyStatus)
        self.endorsement = try c.decodeIfPresent(String.self, forKey: .endorsement)
    }
}

struct RailDeadheadPositioningScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDeadheadPositioningBody() } nav: {
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

private struct RailDeadheadPositioningBody: View {
    @Environment(\.palette) private var palette
    @State private var crew: [CrewHOS678] = []
    @State private var loading = true
    @State private var country = 0

    private let hosCeiling: Double = 12.0   // 49 CFR Part 228 max on-duty (hours)
    private let regimes: [(String, String)] = [("US · 49 CFR 228", "limbo = on duty"),
                                               ("CA · TC W/R", "deadhead duty"),
                                               ("MX · ARTF", "tiempo traslado")]

    private var available: [CrewHOS678] { crew.filter { ($0.dutyStatus ?? "") == "off_duty" } }
    private var onDuty: [CrewHOS678]    { crew.filter { ($0.dutyStatus ?? "") == "on_duty" } }
    private var nearLimit: [CrewHOS678] { crew.filter { ($0.dutyStatus ?? "") == "near_limit" } }
    /// Candidates are those with real HOS headroom to be repositioned.
    private var candidates: [CrewHOS678] {
        crew.filter { ($0.dutyStatus ?? "") != "on_duty" }
            .sorted { ($0.remainingHours ?? 0) > ($1.remainingHours ?? 0) }
    }
    private var net: Int { available.count - nearLimit.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Deadhead moves")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("Aurora Rail Division · crew repositioning · ruling board")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else if crew.isEmpty {
                    EusoEmptyState(systemImage: "arrow.left.arrow.right",
                                   title: "No crew on the board",
                                   subtitle: "Crew HOS rows drive the reposition board. None are assigned to your company right now.")
                } else {
                    balanceHero
                    candidatesHeader
                    candidateList
                    pendingMovesBand
                    regimeBand
                    footerActions
                }
            }
            .padding(.horizontal, 20).padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ RAIL ENGINEER · DEADHEAD POSITIONING")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("PART 228").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip(net < 0 ? "\(-net) short" : "balanced", net < 0 ? Brand.warning : Brand.success)
            chip("\(candidates.count) candidates", palette.textSecondary)
            chip("\(nearLimit.count) near limit", nearLimit.isEmpty ? Brand.success : Brand.warning)
        }
    }
    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var balanceHero: some View {
        let short = net < 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CREW BALANCE · \(crew.count) ON BOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(short ? Brand.warning : Brand.success)
                Spacer()
                Text(short ? "ACTION" : "STEADY")
                    .font(.system(size: 10.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(short ? Brand.warning : Brand.success)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill((short ? Brand.warning : Brand.success).opacity(0.16)))
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: short ? [Brand.warning.opacity(0.16), Brand.blue.opacity(0.05)]
                                                     : [Brand.success.opacity(0.14), Brand.blue.opacity(0.06)],
                                       startPoint: .leading, endPoint: .trailing))
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(short ? "\(-net) short" : "\(available.count) ready")
                        .font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text(short ? "crews" : "to reposition").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
                }
                Text("\(onDuty.count) on duty · \(available.count) available · \(nearLimit.count) near HOS limit")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                GeometryReader { geo in
                    let total = max(crew.count, 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.bgCardSoft).frame(height: 8)
                        HStack(spacing: 0) {
                            Capsule().fill(Brand.success).frame(width: geo.size.width * CGFloat(available.count) / CGFloat(total))
                            Capsule().fill(Brand.blue).frame(width: geo.size.width * CGFloat(onDuty.count) / CGFloat(total))
                            Capsule().fill(Brand.warning).frame(width: geo.size.width * CGFloat(nearLimit.count) / CGFloat(total))
                        }
                        .frame(height: 8)
                    }
                }
                .frame(height: 8)
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var candidatesHeader: some View {
        HStack {
            Text("REPOSITION CANDIDATES · \(candidates.count)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            Spacer()
            Text("limbo time on duty").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
    }

    private var candidateList: some View {
        VStack(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { i, m in
                candidateRow(m)
                if i < candidates.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func candidateRow(_ m: CrewHOS678) -> some View {
        let remaining = m.remainingHours ?? hosCeiling
        let ok = remaining >= 4.0
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(roleGradient(m.role)).frame(width: 34, height: 34)
                Text(initials(m)).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(m.role?.capitalized ?? "Crew") · \(m.crewId ?? "—")")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(String(format: "%.1f", remaining))h remaining\(m.endorsement.map { " · \($0)" } ?? "")")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(ok ? "HOS ok" : "HOS tight")
                .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                .foregroundStyle(ok ? Brand.success : Brand.warning)
                .padding(.horizontal, 8).frame(height: 18)
                .background(Capsule().fill((ok ? Brand.success : Brand.warning).opacity(0.14)))
        }
        .padding(.vertical, 11)
    }

    private var pendingMovesBand: some View {
        HStack(spacing: 12) {
            Image(systemName: "map").font(.system(size: 18, weight: .semibold)).foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Deadhead match pending").font(.system(size: 12.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("From-yard → to-yard, miles, mode and cost bind once the deadhead planner ships.")
                    .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var regimeBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == country ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == country ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { country = i } }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Dispatch moves", action: {}).frame(maxWidth: .infinity).disabled(true)
            Button {} label: {
                Text("Optimize").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }.buttonStyle(.plain).disabled(true)
        }
    }

    private func reload() async {
        loading = true
        crew = (try? await EusoTripAPI.shared.queryNoInput("railShipments.getRailCrewHOS")) ?? []
        loading = false
    }

    private func initials(_ m: CrewHOS678) -> String {
        if let c = m.crewId, c.count >= 2 { return String(c.prefix(2)).uppercased() }
        if let r = m.role, let f = r.first { return String(f).uppercased() }
        return "C"
    }
    private func roleGradient(_ role: String?) -> AnyShapeStyle {
        switch (role ?? "").lowercased() {
        case "engineer":  return AnyShapeStyle(LinearGradient.diagonal)
        case "conductor": return AnyShapeStyle(Brand.blue)
        case "helper":    return AnyShapeStyle(Brand.info)
        default:          return AnyShapeStyle(Brand.rail)
        }
    }
}

#Preview("678 · Deadhead Positioning · Night") {
    RailDeadheadPositioningScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("678 · Deadhead Positioning · Light") {
    RailDeadheadPositioningScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
