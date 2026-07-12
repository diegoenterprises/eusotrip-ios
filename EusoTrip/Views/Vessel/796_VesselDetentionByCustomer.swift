//
//  796_VesselDetentionByCustomer.swift
//  EusoTrip — Vessel Operator · Detention by Customer (CUSTOMER-SHARE archetype).
//
//  Faithful port of "796 Vessel Detention by Customer.svg" (Dark + Light). Shows
//  which shipper-of-record drives the most detention spend and who is slow to pay:
//  a total-spend headline, a donut share-of-spend card with a right-hand legend,
//  and a customer ledger built on INITIALS DISCS (not container chips) with an
//  events / avg-dwell sub, the charge, and a collection-rate read — so the operator
//  targets statements and credit terms at the customers actually leaking cash.
//
//  Nav: Shell + BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME), COMPLIANCE inked.
//
//  REAL WIRING (tRPC · server/routers/detentionAccessorials.ts):
//    · detentionAccessorials.getDetentionByCustomer  {dateFrom?, dateTo?, limit}
//        -> { customers:[{customerId, customerName, eventCount, totalCharges,
//              avgWaitMinutes, paidAmount, disputeCount, collectionRate}] }  (:1028)
//        catalystId-scoped (carrier-of-record view). Donut segment = totalCharges
//        share; ledger amount = totalCharges; sub = eventCount + avgWaitMinutes;
//        disc = customerName initials; collection = collectionRate.
//    · "View all customers" re-queries with a larger limit (paged in place).
//    · "Export" composes a customer statement CSV from the LIVE rows and opens the
//        native share sheet (server exportCustomerStatement is a NAMED GAP; the
//        client CSV is the honest interim — never a dead tap).
//
//  RBAC: getDetentionByCustomer protectedProcedure, catalystId-scoped. transportMode=
//  vessel · USD. COUNTRY-DONE: a billing-regime strip by shipper country — US FMC
//  46 CFR 541 (net terms · USD) active / CA CTA storage (CAD) · MX SAT estadías (MXN)
//  standby. NO mock data — every disc, share and dollar derives from a live row.
//

import SwiftUI
import UIKit

struct VesselDetentionByCustomerScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselDetentionByCustomerBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct DetentionByCustomerResult796: Decodable {
    let customers: [DetentionCustomer796]
}

private struct DetentionCustomer796: Decodable, Identifiable {
    var id: Int { customerId ?? customerName.hashValue }
    let customerId: Int?
    let customerName: String
    let eventCount: Int?
    let totalCharges: Double?
    let avgWaitMinutes: Int?
    let paidAmount: Double?
    let disputeCount: Int?
    let collectionRate: Int?
}

// MARK: - Body

private struct VesselDetentionByCustomerBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.vesselOperatorNavHandler) private var navHandler

    @State private var customers: [DetentionCustomer796] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var showAll = false
    @State private var exportDoc: ShareDoc796? = nil

    /// Segment palette — assigned by rank; ties into the donut + legend swatch.
    private let segColors: [Color] = [Brand.info, Color(hex: 0xC26AD6), Brand.warning, Brand.neutral]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                IridescentHairline().padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        errorCard(err)
                    } else {
                        shareCard
                        ledgerSection
                        billingRegimeStrip
                        ctaRow
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.top, Space.s5)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $exportDoc) { doc in ActivityShareSheet796(items: [doc.url]) }
    }

    // MARK: Header (eyebrow + breadcrumb + total-spend hero)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Text("✦").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("VESSEL OPERATOR · BY CUSTOMER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("SHARE · 30D").font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Button { navHandler?("Compliance") } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text("Compliance").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain).padding(.top, Space.s2)

            Text(money(totalSpend, compact: false))
                .font(.system(size: 34, weight: .bold, design: .monospaced)).tracking(-0.6)
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.top, Space.s3)
            Text("by shipper-of-record · \(customers.count) customer\(customers.count == 1 ? "" : "s") · 30 days")
                .font(EType.caption).foregroundStyle(palette.textSecondary).padding(.top, 2)
        }
    }

    // MARK: Donut share card

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("SHARE OF DETENTION SPEND")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .center, spacing: Space.s5) {
                DonutShare796(segments: donutSegments, centerTop: "\(customers.count)", centerBottom: "CUSTOMERS")
                    .frame(width: 108, height: 108)
                VStack(alignment: .leading, spacing: Space.s3) {
                    ForEach(Array(legendRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: Space.s2) {
                            RoundedRectangle(cornerRadius: 3).fill(row.color)
                                .frame(width: 11, height: 11)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name).font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                                Text("\(row.pct)% · \(money(row.amount, compact: true))")
                                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: Customer ledger (initials disc + collection rate)

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("BY CUSTOMER · COLLECTION RATE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if customers.isEmpty {
                EusoEmptyState(systemImage: "person.2",
                               title: "No customer detention",
                               subtitle: "Detention spend by shipper-of-record appears here once dwells close and bill.")
            } else {
                VStack(spacing: 0) {
                    let shown = Array(customers.prefix(showAll ? customers.count : 5))
                    ForEach(Array(shown.enumerated()), id: \.element.id) { idx, c in
                        customerRow(c, rank: idx)
                        if idx < shown.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            }
        }
    }

    private func customerRow(_ c: DetentionCustomer796, rank: Int) -> some View {
        let accent = segColors[min(rank, segColors.count - 1)]
        let rate = c.collectionRate ?? 0
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(accent.opacity(0.18)).frame(width: 40, height: 40)
                Text(initials(c.customerName))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(c.customerName).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("\(c.eventCount ?? 0) events · avg \(dwell(c.avgWaitMinutes ?? 0))")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 3) {
                Text(money(c.totalCharges ?? 0, compact: false))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Text("\(rate)% collected")
                    .font(EType.mono(.micro))
                    .foregroundStyle(collectionColor(rate))
            }
        }
        .padding(Space.s4)
    }

    // MARK: Billing regime strip

    private var billingRegimeStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("BILLING REGIME · BY SHIPPER COUNTRY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("US ACTIVE").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("US · FMC 46 CFR 541")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.info)
                    Text("billing rule · net terms · USD")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.info.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.info.opacity(0.28)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("CA · CTA storage · CAD")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("MX · SAT estadías · MXN")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { withAnimation(.easeOut(duration: 0.18)) { showAll.toggle() } } label: {
                Text(showAll ? "Show top 5" : "View all customers")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(customers.isEmpty)
            .opacity(customers.isEmpty ? 0.6 : 1.0)

            Button { exportStatement() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 12, weight: .bold))
                    Text("Export").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(palette.textPrimary)
                .frame(minWidth: 116, minHeight: 48)
                .padding(.horizontal, Space.s3)
                .background(palette.bgCard)
                .overlay(Capsule().strokeBorder(palette.borderFaint))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(customers.isEmpty)
            .opacity(customers.isEmpty ? 0.6 : 1.0)
        }
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 158)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 240)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    private func errorCard(_ err: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Derived

    private var totalSpend: Double { customers.reduce(0) { $0 + ($1.totalCharges ?? 0) } }

    private var donutSegments: [(share: Double, color: Color)] {
        guard totalSpend > 0 else { return [] }
        // Top 3 discrete + an aggregated "others" tail so the donut stays legible.
        let sorted = customers.sorted { ($0.totalCharges ?? 0) > ($1.totalCharges ?? 0) }
        var segs: [(Double, Color)] = []
        for (i, c) in sorted.prefix(3).enumerated() {
            segs.append(((c.totalCharges ?? 0) / totalSpend, segColors[min(i, segColors.count - 1)]))
        }
        let othersAmt = sorted.dropFirst(3).reduce(0) { $0 + ($1.totalCharges ?? 0) }
        if othersAmt > 0 { segs.append((othersAmt / totalSpend, Brand.neutral)) }
        return segs
    }

    private struct LegendRow796 { let name: String; let pct: Int; let amount: Double; let color: Color }

    private var legendRows: [LegendRow796] {
        guard totalSpend > 0 else { return [] }
        let sorted = customers.sorted { ($0.totalCharges ?? 0) > ($1.totalCharges ?? 0) }
        var rows: [LegendRow796] = []
        for (i, c) in sorted.prefix(3).enumerated() {
            let amt = c.totalCharges ?? 0
            rows.append(LegendRow796(name: c.customerName, pct: Int((amt / totalSpend * 100).rounded()),
                                     amount: amt, color: segColors[min(i, segColors.count - 1)]))
        }
        let othersCount = max(sorted.count - 3, 0)
        let othersAmt = sorted.dropFirst(3).reduce(0) { $0 + ($1.totalCharges ?? 0) }
        if othersCount > 0 {
            rows.append(LegendRow796(name: "Others (\(othersCount))", pct: Int((othersAmt / totalSpend * 100).rounded()),
                                     amount: othersAmt, color: Brand.neutral))
        }
        return rows
    }

    private func initials(_ name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    private func dwell(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 { return "\(h)h \(String(format: "%02dm", m))" }
        return "\(m)m"
    }

    private func collectionColor(_ rate: Int) -> Color {
        if rate >= 85 { return Brand.success }
        if rate >= 70 { return Brand.warning }
        return Brand.danger
    }

    private func money(_ v: Double, compact: Bool) -> String {
        if compact {
            if abs(v) >= 1000 { return "$\(String(format: "%.1f", v / 1000))K" }
            return "$\(Int(v))"
        }
        if v == v.rounded() { return "$\(Int(v).formatted(.number.grouping(.automatic)))" }
        return "$\(String(format: "%.2f", v))"
    }

    // MARK: - Actions

    private func load() async {
        loading = true; loadError = nil
        struct ByCustomerIn: Encodable { let limit: Int }
        do {
            let res: DetentionByCustomerResult796 = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getDetentionByCustomer",
                input: ByCustomerIn(limit: showAll ? 100 : 20))
            self.customers = res.customers
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func exportStatement() {
        guard !customers.isEmpty else { return }
        var csv = "customer,events,avg_wait_minutes,total_charges_usd,paid_usd,disputes,collection_rate_pct\n"
        for c in customers {
            let name = c.customerName.replacingOccurrences(of: ",", with: " ")
            csv += "\(name),\(c.eventCount ?? 0),\(c.avgWaitMinutes ?? 0),"
            csv += "\(String(format: "%.2f", c.totalCharges ?? 0)),\(String(format: "%.2f", c.paidAmount ?? 0)),"
            csv += "\(c.disputeCount ?? 0),\(c.collectionRate ?? 0)\n"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("detention-by-customer-\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.data(using: .utf8)?.write(to: url)
            exportDoc = ShareDoc796(url: url)
        } catch {
            loadError = "Couldn't compose the customer statement."
        }
    }
}

// MARK: - Donut

private struct DonutShare796: View {
    let segments: [(share: Double, color: Color)]
    let centerTop: String
    let centerBottom: String
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            Circle().stroke(palette.borderFaint, lineWidth: 16)
            ForEach(Array(cumulative.enumerated()), id: \.offset) { _, seg in
                Circle()
                    .trim(from: seg.start, to: seg.end)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                Text(centerTop)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Text(centerBottom)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var cumulative: [(start: CGFloat, end: CGFloat, color: Color)] {
        var out: [(CGFloat, CGFloat, Color)] = []
        var acc: CGFloat = 0
        for s in segments {
            let start = acc
            let end = acc + CGFloat(max(0, s.share))
            out.append((start, min(end, 1), s.color))
            acc = end
        }
        return out
    }
}

// MARK: - Share plumbing

private struct ShareDoc796: Identifiable { let id = UUID(); let url: URL }

private struct ActivityShareSheet796: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview("796 · Vessel Detention by Customer · Night") {
    VesselDetentionByCustomerScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("796 · Vessel Detention by Customer · Light") {
    VesselDetentionByCustomerScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
