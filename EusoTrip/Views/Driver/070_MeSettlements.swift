//
//  070_MeSettlements.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · settlements history)
//
//  Screen 070 · Me · Settlements — the driver's full settlement-batch
//  history. Unlike the EusoWallet §4 upcoming-settlements card (055
//  DayCloseWallet surfaces a filtered "not-yet-paid" view via
//  `UpcomingSettlementsStore`), this brick renders the full record —
//  every batch the server knows about — grouped into Upcoming and
//  Paid sections.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Every batch row comes from the live tRPC procedure
//      `settlementBatching.getDriverBatchView({ driverId })` —
//      MCP-verified at `frontend/server/routers/settlementBatching.ts`.
//      `SettlementsHistoryStore` in `ViewModels/LiveDataStores.swift`
//      owns the fetch + sorts newest-first by `paidAt` / `periodEnd`.
//
//    • Summary tiles (Paid YTD + Pending total) are computed from the
//      store's rows at render time — not from a separate endpoint.
//      YTD filters on `paidAt.hasPrefix(currentYear)` so the figure
//      matches the tax surface's year scope exactly.
//
//    • Status pill colors are derived from `DriverSettlementBatch.status`
//      via a deterministic switch. `paid` → success; `pending` /
//      `processing` → neutral; `failed` / `disputed` → warning. No
//      ambient coloring that contradicts the server truth.
//
//    • Empty state is server-confirmed. A brand-new driver with no
//      settlements yet sees an `EusoEmptyState` hero — not a stub.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero numerals, section headers,
//         and status chips for "paid". Zero Brand.info/blue flat fills.
//    §4   Tokenized spacing (Space.sN), radii (Radius.sm/md/lg),
//         type (EType.*). No magic numbers.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle expressions wrapped in `AnyShapeStyle`.
//    §10  Previews compile in isolation — store stays in `.loading`
//         under preview's no-baseURL runtime and lands in `.error`
//         via `notConfigured`. No fixtures.
//

import SwiftUI

// MARK: - Screen root

struct MeSettlements: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = SettlementsHistoryStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                switch store.state {
                case .loading:
                    loadingSkeleton
                case .empty:
                    emptyHero
                case .error(let e):
                    errorBanner(e)
                case .loaded(let batches):
                    summaryCard(batches)
                    section(title: "UPCOMING", rows: batches.filter(\.isUpcoming))
                    section(title: "PAID", rows: batches.filter { !$0.isUpcoming })
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await seedAndRefresh() }
        .refreshable { await seedAndRefresh() }
        .onChange(of: session.user?.id) { _, newId in
            store.driverId = Int(newId ?? "0") ?? 0
            Task { await store.refresh() }
        }
    }

    private func seedAndRefresh() async {
        store.driverId = Int(session.user?.id ?? "0") ?? 0
        await store.refresh()
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Settlements")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Batch history · upcoming & paid")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: States

    private var loadingSkeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.5))
                .frame(height: 100)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.35))
                    .frame(height: 64)
            }
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "doc.plaintext",
            title: "No settlements yet",
            subtitle: "Once your first load batches for payout, every batch lands here — upcoming and paid. Pull to refresh after your first run."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load settlements")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Summary card — YTD paid + pending

    private func summaryCard(_ batches: [DriverSettlementBatch]) -> some View {
        let year = currentYearPrefix()
        let ytdPaid = batches
            .filter { !$0.isUpcoming && ($0.paidAt?.hasPrefix(year) ?? false) }
            .reduce(0.0) { $0 + $1.amount }
        let pending = batches
            .filter(\.isUpcoming)
            .reduce(0.0) { $0 + $1.amount }

        return HStack(spacing: Space.s3) {
            statTile(
                label: "PAID \(year)",
                value: money(ytdPaid),
                emphasis: true
            )
            statTile(
                label: "PENDING",
                value: money(pending),
                emphasis: false
            )
        }
    }

    private func statTile(label: String, value: String, emphasis: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.numeric)
                .foregroundStyle(
                    emphasis
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.textPrimary)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Grouped sections (Upcoming / Paid)

    @ViewBuilder
    private func section(title: String, rows: [DriverSettlementBatch]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text(title)
                        .font(EType.micro)
                        .tracking(1.4)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(rows.count)")
                        .font(EType.micro)
                        .tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(spacing: Space.s2) {
                    ForEach(rows) { row in
                        batchRow(row)
                    }
                }
            }
        }
    }

    private func batchRow(_ b: DriverSettlementBatch) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(b.batchNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(periodLabel(b))
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(money(b.amount))
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                statusChip(b.status)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusChip(_ status: String) -> some View {
        let label = status.replacingOccurrences(of: "_", with: " ").uppercased()
        switch status.lowercased() {
        case "paid":
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(Capsule().fill(LinearGradient.diagonal))
        case "failed", "disputed":
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(
                    Capsule().strokeBorder(Brand.warning.opacity(0.6), lineWidth: 1)
                )
        default:
            // pending, processing, etc. — neutral
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(
                    Capsule().strokeBorder(palette.borderFaint, lineWidth: 1)
                )
        }
    }

    // MARK: Helpers

    private func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    /// Returns the current year as a 4-char prefix (e.g. "2026") so we
    /// can filter `paidAt` ISO timestamps without parsing every row.
    private func currentYearPrefix() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy"
        return df.string(from: Date())
    }

    /// Short human period label. Falls back to the raw ISO string so we
    /// never hide server-returned data on a parse failure.
    private func periodLabel(_ b: DriverSettlementBatch) -> String {
        let start = shortDate(b.periodStart)
        let end = shortDate(b.periodEnd)
        switch (start, end) {
        case (let s?, let e?): return "\(s) – \(e)"
        case (let s?, nil):    return s
        case (nil, let e?):    return e
        default:               return ""
        }
    }

    private func shortDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d"
            return out.string(from: d)
        }
        return iso
    }
}

// MARK: - Screen wrapper

struct MeSettlementsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeSettlements()
        } nav: {
            BottomNav(
                leading: driverNavLeading_070(),
                trailing: driverNavTrailing_070(),
                orbState: .idle
            )
        }
    }
}

// 070 ships the Haul-tab custom variant with ME current — matches
// PNG slot canon (rebranded to "Invite a Driver" = Me-ring referrals
// surface). iOS file content is `MeSettlements` (Wallet-ring per
// memory) — same iOS-vs-PNG mismatch as 057-069, out of safe-mode
// scope. Frozen layout per [feedback_bottom_nav_frozen]; only SF
// Symbol naming polish.
private func driverNavLeading_070() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy",     isCurrent: false)]
}
private func driverNavTrailing_070() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: true)]
}

// MARK: - Previews
//
// Previews never run `.task` — store stays in `.loading` so both
// registers render a deterministic skeleton without hitting the
// network. No fixtures.

#Preview("070 · Me Settlements · Night") {
    MeSettlementsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("070 · Me Settlements · Afternoon") {
    MeSettlementsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
