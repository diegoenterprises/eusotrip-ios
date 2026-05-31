//
//  581_RailSettlementSummary.swift
//  EusoTrip — Rail Engineer · Settlement Summary (period revenue, open AR, settlement rows).
//
//  Verbatim port of "581 Rail Settlement Summary.svg" (Light + Dark).
//  Gross MTD hero + open-AR danger panel, 3-cell KPI (settled/open/cycle),
//  settlement row list with PAID/OPEN/HOLD pills + tabular amounts,
//  period-stats context strip.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Data:
//    railShipments.getRailFinancialSummary(EXISTS railShipments.ts:872) → {settlements,demurrage}
//    railShipments.getRailDashboardStats  (EXISTS railShipments.ts:540) → {activeShipments,carsInTransit,revenue}
//

import SwiftUI

struct RailSettlementSummaryScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailSettlementSummaryBody() } nav: {
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

// MARK: - Data shapes

private struct FinancialSummary581: Decodable {
    let settlements: [Settlement581]
    let demurrage: [DemurrageItem581]
}

private struct Settlement581: Decodable, Identifiable {
    let id: Int
    let loadId: Int?
    let shipmentNumber: String?
    let origin: String?
    let destination: String?
    let linehaul: Double?
    let total: Double?
    let totalAmount: String?
    let status: String?
    let currency: String?
    let carCount: Int?
    let notes: String?
    let createdAt: String?
}

private struct DemurrageItem581: Decodable, Identifiable {
    let id: Int
    let totalCharge: String?
    let status: String?
}

private struct DashStats581: Decodable {
    let activeShipments: Int?
    let carsInTransit: Int?
    let avgTransitDays: Int?
    let revenue: Double?
}

// MARK: - Body

private struct RailSettlementSummaryBody: View {
    @Environment(\.palette) private var palette

    @State private var financial: FinancialSummary581? = nil
    @State private var dashStats: DashStats581? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isExporting = false

    // MARK: Derived

    private var settlements: [Settlement581] { financial?.settlements ?? [] }

    private func settlementAmount(_ s: Settlement581) -> Double {
        if let t = s.total { return t }
        if let ts = s.totalAmount, let tv = Double(ts) { return tv }
        return s.linehaul ?? 0
    }

    private var grossTotal: Double  { settlements.reduce(0) { $0 + settlementAmount($1) } }
    private var settledTotal: Double {
        settlements.filter { ["paid","settled"].contains(($0.status ?? "").lowercased()) }
            .reduce(0) { $0 + settlementAmount($1) }
    }
    private var openTotal: Double {
        settlements.filter { !["paid","settled"].contains(($0.status ?? "").lowercased()) }
            .reduce(0) { $0 + settlementAmount($1) }
    }
    private var openCount: Int {
        settlements.filter { !["paid","settled"].contains(($0.status ?? "").lowercased()) }.count
    }

    private func formatK(_ v: Double) -> String {
        if v == 0 { return "—" }
        if v >= 1_000 { return String(format: "$%.1fK", v / 1000) }
        return String(format: "$%.0f", v)
    }
    private var grossLabel: String  { formatK(grossTotal) }
    private var settledLabel: String { formatK(settledTotal) }
    private var openLabel: String   { formatK(openTotal) }
    private var cycleLabel: String  { dashStats?.avgTransitDays.map { "\($0).0d" } ?? "—" }

    private var periodStatsLine1: String {
        let ships = dashStats?.activeShipments ?? 0
        let cars  = dashStats?.carsInTransit ?? 0
        guard ships > 0 || cars > 0 else { return "—" }
        return "\(ships) shipment\(ships == 1 ? "" : "s") · \(cars) car\(cars == 1 ? "" : "s") in transit"
    }
    private var periodStatsLine2: String {
        let cycle = cycleLabel != "—" ? "avg cycle \(cycleLabel)" : "—"
        let open  = openCount > 0 ? "\(openCount) open invoice\(openCount == 1 ? "" : "s")" : "no open invoices"
        return "\(cycle) · \(open)"
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading settlements…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    settlementsList
                    periodStatsStrip
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · SETTLEMENT")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("MTD · Rail")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Settlement summary")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("MTD")
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Text("carrier rail")
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(grossLabel)
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("gross MTD")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Text("getRailFinancialSummary")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("OPEN")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(openLabel)
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(openTotal > 0 ? Brand.danger : palette.textPrimary)
                    Text("\(openCount) pending")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "SETTLED", value: settledLabel, accent: settledTotal > 0 ? Brand.success : nil)
            MetricTile(label: "OPEN",    value: openLabel,    accent: openTotal > 0 ? Brand.danger : nil)
            MetricTile(label: "CYCLE",   value: cycleLabel)
        }
    }

    // MARK: - Settlements list

    private var settlementsList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("SETTLEMENTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getRailSettlement")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if settlements.isEmpty {
                EusoEmptyState(systemImage: "dollarsign.circle",
                               title: "No settlements",
                               subtitle: "Settlement records will appear here as shipments complete.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(settlements.prefix(8).enumerated()), id: \.element.id) { idx, s in
                        settlementRow(s)
                        if idx < min(settlements.count, 8) - 1 {
                            Divider().padding(.leading, 68).overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func settlementRow(_ s: Settlement581) -> some View {
        let (chipColor, pillLabel, pillColor) = settlementStatusInfo(s.status ?? "")
        let title: String = {
            if let o = s.origin, let d = s.destination, !o.isEmpty, !d.isEmpty {
                return "\(o) to \(d)"
            }
            return s.shipmentNumber ?? "Settlement #\(s.id)"
        }()
        // Split into typed sub-expressions to keep the Swift type-checker fast.
        let idPart: String = s.shipmentNumber ?? s.loadId.map(String.init) ?? "—"
        let carPart: String = s.carCount.map { " · \($0) car\($0 == 1 ? "" : "s")" } ?? ""
        let notePart: String = s.notes.map { " · \($0.prefix(16))" } ?? ""
        let sub: String = idPart + carPart + notePart
        let amountStr: String = {
            let v = settlementAmount(s)
            if v == 0 { return "—" }
            if v >= 1_000 { return String(format: "$%,.0f", v) }
            return String(format: "$%.2f", v)
        }()

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chipColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(sub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(pillLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(pillColor)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(pillColor.opacity(0.14)))
                Text(amountStr)
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    private func settlementStatusInfo(_ status: String) -> (Color, String, Color) {
        switch status.lowercased() {
        case "paid", "settled": return (Brand.success, "PAID",    Brand.success)
        case "hold":            return (Brand.danger,  "HOLD",    Brand.danger)
        case "open":            return (Brand.warning, "OPEN",    Brand.warning)
        case "pending":         return (Brand.info,    "PENDING", Brand.info)
        case "disputed":        return (Brand.danger,  "DISPUTE", Brand.danger)
        default:                return (palette.textSecondary, status.uppercased(), palette.textSecondary)
        }
    }

    // MARK: - Period stats strip

    private var periodStatsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PERIOD STATS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getRailDashboardStats")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            Text(periodStatsLine1)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(periodStatsLine2)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Export statement",
                      action: { Task { await exportStatement() } },
                      leadingIcon: "plus",
                      isLoading: isExporting)
            Button {} label: {
                Text("Open AR")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        do {
            async let financialResult: FinancialSummary581 = EusoTripAPI.shared.queryNoInput("railShipments.getRailFinancialSummary")
            async let statsResult: DashStats581 = EusoTripAPI.shared.queryNoInput("railShipments.getRailDashboardStats")
            let (f, s) = try await (financialResult, statsResult)
            self.financial  = f
            self.dashStats  = s
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func exportStatement() async {
        isExporting = true
        try? await Task.sleep(nanoseconds: 800_000_000)
        isExporting = false
    }
}

#Preview("581 · Rail Settlement Summary · Night") { RailSettlementSummaryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("581 · Rail Settlement Summary · Light") { RailSettlementSummaryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
