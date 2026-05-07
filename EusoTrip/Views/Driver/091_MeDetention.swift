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
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $disputing) { event in
            DisputeSheet(event: event, store: store)
                .eusoSheetX()
        }
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
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
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
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.facilityName)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
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
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.facilityName)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
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
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_091() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
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
