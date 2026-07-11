//
//  677_RailBadOrderTagging.swift
//  EusoTrip — Rail Engineer · Bad-Order Tagging (AAR field manual).
//
//  Bespoke port of "05 Rail/Dark-SVG/677 Rail Bad-Order Tagging.svg".
//  ARCHETYPE = DEFECT WORK BOARD / TRIAGE — a danger-rim attention card
//  for the worst car (set-out required) over disposition bands
//  (SET OUT NOW / REPAIR IN PLACE / MONITOR), each a full-width railcar
//  row with a defect chip + set-out context. Not the HOS clock-bar row,
//  not a duty roster.
//
//  Role: RAIL_ENGINEER (carrier family). transportMode = rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getRailInspections EXISTS:2684 {limit} →
//        [{id,type,date,location,status,inspector,notes,passed}]. A FAILING
//        or CONDITIONAL inspection IS a bad order — the board is built from
//        the real inspection results, dispositioned by result (fail →
//        SET OUT, conditional → REPAIR, other-non-pass → MONITOR). Passed
//        cars are never shown as bad orders.
//    HONEST GAP: the tag-write + carman handoff (getBadOrders / tagBadOrder /
//    notifyCarman — STUB per 677) is not wired here; the deeper single-car
//    dossier + RIP handoff live on the real railMechanical.getBadOrder
//    surface (699). The disposition defaults to SET OUT for a failing car —
//    never auto-clears a defective car for haul (49 CFR §215).
//

import SwiftUI

private struct InspRow677: Decodable, Identifiable {
    let id: String?
    let type: String?
    let date: String?
    let location: String?
    let status: String?
    let inspector: String?
    let notes: String?
    let passed: Bool?
    var rowId: String { id ?? "\(date ?? "")-\(location ?? "")" }
}
private struct LimitIn677: Encodable { let limit: Int }

private enum Disposition677: CaseIterable {
    case setOut, repairInPlace, monitor
    var title: String { switch self { case .setOut: "SET OUT NOW"; case .repairInPlace: "REPAIR IN PLACE"; case .monitor: "MONITOR" } }
    var color: Color { switch self { case .setOut: Brand.danger; case .repairInPlace: Brand.warning; case .monitor: Color(hex: 0x6E7681) } }
    var pill: String { switch self { case .setOut: "SET OUT"; case .repairInPlace: "REPAIR"; case .monitor: "MONITOR" } }
}

private struct BadCar677: Identifiable {
    let key: String
    let railcar: String
    let defect: String
    let inspector: String?
    let date: Date?
    let disposition: Disposition677
    var id: String { key }
}

struct RailBadOrderTaggingScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailBadOrderTaggingBody() } nav: {
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

private struct RailBadOrderTaggingBody: View {
    @Environment(\.palette) private var palette
    @State private var raw: [InspRow677] = []
    @State private var loading = true
    @State private var country = 0

    private let regimes: [(String, String)] = [("US · FRA §215", "defective car"),
                                               ("CA · TC", "RFC insp. rules"),
                                               ("MX · ARTF", "carro averiado")]

    private var cars: [BadCar677] {
        raw.compactMap { r -> BadCar677? in
            let status = (r.status ?? "").lowercased()
            let disp: Disposition677
            if r.passed == false || status == "fail" { disp = .setOut }
            else if status == "conditional" { disp = .repairInPlace }
            else if r.passed == true || status == "pass" { return nil }   // not a bad order
            else { disp = .monitor }
            let railcar = Self.railcarName(r.location)
            let defect = Self.defectLabel(r.notes, type: r.type)
            return BadCar677(key: r.rowId, railcar: railcar, defect: defect,
                             inspector: r.inspector, date: Self.date(r.date), disposition: disp)
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    private func cars(_ d: Disposition677) -> [BadCar677] { cars.filter { $0.disposition == d } }
    private var worst: BadCar677? { cars(.setOut).first ?? cars(.repairInPlace).first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Bad-order cars")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("Aurora Rail Division · AAR field manual · set-out plan")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else if cars.isEmpty {
                    EusoEmptyState(systemImage: "checkmark.shield",
                                   title: "No bad orders on file",
                                   subtitle: "Failing and conditional inspections surface here as set-out / repair / monitor bad orders. Every car currently passes the AAR field manual.")
                } else {
                    if let w = worst { attentionCard(w) }
                    ForEach(Disposition677.allCases, id: \.self) { d in
                        let list = cars(d)
                        if !list.isEmpty { dispositionSection(d, list) }
                    }
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
            Text("✦ RAIL ENGINEER · BAD ORDER")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("AAR FIELD MANUAL").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("All · \(cars.count)", Brand.blue)
            chip("Set out · \(cars(.setOut).count)", Brand.danger)
            chip("Repair · \(cars(.repairInPlace).count)", Brand.warning)
            chip("Monitor · \(cars(.monitor).count)", palette.textSecondary)
        }
    }
    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 10).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private func attentionCard(_ c: BadCar677) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.danger)
                Text(c.disposition == .setOut ? "SET-OUT REQUIRED BEFORE DEPARTURE" : "REPAIR REQUIRED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.danger)
                Spacer()
                Text(c.disposition.pill).font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(c.disposition.color)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(c.disposition.color.opacity(0.16)))
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [Brand.danger.opacity(0.14), Brand.warning.opacity(0.10)], startPoint: .leading, endPoint: .trailing))
            HStack(spacing: 12) {
                Image(systemName: "tram.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(palette.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.railcar).font(.system(size: 15, weight: .heavy)).monospaced().foregroundStyle(palette.textPrimary)
                    Text(c.defect).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary).lineLimit(2)
                }
                Spacer()
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private func dispositionSection(_ d: Disposition677, _ list: [BadCar677]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("\(d.title) · \(list.count)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(d.color)
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                    carRow(c)
                    if i < list.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
            .padding(.horizontal, 14)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func carRow(_ c: BadCar677) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tram.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.railcar).font(.system(size: 13, weight: .heavy)).monospaced().foregroundStyle(palette.textPrimary)
                Text(c.defect).font(.system(size: 10)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer()
            Text(c.disposition.pill).font(.system(size: 9, weight: .heavy)).tracking(0.3)
                .foregroundStyle(c.disposition.color)
                .padding(.horizontal, 8).frame(height: 20)
                .background(Capsule().fill(c.disposition.color.opacity(0.14)))
        }
        .padding(.vertical, 11)
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
            CTAButton(title: "Tag bad order", action: {})
                .frame(maxWidth: .infinity).disabled(true)
            Button {} label: {
                Text("Notify carman").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }.buttonStyle(.plain).disabled(true)
        }
    }

    private func reload() async {
        loading = true
        raw = (try? await EusoTripAPI.shared.query(
            "railShipments.getRailInspections", input: LimitIn677(limit: 120))) ?? []
        loading = false
    }

    private static func railcarName(_ loc: String?) -> String {
        guard let loc, !loc.isEmpty else { return "Railcar (unnamed)" }
        return loc.replacingOccurrences(of: "Railcar ", with: "")
    }
    private static func defectLabel(_ notes: String?, type: String?) -> String {
        if let n = notes, !n.isEmpty { return String(n.prefix(60)) }
        if let t = type, !t.isEmpty { return "\(t) — inspection failed" }
        return "Inspection failed · AAR field manual"
    }
    private static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }
}

#Preview("677 · Bad-Order Tagging · Night") {
    RailBadOrderTaggingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("677 · Bad-Order Tagging · Light") {
    RailBadOrderTaggingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
