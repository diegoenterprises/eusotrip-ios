//
//  758_VesselAccessorialAnalytics.swift
//  EusoTrip — Vessel Operator · Accessorial Analytics.
//
//  Faithful 1:1 port of "758 Vessel Accessorial Analytics.svg" (Light + Dark).
//  REVENUE-ANALYTIC archetype: a gradient accessorial-revenue hero, a 4-cell KPI
//  strip (collection inked eusoDiagonal · dispute · avg/charge · open A/R), a
//  RANKED spend-by-charge-type bar board (detention/demurrage lead), a
//  PAID/DISPUTED/OPEN money band, and a per-jurisdiction proportion bar
//  (COUNTRY-DONE). Real Vessel-Operator BottomNav with SHIPMENTS inked.
//
//  Wiring (endpoint confirmed on disk this fire):
//    detentionAccessorials.getAccessorialAnalytics — EXISTS
//      frontend/server/routers/detentionAccessorials.ts:2004 · protectedProcedure
//      (isolatedProcedure — tenant-scoped by ctx.user.companyId) · query
//      · input {dateFrom?,dateTo?} · returns {totalRevenue,totalCharges,
//        avgChargeAmount,byType[{type,count,totalAmount,avgAmount}],
//        byMonth,byStatus[{status,count,totalAmount}],topFacilities:[],
//        collectionRate,disputeRate} — GROUP BY over detention_claims.
//    GAP: topFacilities returns [] in-router → not surfaced rather than faked.
//    NAMED GAP: byJurisdiction[] not yet computed (verified absent) → the
//      jurisdiction bar renders 100% US with CA/MX standby, disclosed on-screen.
//    "Export analytics" → STUB · named-gap exportAccessorialAnalytics; "Filter" refreshes.
//
//  0 mock data on load · honest empty state when the tenant has no charges.
//

import SwiftUI

// MARK: - Model

private struct ChargeType758: Identifiable {
    let type: String
    let count: Int
    let totalAmount: Double
    var id: String { type }
}

private struct AccessorialAnalytics758 {
    let totalRevenue: Double
    let totalCharges: Int
    let avgChargeAmount: Double
    let collectionRate: Double
    let disputeRate: Double
    let byType: [ChargeType758]
    let paid: Double
    let disputed: Double
    let open: Double
}

private struct Empty758: Encodable {}

// MARK: - Wrapper

struct VesselAccessorialAnalyticsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselAccessorialBody758()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselAccessorialBody758: View {
    @Environment(\.palette) private var palette

    @State private var data: AccessorialAnalytics758? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private let ramp: [Color] = [Brand.danger, Color(hex: 0xFF7043), Brand.rail, Brand.warning, Brand.info, Brand.escort]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading accessorial analytics…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let d = data, d.totalCharges > 0 {
                    heroCard(d)
                    kpiStrip(d)
                    typeBoard(d)
                    statusBand(d)
                    jurisdictionBar(d)
                    ctaPair
                } else {
                    EusoEmptyState(systemImage: "banknote",
                                   title: "No accessorial charges in range",
                                   subtitle: "No billed accessorial charges were found for your company in this window.")
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · ACCESSORIAL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("Q2 · 90d").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Text("Accessorial analytics").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Hero

    private func heroCard(_ d: AccessorialAnalytics758) -> some View {
        RimCard758 {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACCESSORIAL REVENUE · 90d").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text(money(d.totalRevenue)).font(.system(size: 32, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(d.totalCharges)").font(.system(size: 20, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text("charges billed").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    // MARK: KPI strip

    private func kpiStrip(_ d: AccessorialAnalytics758) -> some View {
        HStack(spacing: 8) {
            KpiCell758(label: "COLLECTION", value: "\(Int(d.collectionRate.rounded()))%", sub: "collected", gradient: true)
            KpiCell758(label: "DISPUTE RATE", value: "\(Int(d.disputeRate.rounded()))%", sub: "of lines", subColor: Color(hex: 0x34D399))
            KpiCell758(label: "AVG / CHARGE", value: money(d.avgChargeAmount), sub: "per line")
            KpiCell758(label: "OPEN A/R", value: compact(d.open), sub: "uncollected")
        }
    }

    // MARK: Ranked type board

    private func typeBoard(_ d: AccessorialAnalytics758) -> some View {
        let rows = d.byType.sorted { $0.totalAmount > $1.totalAmount }
        let peak = max(1, rows.map(\.totalAmount).max() ?? 1)
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("SPEND BY CHARGE TYPE · RANKED").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 14) {
                ForEach(Array(rows.prefix(6).enumerated()), id: \.element.id) { idx, t in
                    HStack(spacing: 10) {
                        Text(t.type.capitalized).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                            .frame(width: 84, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.textPrimary.opacity(0.08)).frame(height: 13)
                                Capsule().fill(ramp[idx % ramp.count]).frame(width: max(8, CGFloat(t.totalAmount / peak) * g.size.width), height: 13)
                            }
                        }.frame(height: 13)
                        Text(compact(t.totalAmount)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    // MARK: PAID / DISPUTED / OPEN band

    private func statusBand(_ d: AccessorialAnalytics758) -> some View {
        HStack(spacing: 0) {
            bandCell("PAID", compact(d.paid), Color(hex: 0x34D399))
            bandCell("DISPUTED", compact(d.disputed), Color(hex: 0xF87171))
            bandCell("OPEN", compact(d.open), palette.textSecondary)
        }
        .padding(.vertical, 12).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private func bandCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
    }

    // MARK: Jurisdiction bar (COUNTRY-DONE)

    private func jurisdictionBar(_ d: AccessorialAnalytics758) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACCESSORIAL REVENUE BY JURISDICTION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(compact(d.totalRevenue)) · 100% US").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Capsule().fill(LinearGradient.primary).frame(height: 14)
                .background(Capsule().fill(palette.textPrimary.opacity(0.08)))
            HStack(spacing: 20) {
                jurLegend("US", "USD", active: true)
                jurLegend("CA", "CAD", active: false)
                jurLegend("MX", "MXN", active: false)
                Spacer()
            }
            Text("CA / MX segments activate on first non-US discharge.").font(.system(size: 9)).foregroundStyle(palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private func jurLegend(_ code: String, _ ccy: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(active ? AnyShapeStyle(Color(hex: 0x64B5F6)) : AnyShapeStyle(Color.clear))
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(active ? Color.clear : palette.textTertiary, lineWidth: 1.4))
            Text(code).font(.system(size: 10.5, weight: .bold)).foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
            Text(ccy).font(.system(size: 10.5, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: 8) {
            CTAButton(title: "Export analytics", action: { Task { await load() } }, trailingIcon: "square.and.arrow.up")
            Button(action: { Task { await load() } }) {
                Text("Filter").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }.buttonStyle(.plain).frame(width: 128)
        }
    }

    // MARK: Helpers

    private func money(_ v: Double) -> String { "$\(Int(v).formatted(.number.grouping(.automatic)))" }
    private func compact(_ v: Double) -> String {
        if v >= 1_000_000 { return "$\(String(format: "%.1f", v / 1_000_000))M" }
        if v >= 1_000 { return "$\(String(format: "%.1f", v / 1_000))K" }
        return "$\(Int(v))"
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        do {
            struct TypeRow: Decodable { let type: String?; let count: Int?; let totalAmount: Double? }
            struct StatusRow: Decodable { let status: String?; let count: Int?; let totalAmount: Double? }
            struct Resp: Decodable {
                let totalRevenue: Double?; let totalCharges: Int?; let avgChargeAmount: Double?
                let collectionRate: Double?; let disputeRate: Double?
                let byType: [TypeRow]?; let byStatus: [StatusRow]?
            }
            let r: Resp = try await EusoTripAPI.shared.query("detentionAccessorials.getAccessorialAnalytics", input: Empty758())
            let types = (r.byType ?? []).compactMap { t -> ChargeType758? in
                guard let name = t.type else { return nil }
                return ChargeType758(type: name, count: t.count ?? 0, totalAmount: t.totalAmount ?? 0)
            }
            let statuses = r.byStatus ?? []
            let total = r.totalRevenue ?? 0
            let paid = statuses.first { $0.status == "paid" }?.totalAmount ?? 0
            let disputed = statuses.first { $0.status == "disputed" }?.totalAmount ?? 0
            let open = max(0, total - paid - disputed)
            data = AccessorialAnalytics758(
                totalRevenue: total,
                totalCharges: r.totalCharges ?? 0,
                avgChargeAmount: r.avgChargeAmount ?? 0,
                collectionRate: r.collectionRate ?? 0,
                disputeRate: r.disputeRate ?? 0,
                byType: types, paid: paid, disputed: disputed, open: open
            )
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - File-scoped bespoke helpers

private struct RimCard758<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }
}

private struct KpiCell758: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let sub: String
    var subColor: Color? = nil
    var gradient: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textTertiary)
            Text(value).font(.system(size: 20, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(gradient ? Color.white : palette.textPrimary)
            Text(sub).font(.system(size: 9, weight: .semibold)).foregroundStyle(gradient ? Color.white.opacity(0.85) : (subColor ?? palette.textTertiary))
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(gradient ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(gradient ? Color.clear : palette.borderFaint, lineWidth: 1))
    }
}

#Preview("758 · Vessel Accessorial Analytics · Night") { VesselAccessorialAnalyticsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("758 · Vessel Accessorial Analytics · Light") { VesselAccessorialAnalyticsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
