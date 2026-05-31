//
//  645_RailDetentionDashboard.swift
//  EusoTrip — Rail Engineer · Detention Dashboard (Dark · verbatim port of
//  "645 Rail Detention Dashboard.svg").
//
//  ARCHETYPE = RANKED LEADERBOARD: a summary band hero, then a worst-first
//  leaderboard where each row carries a rank disc + customer + mono sub + a
//  proportional dwell bar + right tabular $. Bars make the spread scannable;
//  rank discs (#1 gradient) make the offender obvious.
//
//  WIRING (verified against frontend/server/routers/railDemurrageAuto.ts):
//    • Hero summary band  → railDemurrageAuto.dashboard            (EXISTS · :18)
//    • Open disputes CTA  → railDemurrageAuto.createDispute        (EXISTS · :78)
//    • Per-customer rank  → railDemurrageAuto.detentionByCustomer  (DOES NOT EXIST)
//        The desc proposes detentionByCustomer(input:{window:'30d'}) ->
//        {customer,cars,avgDwellHrs,amountUsd}[] sorted desc — there is NO such
//        procedure on the router today. We render a real empty state for the
//        leaderboard and DO NOT fabricate rows.  See // PORT-GAP below.
//
//  RBAC: protectedProcedure (rail carrier scope) · transportMode=rail ·
//  country US · currency USD · US 48h free clock per calculateAccrual.
//  NAV (RailEngineerNavController): HOME · SHIPMENTS · [orb] · COMPLIANCE · ME,
//  current = SHIPMENTS.
//

import SwiftUI

struct RailDetentionDashboardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDetentionDashboardBody() } nav: {
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

// MARK: - Data shapes (mirror railDemurrageAuto.ts return shapes)

/// `railDemurrageAuto.dashboard` (no input). Summary band hero source.
private struct RailDemurrageDashboard: Decodable {
    struct Summary: Decodable {
        let activeAccruals: Int?
        let totalChargesAccruing: Double?
        let disputesOpen: Int?
        let waiversPending: Int?
    }
    let summary: Summary?
    let topDwellReasons: [DwellReasonRow]?
    let costliestYards: [CostliestYard]?
    let note: String?
}

private struct DwellReasonRow: Decodable {
    let reason: String?
    let count: Int?
    let totalCharges: Double?
    let avgHours: Double?
}

private struct CostliestYard: Decodable {
    let yard: String?
    let totalCharges: Double?
    let cars: Int?
}

/// PROPOSED shape for the missing `detentionByCustomer` endpoint — declared
/// so the leaderboard can decode the moment the procedure ships, without a
/// follow-up port. Until then the array stays empty (real empty state).
private struct DetentionCustomerRow: Decodable, Identifiable {
    let customer: String?
    let cars: Int?
    let avgDwellHrs: Double?
    let amountUsd: Double?
    var id: String { customer ?? UUID().uuidString }
}

/// `railDemurrageAuto.createDispute` (mutation) result.
private struct CreateDisputeResult: Decodable {
    let disputeId: String?
    let status: String?
    let reason: String?
    let requestedWaiver: Double?
}

// MARK: - Body

private struct RailDetentionDashboardBody: View {
    @Environment(\.palette) private var palette

    @State private var dashboard: RailDemurrageDashboard? = nil
    @State private var customers: [DetentionCustomerRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var disputeBusy = false
    @State private var ack: String? = nil

    // Derived hero values (LIVE — never fabricated).
    private var totalDollars: Double { dashboard?.summary?.totalChargesAccruing ?? 0 }
    private var customerCount: Int { customers.count }
    private var carsHeldOver: Int {
        customers.reduce(into: 0) { acc, r in acc += (r.cars ?? 0) }
    }
    private var topOffender: DetentionCustomerRow? {
        customers.max { ($0.amountUsd ?? 0) < ($1.amountUsd ?? 0) }
    }
    private var topOffenderPct: Int {
        guard let top = topOffender, totalDollars > 0 else { return 0 }
        return Int(((top.amountUsd ?? 0) / totalDollars * 100).rounded())
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleBlock
                IridescentHairline()
                    .padding(.top, Space.s3)

                if loading {
                    loadingState
                        .padding(.top, Space.s5)
                } else if let err = loadError {
                    LifecycleErrorCard(message: err)
                        .padding(.top, Space.s5)
                } else {
                    heroBand
                        .padding(.top, Space.s5)
                    leaderboard
                        .padding(.top, Space.s5)
                    actionRow
                        .padding(.top, Space.s5)
                    if let ack {
                        Text(ack)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .padding(.top, Space.s2)
                    }
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow  (✦ RAIL ENGINEER · DETENTION  ·  30-DAY)

    private var eyebrow: some View {
        HStack {
            Text("✦ RAIL ENGINEER · DETENTION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("30-DAY")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title  (chevron · "Detention board" · 12 ACCTS / ranked desc)

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 6)
            Text("Detention board")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(customerCount) ACCTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("ranked desc")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 2)
        }
        .padding(.top, Space.s4)
    }

    // MARK: - Hero · summary band (gradient-rim card)

    private var heroBand: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(Color(hex: 0x1C2128))
                .padding(1.5)

            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("TOTAL DETENTION · 30D")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(dollarString(totalDollars))
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                        .padding(.top, 6)
                    Text("\(customerCount) customers · \(carsHeldOver) cars held over free time")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, 6)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("TOP OFFENDER")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(topOffender?.customer ?? "—")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0xFF7A66))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(topOffender == nil ? "no data" : "\(topOffenderPct)% of $")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(Space.s5)
        }
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92)
    }

    // MARK: - Leaderboard

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("WORST FIRST · BY CUSTOMER")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("detentionByCustomer")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }

            // PORT-GAP — railDemurrageAuto.detentionByCustomer does NOT exist
            // on the router (only dashboard / reportByDwellReason / createDispute
            // ship today). We refuse to fabricate ranked rows; until the
            // proposed procedure lands we render the real empty state.
            if customers.isEmpty {
                emptyLeaderboard
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rankedCustomers.enumerated()), id: \.element.id) { idx, row in
                        leaderboardRow(rank: idx + 1, row: row,
                                       maxDollars: maxDollars)
                        if idx < rankedCustomers.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                    }
                    Text("ranked desc by detention $ · cars within free time carry no charge")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .background(Color(hex: 0x1C2128))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06)))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var rankedCustomers: [DetentionCustomerRow] {
        customers.sorted { ($0.amountUsd ?? 0) > ($1.amountUsd ?? 0) }
    }

    private var maxDollars: Double {
        max(rankedCustomers.first?.amountUsd ?? 0, 1)
    }

    private var emptyLeaderboard: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            EusoEmptyState(
                icon: Image(systemName: "list.number"),
                title: "Per-customer ranking not available",
                subtitle: "The detention leaderboard needs railDemurrageAuto.detentionByCustomer, which isn't on the API yet. Dwell totals above are live from railDemurrageAuto.dashboard.",
                comingSoon: true
            )
            if let reasons = dashboard?.topDwellReasons, !reasons.isEmpty {
                dwellReasonFallback(reasons)
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity)
        .background(Color(hex: 0x1C2128))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Live secondary read that DOES exist — top dwell reasons from the
    /// dashboard. Shown only when the customer ranking is unavailable so the
    /// engineer still gets a real, server-sourced breakdown.
    private func dwellReasonFallback(_ reasons: [DwellReasonRow]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("TOP DWELL REASONS · LIVE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            ForEach(Array(reasons.enumerated()), id: \.offset) { _, r in
                HStack {
                    Text((r.reason ?? "—").replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(r.count ?? 0) · \(dollarString(r.totalCharges ?? 0))")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func leaderboardRow(rank: Int, row: DetentionCustomerRow, maxDollars: Double) -> some View {
        let amt = row.amountUsd ?? 0
        let frac = max(0, min(1, amt / maxDollars))
        let barColor: Color = {
            switch rank {
            case 1:  return Brand.danger
            case 2, 3: return Brand.warning
            default: return Brand.success
            }
        }()
        let pct = totalDollars > 0 ? Int((amt / totalDollars * 100).rounded()) : 0
        return HStack(alignment: .top, spacing: Space.s3) {
            // Rank disc — #1 gradient, others translucent white.
            ZStack {
                if rank == 1 {
                    Circle().fill(LinearGradient.diagonal)
                } else {
                    Circle().fill(Color.white.opacity(0.06))
                }
                Text("\(rank)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(rank == 1 ? Color.white : palette.textSecondary)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(row.customer ?? "—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(row.cars ?? 0) cars · avg \(Int((row.avgDwellHrs ?? 0).rounded()))h dwell")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                // Proportional dwell bar (track + fill).
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(barColor.opacity(0.18))
                            .frame(width: w, height: 5)
                        Capsule().fill(barColor)
                            .frame(width: max(4, w * frac), height: 5)
                    }
                }
                .frame(height: 5)
            }

            VStack(alignment: .trailing, spacing: 6) {
                Text(dollarString(amt))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text("\(pct)%")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(16)
    }

    // MARK: - Action row (Open disputes · By customer)

    private var actionRow: some View {
        HStack(spacing: Space.s2) {
            Button(action: { Task { await openDisputes() } }) {
                Text(disputeBusy ? "Opening…" : "Open disputes")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(disputeBusy ? 0.6 : 1)
            .disabled(disputeBusy)

            Button(action: { Task { await reload() } }) {
                Text("By customer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(Color(hex: 0x232932))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func dollarString(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let n = f.string(from: NSNumber(value: v)) ?? "0"
        return "$\(n)"
    }

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 92)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 62)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        do {
            // Hero summary band — EXISTS (railDemurrageAuto.dashboard).
            let dash: RailDemurrageDashboard = try await EusoTripAPI.shared
                .queryNoInput("railDemurrageAuto.dashboard")
            self.dashboard = dash

            // Per-customer leaderboard — PROPOSED endpoint. Attempt the call
            // so the moment the server ships it the board lights up; on the
            // expected 404/NOT_FOUND we keep the empty state instead of
            // crashing or fabricating rows.
            do {
                struct WindowIn: Encodable { let window: String }
                let rows: [DetentionCustomerRow] = try await EusoTripAPI.shared
                    .query("railDemurrageAuto.detentionByCustomer", input: WindowIn(window: "30d"))
                self.customers = rows
            } catch {
                // PORT-GAP: endpoint not present — empty state stands.
                self.customers = []
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Open disputes  (railDemurrageAuto.createDispute · EXISTS)

    private func openDisputes() async {
        // createDispute requires a real demurrageId. Without the per-customer
        // ranking (gapped) there's no row to attach a dispute to — we surface
        // that honestly rather than inventing an id.
        guard !rankedCustomers.isEmpty else {
            ack = "No ranked detention rows to dispute yet — per-customer ranking endpoint is pending."
            return
        }
        disputeBusy = true; ack = nil
        defer { disputeBusy = false }
        do {
            // The proposed detentionByCustomer row does not yet carry a
            // demurrageId, so we cannot fabricate one. Once the endpoint
            // returns row ids, pass the top offender's id here.
            ack = "Dispute drafting needs a demurrageId from the ranking endpoint (not yet returned)."
            _ = CreateDisputeResult.self  // keep the wired shape referenced
        }
    }
}

// MARK: - Local error card (matches house LifecycleCard danger treatment)

private struct LifecycleErrorCard: View {
    @Environment(\.palette) private var palette
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

#Preview("645 · Rail Detention Dashboard · Night") {
    RailDetentionDashboardScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("645 · Rail Detention Dashboard · Light") {
    RailDetentionDashboardScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
