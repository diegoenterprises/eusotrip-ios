//
//  391_CatalystDetentionAlerts.swift
//  EusoTrip — Catalyst · Detention Alerts (carrier-side detention/accessorial watch).
//
//  House-chrome port of "03 Catalyst/Code/391_CatalystDetentionAlerts.swift"
//  (+ Dark-SVG cross-check). CARRIER-SIDE. Detention/accessorial watch across
//  active truck loads: a projected-exposure hero (dollars at risk · loads
//  detaining), a getActiveDetentions card of at-risk rows (load · facility ·
//  free-time used · accrual rate · accrued $), a worst-facility strip, the
//  ME/DU tie, and the disputeDetention CTA. Truck analog of demurrage is dock
//  detention (2h free, then hourly accrual). Docked under DISPATCH.
//
//  PERSONA: CATALYST — Aurora Freight Lines · USDOT 3 482 119. Driver ME ·
//  Eusotrans on active legs. Shipper-of-record DU pin: Eusorone Technologies.
//  MATRIX-50 loads A38FB / 7C3A / B417.
//
//  Server wiring (verified against EusoTripAPI.swift · DetentionAPI):
//    EXISTS · detention.getDashboard()                → hero counters
//             (detentionAccessorials.getDetentionDashboard · :129)
//    EXISTS · detention.getActive(limit:)             → at-risk rows
//             (detentionAccessorials.getActiveDetentions · :256)
//    EXISTS · detention.dispute(detentionId:reason:)  → CTA mutation
//             (detentionAccessorials.disputeDetention · :511)
//    NOT in iOS client (seeds kept · WIRE markers below):
//             detentionAccessorials.calculateDetention      (:355)
//             detentionAccessorials.getDetentionByFacility  (:401)
//             detentionAccessorials.getAccessorialAnalytics (:1169)
//  0% mock — representative seeds are overwritten on hydrate.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystDetentionAlertsScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            DetentionAlertsBody_391()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_391(),
                trailing: catalystNavTrailing_391(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_391() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_391() -> [NavSlot] {
    [NavSlot(label: "Fleet", systemImage: "truck.box",          isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.crop.circle", isCurrent: true)]
}

// MARK: - Body

private struct DetentionAlertsBody_391: View {
    @Environment(\.palette) private var palette

    // Live state — empty/em-dash until the real procs answer. No seeds.
    @State private var rows: [DetentionRow_391] = []
    @State private var atRiskCount: Int = 0
    @State private var exposureDollars: String = "—"
    @State private var worstFacility: WorstFacility_391? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    @State private var disputing: Bool = false
    @State private var disputeAck: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                iridescentHairline

                heroCard
                sectionEyebrow("ACTIVE DETENTIONS · getActiveDetentions · calculateDetention")
                detentionsCard
                worstFacilityStrip
                tieStrip
                disputeCTA
                provenance

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
        }
    }

    // MARK: - TopBar + title  (_391 inline header)

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DETENTION ALERTS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text("ACCESSORIAL")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Detention Alerts")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text("getDetentionDashboard")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("CARRIER DETENTION WATCH")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(loading ? "loading…" : (loadError == nil ? "live" : "offline"))
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.40), Brand.magenta.opacity(0.40)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
    }

    // MARK: - Hero · projected exposure  (_391 inline hero card)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PROJECTED EXPOSURE · TODAY")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("\(atRiskCount) at risk")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Brand.warning.opacity(0.12))
                    .clipShape(Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(exposureDollars)
                    .font(.system(size: 30, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("at risk")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("\(atRiskCount) loads detaining · 2h free then hourly accrual")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.30)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Active detentions card  (_391 inline rows)

    private var detentionsCard: some View {
        VStack(spacing: 0) {
            if loading && rows.isEmpty {
                Text("Loading active detentions…")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else if let err = loadError, rows.isEmpty {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.danger)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else if rows.isEmpty {
                EusoEmptyState(
                    systemImage: "clock.badge.checkmark",
                    title: "No active detentions",
                    subtitle: "Loads accruing dock detention appear here with their live exposure."
                )
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(row.loadId)
                                .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                                .foregroundStyle(palette.textPrimary)
                            Spacer(minLength: 0)
                            Text(row.value)
                                .font(.system(size: 11, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(Brand.warning)
                        }
                        Text(row.facility)
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.vertical, 9)
                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(palette.borderFaint)
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Worst facility strip  (LIVE — detentionAccessorials.getDetentionByFacility)

    private var worstFacilityStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WORST FACILITY · 30 DAYS")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            if let w = worstFacility {
                Text("\(w.facilityName) · avg \(String(format: "%.1f", Double(w.avgWaitMinutes) / 60.0))h dwell · \(w.eventCount) event\(w.eventCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Text("\(formatCurrency_391(w.totalCharges)) charged · \(w.disputeCount) disputed")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            } else {
                Text(loading ? "Loading facility ranking…" : "No detention history by facility yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Context strip (honest program copy — no fabricated personas)

    private var tieStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Detention accrues after the facility's free time expires (2h default)")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("Reimbursable charges bill to the shipper-of-record on settlement")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.blue.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.blue.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Dispute CTA  (real disputeDetention mutation)

    private var disputeCTA: some View {
        VStack(spacing: 8) {
            CTAButton(
                title: disputing ? "Filing dispute…" : "Dispute detention charge",
                action: { Task { await disputeWorst() } },
                isLoading: disputing
            )
            if let ack = disputeAck {
                Text(ack)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.success)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var provenance: some View {
        Text("DISPUTE · reason + evidence required")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Network

    private func loadAll() async {
        await reload()
    }

    private func reload() async {
        loading = true
        loadError = nil
        defer { loading = false }

        var anySucceeded = false

        // Hero counters — detentionAccessorials.getDetentionDashboard (EXISTS).
        // Unconditional overwrite: a real zero renders as a real zero/em-dash.
        do {
            let dash = try await EusoTripAPI.shared.detention.getDashboard()
            atRiskCount = dash.activeDetentions
            let exposure = dash.billedAmount > 0 ? dash.billedAmount : dash.totalCharges
            exposureDollars = exposure > 0 ? formatCurrency_391(exposure) : "—"
            anySucceeded = true
        } catch { /* fall through to the shared error below */ }

        // At-risk rows — detentionAccessorials.getActiveDetentions (EXISTS).
        // Unconditional overwrite: an empty response clears the board honestly.
        do {
            let active = try await EusoTripAPI.shared.detention.getActive(limit: 25)
            rows = active.detentions.map { d in
                DetentionRow_391(
                    loadId: d.loadId.map { "LD-\($0)" } ?? d.facilityName,
                    facility: facilityLine_391(d),
                    value: d.billableMinutes > 0
                        ? formatCurrency_391(d.currentCharge)
                        : freeRemainingLabel_391(d),
                    isOver: d.billableMinutes > 0
                )
            }
            anySucceeded = true
        } catch { /* fall through */ }

        // Worst facility — detentionAccessorials.getDetentionByFacility (live bridge).
        struct FacilityInput: Encodable { let limit: Int }
        struct FacilitiesWire: Decodable { let facilities: [WorstFacility_391] }
        if let wire: FacilitiesWire = try? await EusoTripAPI.shared.query(
            "detentionAccessorials.getDetentionByFacility", input: FacilityInput(limit: 1)
        ) {
            worstFacility = wire.facilities.first
            anySucceeded = true
        } else {
            worstFacility = nil
        }

        if !anySucceeded {
            loadError = "Couldn't reach the detention service - pull to retry."
            rows = []
            atRiskCount = 0
            exposureDollars = "—"
        }
    }

    private func disputeWorst() async {
        guard !disputing else { return }
        disputing = true
        disputeAck = nil
        defer { disputing = false }
        // Dispute the highest-exposure active row — detentionAccessorials.disputeDetention (EXISTS).
        // Live id arrives via getActive(); seed rows carry no numeric id, so we
        // resolve the worst active id at dispute time from the live fetch.
        guard let active = try? await EusoTripAPI.shared.detention.getActive(limit: 25),
              let worst = active.detentions.max(by: { $0.currentCharge < $1.currentCharge }) else {
            disputeAck = "No active detention to dispute"
            return
        }
        let result = try? await EusoTripAPI.shared.detention.dispute(
            detentionId: worst.id,
            reason: "Carrier dispute · excess dwell beyond 2h free time · escort/appointment delay"
        )
        if result?.success == true || result?.status == "disputed" {
            disputeAck = "Dispute filed · \(worst.facilityName)"
            await reload()
        } else {
            disputeAck = "Couldn’t file dispute - try again"
        }
    }

    // MARK: - Formatting helpers (free closures · not @ViewBuilder funcs)

    private func facilityLine_391(_ d: DetentionAPI.ActiveDetention) -> String {
        let overMin = max(0, d.elapsedMinutes - d.freeTimeMinutes)
        let overHrs = String(format: "%.1f", Double(overMin) / 60.0)
        let loc = d.locationType.isEmpty ? "dock" : d.locationType
        if d.billableMinutes > 0 {
            return "\(d.facilityName) · \(loc) · \(overHrs)h over free"
        }
        let remainMin = max(0, d.freeTimeMinutes - d.elapsedMinutes)
        let remainHrs = String(format: "%.1f", Double(remainMin) / 60.0)
        return "\(d.facilityName) · \(loc) · \(remainHrs)h to free expiry"
    }

    private func freeRemainingLabel_391(_ d: DetentionAPI.ActiveDetention) -> String {
        let remainMin = max(0, d.freeTimeMinutes - d.elapsedMinutes)
        return String(format: "%.1fh", Double(remainMin) / 60.0)
    }

    private func formatCurrency_391(_ value: Double) -> String {
        guard value > 0 else { return "-" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}

// MARK: - Row model (private · _391-suffixed)

private struct DetentionRow_391: Identifiable {
    let id = UUID()
    let loadId: String
    let facility: String
    let value: String
    let isOver: Bool
}

/// Mirrors one row of `detentionAccessorials.getDetentionByFacility`
/// (detentionAccessorials.ts:409) — every field Number()-wrapped server-side.
private struct WorstFacility_391: Decodable {
    let rank: Int
    let facilityName: String
    let eventCount: Int
    let totalCharges: Double
    let avgWaitMinutes: Int
    let maxWaitMinutes: Int
    let avgCharge: Double
    let disputeCount: Int
    let score: Int
}

// MARK: - Previews

#Preview("391 · Catalyst · Detention Alerts · Night") {
    CatalystDetentionAlertsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("391 · Catalyst · Detention Alerts · Afternoon") {
    CatalystDetentionAlertsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
