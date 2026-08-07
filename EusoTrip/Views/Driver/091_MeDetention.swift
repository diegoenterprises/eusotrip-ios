//
//  091_MeDetention.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · Detention Tracker)
//
//  Screen 091 · Me · Detention — the driver's detention pay recovery
//  cockpit. Hero shows $ billed / collected / disputed for the
//  current window. Live "Right now" card lists any facility the
//  driver is currently stuck at with a live-elapsed minute counter.
//  History list shows recent claims with billing status and a quick
//  Dispute action.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Dashboard counters from `detentionAccessorials.getDetentionDashboard`
//      (MCP-verified at `frontend/server/routers/detentionAccessorials.ts`).
//    • Active detentions from `getActiveDetentions` — elapsed /
//      billable minutes computed server-side from arrival time so
//      the counter is consistent across the iOS + web surfaces.
//    • History from `getDetentionHistory` with server billing status
//      ("paid" | "invoiced" | "disputed" | "pending").
//    • Dispute fires `disputeDetention` with the driver's reason;
//      server flips the claim row to `disputed` for review.
//
//    • No fabricated charges. No placeholder elapsed timers. When
//      the driver has no active detention, the "Right now" card
//      collapses to a calm "No active dwell" empty state instead of
//      rendering a fake counter.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero + collected amount.
//         Brand.warning on elapsed > 2h. Danger stroke on disputed.
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

// MARK: - Screen root

struct MeDetention: View {
    @Environment(\.palette) var palette
    @StateObject private var store = DetentionStore()

    @State private var disputing: DetentionAPI.HistoryEvent?

    /// Per-row weather snapshot + wxHold (Wave 4-server #85), keyed by
    /// detention `id`. The shared `DetentionStore` (LiveDataStores.swift)
    /// doesn't decode these yet, so we overlay them locally: a row with
    /// `wxHold==true` auto-tags "WX HOLD" and surfaces the cited readings
    /// (max gust / min vis / peak condition) as dispute evidence. Honest by
    /// absence — empty until the weather-aware re-query lands.
    @State private var activeWeather: [Int: DetentionWxSnapshot] = [:]
    @State private var historyWeather: [Int: DetentionWxSnapshot] = [:]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                dashboardStrip
                rightNowSection
                historySection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $disputing) { event in
            DisputeSheet(event: event, store: store)
                .eusoSheetX()
        }
    }

    /// Refresh the shared store, then overlay the per-row weather snapshots.
    /// Both weather pulls are best-effort: a miss leaves rows untagged
    /// rather than failing the screen.
    private func load() async {
        await store.refresh()
        async let act = try? EusoTripAPI.shared.detention.getActiveWeather(limit: 10)
        async let hist = try? EusoTripAPI.shared.detention.getHistoryWeather(limit: 20)
        let (a, h) = await (act, hist)
        activeWeather = a ?? [:]
        historyWeather = h ?? [:]
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Detention")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Track dwell · recover pay")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Dashboard strip

    private var dashboardStrip: some View {
        let d = store.dashboard
        return HStack(spacing: Space.s2) {
            moneyTile(
                label: "BILLED",
                value: currency(d?.billedAmount ?? 0),
                gradient: true
            )
            moneyTile(
                label: "COLLECTED",
                value: currency(d?.collectedAmount ?? 0),
                gradient: true
            )
            moneyTile(
                label: "DISPUTED",
                value: currency(d?.disputedAmount ?? 0),
                gradient: false
            )
        }
    }

    private func moneyTile(label: String, value: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(gradient
                                 ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.textPrimary))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Right now

    private var rightNowSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("RIGHT NOW")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            if store.active.isEmpty && !store.isLoading {
                EusoEmptyState(
                    systemImage: "clock",
                    title: "No active dwell",
                    subtitle: "When you arrive at a pickup or delivery and the clock starts, your live timer shows up here."
                )
            } else if store.active.isEmpty && store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s4)
            } else {
                ForEach(store.active) { d in
                    activeCard(d)
                }
            }
        }
    }

    private func activeCard(_ d: DetentionAPI.ActiveDetention) -> some View {
        let overtimeRatio = d.freeTimeMinutes > 0
            ? Double(d.elapsedMinutes) / Double(d.freeTimeMinutes)
            : 0
        let urgent = overtimeRatio >= 1.0
        let wx = activeWeather[d.id]
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(d.facilityName)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        // Auto WX HOLD tag — server-flagged severe-weather
                        // overlap only; never inferred client-side.
                        if wx?.isHold == true { wxHoldChip }
                    }
                    Text(d.locationType.capitalized)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                if d.loadId != nil {
                    Text("#\(d.loadId!)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .monospacedDigit()
                }
            }

            // Cited historical-weather evidence for a WX HOLD dwell.
            if wx?.isHold == true { weatherEvidence(wx) }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ELAPSED")
                        .font(EType.micro)
                        .tracking(1.2)
                        .foregroundStyle(palette.textTertiary)
                    Text(humanMinutes(d.elapsedMinutes))
                        .font(EType.bodyStrong)
                        .foregroundStyle(urgent ? Brand.warning : palette.textPrimary)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("BILLABLE")
                        .font(EType.micro)
                        .tracking(1.2)
                        .foregroundStyle(palette.textTertiary)
                    Text(humanMinutes(d.billableMinutes))
                        .font(EType.bodyStrong)
                        .foregroundStyle(d.billableMinutes > 0 ? Brand.warning : palette.textPrimary)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ACCRUING")
                        .font(EType.micro)
                        .tracking(1.2)
                        .foregroundStyle(palette.textTertiary)
                    Text(currency(d.currentCharge))
                        .font(EType.bodyStrong)
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                }
            }

            VStack(spacing: 2) {
                HStack {
                    Text("Free time: \(humanMinutes(d.freeTimeMinutes))")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(urgent ? "OVER FREE" : "WITHIN FREE")
                        .font(EType.micro)
                        .tracking(1.1)
                        .foregroundStyle(urgent ? Brand.warning : palette.textTertiary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.tintNeutral.opacity(0.5))
                        Capsule().fill(urgent
                                       ? AnyShapeStyle(Brand.warning)
                                       : AnyShapeStyle(LinearGradient.diagonal))
                            .frame(width: max(4, geo.size.width * min(1, overtimeRatio)))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("HISTORY")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            if store.history.isEmpty && !store.isLoading {
                EusoEmptyState(
                    systemImage: "tray.full",
                    title: "No past detention",
                    subtitle: "Cleared events land here after you check out of the facility."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(store.history) { e in
                        historyRow(e)
                    }
                }
            }
        }
    }

    private func historyRow(_ e: DetentionAPI.HistoryEvent) -> some View {
        let billing = (e.billingStatus ?? e.status ?? "pending").lowercased()
        let canDispute = !(billing == "disputed" || billing == "paid")
        let wx = historyWeather[e.id]
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(e.facilityName)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        if wx?.isHold == true { wxHoldChip }
                    }
                    HStack(spacing: 4) {
                        Text(e.locationType.capitalized)
                        if let shipper = e.shipperName, shipper != "N/A", !shipper.isEmpty {
                            Text("· \(shipper)")
                        }
                    }
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                billingChip(billing)
            }

            HStack {
                Text("\(humanMinutes(e.billableMinutes)) billable")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text(currency(e.totalCharge))
                    .font(EType.bodyStrong)
                    .foregroundStyle(billing == "paid"
                                     ? AnyShapeStyle(LinearGradient.diagonal)
                                     : AnyShapeStyle(palette.textPrimary))
                    .monospacedDigit()
            }

            // Cited historical-weather evidence for a WX HOLD dwell — the
            // exhibit a driver attaches when disputing a weather dwell.
            if wx?.isHold == true { weatherEvidence(wx) }

            if canDispute {
                Button {
                    disputing = e
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.raised")
                        Text("Dispute")
                    }
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule().stroke(palette.textTertiary.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    @ViewBuilder
    private func billingChip(_ status: String) -> some View {
        let (label, fg, strokeOrFill): (String, Color, AnyShapeStyle) = {
            switch status {
            case "paid":
                return ("PAID", .white, AnyShapeStyle(LinearGradient.diagonal))
            case "invoiced":
                return ("INVOICED", Brand.warning, AnyShapeStyle(Brand.warning.opacity(0.2)))
            case "disputed":
                return ("DISPUTED", Brand.magenta, AnyShapeStyle(Brand.magenta.opacity(0.2)))
            default:
                return ("PENDING", palette.textSecondary, AnyShapeStyle(palette.tintNeutral.opacity(0.55)))
            }
        }()
        Text(label)
            .font(EType.micro)
            .tracking(1.2)
            .foregroundStyle(fg)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .background(Capsule().fill(strokeOrFill))
    }

    // MARK: WX HOLD chip + weather evidence (Wave 4-server #85)

    /// Bespoke "WX HOLD" chip — the alert glyph via `WeatherIcons` (NEVER an
    /// SF Symbol on a weather element). Shown only when the row's
    /// `wxHold==true` (a documented severe-alert overlap).
    private var wxHoldChip: some View {
        HStack(spacing: 4) {
            WeatherIcons.utility(.alert, size: 11, tint: Brand.danger)
            Text("WX HOLD")
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(Brand.danger)
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 3)
        .background(Capsule().fill(Brand.danger.opacity(0.16)))
    }

    /// The cited historical-weather exhibit for a WX HOLD dwell — the
    /// dispute evidence (max gust / min vis / peak condition) with a bespoke
    /// condition glyph. Honest: the historical record is Enterprise-gated, so
    /// when it isn't `available` (or carries no readings) we render the
    /// "available with the enterprise feed" em-dash state — never a
    /// fabricated reading / report.
    @ViewBuilder
    private func weatherEvidence(_ wx: DetentionWxSnapshot?) -> some View {
        let resolved = wx?.isAvailable == true && wx?.hasCitedReadings == true
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                WeatherIcons.symbolView(for: wx?.peakWeatherCode ?? 0, size: 20)
                Text("Cited weather evidence")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if let sev = wx?.alertSeverity {
                    let s = WeatherSnapshot.AlertSeverity(capString: sev)
                    Text(s.label)
                        .font(EType.micro)
                        .tracking(0.6)
                        .foregroundStyle(s.color)
                        .padding(.horizontal, Space.s2)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(s.color.opacity(0.16)))
                }
            }

            if resolved {
                HStack(spacing: Space.s4) {
                    evidenceMetric(.wind, "MAX GUST",
                                   wx?.maxGustMph.map { "\(Int($0.rounded())) mph" } ?? "—")
                    evidenceMetric(.eye, "MIN VIS",
                                   wx?.minVisibilityMi.map {
                                       "\($0.formatted(.number.precision(.fractionLength(0...1)))) mi"
                                   } ?? "—")
                    evidenceMetric(.precip, "PEAK", wx?.peakCondition ?? "—")
                }
                if let head = wx?.alertHeadline, !head.isEmpty {
                    Text(head)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
            } else {
                HStack(alignment: .top, spacing: 6) {
                    WeatherIcons.utility(.alert, size: 13, tint: palette.textTertiary)
                    Text("Historical weather evidence available with the enterprise feed. Max gust, minimum visibility and peak condition for this dwell auto-attach as a cited dispute exhibit with the enterprise historical weather feed.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(Brand.danger.opacity(resolved ? 0.35 : 0.18), lineWidth: 1)
        )
    }

    /// One cited reading tile (bespoke utility glyph + label + value or "—").
    private func evidenceMetric(_ glyph: WeatherIcons.Utility, _ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                WeatherIcons.utility(glyph, size: 12, tint: palette.textTertiary)
                Text(label)
                    .font(EType.micro)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(value)
                .font(EType.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(value == "—" ? palette.textTertiary : palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Footer

    private var footer: some View {
        Text("Detention pay recovery is automatic when clocks + POD timestamps agree. Dispute within 7 days when they don't.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func humanMinutes(_ mins: Int) -> String {
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        let m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

// MARK: - Dispute sheet

private struct DisputeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: DetentionAPI.HistoryEvent
    @ObservedObject var store: DetentionStore

    @State private var reason: String = ""
    @State private var submitting: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Detention") {
                    Text(event.facilityName)
                        .font(EType.bodyStrong)
                    Text(event.locationType.capitalized)
                        .font(EType.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Why are you disputing?") {
                    TextEditor(text: $reason)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Dispute")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            submitting = true
                            await store.dispute(
                                detention: event,
                                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                            submitting = false
                            dismiss()
                        }
                    } label: {
                        if submitting {
                            ProgressView()
                        } else {
                            Text("Submit").fontWeight(.semibold)
                        }
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting)
                }
            }
        }
    }
}

// MARK: - History weather snapshot (Wave 4-server #85)
//
// `DetentionWxSnapshot` + the active-row weather decoder live on 298's
// `DetentionAPI` extension (same module). The history surface needs the
// same overlay for PAST dwells, so this adds the history-row decoder + a
// `getHistoryWeather` accessor here. Re-queries `getDetentionHistory`
// into a weather-aware row and merges by `id` — no fabricated hold/report.

extension DetentionAPI {

    /// A `getDetentionHistory` event decoded WITH the Wave 4 weather fields.
    struct HistoryEventWx: Decodable, Identifiable {
        let id: Int
        let weatherSnapshot: DetentionWxSnapshot?
        // Accept inline flags too, in case a server build doesn't nest them.
        let wxHold: Bool?
        let maxGustMph: Double?
        let minVisibilityMi: Double?
        let peakWeatherCode: Int?
        let peakCondition: String?

        var snapshot: DetentionWxSnapshot? {
            if let s = weatherSnapshot { return s }
            guard wxHold != nil || maxGustMph != nil || minVisibilityMi != nil
                    || peakWeatherCode != nil || peakCondition != nil else { return nil }
            return DetentionWxSnapshot(
                available: nil, wxHold: wxHold, maxGustMph: maxGustMph,
                minVisibilityMi: minVisibilityMi, peakWeatherCode: peakWeatherCode,
                peakCondition: peakCondition, alertHeadline: nil,
                alertSeverity: nil, source: nil
            )
        }
    }

    struct HistoryWxResponse: Decodable {
        let events: [HistoryEventWx]
    }

    /// Re-query `getDetentionHistory` decoding the per-row weather snapshot.
    /// Best-effort — a miss leaves history rows untagged.
    func getHistoryWeather(limit: Int = 50) async throws -> [Int: DetentionWxSnapshot] {
        struct Input: Encodable {
            let status: String?
            let facilityName: String?
            let limit: Int
            let offset: Int
        }
        let resp: HistoryWxResponse = try await api.query(
            "detentionAccessorials.getDetentionHistory",
            input: Input(status: nil, facilityName: nil, limit: limit, offset: 0)
        )
        return Dictionary(
            resp.events.compactMap { row in row.snapshot.map { (row.id, $0) } },
            uniquingKeysWith: { a, _ in a }
        )
    }
}

// MARK: - Screen wrapper

struct MeDetentionScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeDetention()
        } nav: {
            BottomNav(
                leading: driverNavLeading_091(),
                trailing: driverNavTrailing_091(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_091() -> [NavSlot] {
    RoleNav.driverLeading(current: .none)
}
private func driverNavTrailing_091() -> [NavSlot] {
    RoleNav.driverTrailing(current: .me)
}

// MARK: - Previews

#Preview("091 · Detention · Night") {
    MeDetentionScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("091 · Detention · Afternoon") {
    MeDetentionScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
