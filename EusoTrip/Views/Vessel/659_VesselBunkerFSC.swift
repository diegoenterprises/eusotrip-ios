//
//  659_VesselBunkerFSC.swift
//  EusoTrip — Vessel Operator · Bunker FSC Schedule (host for BunkerFSCStepLadder).
//
//  Founder proof "685 Vessel Bunker FSC Schedule" — the vessel-operator surface
//  that shows the live VLSFO bunker surcharge bracket. Hosts the bespoke
//  BunkerFSCStepLadder component (EusoTrip/Views/Components/BunkerFSCStepLadder.swift):
//  a monotonic staircase mapping the bunker index ($/MT) → fuel-surcharge %,
//  highlighting the bracket the live index currently sits inside and dropping a
//  "$<amount>" pill marker to the x-axis.
//
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS · [orb] ·
//  COMPLIANCE · ME). This is a drill-in leaf reached via .eusoVesselNavSwap to
//  "Vesl659"; it carries the canonical bottom-nav with no tab current (matches
//  the sibling leaf 658). The shared RoleNavBackOverlay paints the back chevron.
//
//  Data:
//    LIVE  vesselShipments.getBunkerPrices(port, fuelTypes) (EXISTS
//          vesselShipments.ts:1230 · OilPriceMarineService.BunkerPrice[]
//          { fuelType, price /* $/MT index */, currency, unit, … }) -> the live
//          VLSFO $/MT index that selects the active FSC bracket + marker label.
//
//    TODO (carrier-supplied, not persisted): the bracket → surcharge-% table is
//    carrier-specific (per BunkerFSCStepLadder's domain note: "Carriers don't
//    share one universal table"). No backend FSC-schedule endpoint exists yet, so
//    the ladder uses the proof reference schedule (450→950 $/MT in $100 brackets
//    ratcheting 2% → 3.5% → 5% → 6% → 8%). When a real FSC-schedule source lands
//    (e.g. vesselShipments.getVesselFSCSchedule), bind `ladder` to it the same
//    way `activeIndex` binds to getBunkerPrices below. NO fabricated persistence.
//

import SwiftUI

struct VesselBunkerFSCScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselBunkerFSCBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror OilPriceMarineService.BunkerPrice)

private struct BunkerPrice: Decodable, Identifiable {
    var id: String { fuelType + port }
    let fuelType: String       // "VLSFO", "MGO", "IFO380" …
    let price: Double          // the bunker index — $/MT
    let currency: String?
    let unit: String?          // typically "USD/MT"
    let port: String
    let portName: String?
    let changePercent24h: Double?
}

// MARK: - Body

private struct VesselBunkerFSCBody: View {
    @Environment(\.palette) private var palette

    // Live VLSFO index ($/MT) — nil until loaded. ZERO-FALLBACK: no proof-$712
    // stand-in; when the upstream index is absent the marker/bracket render "—".
    @State private var liveIndex: Double? = nil
    @State private var changePct: Double? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Benchmark bunkering hub for the index (Singapore — the proof's reference hub).
    private let hubCode = "SGSIN"
    private let hubName = "Singapore"

    // The carrier FSC bracket ladder. Reference schedule until a real
    // FSC-schedule endpoint exists (see file header TODO).
    private let ladder: [BunkerFSCStep] = BunkerFSCStepLadder.proofSchedule

    // Base freight the surcharge is applied to (the booking's base ocean rate).
    // ZERO-FALLBACK: no booking-rate source is wired into this surface yet, so
    // this stays nil and the "applied to booking" card em-dashes its dollars —
    // a hardcoded figure must never flow into a displayed total.
    private let baseFreightUsd: Double? = nil

    // Resolved live index ($/MT) — live value only, never a stand-in.
    private var activeIndex: Double? { liveIndex }
    private var markerLabel: String { activeIndex.map { "$\(Int($0.rounded()))" } ?? "—" }

    /// Active bracket the live index sits inside (mirrors the component's own
    /// clamping: below floor → first, above ceiling → last). nil until a live
    /// index exists — no bracket is ever claimed off a fabricated index.
    private var activeStep: BunkerFSCStep? {
        guard let idx = activeIndex else { return nil }
        let sorted = ladder.sorted { $0.indexFrom < $1.indexFrom }
        guard !sorted.isEmpty else { return nil }
        for (i, s) in sorted.enumerated() {
            let isLast = (i == sorted.count - 1)
            if idx >= s.indexFrom && (idx < s.indexTo || (isLast && idx <= s.indexTo)) {
                return s
            }
        }
        if idx < sorted.first!.indexFrom { return sorted.first }
        return sorted.last
    }

    private var surchargePct: Double? { activeStep?.surchargePct }
    private var surchargeUsd: Double? {
        guard let base = baseFreightUsd, let pct = surchargePct else { return nil }
        return base * pct / 100
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading bunker index…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text("Live VLSFO index unavailable. \(err)")
                                .font(EType.caption).foregroundStyle(Brand.warning)
                        }
                    } else if liveIndex == nil {
                        // Upstream returned nothing — honest seam, no proof index.
                        LifecycleCard {
                            Text("Live VLSFO index unavailable — the upstream bunker feed returned no \(hubName) quote. Bracket marker hidden until a real index lands.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                    kpiStrip
                    ladderCard
                    appliedCard
                    CTAButton(title: "Export FSC schedule", leadingIcon: "square.and.arrow.up")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · BUNKER FSC")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: Space.s2)
                Text("VLSFO · WEEKLY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            Text("Bunker FSC").font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Bunker prices · VLSFO @ \(hubName) · $/MT → surcharge %")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "VLSFO INDEX", value: activeIndex.map { "$\(Int($0.rounded()))" } ?? "—", gradientNumeral: true)
            MetricTile(label: "FSC BRACKET", value: surchargePct.map { pctString($0) } ?? "—", accent: Brand.info)
            MetricTile(
                label: "24H",
                value: changePct == nil ? "—" : String(format: "%+.1f%%", changePct!),
                accent: (changePct ?? 0) >= 0 ? Brand.warning : Brand.success
            )
        }
    }

    @ViewBuilder
    private var ladderCard: some View {
        // The hosted bespoke component. The LIVE index drives the active bracket +
        // the "$<amount>" pill marker; the reference ladder supplies the steps.
        // ZERO-FALLBACK: without a live index the ladder is not rendered with a
        // fabricated marker — the honest seam card above explains the absence.
        if let idx = activeIndex {
            BunkerFSCStepLadder(
                steps: ladder,
                activeIndex: idx,
                markerLabel: markerLabel
            )
        }
    }

    private var appliedCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("APPLIED TO BOOKING").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard(accentGradient: true) {
                VStack(alignment: .leading, spacing: 10) {
                    appliedRow(label: "Base ocean freight", value: baseFreightUsd.map { "$\(Int($0))" } ?? "—")
                    appliedRow(label: "Active bracket", value: bracketRangeLabel)
                    appliedRow(label: "Bunker surcharge", value: surchargePct.map { pctString($0) } ?? "—")
                    Divider().overlay(palette.borderSoft)
                    HStack(alignment: .firstTextBaseline) {
                        Text("Surcharge applied").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(surchargeUsd.map { "+$\(Int($0.rounded()))" } ?? "—")
                            .font(.system(size: 18, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    // ZERO-FALLBACK: dollar math renders only when a real booking
                    // rate exists — the % bracket alone is what we can honestly show.
                    Text(appliedMathLine)
                        .font(.system(size: 11)).monospaced().foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var appliedMathLine: String {
        if let base = baseFreightUsd, let pct = surchargePct, let usd = surchargeUsd {
            return "$\(Int(base)) base × \(pctString(pct)) = +$\(Int(usd.rounded())) · all-in $\(Int((base + usd).rounded()))"
        }
        if let pct = surchargePct {
            return "\(pctString(pct)) applies to the booking's ocean rate at invoicing — no booking rate wired to this surface"
        }
        return "bracket resolves once a live VLSFO index lands"
    }

    private func appliedRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(EType.body).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
        }
    }

    private var bracketRangeLabel: String {
        guard let s = activeStep else { return "—" }
        return "\(Int(s.indexFrom))–\(Int(s.indexTo)) $/MT"
    }

    private func pctString(_ pct: Double) -> String {
        pct == pct.rounded() ? "\(Int(pct))%" : String(format: "%.1f%%", pct)
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct BunkerIn: Encodable { let port: String; let fuelTypes: [String] }
        do {
            // getBunkerPrices returns BunkerPrice[] (or null on upstream miss).
            let prices: [BunkerPrice]? = try await EusoTripAPI.shared.query(
                "vesselShipments.getBunkerPrices",
                input: BunkerIn(port: hubCode, fuelTypes: ["VLSFO"])
            )
            if let vlsfo = (prices ?? []).first(where: { $0.fuelType.uppercased().contains("VLSFO") })
                ?? (prices ?? []).first {
                liveIndex = vlsfo.price
                changePct = vlsfo.changePercent24h
            } else {
                // Upstream returned nothing — honest absence (em-dash KPIs +
                // explanatory seam card), never a stand-in index.
                liveIndex = nil
                changePct = nil
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("659 · Vessel Bunker FSC · Night") { VesselBunkerFSCScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("659 · Vessel Bunker FSC · Light") { VesselBunkerFSCScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
