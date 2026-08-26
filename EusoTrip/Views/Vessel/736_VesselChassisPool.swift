//
//  736_VesselChassisPool.swift
//  EusoTrip — Vessel Operator · Chassis Pool (PURPOSE-BUILT UTILIZATION BOARD).
//
//  Verbatim bespoke port of canonical wireframe "736 Vessel Chassis Pool · Dark"
//  (06 Vessel · Vessel Operator, carrier-side). An EQUIPMENT-UTILIZATION board:
//  an availability hero with a stacked available/in-use/maint/out-of-service rail,
//  a per-pool utilization card (one row per leasing pool with its own utilization
//  bar), a by-type availability grid, a pool-health strip, and the tri-country
//  interchange-regime band. NOT a stat-tile stamp — the whole page reads as "what
//  equipment can I pull right now, from which pool." Docked under SHIPMENTS.
//
//  REAL WIRING (tRPC · server/routers/multiModal.ts — re-verified 2026-07-11):
//    · multiModal.getChassisManagement {limit}                            (:1258)
//        -> { chassis:[{pool,type,size,status,iepCompliant,uiiaCompliant,
//        nextInspection,…}], total, pools:[…], stats:{available,inUse,
//        maintenance,iepNonCompliant,uiiaNonCompliant} }. Backs the hero, the
//        stacked rail, every pool row (grouped by pool), the by-type grid, and
//        the pool-health strip. Live off the vehicles table; empty when the DB
//        carries no chassis inventory (honest zero-state).
//    · multiModal.getChassisAvailability {}                              (:1361)
//        -> { locations:[] } (empty today) — location-level availability; the
//        named gap is surfaced honestly, the board falls back to the management
//        rollup for utilization.  STUB · named-gap (location availability data).
//    · "Reserve chassis" — no reserveChassis mutation exists yet; the affordance
//        surfaces the gap honestly instead of faking a hold.  STUB · named-gap.
//
//  transportMode=vessel · RBAC protectedProcedure. NO mock data — every count,
//  bar, and pool row derives from the live chassis rollup.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Data shapes

/// multiModal.getChassisManagement -> { chassis, total, pools, stats }
private struct ChassisManagement736: Decodable {
    let chassis: [ChassisRow736]
    let total: Int?
    let pools: [String]?
    let stats: ChassisStats736?
}

private struct ChassisStats736: Decodable {
    let available: Int?
    let inUse: Int?
    let maintenance: Int?
    let iepNonCompliant: Int?
    let uiiaNonCompliant: Int?
}

private struct ChassisRow736: Decodable, Identifiable {
    let id: String
    let pool: String?
    let type: String?
    let size: String?
    let status: String?
    let iepCompliant: Bool?
    let uiiaCompliant: Bool?
    let nextInspection: String?
}

// MARK: - Screen

struct VesselChassisPoolScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselChassisPoolBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle)
        }
    }
}

// MARK: - Body

private struct VesselChassisPoolBody: View {
    @Environment(\.palette) private var palette

    @State private var mgmt: ChassisManagement736? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var reserveNote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else {
                    availabilityHero
                    poolUtilizationSection
                    byTypeSection
                    poolHealthStrip
                    TriCountryAuthorityBand(
                        title: "INTERCHANGE REGIME · POST-DISCHARGE DRAYAGE",
                        regimes: interchangeRegimes)
                    if let note = reserveNote { infoBanner(note) }
                    ctaRow
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Derived

    private var rows: [ChassisRow736] { mgmt?.chassis ?? [] }
    private var stats: ChassisStats736? { mgmt?.stats }
    private var available: Int { stats?.available ?? rows.filter { statusKey($0.status) == "available" }.count }
    private var inUse: Int { stats?.inUse ?? rows.filter { statusKey($0.status) == "in_use" }.count }
    private var maintenance: Int { stats?.maintenance ?? rows.filter { statusKey($0.status) == "maintenance" }.count }
    private var outOfService: Int { rows.filter { statusKey($0.status) == "out_of_service" }.count }
    private var fleetTotal: Int { max(rows.count, available + inUse + maintenance + outOfService) }
    private var inUsePct: Int { fleetTotal == 0 ? 0 : Int((Double(inUse) / Double(fleetTotal)) * 100) }

    /// Distinct pools present in the live rows (falls back to server's pools list).
    private var poolNames: [String] {
        let fromRows = Array(Set(rows.compactMap { $0.pool }.filter { !$0.isEmpty }))
        if !fromRows.isEmpty { return fromRows.sorted() }
        return mgmt?.pools ?? []
    }

    private struct PoolAgg { let name: String; let available: Int; let inUse: Int; let maint: Int; let oos: Int; var total: Int { available + inUse + maint + oos } }

    private var poolAggs: [PoolAgg] {
        poolNames.map { name in
            let ps = rows.filter { $0.pool == name }
            return PoolAgg(
                name: name,
                available: ps.filter { statusKey($0.status) == "available" }.count,
                inUse: ps.filter { statusKey($0.status) == "in_use" }.count,
                maint: ps.filter { statusKey($0.status) == "maintenance" }.count,
                oos: ps.filter { statusKey($0.status) == "out_of_service" }.count)
        }
    }

    private var typeCounts: [(label: String, sub: String, count: Int, key: String)] {
        [("STANDARD", "20-40ft", typeAvail("standard"), "standard"),
         ("TRI-AXLE", "40-53ft", typeAvail("tri_axle"), "tri_axle"),
         ("GOOSENECK", "20-45ft", typeAvail("gooseneck"), "gooseneck"),
         ("EXTENDABLE", "40-53ft", typeAvail("extendable"), "extendable")]
    }
    private func typeAvail(_ key: String) -> Int {
        rows.filter { ($0.type ?? "").lowercased().replacingOccurrences(of: "-", with: "_") == key
                      && statusKey($0.status) == "available" }.count
    }

    private var iepNon: Int { stats?.iepNonCompliant ?? rows.filter { $0.iepCompliant == false }.count }
    private var uiiaNon: Int { stats?.uiiaNonCompliant ?? rows.filter { $0.uiiaCompliant == false }.count }
    private var dueInspection: Int {
        rows.filter { r in
            guard let iso = r.nextInspection, let d = parseDate(iso) else { return false }
            let days = d.timeIntervalSinceNow / 86400
            return days >= 0 && days <= 30
        }.count
    }

    private func statusKey(_ s: String?) -> String {
        (s ?? "").lowercased().replacingOccurrences(of: "-", with: "_")
    }

    private var interchangeRegimes: [CountryRegime] {
        [.init(code: "US", authority: "UIIA · IEP interchange", detail: "IEP 49 CFR 396 · roadability · USD", consequence: nil, state: .active),
         .init(code: "CA", authority: "TC · NSC interchange", detail: "provincial CVOR · CAD", consequence: nil, state: .standby),
         .init(code: "MX", authority: "SICT · NOM-068", detail: "verificación físico-mecánica · MXN", consequence: nil, state: .standby)]
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · CHASSIS POOL")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("CHS · \(poolNames.count) POOLS")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Text("Chassis pool")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary).padding(.top, Space.s4)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5).padding(.bottom, Space.s3)
    }

    // MARK: Availability hero

    private var availabilityHero: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(available)")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                    Text("available now")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Text("across \(poolNames.count) pool\(poolNames.count == 1 ? "" : "s") · live")
                        .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("IN USE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text("\(inUsePct)%")
                        .font(.system(size: 22, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text("\(inUse) / \(fleetTotal)")
                        .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                }
            }
            stackedRail
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
    }

    private var stackedRail: some View {
        let total = max(1, fleetTotal)
        return GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 2) {
                seg(Brand.success, available, total, w)
                seg(Brand.info, inUse, total, w)
                seg(Brand.warning, maintenance, total, w)
                seg(Brand.rail, outOfService, total, w)
            }
        }
        .frame(height: 10)
    }
    private func seg(_ c: Color, _ n: Int, _ total: Int, _ w: CGFloat) -> some View {
        Capsule().fill(c).frame(width: n == 0 ? 0 : max(3, w * CGFloat(n) / CGFloat(total) - 2))
    }

    // MARK: Pool utilization

    private var poolUtilizationSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("POOL UTILIZATION")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("CHASSIS POOL STATUS").font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            if poolAggs.isEmpty {
                EusoEmptyState(systemImage: "truck.box",
                               title: "No chassis inventory yet",
                               subtitle: "Pool utilization lights up as chassis are enrolled from the fleet.")
            } else {
                VStack(spacing: Space.s4) {
                    ForEach(Array(poolAggs.enumerated()), id: \.offset) { _, p in
                        poolRow(p)
                    }
                    legend
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func poolRow(_ p: PoolAgg) -> some View {
        let util = p.total == 0 ? 0 : Int((Double(p.inUse) / Double(p.total)) * 100)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(p.name).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(p.available) / \(p.total) · \(util)% util")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            GeometryReader { geo in
                let w = geo.size.width, t = max(1, p.total)
                HStack(spacing: 1.5) {
                    seg(Brand.success, p.available, t, w)
                    seg(Brand.info, p.inUse, t, w)
                    seg(Brand.warning, p.maint, t, w)
                    seg(Brand.rail, p.oos, t, w)
                }
            }
            .frame(height: 8)
        }
    }

    private var legend: some View {
        HStack(spacing: Space.s4) {
            legendDot(Brand.success, "available")
            legendDot(Brand.info, "in use")
            legendDot(Brand.warning, "maint")
            legendDot(Brand.rail, "out-of-svc")
            Spacer()
        }
    }
    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { Circle().fill(c).frame(width: 6, height: 6)
            Text(t).font(.system(size: 10)).foregroundStyle(palette.textSecondary) }
    }

    // MARK: By type

    private var byTypeSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("BY TYPE · AVAILABLE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("LIVE CHASSIS AVAILABILITY").font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                ForEach(Array(typeCounts.enumerated()), id: \.offset) { idx, t in
                    typeTile(t, highlight: idx == 0)
                }
            }
        }
    }

    private func typeTile(_ t: (label: String, sub: String, count: Int, key: String), highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t.label).font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(highlight ? Color.white.opacity(0.85) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("\(t.count)").font(.system(size: 22, weight: .bold)).monospacedDigit()
                .foregroundStyle(highlight ? Color.white : palette.textPrimary)
            Text(t.sub).font(.system(size: 10))
                .foregroundStyle(highlight ? Color.white.opacity(0.8) : palette.textSecondary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(highlight ? Color.clear : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Pool health

    private var poolHealthStrip: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("POOL HEALTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("IEP non-compliant \(iepNon) · UIIA \(uiiaNon) · \(dueInspection) due inspection < 30d")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: CTA

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                reserveNote = "Chassis reservation writes land with the reserveChassis endpoint — hold requests route through your pool provider until then."
            } label: {
                Text("Reserve chassis")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary).clipShape(Capsule())
            }
            .buttonStyle(.plain).frame(maxWidth: .infinity)
            Button { } label: {
                Text("Pools").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 110, minHeight: 48).padding(.horizontal, Space.s3)
                    .background(palette.bgCard).overlay(Capsule().strokeBorder(palette.borderFaint)).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func infoBanner(_ msg: String) -> some View {
        LifecycleCard(accentWarning: true) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.warning)
                Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }
    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }
    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 120)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
        }
    }

    private func parseDate(_ iso: String) -> Date? {
        if let d = ISO8601DateFormatter().date(from: iso) { return d }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(iso.prefix(10)))
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int }
        do {
            let resp: ChassisManagement736 = try await EusoTripAPI.shared.query(
                "multiModal.getChassisManagement", input: In(limit: 100))
            self.mgmt = resp
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("736 · Vessel Chassis Pool · Night") {
    VesselChassisPoolScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("736 · Vessel Chassis Pool · Light") {
    VesselChassisPoolScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
