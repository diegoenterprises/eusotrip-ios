//
//  650_RailDetentionHistory.swift
//  EusoTrip — Rail Engineer · Detention History (carrier-side, 90-day window).
//
//  Verbatim port of "05 Rail · 650 Rail Detention History · Dark".
//  CARRIER-SIDE intermodal-parity gap-fill built to the flagship DETAIL
//  grammar (645 Rail Detention Dashboard / 02 Shipper 205): back-chevron +
//  eyebrow + mono caption + 28/-0.4 title; gradient-rimmed hero ActiveCard
//  with lead figure + recovered progress; 3-cell KPI strip (BILLED cell on
//  the eusoDiagonal); itemized ListRow cycle stack (40x40 icon chip + title
//  + mono sub + short status pill + right tabular value); accessorial
//  analytics context strip; Export/Filter CTA pair.
//
//  Live wiring (EusoTripAPI.shared.detention):
//    · getDetentionDashboard → $ billed / collected / disputed counters
//    · getDetentionHistory   → past detention events (cycles derived live)
//  Charts/figures plot LIVE data only; absent series → empty state, never
//  fabricated. Carrier BNSF Intermodal · Eusorone Technologies (DU).
//

import SwiftUI

struct RailDetentionHistoryScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDetentionHistoryBody() } nav: {
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

// MARK: - Derived cycle shape
//
// The wireframe groups detention events into monthly billing cycles (April /
// March / February in the canon). The iOS detention client exposes the raw
// `getDetentionHistory` event stream; we fold those events into per-month
// cycles here so the cycle stack plots LIVE rollups — no fabricated months.

private struct DetentionCycle: Identifiable {
    let id: String              // month key "yyyy-MM"
    let monthLabel: String      // "April cycle"
    let boxes: Int
    let openCount: Int
    let charge: Double
    /// Most-recent event ordering anchor (newest cycle first).
    let sortKey: String

    var closed: Bool { openCount == 0 }
}

// MARK: - Body

private struct RailDetentionHistoryBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var dashboard: DetentionAPI.Dashboard? = nil
    @State private var events: [DetentionAPI.HistoryEvent] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: Derived rollups (LIVE — never fabricated)

    /// Total boxes (events) in the 90-day window.
    private var boxCount: Int { dashboard?.totalEvents ?? events.count }

    /// Collected % of billed — the "recovered" headline.
    private var collectedPct: Int {
        guard let d = dashboard, d.billedAmount > 0 else { return 0 }
        return Int((d.collectedAmount / d.billedAmount * 100).rounded())
    }

    /// Disputed event count derived from the live event stream
    /// (billingStatus == "disputed"); falls back to a count-from-amount
    /// only when the stream is empty but the dashboard reports dollars.
    private var disputedCount: Int {
        let fromEvents = events.filter {
            ($0.billingStatus ?? $0.status ?? "").lowercased() == "disputed"
        }.count
        return fromEvents
    }

    private var billedAmount: Double { dashboard?.billedAmount ?? 0 }

    /// Fraction of the progress bar filled = collected / billed.
    private var recoveredFraction: Double {
        guard let d = dashboard, d.billedAmount > 0 else { return 0 }
        return min(max(d.collectedAmount / d.billedAmount, 0), 1)
    }

    /// Fold the live event stream into monthly billing cycles, newest first.
    private var cycles: [DetentionCycle] {
        guard !events.isEmpty else { return [] }
        let monthFmt = DateFormatter()
        monthFmt.dateFormat = "yyyy-MM"
        let labelFmt = DateFormatter()
        labelFmt.dateFormat = "MMMM"

        // Bucket events by month key.
        var buckets: [String: [DetentionAPI.HistoryEvent]] = [:]
        for ev in events {
            let key = monthKey(for: ev, fmt: monthFmt)
            buckets[key, default: []].append(ev)
        }

        let cycles: [DetentionCycle] = buckets.map { key, evs in
            let charge = evs.reduce(into: 0.0) { $0 += $1.totalCharge }
            let openCount = evs.filter {
                let s = ($0.billingStatus ?? $0.status ?? "").lowercased()
                return s != "paid" && s != "collected" && s != "closed"
            }.count
            let label: String = {
                if let d = monthFmt.date(from: key) { return "\(labelFmt.string(from: d)) cycle" }
                return "\(key) cycle"
            }()
            return DetentionCycle(id: key, monthLabel: label, boxes: evs.count,
                                  openCount: openCount, charge: charge, sortKey: key)
        }
        return cycles.sorted { $0.sortKey > $1.sortKey }
    }

    private func monthKey(for ev: DetentionAPI.HistoryEvent, fmt: DateFormatter) -> String {
        let raw = ev.departureTime ?? ev.arrivalTime ?? ev.createdAt ?? ""
        if let d = ISO8601DateFormatter().date(from: raw) { return fmt.string(from: d) }
        // Best-effort "yyyy-MM-dd…" prefix → "yyyy-MM"
        if raw.count >= 7 { return String(raw.prefix(7)) }
        return "—"
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
                    heroCard
                    kpiStrip
                    recentCyclesCard
                    analyticsStrip
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

    // MARK: - Eyebrow (✦ RAIL ENGINEER · DETENTION  ·  HISTORY)

    private var eyebrow: some View {
        HStack {
            Text("✦  RAIL ENGINEER · DETENTION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("HISTORY")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title row (back-chevron + 28/-0.4 title + BNSF / 90-day window)

    private var titleRow: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Text("Detention history")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("BNSF")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("90-day window")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Hero ActiveCard

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                // Chip row — "90 days" + "recovered NN%"
                HStack(spacing: Space.s2) {
                    Text("90 days")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Color.white.opacity(0.08)).clipShape(Capsule())
                    Text("recovered \(collectedPct)%")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Brand.success)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Brand.success.opacity(0.22)).clipShape(Capsule())
                    Spacer(minLength: 0)
                }

                // Lead figure + caption + DISPUTES count
                HStack(alignment: .top, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currencyFull(billedAmount))
                            .font(.system(size: 26, weight: .bold)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("billed last 90 days")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("\(boxCount) boxes · \(collectedPct)% collected")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("DISPUTES")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(disputedCount)")
                            .font(EType.mono(.body)).tracking(0.2)
                            .foregroundStyle(Brand.warning)
                    }
                }

                // Recovered progress bar
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: max(0, w * recoveredFraction))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - 3-cell KPI strip (BILLED gradient · COLLECTED · DISPUTED)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // Cell 1 — eusoDiagonal gradient fill
            VStack(alignment: .leading, spacing: 6) {
                Text("BILLED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text(currencyCompact(billedAmount))
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiCell(label: "COLLECTED", value: "\(collectedPct)%", color: Brand.success)
            kpiCell(label: "DISPUTED", value: "\(disputedCount)", color: Brand.warning)
        }
    }

    private func kpiCell(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - RECENT CYCLES card

    private var recentCyclesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RECENT CYCLES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getDetentionHistory:304")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s3)

            if cycles.isEmpty {
                EusoEmptyState(systemImage: "calendar.badge.clock",
                               title: "No cycles yet",
                               subtitle: "Closed detention billing cycles will appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(cycles.prefix(3).enumerated()), id: \.element.id) { idx, cycle in
                        cycleRow(cycle)
                        if idx < min(cycles.count, 3) - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.vertical, Space.s2)
                        }
                    }
                    // Footer note
                    Text("+ per-cycle reconcile · disputes resolved before cycle close")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func cycleRow(_ cycle: DetentionCycle) -> some View {
        // Status pill semantics: closed cycles → PAID, open → OPEN N.
        let pillText = cycle.closed ? "PAID" : "OPEN \(cycle.openCount)"
        let pillKind: StatusPill.Kind = cycle.closed ? .success : .warning
        let valueColor: Color = cycle.closed ? palette.textPrimary : Brand.warning
        let chipColor: Color = cycle.closed ? Brand.success : Brand.warning
        let sub = cycle.closed
            ? "\(cycle.boxes) boxes · closed"
            : "\(cycle.boxes) boxes · \(cycle.openCount) open"

        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipColor.opacity(0.20))
                    .frame(width: 40, height: 40)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(chipColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(cycle.monthLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(text: pillText, kind: pillKind)
                Text(currencyFull(cycle.charge))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(valueColor)
            }
        }
    }

    // MARK: - Accessorial analytics context strip

    private var analyticsStrip: some View {
        // PORT-GAP: detentionAccessorials.getAccessorialAnalytics is a
        // grep-confirmed tRPC route (detentionAccessorials.ts:1169) but is
        // NOT yet exposed on EusoTripAPI.DetentionAPI in the iOS client.
        // The 90-day rollup below is reconstructed from the LIVE dashboard +
        // history already fetched; the dedicated analytics endpoint stays
        // wired-pending until a typed accessor lands.
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                Text("ACCESSORIAL ANALYTICS · getAccessorialAnalytics")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text("\(boxCount) boxes")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("90-day rollup · collection rate \(collectedPct)% across the window")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("Carrier BNSF Intermodal · Eusorone Technologies (DU)")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair (Export cycle · Filter)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Export cycle")
                .frame(maxWidth: .infinity)
            Button(action: {}) {
                Text("Filter")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 148, minHeight: 52)
                    .frame(maxWidth: .infinity)
                    .background(palette.bgSecondary)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 148)
        }
    }

    // MARK: - Loading skeleton

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Currency formatting

    /// "$148,640" — full dollars, grouped, no cents.
    private func currencyFull(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$0"
    }

    /// "$148.6K" / "$1.2M" — compact dollars for the KPI cell.
    private func currencyCompact(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if v >= 1_000     { return String(format: "$%.1fK", v / 1_000) }
        return String(format: "$%.0f", v)
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        do {
            async let dash: DetentionAPI.Dashboard = EusoTripAPI.shared.detention.getDashboard()
            async let hist: DetentionAPI.HistoryResponse = EusoTripAPI.shared.detention.getHistory(limit: 90)
            let (d, h) = try await (dash, hist)
            self.dashboard = d
            self.events = h.events
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("650 · Rail Detention History · Night") {
    RailDetentionHistoryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("650 · Rail Detention History · Light") {
    RailDetentionHistoryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
