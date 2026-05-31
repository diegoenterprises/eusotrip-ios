//
//  573_RailAccessorialCharges.swift
//  EusoTrip — Rail Engineer · Accessorial Charges (carrier-side per-load billing).
//
//  Verbatim port of "573 Rail Accessorial Charges.svg" (Light + Dark).
//  Open accessorial billing for active load: demurrage, switching, reefer, FSC.
//  APPLY pills + bulk apply CTA + send to billing.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Data:
//    detentionAccessorials.getAccessorialBilling    (EXISTS :1354)  → hero: total, status, dwell, lineCount
//    detentionAccessorials.getAccessorialCatalog    (EXISTS :660)   → catalog rows
//    detentionAccessorials.getFuelSurchargeTracking (EXISTS :1046)  → FSC rate (best-effort)
//    detentionAccessorials.applyAccessorial         (EXISTS :712)   → APPLY pills + CTA
//

import SwiftUI

struct RailAccessorialChargesScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) { RailAccessorialChargesBody(railId: railId) } nav: {
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

// MARK: - Data shapes

private struct AccessorialBilling573: Decodable {
    let totalAmountUsd: Double?
    let status: String?
    let dwellHours: Double?
    let lineCount: Int?
    let shipperName: String?
    let billedMtdUsd: Double?
    let pendingUsd: Double?
    let disputedUsd: Double?
    let routeSummary: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        // Server returns { pendingCharges: [...], batchSummary: {...} }
        // Try to decode as envelope; fall back to direct key access
        if let envC = try? decoder.container(keyedBy: EnvelopeCodingKeys.self),
           let charges = try? envC.decodeIfPresent([PendingCharge].self, forKey: .pendingCharges),
           let summary = try? envC.decodeIfPresent(BatchSummary.self, forKey: .batchSummary) {
            // Extract KPIs from envelope
            self.totalAmountUsd = Double(summary.totalAmount ?? 0)
            self.status = "pending" // Default status since server doesn't explicitly return it
            self.dwellHours = nil
            self.lineCount = summary.totalItems ?? 0
            self.shipperName = charges.first?.shipperName
            self.billedMtdUsd = nil
            self.pendingUsd = Double(summary.totalAmount ?? 0)
            self.disputedUsd = nil
            self.routeSummary = nil
        } else {
            // Fall back to direct key decoding for flat response
            self.totalAmountUsd = try c.decodeIfPresent(Double.self, forKey: .totalAmountUsd)
            self.status = try c.decodeIfPresent(String.self, forKey: .status)
            self.dwellHours = try c.decodeIfPresent(Double.self, forKey: .dwellHours)
            self.lineCount = try c.decodeIfPresent(Int.self, forKey: .lineCount)
            self.shipperName = try c.decodeIfPresent(String.self, forKey: .shipperName)
            self.billedMtdUsd = try c.decodeIfPresent(Double.self, forKey: .billedMtdUsd)
            self.pendingUsd = try c.decodeIfPresent(Double.self, forKey: .pendingUsd)
            self.disputedUsd = try c.decodeIfPresent(Double.self, forKey: .disputedUsd)
            self.routeSummary = try c.decodeIfPresent(String.self, forKey: .routeSummary)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case totalAmountUsd, status, dwellHours, lineCount, shipperName
        case billedMtdUsd, pendingUsd, disputedUsd, routeSummary
    }

    private enum EnvelopeCodingKeys: String, CodingKey {
        case pendingCharges, batchSummary
    }

    private struct PendingCharge: Decodable {
        let id: Int?
        let loadId: Int?
        let type: String?
        let amount: Double?
        let status: String?
        let facilityName: String?
        let shipperName: String?
        let carrierName: String?
        let origin: String?
        let destination: String?
        let createdAt: String?
        let selected: Bool?
    }

    private struct BatchSummary: Decodable {
        let totalItems: Int?
        let totalAmount: Int?
        let byType: [TypeSummary]?
        let readyToInvoice: Int?
    }

    private struct TypeSummary: Decodable {
        let type: String?
        let count: Int?
        let total: Int?
    }
}

private struct AccessorialLine573: Decodable, Identifiable {
    let id: Int
    let name: String?
    let code: String?
    let rateDescription: String?
    let amountUsd: Double?
    let isApplied: Bool?
    let chargeType: String?
}

/// `detentionAccessorials.getAccessorialCatalog` returns a wrapper envelope
/// `{ items, categories, total }`, not a bare array.
private struct AccessorialCatalogResponse: Decodable {
    let items: [AccessorialLine573]?
    let categories: [String]?
    let total: Int?
}

private struct FSCTracking573: Decodable {
    let fscRate: Double?
    let fscAmountUsd: Double?
}

// MARK: - Body

private struct RailAccessorialChargesBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var billing: AccessorialBilling573? = nil
    @State private var catalog: [AccessorialLine573] = []
    @State private var fsc: FSCTracking573? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var appliedLines: Set<Int> = []
    @State private var applyingLines: Set<Int> = []
    @State private var isApplyingAll = false

    // MARK: Derived

    private var heroTotalLabel: String {
        guard let t = billing?.totalAmountUsd else { return "—" }
        return "$\(Int(t))"
    }
    private var lineCountLabel: String {
        let n = billing?.lineCount.map { "\($0) line items" } ?? "—"
        if let shipper = billing?.shipperName { return "\(n) · shipper \(shipper)" }
        return n
    }
    private var routeLabel: String  { billing?.routeSummary ?? "Open billing" }
    private var dwellLabel: String  { billing?.dwellHours.map { "\(Int($0))h" } ?? "—" }
    private var billingStatusLabel: String {
        (billing?.status ?? "PENDING REVIEW").uppercased().replacingOccurrences(of: "_", with: " ")
    }
    private var billingStatusColor: Color {
        switch (billing?.status ?? "").lowercased() {
        case "approved", "paid":   return Brand.success
        case "disputed":            return Brand.danger
        default:                    return Brand.warning
        }
    }
    private var billedMtdLabel: String { billing?.billedMtdUsd.map { "$\(Int($0))" } ?? "—" }
    private var pendingLabel: String   { billing?.pendingUsd.map   { "$\(Int($0))" } ?? "—" }
    private var disputedLabel: String  { billing?.disputedUsd.map  { "$\(Int($0))" } ?? "—" }

    private func isLineApplied(_ line: AccessorialLine573) -> Bool {
        appliedLines.contains(line.id) || (line.isApplied ?? false)
    }

    private func chipInfo(_ line: AccessorialLine573) -> (color: Color, icon: String) {
        switch (line.chargeType ?? "").lowercased() {
        case "demurrage":                          return (Brand.danger,  "clock.fill")
        case "switching", "switch":                return (Brand.blue,    "arrow.right.circle.fill")
        case "reefer", "refrigerated", "genset":   return (Brand.success, "thermometer.snowflake")
        case "fsc", "fuel_surcharge", "fuel":      return (Brand.warning, "fuelpump.fill")
        default:                                   return (Brand.rail, "creditcard.fill")
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading accessorials…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    catalogList
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
                    Text("RAIL ENGINEER · ACCESSORIALS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(String(railId.prefix(22)))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Accessorial charges")
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
                Text(billingStatusLabel)
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(billingStatusColor)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(billingStatusColor.opacity(0.14)))
                Text(routeLabel)
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(heroTotalLabel)
                        .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("open accessorial billing")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(lineCountLabel)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("ACCRUING")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(dwellLabel)
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Brand.danger)
                    Text("dwell at ramp")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "BILLED MTD", value: billedMtdLabel)
            MetricTile(label: "PENDING",    value: pendingLabel, gradientNumeral: true)
            MetricTile(label: "DISPUTED",   value: disputedLabel, accent: Brand.danger)
        }
    }

    // MARK: - Catalog list

    private var catalogList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ACCESSORIAL CATALOG")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getAccessorialCatalog")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if catalog.isEmpty {
                EusoEmptyState(
                    systemImage: "doc.plaintext",
                    title: "No accessorials",
                    subtitle: "Accessorial charges for this load will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(catalog.enumerated()), id: \.element.id) { idx, line in
                        catalogRow(line)
                        if idx < catalog.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                                .overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            }
        }
    }

    private func catalogRow(_ line: AccessorialLine573) -> some View {
        let chip = chipInfo(line)
        let applied = isLineApplied(line)
        let isApplyingThis = applyingLines.contains(line.id)
        let pillColor: Color = applied ? Brand.success : Brand.blue
        let pillLabel = applied ? "APPLIED" : "APPLY"
        let amount = line.amountUsd ?? 0
        let amountStr = amount == 0 ? "$0" : "$\(Int(amount))"
        let amountColor: Color = amount == 0 ? palette.textTertiary : palette.textPrimary

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chip.color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: chip.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chip.color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(line.name ?? "—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(line.code ?? "—") · \(line.rateDescription ?? "—")")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    if !applied { Task { await applyLine(line) } }
                } label: {
                    Group {
                        if isApplyingThis {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Text(pillLabel)
                                .font(.system(size: 11, weight: .bold)).kerning(0.6)
                                .foregroundStyle(pillColor)
                        }
                    }
                    .frame(width: 60, height: 24)
                    .background(Capsule().fill(pillColor.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .disabled(applied)
                Text(amountStr)
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(amountColor)
            }
        }
        .padding(16)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Apply accessorial", action: { Task { await applyAll() } }, leadingIcon: "plus.circle", isLoading: isApplyingAll)
            Button {} label: {
                Text("Send to billing")
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
        struct RailIn: Encodable { let railId: String }
        do {
            async let billingResult: AccessorialBilling573 = EusoTripAPI.shared.query(
                "detentionAccessorials.getAccessorialBilling", input: RailIn(railId: railId))
            async let catalogResult: AccessorialCatalogResponse = EusoTripAPI.shared.query(
                "detentionAccessorials.getAccessorialCatalog", input: RailIn(railId: railId))
            let (b, c) = try await (billingResult, catalogResult)
            self.billing = b
            self.catalog = c.items ?? []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        do {
            let f: FSCTracking573 = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getFuelSurchargeTracking", input: RailIn(railId: railId))
            self.fsc = f
        } catch { /* best-effort FSC enrichment */ }
        loading = false
    }

    private func applyLine(_ line: AccessorialLine573) async {
        guard !isLineApplied(line) else { return }
        applyingLines.insert(line.id)
        struct ApplyIn: Encodable { let railId: String; let accessorialCode: String }
        struct ApplyOut: Decodable {
            let success: Bool
            let loadId: Int
            let chargeCode: String
            let amount: Double
            let status: String
        }
        do {
            let _: ApplyOut = try await EusoTripAPI.shared.query(
                "detentionAccessorials.applyAccessorial",
                input: ApplyIn(railId: railId, accessorialCode: line.code ?? ""))
            appliedLines.insert(line.id)
        } catch { /* show current state */ }
        applyingLines.remove(line.id)
    }

    private func applyAll() async {
        isApplyingAll = true
        for line in catalog where !isLineApplied(line) {
            await applyLine(line)
        }
        isApplyingAll = false
    }
}

#Preview("573 · Rail Accessorial Charges · Night") { RailAccessorialChargesScreen(theme: Theme.dark, railId: "RAIL-260523-7C3A0B12D4").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("573 · Rail Accessorial Charges · Light") { RailAccessorialChargesScreen(theme: Theme.light, railId: "RAIL-260523-7C3A0B12D4").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
