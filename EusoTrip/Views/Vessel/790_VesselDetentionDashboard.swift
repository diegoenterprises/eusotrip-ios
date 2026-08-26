//
//  790_VesselDetentionDashboard.swift
//  EusoTrip — Vessel Operator · Detention Dashboard (PORTFOLIO archetype).
//
//  Faithful 1:1 port of "790 Vessel Detention Dashboard.svg" (Light + Dark).
//  PORTFOLIO grammar (distinct from the live board 791 and the ranked bars
//  793): a gradient-rimmed hero ActiveCard with the total-outstanding figure +
//  a collected/open/disputed split bar + collection %, a 4-cell KPI strip
//  (ACTIVE highlighted), an itemized worst-facility ledger (where the cash is
//  leaking), a View-all / Export CTA pair, and the tri-country per-diem regime
//  footer. One glance answers: how much detention cash is outstanding, how much
//  is collected vs disputed, and which few facilities cause most of the leak.
//
//  WIRING (server/routers/detentionAccessorials.ts — verified this fire):
//    · getDetentionDashboard  {dateFrom?,dateTo?}?  (query, protectedProcedure,
//        companyId-scoped catalystId|shipperId :450)
//        -> { activeDetentions, avgWaitMinutes, totalCharges, totalEvents,
//             billedAmount, collectedAmount, disputedAmount,
//             worstOffenders[{facilityName,eventCount,totalAmount,avgWaitMinutes}],
//             recentEvents[], chargesByType[] }
//      hero figure = totalCharges · split = collected / open(total-collected-
//      disputed) / disputed · KPI ACTIVE = activeDetentions · ledger =
//      worstOffenders.
//    · "View all events" -> getDetentionHistory {limit} (query :635) — real
//      count surfaced.
//    · "Export" -> exportDetentionLedger is a NAMED SERVER GAP (absent) — the
//      button surfaces the gap honestly rather than faking a download.
//  transportMode=vessel · USLGB · USD. No mock data — every value derives from
//  the live endpoint with honest loading / error / empty states.
//

import SwiftUI

// MARK: - Server shape

private struct DashOffender790: Decodable, Identifiable {
    var id: String { facilityName }
    let facilityName: String
    let eventCount: Int?
    let totalAmount: Double?
    let avgWaitMinutes: Int?
}
private struct DashResponse790: Decodable {
    let activeDetentions: Int?
    let avgWaitMinutes: Int?
    let totalCharges: Double?
    let totalEvents: Int?
    let billedAmount: Double?
    let collectedAmount: Double?
    let disputedAmount: Double?
    let worstOffenders: [DashOffender790]?
}
private struct DashHistory790: Decodable { let total: Int? }

struct VesselDetentionDashboardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselDetentionDashboardBody() } nav: { VesselDetnNav(active: .compliance) }
    }
}

private struct VesselDetentionDashboardBody: View {
    @Environment(\.palette) private var palette
    @State private var data: DashResponse790? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var busy = false

    private let accrue = Color(hex: 0xFF6B61)

    // Derived
    private var total: Double { data?.totalCharges ?? 0 }
    private var collected: Double { data?.collectedAmount ?? 0 }
    private var disputed: Double { data?.disputedAmount ?? 0 }
    private var open: Double { max(0, total - collected - disputed) }
    private var collectPct: Int { total > 0 ? Int((collected / total * 100).rounded()) : 0 }
    private var offenders: [DashOffender790] { data?.worstOffenders ?? [] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                VDetnEyebrow(section: "DETENTION", caption: "PORTFOLIO · 30D")
                titleRow
                IridescentHairline()

                if loading {
                    loadingCard
                } else if let err = loadError {
                    errorCard(err)
                } else if total <= 0 && offenders.isEmpty {
                    EusoEmptyState(systemImage: "shield.lefthalf.filled",
                                   title: "No detention on file",
                                   subtitle: "No detention charges were found in this window.")
                } else {
                    heroCard
                    kpiStrip
                    facilitiesCard
                    ctaPair
                    if let e = actionError {
                        errorCard(e)
                    } else if let m = actionMessage {
                        LifecycleCard { Text(m).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    }
                    VDetnRegimeStrip(
                        title: "DETENTION PER-DIEM REGIME · AUTHORITY + CURRENCY",
                        active: .init(code: "US", name: "FMC · per-diem per carrier tariff · USLGB", money: "USD · active"),
                        standby: [.init(code: "CA", name: "CBSA · CTA", money: "CAD"),
                                  .init(code: "MX", name: "SAT · API estadías", money: "MXN")])
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text("Detention exposure")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(Brand.success).frame(width: 7, height: 7)
                Text("30-DAY WINDOW").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Brand.success.opacity(0.16)))
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TOTAL OUTSTANDING · 30 DAYS")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        Text(VDetn.money(total))
                            .font(.system(size: 38, weight: .bold, design: .monospaced)).tracking(-0.6)
                            .foregroundStyle(LinearGradient.diagonal)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Text("\(data?.totalEvents ?? 0) events · avg \(VDetn.avgHours(data?.avgWaitMinutes ?? 0)) dwell")
                            .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("COLLECTED").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(collectPct)%")
                            .font(.system(size: 22, weight: .bold, design: .monospaced)).tracking(-0.4)
                            .foregroundStyle(Brand.success)
                    }
                }
                // Collected / open / disputed split
                GeometryReader { g in
                    let w = g.size.width
                    let cW = total > 0 ? CGFloat(collected / total) * w : 0
                    let oW = total > 0 ? CGFloat(open / total) * w : 0
                    let dW = total > 0 ? CGFloat(disputed / total) * w : 0
                    HStack(spacing: 4) {
                        Capsule().fill(Brand.success).frame(width: max(0, cW - 4))
                        Capsule().fill(Brand.warning).frame(width: max(0, oW - 4))
                        Capsule().fill(accrue).frame(width: max(0, dW - 4))
                    }
                    .frame(height: 12)
                }
                .frame(height: 12)
                HStack(spacing: 16) {
                    legendDot("Collected", VDetn.moneyK(collected), Brand.success)
                    legendDot("Open", VDetn.moneyK(open), Brand.warning)
                    legendDot("Disputed", VDetn.moneyK(disputed), accrue)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func legendDot(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(value)").font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            VDetnKPICell(label: "ACTIVE", value: "\(data?.activeDetentions ?? 0)", sub: "clocks live", gradient: true)
            VDetnKPICell(label: "AVG WAIT", value: VDetn.avgHours(data?.avgWaitMinutes ?? 0), sub: "per event")
            VDetnKPICell(label: "DISPUTED", value: VDetn.moneyK(disputed), sub: "held", valueTint: accrue)
            VDetnKPICell(label: "EVENTS", value: "\(data?.totalEvents ?? 0)", sub: "30 days")
        }
    }

    // MARK: Worst facilities

    private var facilitiesCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VDetnSectionLabel(title: "WHERE IT IS LEAKING · WORST FACILITIES",
                              trailing: "See all (\(offenders.count))", trailingTint: Brand.info)
            VStack(spacing: 0) {
                let top = Array(offenders.prefix(3).enumerated())
                ForEach(top, id: \.element.id) { idx, f in
                    facilityRow(f, rank: idx)
                    if idx < top.count - 1 {
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

    private func facilityRow(_ f: DashOffender790, rank: Int) -> some View {
        let tint = [accrue, Brand.warning, Brand.info][min(rank, 2)]
        return HStack(spacing: Space.s3) {
            VDetnIconChip(systemImage: "building.2", color: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(f.facilityName).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("\(f.eventCount ?? 0) events · avg \(VDetn.hoursMin(f.avgWaitMinutes ?? 0))")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            Text(VDetn.money(f.totalAmount ?? 0))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: busy ? "Loading…" : "View all events", action: { Task { await viewAll() } }, isLoading: busy)
            secondaryButton790(title: "Export") { exportGap() }.frame(width: 130)
        }
    }

    private func secondaryButton790(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(EType.title).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(hex: 0x232932))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Load / actions

    private struct DashInput790: Encodable { let limit: Int }

    private func load() async {
        loading = true; loadError = nil
        do {
            self.data = try await EusoTripAPI.shared.queryNoInput("detentionAccessorials.getDetentionDashboard")
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func viewAll() async {
        guard !busy else { return }
        busy = true; actionError = nil; actionMessage = nil
        do {
            let hist: DashHistory790 = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getDetentionHistory", input: DashInput790(limit: 50))
            actionMessage = "\(hist.total ?? 0) detention events in the current window."
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        busy = false
    }

    private func exportGap() {
        actionMessage = nil
        actionError = "Export is not available for this view. Live detention totals remain available here."
    }

    // MARK: Shared cards
    private var loadingCard: some View {
        LifecycleCard { Text("Loading detention portfolio…").font(EType.caption).foregroundStyle(palette.textSecondary) }
    }
    private func errorCard(_ e: String) -> some View {
        LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
    }
}

#Preview("790 · Vessel Detention Dashboard · Night") { VesselDetentionDashboardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("790 · Vessel Detention Dashboard · Light") { VesselDetentionDashboardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
