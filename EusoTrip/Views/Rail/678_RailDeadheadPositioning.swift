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
    let id: String
    let role: String?
    let crewId: String?
    let onDutyHours: Double?
    let remainingHours: Double?
    let dutyStatus: String?
    let endorsement: String?
    let tracked: Bool?
    let trackingState: HOSTrackingState?
    let source: String?
    let freshness: String?
    let observationState: String?

    enum CodingKeys: String, CodingKey {
        case id, role, crewId, remainingHours, dutyStatus, endorsement, hoursOnDuty
        case tracked, trackingState, source, freshness, observationState
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        if let id = try? c.decode(String.self, forKey: .id), !id.isEmpty {
            self.id = id
        } else if let id = try? c.decode(Int.self, forKey: .id) {
            self.id = String(id)
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                .init(codingPath: c.codingPath, debugDescription: "Rail crew HOS row has no stable identifier.")
            )
        }
        self.role = try c.decodeIfPresent(String.self, forKey: .role)
        self.crewId = try c.decodeIfPresent(String.self, forKey: .crewId)
        if let s = try? c.decodeIfPresent(String.self, forKey: .hoursOnDuty), let h = Double(s) {
            self.onDutyHours = h
        } else {
            self.onDutyHours = try? c.decodeIfPresent(Double.self, forKey: .hoursOnDuty)
        }
        if let hours = try? c.decodeIfPresent(Double.self, forKey: .remainingHours) {
            self.remainingHours = hours
        } else if let hours = try? c.decodeIfPresent(String.self, forKey: .remainingHours) {
            self.remainingHours = Double(hours)
        } else {
            self.remainingHours = nil
        }
        self.dutyStatus = try c.decodeIfPresent(String.self, forKey: .dutyStatus)
        self.endorsement = try c.decodeIfPresent(String.self, forKey: .endorsement)
        self.tracked = try c.decodeIfPresent(Bool.self, forKey: .tracked)
        self.trackingState = try c.decodeIfPresent(HOSTrackingState.self, forKey: .trackingState)
        self.source = try c.decodeIfPresent(String.self, forKey: .source)
        self.freshness = try c.decodeIfPresent(String.self, forKey: .freshness)
        self.observationState = try c.decodeIfPresent(String.self, forKey: .observationState)
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
    @State private var loadError: String?
    private var available: [CrewHOS678] {
        crew.filter { row in
            row.dutyStatus == "off_duty"
                && hasCurrentObservation(row)
                && row.remainingHours.map { $0.isFinite && $0 > 0 } == true
        }
    }
    private var onDuty: [CrewHOS678] {
        crew.filter { hasCurrentObservation($0) && $0.dutyStatus == "on_duty" }
    }
    private var nearLimit: [CrewHOS678] {
        crew.filter { row in
            hasCurrentObservation(row)
                && row.dutyStatus == "near_limit"
                && row.remainingHours.map { $0.isFinite && $0 >= 0 } == true
        }
    }
    private var unverified: [CrewHOS678] {
        crew.filter { row in
            guard hasCurrentObservation(row) else { return true }
            guard let remaining = row.remainingHours, remaining.isFinite, remaining >= 0 else { return true }
            return !["off_duty", "on_duty", "near_limit"].contains(row.dutyStatus ?? "")
        }
    }
    /// Candidates are those with real HOS headroom to be repositioned.
    private var candidates: [CrewHOS678] {
        available.sorted { lhs, rhs in
            guard let left = lhs.remainingHours else { return false }
            guard let right = rhs.remainingHours else { return true }
            return left > right
        }
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
                } else if let loadError {
                    EusoEmptyState(
                        systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                        title: "Crew HOS unavailable",
                        subtitle: loadError
                    )
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
        .eusoRefreshable { await reload() }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            EusoTripEyebrow(verbatim: "RAIL ENGINEER · DEADHEAD POSITIONING")
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
            chip(unverified.isEmpty ? (net < 0 ? "\(-net) short" : "balanced") : "balance unverified",
                 unverified.isEmpty && net >= 0 ? Brand.success : Brand.warning)
            chip("\(candidates.count) candidates", palette.textSecondary)
            chip(unverified.isEmpty ? "\(nearLimit.count) near limit" : "\(unverified.count) unverified",
                 unverified.isEmpty && nearLimit.isEmpty ? Brand.success : Brand.warning)
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
        let verified = unverified.isEmpty
        let statusColor = verified && !short ? Brand.success : Brand.warning
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CREW BALANCE · \(crew.count) ON BOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(statusColor)
                Spacer()
                Text(!verified ? "VERIFY" : short ? "ACTION" : "STEADY")
                    .font(.system(size: 10.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(statusColor.opacity(0.16)))
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: short ? [Brand.warning.opacity(0.16), Brand.blue.opacity(0.05)]
                                                     : [Brand.success.opacity(0.14), Brand.blue.opacity(0.06)],
                                       startPoint: .leading, endPoint: .trailing))
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(!verified ? "—" : short ? "\(-net) short" : "\(available.count) ready")
                        .font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text(short ? "crews" : "to reposition").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
                }
                Text(verified
                     ? "\(onDuty.count) on duty · \(available.count) available · \(nearLimit.count) near HOS limit"
                     : "duty totals withheld · current sourced evidence required")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                if !unverified.isEmpty {
                    Text("\(unverified.count) crew row\(unverified.count == 1 ? "" : "s") lack complete duty-hour evidence. Provider freshness is not supplied by this feed.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            if candidates.isEmpty {
                Text("No crew row has current, sourced Part 228 evidence. Reposition eligibility is held closed.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 14)
            } else {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { i, m in
                    candidateRow(m)
                    if i < candidates.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
        }
        .padding(.horizontal, 16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func candidateRow(_ m: CrewHOS678) -> some View {
        let remaining = m.remainingHours
        let ok = remaining.map { $0 >= 4.0 } == true
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(roleGradient(m.role)).frame(width: 34, height: 34)
                Text(initials(m)).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(m.role?.capitalized ?? "Crew") · \(m.crewId ?? "—")")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(remaining.map { String(format: "%.1fh remaining", $0) } ?? "HOS remaining unavailable")\(m.endorsement.map { " · \($0)" } ?? "")")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(remaining == nil ? "UNVERIFIED" : ok ? "HOS HEADROOM" : "HOS TIGHT")
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
        VStack(alignment: .leading, spacing: 3) {
            Text("US · 49 CFR PART 228")
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.blue)
            Text("This source does not evaluate Canadian or Mexican duty regimes.")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.borderFaint))
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
        loading = true; loadError = nil
        defer { loading = false }
        do {
            crew = try await EusoTripAPI.shared.queryNoInput("railShipments.getRailCrewHOS")
        } catch {
            crew = []
            loadError = "Current rail crew HOS rows could not refresh. No reposition decision is shown."
        }
    }

    private func initials(_ m: CrewHOS678) -> String {
        if let c = m.crewId, c.count >= 2 { return String(c.prefix(2)).uppercased() }
        if let r = m.role, let f = r.first { return String(f).uppercased() }
        return "C"
    }

    private func hasCurrentObservation(_ member: CrewHOS678) -> Bool {
        member.tracked == true
            && member.trackingState == .tracked
            && member.observationState == "current"
            && member.source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && HOSObservationClock.freshness(member.freshness).isCurrent
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
