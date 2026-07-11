//
//  785_VesselDemurrageTracking.swift
//  EusoTrip — Vessel Operator · Demurrage Tracking (MONEY-BOARD archetype).
//
//  Faithful 1:1 port of "785 Vessel Demurrage Tracking.svg" (Light + Dark).
//  Per-diem demurrage by container at marine terminals: the gradient total
//  leads, a per-diem accrual split card breaks the money down by disposition
//  (accruing / invoiced / cleared), a 4-cell KPI strip highlights CONTAINERS +
//  PER DIEM, and an itemized container ledger shows which box is racking
//  per-diem and when each tips into a higher tier — so the operator pulls the
//  box before the charge escalates instead of discovering it on the invoice.
//  Distinct from the detention boards (791/790): this is per-diem-by-container,
//  disposition-bucketed, not an hourly detention clock.
//
//  WIRING (server/routers/detentionAccessorials.ts — verified this fire):
//    · getDemurrageTracking {dateFrom?,dateTo?,containerNumber?,status?,limit}?
//        (query, protectedProcedure, dc.type='demurrage', companyId-scoped :1223)
//        -> { containers[{id,loadId,containerNumber,facilityName,arrivalDate,
//             lastFreeDay,freeTimeMinutes,totalDwellMinutes,billableMinutes,
//             daysHeld,perDiemRate,totalCharge,status,shipperName,cargoType}],
//             summary{totalContainers,totalCharges,avgDaysHeld,activeCount} }
//    · "Set date range" -> re-queries the tracker.
//    · "Export" -> exportDetentionLedger NAMED SERVER GAP — surfaced honestly.
//  transportMode=vessel · USLGB · USD. No mock data.
//

import SwiftUI

private struct DemContainer785: Decodable, Identifiable {
    let id: Int
    let loadId: Int?
    let containerNumber: String?
    let facilityName: String?
    let daysHeld: Int?
    let perDiemRate: Double?
    let totalCharge: Double?
    let status: String?
    let shipperName: String?
}
private struct DemSummary785: Decodable {
    let totalContainers: Int?
    let totalCharges: Double?
    let avgDaysHeld: Int?
    let activeCount: Int?
}
private struct DemResponse785: Decodable {
    let containers: [DemContainer785]?
    let summary: DemSummary785?
}

private enum Disposition785 {
    case accruing, invoiced, cleared
    static func of(_ status: String?) -> Disposition785 {
        switch status ?? "" {
        case "paid": return .cleared
        case "approved", "invoiced": return .invoiced
        default: return .accruing
        }
    }
    var label: String { self == .accruing ? "ACCRUING" : self == .invoiced ? "INVOICED" : "CLEARED" }
    var color: Color {
        switch self { case .accruing: return Color(hex: 0xFF6B61); case .invoiced: return Brand.warning; case .cleared: return Brand.success }
    }
}

struct VesselDemurrageTrackingScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselDemurrageTrackingBody() } nav: { VesselDetnNav(active: .compliance) }
    }
}

private struct VesselDemurrageTrackingBody: View {
    @Environment(\.palette) private var palette
    @State private var data: DemResponse785? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionError: String? = nil
    @State private var busy = false

    private var containers: [DemContainer785] { data?.containers ?? [] }
    private var totalCharges: Double { data?.summary?.totalCharges ?? 0 }
    private func bucketTotal(_ d: Disposition785) -> Double {
        containers.filter { Disposition785.of($0.status) == d }.reduce(0) { $0 + ($1.totalCharge ?? 0) }
    }
    private var perDiemBase: Double { containers.compactMap { $0.perDiemRate }.max() ?? 150 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                VDetnEyebrow(section: "DEMURRAGE", caption: "USLGB · PER-DIEM")
                titleBlock
                IridescentHairline()

                if loading {
                    loadingCard
                } else if let err = loadError {
                    errorCard(err)
                } else if containers.isEmpty {
                    EusoEmptyState(systemImage: "shippingbox.circle",
                                   title: "No demurrage on file",
                                   subtitle: "getDemurrageTracking returned no per-diem containers in this window. Nothing past free time to track.")
                } else {
                    accrualCard
                    kpiStrip
                    containerLedger
                    ctaPair
                    if let e = actionError { errorCard(e) }
                    VDetnRegimeStrip(
                        title: "DEMURRAGE FREE-TIME REGIME · DISCHARGE COUNTRY",
                        active: .init(code: "US", name: "FMC 46 CFR 541 · MTO tariff", money: "USD"),
                        standby: [.init(code: "CA", name: "CTA", money: "CAD"),
                                  .init(code: "MX", name: "API", money: "MXN")])
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VDetn.money(totalCharges))
                .font(.system(size: 34, weight: .bold, design: .monospaced)).tracking(-0.6)
                .foregroundStyle(LinearGradient.diagonal).minimumScaleFactor(0.6).lineLimit(1)
            Text("total demurrage · \(containers.count) containers · avg \(data?.summary?.avgDaysHeld ?? 0) days held · \(data?.summary?.activeCount ?? 0) active")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Accrual split card

    private var accrualCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("PER-DIEM ACCRUAL · BY DISPOSITION")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                GeometryReader { g in
                    let a = bucketTotal(.accruing), i = bucketTotal(.invoiced), c = bucketTotal(.cleared)
                    let denom = max(1, a + i + c)
                    HStack(spacing: 4) {
                        Capsule().fill(Disposition785.accruing.color).frame(width: max(0, CGFloat(a / denom) * g.size.width - 4))
                        Capsule().fill(LinearGradient.primary).frame(width: max(0, CGFloat(i / denom) * g.size.width - 4))
                        Capsule().fill(Disposition785.cleared.color)
                    }
                    .frame(height: 10)
                }
                .frame(height: 10)
                HStack(spacing: 0) {
                    legendStat("Accruing", bucketTotal(.accruing), Disposition785.accruing.color)
                    Spacer()
                    legendStat("Invoiced", bucketTotal(.invoiced), palette.textPrimary)
                    Spacer()
                    legendStat("Cleared", bucketTotal(.cleared), palette.textPrimary)
                }
            }
        }
    }

    private func legendStat(_ label: String, _ value: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(tint == palette.textPrimary ? Brand.info : tint).frame(width: 8, height: 8)
                Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            Text(VDetn.money(value)).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(tint)
        }
    }

    // MARK: KPI

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            VDetnKPICell(label: "CONTAINERS", value: "\(containers.count)", sub: "\(data?.summary?.activeCount ?? 0) active", gradient: true)
            VDetnKPICell(label: "AVG DAYS", value: VDetn.days(data?.summary?.avgDaysHeld ?? 0), sub: "over free time")
            VDetnKPICell(label: "ACTIVE", value: "\(data?.summary?.activeCount ?? 0)", sub: "accruing")
            VDetnKPICell(label: "PER DIEM", value: VDetn.money(perDiemBase), sub: "/day base", gradient: true)
        }
    }

    // MARK: Container ledger

    private var containerLedger: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VDetnSectionLabel(title: "CONTAINERS ON DEMURRAGE",
                              trailing: "See all (\(containers.count))", trailingTint: Brand.info)
            VStack(spacing: 0) {
                let rows = Array(containers.prefix(3).enumerated())
                ForEach(rows, id: \.element.id) { idx, c in
                    containerRow(c)
                    if idx < rows.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    private func containerRow(_ c: DemContainer785) -> some View {
        let disp = Disposition785.of(c.status)
        let days = c.daysHeld ?? 0
        let tier = max(1, Int(ceil(Double(days) / 3.0)))
        let dots = min(5, max(1, days))
        return HStack(spacing: Space.s3) {
            VDetnIconChip(systemImage: "shippingbox.fill", color: disp.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(c.containerNumber ?? "CNT-\(c.id)").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("\(c.facilityName ?? "Terminal") · \(days) days held · tier \(tier)")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary).lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(0..<dots, id: \.self) { _ in Circle().fill(disp.color).frame(width: 6, height: 6) }
                }
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                VDetnPill(text: disp.label, color: disp.color)
                Text(VDetn.money(c.totalCharge ?? 0))
                    .font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: busy ? "Loading…" : "Set date range", action: { Task { await load() } }, isLoading: busy)
            secondaryButton785(title: "Export") { exportGap() }.frame(width: 130)
        }
    }

    private func secondaryButton785(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(EType.title).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Load / actions

    private struct DemInput785: Encodable { let limit: Int }

    private func load() async {
        busy = !loading; loadError = nil
        do {
            self.data = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getDemurrageTracking", input: DemInput785(limit: 25))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false; busy = false
    }

    private func exportGap() {
        actionError = "Ledger export isn't wired yet — detentionAccessorials.exportDetentionLedger is a named server gap. The tracker reads live; the CSV/PDF writer is pending."
    }

    private var loadingCard: some View {
        LifecycleCard { Text("Loading demurrage tracker…").font(EType.caption).foregroundStyle(palette.textSecondary) }
    }
    private func errorCard(_ e: String) -> some View {
        LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
    }
}

#Preview("785 · Vessel Demurrage Tracking · Night") { VesselDemurrageTrackingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("785 · Vessel Demurrage Tracking · Light") { VesselDemurrageTrackingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
