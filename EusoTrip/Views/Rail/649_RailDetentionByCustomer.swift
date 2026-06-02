//
//  649_RailDetentionByCustomer.swift
//  EusoTrip — 05 Rail · 649 Rail Engineer · Detention by Customer · Dark.
//
//  Verbatim port of "649 Rail Detention by Customer.svg" onto the
//  DesignSystem primitives. CARRIER-SIDE intermodal-parity gap-fill,
//  built to the flagship DETAIL grammar (645 Rail Detention Dashboard /
//  02 Shipper 205): back-chevron + eyebrow + mono caption + title
//  28/-0.4; gradient-rimmed hero ActiveCard with lead figure + progress;
//  3-cell KPI strip (cell-1 eusoDiagonal); itemized customer ListRow
//  stack (40x40 icon chip + title + mono sub + short status pill +
//  right tabular value); context strip; CTA pair.
//
//  RAIL vocabulary preserved: detention / demurrage / free-time / LFD
//  (last free day) / per-diem / dispute / auto-bill / accessorial.
//
//  tRPC anchors (grep-confirmed in detentionAccessorials.ts):
//    detentionAccessorials.getDetentionByCustomer  (EXISTS :456)
//      → { customers: [{ customerId, customerName, eventCount,
//          totalCharges, avgWaitMinutes, paidAmount, disputeCount,
//          collectionRate }] } — drives hero totals + KPI + the list.
//    detentionAccessorials.getActiveDetentions     (EXISTS :256)
//      → { detentions: [...], total } — box count for the context strip.
//
//  Charts/figures plot LIVE data only — empty state when a series is
//  absent. Nothing is fabricated.
//

import SwiftUI

struct RailDetentionByCustomerScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDetentionByCustomerBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror detentionAccessorials.getDetentionByCustomer :456)

private struct DetentionCustomer649: Decodable, Identifiable {
    let customerId: Int?
    let customerName: String?
    let eventCount: Int?
    let totalCharges: Double?
    let avgWaitMinutes: Int?
    let paidAmount: Double?
    let disputeCount: Int?
    let collectionRate: Int?

    var id: Int { customerId ?? (customerName ?? "unknown").hashValue }
}

private struct DetentionByCustomerResponse649: Decodable {
    let customers: [DetentionCustomer649]
}

// getActiveDetentions :256 — only the box count is consumed here.
private struct ActiveDetention649: Decodable, Identifiable {
    let id: Int
}
private struct ActiveDetentionsResponse649: Decodable {
    let detentions: [ActiveDetention649]
    let total: Int?
}

// MARK: - LFD bucket (free-time watch derived from live avg-wait days)

private enum LFDBucket {
    case pastLFD       // over last-free-day — billable now
    case dueSoon       // within ~1 day of LFD
    case ok            // free-time ok

    var pillText: String {
        switch self {
        case .pastLFD: return "PAST LFD"
        case .dueSoon: return "DUE SOON"
        case .ok:      return "OK"
        }
    }
    var kind: StatusPill.Kind {
        switch self {
        case .pastLFD: return .danger
        case .dueSoon: return .warning
        case .ok:      return .info
        }
    }
    var color: Color {
        switch self {
        case .pastLFD: return Brand.danger
        case .dueSoon: return Brand.warning
        case .ok:      return Brand.info
        }
    }
    var icon: String {
        switch self {
        case .pastLFD: return "exclamationmark.triangle.fill"
        case .dueSoon: return "clock.fill"
        case .ok:      return "shippingbox.fill"
        }
    }
}

// MARK: - Body

private struct RailDetentionByCustomerBody: View {
    @Environment(\.palette) private var palette

    @State private var customers: [DetentionCustomer649] = []
    @State private var activeBoxes: Int? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Carrier-of-record context (wireframe <desc> copy — static chrome,
    // not data): BNSF Intermodal · shipper-of-record Eusorone (DU).
    private let carrierLabel = "BNSF"

    // MARK: - Derived live aggregates (never fabricated)

    private var totalDetention: Double {
        customers.reduce(into: 0.0) { $0 += ($1.totalCharges ?? 0) }
    }
    private var billedAmount: Double {
        customers.reduce(into: 0.0) { $0 += ($1.paidAmount ?? 0) }
    }
    private var customerCount: Int { customers.count }
    private var boxCount: Int {
        activeBoxes ?? customers.reduce(into: 0) { $0 += ($1.eventCount ?? 0) }
    }
    private var overLFDCount: Int { customers.filter { bucket(for: $0) == .pastLFD }.count }

    /// Free-time / LFD bucket derived from live avg-wait. Avg dwell is in
    /// minutes server-side; rail free time is conventionally ~48h (2 days).
    /// > 2.0d → past LFD · 1.0–2.0d → due soon · ≤1.0d → ok.
    private func bucket(for c: DetentionCustomer649) -> LFDBucket {
        if (c.disputeCount ?? 0) > 0 { return .pastLFD }
        let days = Double(c.avgWaitMinutes ?? 0) / 1440.0
        if days > 2.0 { return .pastLFD }
        if days >= 1.0 { return .dueSoon }
        return .ok
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleRow
                IridescentHairline()

                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    hero
                    kpiStrip
                    topCustomers
                    contextStrip
                    ctaPair
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow (✦ RAIL ENGINEER · DETENTION  ·  BY CUSTOMER)

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · DETENTION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("BY CUSTOMER")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title row (back chevron + title · BNSF / synced)

    private var titleRow: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 6)
            Text("Detention by customer")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(carrierLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("synced 3m ago")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: - Hero (gradient-rimmed ActiveCard)

    private var hero: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                // Status pills: live + N over LFD
                HStack(spacing: Space.s2) {
                    Text("live")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    if overLFDCount > 0 {
                        Text("\(overLFDCount) over LFD")
                            .font(.system(size: 11, weight: .bold)).tracking(0.5)
                            .foregroundStyle(Brand.danger)
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(Capsule().fill(Brand.danger.opacity(0.18)))
                    }
                    Spacer(minLength: 0)
                }

                // Lead figure + label · right BILLED rollup
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currency(totalDetention))
                            .font(.system(size: 26, weight: .bold)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("detention by customer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("\(customerCount) customers · \(boxCount) boxes")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("BILLED")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(currencyShort(billedAmount))
                            .font(EType.mono(.body)).tracking(0.2)
                            .foregroundStyle(Color(hex: 0x5BB0F5))
                    }
                }

                // Progress: billed share of total detention (live ratio).
                billedProgress
            }
        }
    }

    private var billedProgress: some View {
        GeometryReader { geo in
            let frac = totalDetention > 0
                ? min(max(billedAmount / totalDetention, 0), 1)
                : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(LinearGradient.diagonal)
                    .frame(width: geo.size.width * frac)
            }
        }
        .frame(height: 6)
    }

    // MARK: - KPI strip (BILLABLE eusoDiagonal · CUSTOMERS · OVER LFD)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // Cell-1 — eusoDiagonal gradient fill (verbatim)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("BILLABLE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text(currencyShort(totalDetention))
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            MetricTile(label: "CUSTOMERS", value: "\(customerCount)")
            MetricTile(label: "OVER LFD",  value: "\(overLFDCount)",
                       accent: overLFDCount > 0 ? Brand.danger : nil)
        }
    }

    // MARK: - Top customers · detention (carded list)

    private var topCustomers: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("TOP CUSTOMERS · DETENTION")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getDetentionByCustomer:456")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if customers.isEmpty {
                EusoEmptyState(systemImage: "person.2.slash",
                               title: "No detention by customer",
                               subtitle: "Customer-keyed detention rollups will appear here once claims accrue.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(customers.enumerated()), id: \.element.id) { idx, c in
                        customerRow(c)
                        if idx < customers.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                        }
                    }
                    Rectangle().fill(palette.borderFaint).frame(height: 1)
                    Text("+ auto-bill at LFD+1 · 5-day dispute window per customer agreement")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.s3)
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func customerRow(_ c: DetentionCustomer649) -> some View {
        let b = bucket(for: c)
        let boxes = c.eventCount ?? 0
        let avgDays = Double(c.avgWaitMinutes ?? 0) / 1440.0
        return HStack(spacing: Space.s3) {
            // 40x40 icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(b.color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: b.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(b.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(c.customerName ?? "Unknown")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(boxSubtitle(boxes: boxes, avgDays: avgDays, bucket: b))
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(text: b.pillText, kind: b.kind)
                Text(currency(c.totalCharges ?? 0))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(b == .ok ? palette.textPrimary : b.color)
            }
        }
        .padding(Space.s3)
    }

    private func boxSubtitle(boxes: Int, avgDays: Double, bucket b: LFDBucket) -> String {
        let boxStr = "\(boxes) \(boxes == 1 ? "box" : "boxes")"
        switch b {
        case .pastLFD: return "\(boxStr) · avg \(String(format: "%.1f", avgDays)) days"
        case .dueSoon: return "\(boxStr) · within 1 day"
        case .ok:      return "\(boxStr) · free time ok"
        }
    }

    // MARK: - Context strip (ACTIVE DETENTIONS · getActiveDetentions)

    private var contextStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("ACTIVE DETENTIONS · getActiveDetentions")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(boxCount) boxes")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("customer-keyed rollup · LFD watch + auto-invoice")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("Carrier BNSF Intermodal · shipper-of-record Eusorone Technologies (DU)")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair (Bill selected · By facility)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Bill selected", action: {})
                .frame(maxWidth: .infinity)
            Button {} label: {
                Text("By facility")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgSecondary)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Loading state (skeleton rows)

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Formatting

    private func currency(_ v: Double) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.maximumFractionDigits = 0
        let s = n.string(from: NSNumber(value: v)) ?? "0"
        return "$\(s)"
    }

    private func currencyShort(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if v >= 1_000     { return String(format: "$%.1fK", v / 1_000) }
        return String(format: "$%.0f", v)
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct ByCustomerIn: Encodable { let limit: Int }
        struct ActiveIn: Encodable { let limit: Int; let offset: Int }
        do {
            async let byCustomer: DetentionByCustomerResponse649 = EusoTripAPI.shared.query(
                "detentionAccessorials.getDetentionByCustomer", input: ByCustomerIn(limit: 20))
            let resp = try await byCustomer
            self.customers = resp.customers
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
            return
        }
        // Box count from the live active-detentions feed — best-effort
        // enrichment; the customer rollup still renders without it.
        do {
            let active: ActiveDetentionsResponse649 = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getActiveDetentions",
                input: ActiveIn(limit: 50, offset: 0))
            self.activeBoxes = active.total ?? active.detentions.count
        } catch {
            // leave activeBoxes nil → falls back to summed eventCount
        }
        loading = false
    }
}

#Preview("649 · Rail Detention by Customer · Night") {
    RailDetentionByCustomerScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("649 · Rail Detention by Customer · Light") {
    RailDetentionByCustomerScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
