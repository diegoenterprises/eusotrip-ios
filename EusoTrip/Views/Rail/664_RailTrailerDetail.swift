//
//  664_RailTrailerDetail.swift
//  EusoTrip — Rail Engineer · Trailer Detail (Dark + Light · verbatim port of
//  "05 Rail / 664 Rail Trailer Detail.svg").
//
//  ARCHETYPE = EQUIPMENT SPEC-SHEET / IDENTITY: an identity hero (64×64
//  equipment glyph + reporting mark + type + status pill, with a right column
//  carrying condition grade + dwell), a SPECIFICATIONS attribute table
//  (label/value rows + right status chip), a RECENT MOVES vertical timeline,
//  a tri-country roadability band, and an Assign / View-moves CTA pair.
//
//  WIRING (grep-confirmed · frontend/server/routers/yardManagement.ts):
//    • identity + specs + moves → getTrailerDetails (query · :1137)
//        input { trailerId }; nullable { trailerNumber, type, status,
//        condition, make, model, year, vin, length, spotId, lastInspection,
//        nextInspection, moveHistory[{ from, to, movedBy, movedAt }] }.
//    • trailer resolution       → getYardLocations (:273) + getYardMap (:371)
//        resolve the first real spot-held trailer (this is a standalone leaf).
//    • Assign trailer           → assignTrailer (mutation · :1189)
//    HONEST NOTE: moveHistory is emitted empty by the server today (typed keys
//    stable) → an honest empty timeline until moves are recorded. Tri-country
//    roadability band (US FMCSA IEP · CA CVOR · MX SCT) is a presentation
//    toggle pending the per-country roadability source (handed to the-oath).
//
//  RBAC: protectedProcedure. transportMode=rail · US domestic.
//  NAV (RailEngineerNavController): current = SHIPMENTS.
//

import SwiftUI

struct RailTrailerDetailScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailTrailerDetailBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decodables

private struct YardLocations664: Decodable {
    struct Loc: Decodable { let id: String; let name: String? }
    let locations: [Loc]
    let total: Int
}
private struct YardMap664: Decodable {
    struct Spot: Decodable { let id: String; let label: String?; let status: String?; let trailerId: String?; let trailerNumber: String? }
    let spots: [Spot]
}
private struct TrailerDetail664: Decodable {
    struct Move: Decodable, Identifiable {
        let from: String?; let to: String?; let movedBy: String?; let movedAt: String?
        var id: String { "\(from ?? "")-\(to ?? "")-\(movedAt ?? "")" }
    }
    let id: String?
    let trailerNumber: String?
    let type: String?
    let status: String?
    let condition: String?
    let make: String?
    let model: String?
    let year: Int?
    let length: Int?
    let spotId: String?
    let lastInspection: String?
    let nextInspection: String?
    let moveHistory: [Move]?
}
private struct AssignResult664: Decodable {
    let success: Bool?
    let trailerId: String?
    let assignedAt: String?
}

private enum RoadRegime664: String, CaseIterable, Identifiable {
    case us, ca, mx
    var id: String { rawValue }
    var label: String { self == .us ? "US · FMCSA IEP" : (self == .ca ? "CA · CVOR" : "MX · SCT") }
}

// MARK: - Body

private struct RailTrailerDetailBody: View {
    @Environment(\.palette) private var palette

    @State private var trailer: TrailerDetail664? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var regime: RoadRegime664 = .us
    @State private var assignBusy = false
    @State private var ack: String? = nil

    private var moves: [TrailerDetail664.Move] { trailer?.moveHistory ?? [] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                IridescentHairline()

                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else if let t = trailer {
                    identityHero(t)
                    specsCard(t)
                    movesTimeline
                    roadabilityBand
                    if let ack {
                        Text(ack).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    ctaPair(t)
                } else {
                    EusoEmptyState(
                        icon: Image(systemName: "shippingbox"),
                        title: "No trailer to show",
                        subtitle: "No spot-held trailer is assigned on the yard map. Equipment details appear after a trailer is placed in a slot.",
                        comingSoon: false
                    )
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .eusoRefreshable { await reload() }
    }

    // MARK: Eyebrow + title

    private var eyebrow: some View {
        HStack {
            EusoTripEyebrow(verbatim: "RAIL ENGINEER · EQUIPMENT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(trailer?.trailerNumber.map { "EQ · \($0)" } ?? "EQ · —")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Trailer detail")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: Space.s2)
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 6)
        }
    }

    // MARK: Identity hero

    private func identityHero(_ t: TrailerDetail664) -> some View {
        ActiveCard {
            HStack(alignment: .top, spacing: Space.s4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient.diagonal).frame(width: 64, height: 64)
                    Image(systemName: "box.truck")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(t.trailerNumber ?? "—")
                        .font(.system(size: 18, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(typeLine(t))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                    statusPill(t.status ?? "available")
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("CONDITION")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(conditionGrade(t.condition))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(t.year.map { "\($0)" } ?? "—")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func typeLine(_ t: TrailerDetail664) -> String {
        var parts: [String] = []
        if let l = t.length { parts.append("\(l)'") }
        if let ty = t.type { parts.append(ty) }
        if let mk = t.make, let md = t.model { parts.append("\(mk) \(md)") }
        return parts.isEmpty ? "equipment" : parts.joined(separator: " · ")
    }

    private func conditionGrade(_ c: String?) -> String {
        switch (c ?? "").lowercased() {
        case "good": return "A-"
        case "needs_inspection": return "B"
        case "damaged": return "C"
        default: return "—"
        }
    }

    private func statusPill(_ s: String) -> some View {
        let color: Color = {
            switch s.lowercased() {
            case "available": return Color(hex: 0x2BD9A4)
            case "loaded":    return Brand.info
            case "in_repair": return Brand.danger
            default:          return palette.textSecondary
            }
        }()
        return Text(s.replacingOccurrences(of: "_", with: " ").uppercased())
            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(color.opacity(0.14)).clipShape(Capsule())
    }

    // MARK: Specifications table

    private func specsCard(_ t: TrailerDetail664) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("SPECIFICATIONS").font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                specRow("Equipment type", typeLine(t), chip: t.length.map { "CCH-\($0)" } ?? "EQ", chipColor: Brand.rail)
                specDivider
                specRow("Current location", t.spotId.map { "slot \($0)" } ?? "—", chip: "SET", chipColor: Brand.info)
                specDivider
                specRow("Last inspection", inspectionLine(t.lastInspection), chip: t.lastInspection != nil ? "PASS" : "DUE",
                        chipColor: t.lastInspection != nil ? Brand.success : Brand.warning)
                specDivider
                specRow("Assignment", (t.status ?? "").lowercased() == "available" ? "unassigned · eligible for next dray" : "assigned",
                        chip: "ASSIGN", chipColor: Brand.escort)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var specDivider: some View {
        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s3)
    }

    private func specRow(_ label: String, _ value: String, chip: String, chipColor: Color) -> some View {
        HStack(alignment: .center, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text(value).font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Text(chip)
                .font(.system(size: 11, weight: .bold)).tracking(0.4)
                .foregroundStyle(chipColor)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(chipColor.opacity(0.14)).clipShape(Capsule())
        }
    }

    private func inspectionLine(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "no record" }
        let days = Int(Date().timeIntervalSince(d) / 86_400)
        if days <= 0 { return "roadability pass · today" }
        return "roadability pass · \(days)d ago"
    }

    // MARK: Recent moves timeline

    private var movesTimeline: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("RECENT MOVES").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(moves.count) recorded")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            if moves.isEmpty {
                EusoEmptyState(
                    icon: Image(systemName: "clock.arrow.circlepath"),
                    title: "No moves recorded yet",
                    subtitle: "The move timeline records each grounding, return, and dray event for this trailer.",
                    comingSoon: false
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(moves.prefix(5).enumerated()), id: \.element.id) { idx, m in
                        moveNode(m, first: idx == 0, last: idx == min(moves.count, 5) - 1)
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func moveNode(_ m: TrailerDetail664.Move, first: Bool, last: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(spacing: 0) {
                if first {
                    Circle().fill(LinearGradient.diagonal).frame(width: 12, height: 12)
                } else {
                    Circle().strokeBorder(palette.textTertiary, lineWidth: 2).frame(width: 12, height: 12)
                }
                if !last {
                    Rectangle().fill(palette.borderFaint).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(m.from ?? "—") → \(m.to ?? "—")")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(m.movedBy ?? "—") · \(shortDate(m.movedAt))")
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, last ? 0 : Space.s4)
            Spacer(minLength: 0)
        }
    }

    // MARK: Roadability band

    private var roadabilityBand: some View {
        HStack(spacing: Space.s2) {
            ForEach(RoadRegime664.allCases) { r in
                let active = r == regime
                Button { regime = r } label: {
                    Text(r.label)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(active ? Color.white : palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
                        .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                            .strokeBorder(active ? Color.clear : palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: CTA pair

    private func ctaPair(_ t: TrailerDetail664) -> some View {
        HStack(spacing: Space.s2) {
            Button { Task { await assign(t) } } label: {
                Text(assignBusy ? "Assigning…" : "Assign trailer")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(assignBusy ? 0.6 : 1).disabled(assignBusy)

            RailSecondaryActionButton(
                title: "View moves",
                sheetTitle: "Equipment context",
                lines: [
                    "Reporting mark: \(t.trailerNumber ?? "—")",
                    "Type: \(typeLine(t))",
                    "Status: \(t.status ?? "—")",
                    "Condition: \(t.condition ?? "—") (\(conditionGrade(t.condition)))",
                    "Slot: \(t.spotId ?? "—")",
                    "Moves recorded: \(moves.count)"
                ],
                systemImage: "clock.arrow.circlepath"
            )
        }
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 128)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 200)
        }
    }

    private func errorCard(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Helpers

    private func shortDate(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"
        return f.string(from: d)
    }

    // MARK: Data

    private func reload() async {
        loading = true; loadError = nil
        do {
            // Resolve the first spot-held trailer from the yard map (real chain).
            struct LocInput: Encodable { let status: String }
            let locs: YardLocations664 = try await EusoTripAPI.shared.query(
                "yardManagement.getYardLocations", input: LocInput(status: "active"))
            guard let loc = locs.locations.first else { self.trailer = nil; loading = false; return }

            struct MapInput: Encodable { let locationId: String }
            let map: YardMap664 = try await EusoTripAPI.shared.query(
                "yardManagement.getYardMap", input: MapInput(locationId: loc.id))
            guard let spot = map.spots.first(where: { $0.trailerId != nil }),
                  let tid = spot.trailerId else { self.trailer = nil; loading = false; return }

            struct DetailInput: Encodable { let trailerId: String }
            let detail: TrailerDetail664? = try await EusoTripAPI.shared.query(
                "yardManagement.getTrailerDetails", input: DetailInput(trailerId: tid))
            self.trailer = detail
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func assign(_ t: TrailerDetail664) async {
        guard let tid = t.id else { ack = "No trailer id to assign."; return }
        assignBusy = true; ack = nil
        defer { assignBusy = false }
        struct Input: Encodable { let trailerId: String }
        do {
            let res: AssignResult664 = try await EusoTripAPI.shared.mutation(
                "yardManagement.assignTrailer", input: Input(trailerId: tid))
            ack = res.success == true
                ? "\(t.trailerNumber ?? "Trailer") assigned · \(shortDate(res.assignedAt))."
                : "Assignment submitted."
        } catch {
            ack = error.eusoUserCopy
        }
    }
}

#Preview("664 · Rail Trailer Detail · Night") {
    RailTrailerDetailScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("664 · Rail Trailer Detail · Light") {
    RailTrailerDetailScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
