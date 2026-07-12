//
//  825_VesselEmptyRepositioning.swift
//  EusoTrip — Vessel Operator · Empty Container Repositioning.
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/825 Vessel Empty Repositioning.svg" (Light + Dark), built
//  on the canonical DesignSystem at the golden-era bar. Archetype = BIDIRECTIONAL BALANCE-BAR +
//  MOVE-LEDGER — a network equipment-balance board (net imbalance + idle exposure hero, surplus/deficit
//  bars per port off a center axis, and a reposition-move ledger), deliberately distinct from a CFS
//  inventory / chassis pool / move queue. Competitive bar: Container xChange, project44 empties. Role
//  VESSEL_OPERATOR · nav SHIPMENTS inked.
//
//  Data / wiring (endpoints confirmed on disk this fire):
//    STUB · named-gap handed to the-oath: the empty-equipment-balance / reposition model is NOT
//      modelled server-side (grep empty/repositioning = 0; blankSailing is voyage rollover, not empty
//      repositioning). Propose vessel.getEquipmentBalance: vesselProcedure.query({corridor}) ->
//      {netTeu, idleCostCents, ports:[{port, locode, balanceTeu}], moves:[{from, to, count, eqType,
//      savingCents, state:suggested|booked|hold}]} · vessel.bookReposition({moveId, confirm:true})
//      .mutation -> books the empty move, writes blockchainAuditTrail vessel.reposition_booked. This
//      screen ATTEMPTS the real query and renders the honest AWAITING state until it lands — no
//      fabricated TEU/savings/moves.
//    Regulator band = published empty-interchange regimes + currency (US IEP/USD · CA in-bond/CAD ·
//      MX vacío-pedimento/MXN).
//
//  EquipmentBalance825 / PortBalance825 / RepoMove825 are file-scoped bespoke types. Dark + Light #Preview.
//
//  — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Proposed data shape (vessel.getEquipmentBalance)

private struct PortBalance825: Decodable, Identifiable {
    let port: String?
    let locode: String?
    let balanceTeu: Int?
    var id: String { locode ?? (port ?? UUID().uuidString) }
}
private struct RepoMove825: Decodable, Identifiable {
    let moveId: String?
    let from: String?
    let to: String?
    let count: Int?
    let eqType: String?
    let savingCents: Int?
    let state: String?
    var id: String { moveId ?? "\(from ?? "")\(to ?? "")" }
}
private struct EquipmentBalance825: Decodable {
    let netTeu: Int?
    let idleCostCents: Int?
    let ports: [PortBalance825]?
    let moves: [RepoMove825]?
}

// MARK: - Screen wrapper (Shell + vessel nav · SHIPMENTS inked)

struct VesselEmptyRepositioningScreen: View {
    let theme: Theme.Palette
    var corridor: String

    init(theme: Theme.Palette, corridor: String = "") { self.theme = theme; self.corridor = corridor }

    var body: some View {
        Shell(theme: theme) {
            VesselEmptyRepositioningBody825(corridor: corridor)
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

// MARK: - Body

private struct VesselEmptyRepositioningBody825: View {
    @Environment(\.palette) private var palette
    let corridor: String

    @State private var data: EquipmentBalance825? = nil
    @State private var loading = true

    private var ports: [PortBalance825] { data?.ports ?? [] }
    private var moves: [RepoMove825] { data?.moves ?? [] }
    private var hasData: Bool { data?.netTeu != nil || !ports.isEmpty }
    private var maxAbs: Int { max(1, ports.compactMap { $0.balanceTeu.map(abs) }.max() ?? 1) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                topBar
                IridescentHairline()
                heroCard
                portBoard
                moveLedger
                regulatorBand
                actionRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Eyebrow + top bar

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · EQUIPMENT BALANCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text("DCSA equipment").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Empty repositioning").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
    }

    // MARK: Hero (net imbalance + idle exposure · gradient rim)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text(corridor.isEmpty ? "40'HC + 20'DV corridor" : corridor)
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1)
                Spacer()
                Text(ports.isEmpty ? "AWAITING" : "\(ports.count) PORTS")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.4).foregroundStyle(ports.isEmpty ? palette.textTertiary : Brand.info)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(palette.bgCardSoft))
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(data?.netTeu.map { "\($0 > 0 ? "+" : "")\($0) TEU" } ?? "— TEU")
                    .font(.system(size: 24, weight: .heavy)).monospacedDigit().foregroundStyle(palette.textPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("NET IMBALANCE").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text(surplusDeficitLine).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(idleExposureText).font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.warning)
                    Text("idle exposure").font(.system(size: 8.5)).foregroundStyle(palette.textTertiary)
                }
            }
            Text(hasData ? "Rebalance to cut idle dwell before next loop"
                         : "Awaiting vessel.getEquipmentBalance — empty-equipment model")
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
    }

    private var surplusDeficitLine: String {
        let surplus = ports.compactMap { $0.balanceTeu }.filter { $0 > 0 }.reduce(0, +)
        let deficit = ports.compactMap { $0.balanceTeu }.filter { $0 < 0 }.reduce(0, +)
        guard hasData else { return "surplus — · deficit —" }
        return "surplus +\(surplus) · deficit \(deficit)"
    }
    private var idleExposureText: String {
        guard let cents = data?.idleCostCents else { return "$—" }
        let dollars = Double(cents) / 100
        if dollars >= 1000 { return "$\(Int(dollars / 1000))K" }
        return "$\(Int(dollars))"
    }

    // MARK: Port balance board (bidirectional bars)

    private var portBoard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("EQUIPMENT BALANCE · by port")
                Spacer()
                Text("STUB · getEquipmentBalance").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            if ports.isEmpty {
                awaitingBlock(icon: "arrow.left.arrow.right", line: "Surplus / deficit by port surfaces here once the empty-equipment balance model is wired.")
            } else {
                VStack(spacing: Space.s3) {
                    ForEach(ports) { p in portBar(p) }
                    HStack {
                        Text("deficit").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(palette.textTertiary)
                        Spacer()
                        Text("surplus").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func portBar(_ p: PortBalance825) -> some View {
        let bal = p.balanceTeu ?? 0
        let surplus = bal >= 0
        return HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(p.port ?? "—").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(p.locode ?? "—").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            .frame(width: 84, alignment: .leading)
            GeometryReader { geo in
                let half = geo.size.width / 2
                let frac = CGFloat(abs(bal)) / CGFloat(maxAbs)
                ZStack {
                    Rectangle().fill(palette.borderFaint).frame(width: 1).offset(x: 0)
                    HStack(spacing: 0) {
                        // Left (deficit) half
                        HStack { Spacer(minLength: 0)
                            if !surplus {
                                RoundedRectangle(cornerRadius: 3).fill(Brand.danger).frame(width: max(4, half * frac), height: 12)
                            }
                        }.frame(width: half)
                        // Right (surplus) half
                        HStack { if surplus {
                            RoundedRectangle(cornerRadius: 3).fill(Brand.success).frame(width: max(4, half * frac), height: 12)
                        }
                        Spacer(minLength: 0) }.frame(width: half)
                    }
                }
            }
            .frame(height: 14)
            Text("\(bal > 0 ? "+" : "")\(bal)").font(.system(size: 9, weight: .heavy))
                .foregroundStyle(surplus ? Brand.success : Brand.danger).frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: Move ledger

    private var moveLedger: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("REPOSITION MOVES · suggested")
                Spacer()
                Text("vessel.bookReposition").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            if moves.isEmpty {
                awaitingBlock(icon: "shippingbox.and.arrow.backward", line: "Cheapest reposition legs (corridor · box count · saving) surface here once the balance model returns move suggestions.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(moves.enumerated()), id: \.offset) { idx, m in
                        moveRow(m)
                        if idx < moves.count - 1 { Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, Space.s4) }
                    }
                }
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func moveRow(_ m: RepoMove825) -> some View {
        let hold = (m.state ?? "").lowercased() == "hold"
        let saving = m.savingCents.map { c -> String in
            let d = Double(c) / 100
            return d >= 1000 ? "saves $\(Int(d/1000))K" : "saves $\(Int(d))"
        }
        return HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(m.from ?? "—") → \(m.to ?? "—")").font(.system(size: 10.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("\(m.count.map(String.init) ?? "—") × \(m.eqType ?? "—")").font(.system(size: 8.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s2)
            Text(hold ? "review cost" : (saving ?? "—"))
                .font(.system(size: 8.5, weight: .bold)).foregroundStyle(hold ? Brand.warning : Brand.success)
            Text(hold ? "HOLD" : "BOOK")
                .font(.system(size: 8, weight: .heavy)).foregroundStyle(hold ? Brand.warning : Brand.success)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill((hold ? Brand.warning : Brand.success).opacity(0.16)))
        }
        .padding(Space.s4)
    }

    // MARK: Regulator band

    private var regulatorBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("REGULATOR · single active gated")
                Spacer()
                Text("reposition · country").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 6) {
                regRow(active: true,  code: "US", body: "USD · IEP empty interchange", state: "ACTIVE")
                regRow(active: false, code: "CA", body: "CAD · cross-border empty in-bond", state: "STANDBY")
                regRow(active: false, code: "MX", body: "MXN · vacío / pedimento", state: "STANDBY")
            }
            .padding(Space.s3)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private func regRow(active: Bool, code: String, body: String, state: String) -> some View {
        HStack(spacing: Space.s2) {
            Text(code).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(active ? .white : palette.textSecondary)
                .frame(width: 22, height: 14).background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard)).clipShape(RoundedRectangle(cornerRadius: 4))
            Text(body).font(.system(size: 10.5, weight: active ? .bold : .semibold)).foregroundStyle(active ? palette.textPrimary : palette.textSecondary).lineLimit(1)
            Spacer(minLength: Space.s2)
            Text(state).font(.system(size: 8, weight: .heavy)).foregroundStyle(active ? Brand.success : palette.textTertiary)
        }
    }

    // MARK: Actions

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Space.s2) {
                CTAButton(title: "Book reposition", action: {}, trailingIcon: "arrow.right", isLoading: true)
                    .frame(maxWidth: .infinity)
                Button(action: {}) {
                    Text("Equipment map")
                        .font(EType.title).foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain).frame(maxWidth: 150)
            }
            Text("Booking a reposition commits feeder capacity — a gated, audited write live when vessel.bookReposition lands.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Helpers

    private func awaitingBlock(icon: String, line: String) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(palette.textTertiary.opacity(0.14)).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            Text(line).font(.system(size: 11)).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }

    // MARK: Load

    private func load() async {
        loading = true
        struct In825: Encodable { let corridor: String }
        data = try? await EusoTripAPI.shared.query("vessel.getEquipmentBalance", input: In825(corridor: corridor))
        loading = false
    }
}

// MARK: - Previews

#Preview("825 · Vessel Empty Repositioning · Night") {
    VesselEmptyRepositioningScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("825 · Vessel Empty Repositioning · Light") {
    VesselEmptyRepositioningScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
