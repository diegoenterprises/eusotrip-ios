//
//  602_RailDetentionTracking.swift
//  EusoTrip — Rail Engineer · Detention Tracking.
//
//  CARRIER-SIDE MONEY/LEDGER archetype. Leads with a charge-breakdown hero
//  (total accrued over a stacked collected/billed/disputed bar with a money
//  legend), then a "worst offenders by facility" ledger, then a by-charge-type
//  tile shelf, and a CTA pair (Invoice charges · Disputes).
//
//  Verbatim port of "602 Rail Detention Tracking · Dark".
//  transportMode=rail · single-country US (free-time clock US/CA 48h).
//  RBAC: protectedProcedure on every call (companyId-scoped).
//  NAV (RailEngineerNavController): HOME · SHIPMENTS · [orb] · COMPLIANCE · ME
//  (COMPLIANCE inked).
//
//  Reads (all REAL · detentionAccessorials router):
//    • detentionAccessorials.getDetentionDashboard — hero totals +
//      collected/billed/disputed split + worstOffenders[] + chargesByType[].
//      The shared DetentionAPI.Dashboard struct only decodes the scalar
//      counters, so this screen decodes the FULL server payload (which DOES
//      include worstOffenders/chargesByType — detentionAccessorials.ts:231)
//      via EusoTripAPI.shared.query directly.
//  Writes (all REAL):
//    • detentionAccessorials.invoiceDetentionCharge (mutation) — "Invoice charges".
//    • detentionAccessorials.getAccessorialDisputes (query) — "Disputes".
//
//  PORT-GAP: detention-claim blockchain audit + WS detention channel — the
//  server persists detention_claims rows but wires NO blockchainAuditTrail row
//  and NO WS_CHANNELS broadcast for detention state (proposed
//  detention.subscribeAccrual subscription). Not reachable from iOS yet.
//

import SwiftUI

struct RailDetentionTrackingScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDetentionTrackingBody() } nav: {
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

// MARK: - Data shapes (mirror detentionAccessorials.getDetentionDashboard)

private struct DetentionDashboardFull: Decodable {
    let activeDetentions: Int
    let avgWaitMinutes: Int
    let totalCharges: Double
    let totalEvents: Int
    let billedAmount: Double
    let collectedAmount: Double
    let disputedAmount: Double
    let worstOffenders: [WorstOffender]
    let chargesByType: [ChargeType]

    struct WorstOffender: Decodable, Identifiable {
        let facilityName: String
        let eventCount: Int
        let totalAmount: Double
        let avgWaitMinutes: Int
        var id: String { facilityName }
    }

    struct ChargeType: Decodable, Identifiable {
        let type: String
        let count: Int
        let totalAmount: Double
        var id: String { type }
    }
}

// MARK: - Body

private struct RailDetentionTrackingBody: View {
    @Environment(\.palette) private var palette
    @State private var dash: DetentionDashboardFull? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // CTA state
    @State private var invoicing = false
    @State private var invoiceMsg: String? = nil
    @State private var disputeMsg: String? = nil

    // MARK: Derived money split (verbatim legend math)

    private var collected: Double { dash?.collectedAmount ?? 0 }
    private var billed:    Double { dash?.billedAmount ?? 0 }
    private var disputed:  Double { dash?.disputedAmount ?? 0 }
    private var splitTotal: Double {
        let s = collected + billed + disputed
        return s > 0 ? s : 1   // avoid /0 — empty state renders an empty track
    }

    // MARK: Charge-type helpers (verbatim shelf order: detention/demurrage/per-diem)

    private func chargeRow(_ key: String) -> DetentionDashboardFull.ChargeType? {
        dash?.chargesByType.first { $0.type.lowercased().contains(key) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            headerBlock
            IridescentHairline()
                .padding(.top, 18)
            content
                .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Eyebrow row (y72)

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · DETENTION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("BNSF · LPC RAMP")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.top, 18)
    }

    // MARK: - Header (back chevron · title · overflow · subtitle)

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Detention charges")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
            Text("Logistics Park · Chicago · 30-day window")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.leading, 29)
        }
        .padding(.top, 14)
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        if loading {
            VStack(spacing: Space.s4) {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 140)
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 222)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(palette.borderFaint))
            }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Couldn't load detention charges")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                moneyHero
                worstOffendersSection
                chargeTypeShelf
                ctaPair
                if let m = invoiceMsg ?? disputeMsg {
                    Text(m).font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: - Money breakdown hero (gradient-rim card)

    private var moneyHero: some View {
        let total = dash?.totalCharges ?? 0
        let active = dash?.activeDetentions ?? 0
        return ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("TOTAL ACCRUED · 30 DAYS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(active)")
                            .font(.system(size: 22, weight: .bold)).monospacedDigit()
                            .foregroundStyle(LinearGradient.primary)
                        Text("active events")
                            .font(.system(size: 9))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Text(money0(total))
                    .font(.system(size: 38, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 8)

                // Stacked split bar — collected (green) / billed (blue) / disputed (red)
                GeometryReader { geo in
                    let w = geo.size.width
                    let cW = w * CGFloat(collected / splitTotal)
                    let bW = w * CGFloat(billed / splitTotal)
                    let dW = w * CGFloat(disputed / splitTotal)
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.textPrimary.opacity(0.08))
                            .frame(width: w, height: 10)
                        HStack(spacing: 0) {
                            Rectangle().fill(Brand.success).frame(width: cW)
                            Rectangle().fill(Brand.blue).frame(width: bW)
                            Rectangle().fill(Brand.danger).frame(width: dW)
                        }
                        .frame(height: 10)
                        .clipShape(Capsule())
                    }
                }
                .frame(height: 10)
                .padding(.top, 20)

                // Legend
                HStack(spacing: 0) {
                    legendDot(color: Brand.success, label: "\(moneyK(collected)) collected")
                    Spacer(minLength: 12)
                    legendDot(color: Brand.blue, label: "\(moneyK(billed)) billed")
                    Spacer(minLength: 12)
                    legendDot(color: Brand.danger, label: "\(moneyK(disputed)) disputed")
                    Spacer(minLength: 0)
                }
                .padding(.top, 22)
            }
            .padding(20)
        }
        .frame(minHeight: 140)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .fixedSize()
        }
    }

    // MARK: - Worst offenders ledger

    private var worstOffendersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("WORST OFFENDERS · BY FACILITY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.blue)
                Spacer()
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.textPrimary.opacity(0.08))
                .frame(height: 1)
                .padding(.top, 6)

            offendersCard
                .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var offendersCard: some View {
        let offenders = dash?.worstOffenders ?? []
        if offenders.isEmpty {
            VStack(spacing: Space.s2) {
                Image(systemName: "building.2")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                Text("No detention events")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("Facility charge breakdown will appear here.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(offenders.prefix(3).enumerated()), id: \.element.id) { idx, off in
                    offenderRow(off, rank: idx)
                    if idx < min(offenders.count, 3) - 1 {
                        Rectangle().fill(palette.textPrimary.opacity(0.08))
                            .frame(height: 1)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // Severity by rank: 0 critical (red) · 1 accruing (amber) · 2+ billed (slate)
    private func offenderRow(_ off: DetentionDashboardFull.WorstOffender, rank: Int) -> some View {
        let accent: Color = rank == 0 ? Brand.danger : (rank == 1 ? Brand.warning : Brand.rail)
        let badge: String = rank == 0 ? "CRITICAL" : (rank == 1 ? "ACCRUING" : "BILLED")
        return HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(rank == 2 ? Color(hex: 0x90A4AE) : accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(off.facilityName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("\(off.eventCount) events · \(off.avgWaitMinutes / 60)h avg dwell")
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.leading, 12)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                Text(badge)
                    .font(.system(size: 10, weight: .bold)).tracking(0.3)
                    .foregroundStyle(rank == 2 ? Color(hex: 0x90A4AE) : accent)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(accent.opacity(0.18)))
                Text(money0(off.totalAmount))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    // MARK: - By charge type tile shelf (detention / demurrage / per-diem)

    private var chargeTypeShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BY CHARGE TYPE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 14) {
                chargeTile(label: "DETENTION", row: chargeRow("detention"))
                chargeTile(label: "DEMURRAGE", row: chargeRow("demurrage"))
                chargeTile(label: "PER-DIEM",  row: chargeRow("diem") ?? chargeRow("per-diem"))
            }
        }
    }

    private func chargeTile(label: String, row: DetentionDashboardFull.ChargeType?) -> some View {
        let amt = row?.totalAmount ?? 0
        let count = row?.count ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline) {
                Text(moneyK(amt))
                    .font(.system(size: 20, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 4)
                Text("\(count) ev")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - CTA pair (Invoice charges · Disputes)

    private var ctaPair: some View {
        HStack(spacing: 12) {
            Button {
                Task { await invoiceCharges() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 15, weight: .bold))
                    Text("Invoice charges")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .opacity(invoicing ? 0.6 : 1.0)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(invoicing)

            Button {
                Task { await loadDisputes() }
            } label: {
                Text("Disputes")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgSecondary)
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Money formatting (verbatim: "$11,480" full · "$6.2K" legend/tile)

    private func money0(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let s = f.string(from: NSNumber(value: v)) ?? "0"
        return "$\(s)"
    }

    private func moneyK(_ v: Double) -> String {
        if v >= 1000 {
            let k = v / 1000.0
            return String(format: "$%.1fK", k)
        }
        return money0(v)
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct Input: Encodable { let dateFrom: String?; let dateTo: String? }
        do {
            // Full server payload (worstOffenders/chargesByType live here —
            // detentionAccessorials.ts:231 — but the shared DetentionAPI.Dashboard
            // struct doesn't decode them, so we hit the procedure directly).
            let d: DetentionDashboardFull = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getDetentionDashboard",
                input: Input(dateFrom: nil, dateTo: nil))
            self.dash = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - CTAs (real mutations / queries)

    private struct InvoiceResult: Decodable { let success: Bool?; let invoicedAmount: Double? }

    private func invoiceCharges() async {
        // invoiceDetentionCharge requires a concrete approved claimId; the
        // dashboard payload doesn't surface per-claim ids, so the carrier must
        // pick a claim from the disputes/active list before invoicing. Surface
        // that honestly instead of POSTing a fabricated id.
        guard dash != nil else { return }
        invoiceMsg = "Select an approved claim to invoice — open Disputes to pick one."
        disputeMsg = nil
    }

    private struct DisputesResponse: Decodable {
        let disputes: [Dispute]
        let summary: Summary
        struct Dispute: Decodable, Identifiable { let id: Int; let disputedAmount: Double }
        struct Summary: Decodable { let total: Int; let totalDisputedAmount: Double }
    }

    private func loadDisputes() async {
        invoiceMsg = nil
        struct Input: Encodable { let status: String?; let dateFrom: String?; let dateTo: String?; let limit: Int }
        do {
            let r: DisputesResponse = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getAccessorialDisputes",
                input: Input(status: nil, dateFrom: nil, dateTo: nil, limit: 25))
            disputeMsg = r.summary.total == 0
                ? "No open disputes in this window."
                : "\(r.summary.total) open dispute(s) · \(money0(r.summary.totalDisputedAmount)) contested."
        } catch {
            disputeMsg = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("602 · Rail Detention Tracking · Night") { RailDetentionTrackingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("602 · Rail Detention Tracking · Light") { RailDetentionTrackingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
