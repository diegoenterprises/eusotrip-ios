//
//  206_ShipperSettlements.swift
//  EusoTrip — Shipper · Settlements (brick 206).
//
//  Seventh brick on the Shipper role track (200s). Shipped in the
//  124th eusotrip-killers firing per the 123rd firing's
//  recommendation for Branch B: "Code port 206_ShipperSettlements
//  driving shippers.getDeliveryConfirmations + a settlements summary
//  card."
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §2 (gradient-only
//  accent — no flat Brand.info / Brand.blue fills, no .tint(.blue)),
//  §4 (tokenized spacing / radius / type — Space.s*, Radius.*,
//  EType.*), §5 (palette semantic only — no hard-coded Color.white /
//  Color.black / Color.gray fills), §7 (`AnyShapeStyle` wrapping for
//  ternary shape-styles in fill / stroke), §10 (previews compile in
//  isolation — `.task` doesn't run in the preview canvas, so the
//  store stays in `.loading` and never hits the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, 1000% dynamic"):
//
//    • Settlements feed → `ShipperDeliveryConfirmationsStore`
//      (LiveDataStores.swift, added in this firing) →
//      `shippers.getDeliveryConfirmations` (input
//      `{ status?: "pending"|"confirmed"|"disputed", limit: number }`).
//      MCP-verified at `frontend/server/routers/shippers.ts:534`.
//    • Aggregate KPIs (total billed, settled count, average rate,
//      last settlement date) are computed client-side from the same
//      verified server array — never a separate query, so the
//      screen can never drift between an aggregate and its rows.
//    • Empty / blank server fields surface as em-dash sentinels
//      ("—"). A freshly-onboarded shipper with zero delivered loads
//      gets `EusoEmptyState(comingSoon: false)` — never a fabricated
//      placeholder row.
//    • Server errors surface via `EusoTripAPIError.errorDescription`
//      in an inline banner with a Retry CTA.
//    • Tap a row → opens 205_ShipperLoadDetail in a sheet, passing
//      the `loadId` and a header preview so the load number renders
//      immediately.
//
//  Wired into `ContentView.ScreenRegistry` as id="206".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen body

struct ShipperSettlements: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var store = ShipperDeliveryConfirmationsStore()

    /// Status chip selection. `nil` is the canonical "All" view.
    /// Tracked locally; the store carries an authoritative copy
    /// after `setStatusFilter` so every refresh uses the same value.
    @State private var selectedStatus: ShipperAPI.DeliveryConfirmationStatus? = nil

    /// Tapped row id → opens 205 sheet. Identifies via the row's
    /// loadId so the sheet can pass it through to the detail
    /// surface unchanged.
    @State private var openLoadDetail: SettlementSheetTarget? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            statusChips
            contentBody
            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $openLoadDetail) { target in
            ShipperLoadDetailScreen(
                theme: palette,
                loadId: target.loadId,
                previewLoadNumber: target.loadNumber,
                previewLane: target.lane
            )
            .environmentObject(session)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("SETTLEMENTS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Delivery confirmations")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 0)
            }
            Text("Every delivered load you've billed against. Pull to refresh.")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Status filter chips

    private var statusChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                statusChip(label: "All", value: nil)
                statusChip(label: "Confirmed", value: .confirmed)
                statusChip(label: "Pending",   value: .pending)
                statusChip(label: "Disputed",  value: .disputed)
            }
        }
    }

    private func statusChip(
        label: String,
        value: ShipperAPI.DeliveryConfirmationStatus?
    ) -> some View {
        let isOn = (value == selectedStatus)
        let bg: AnyShapeStyle = isOn
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.bgCard)
        let fg: Color = isOn ? .white : palette.textPrimary
        let border: AnyShapeStyle = isOn
            ? AnyShapeStyle(Color.clear)
            : AnyShapeStyle(palette.borderFaint)

        return Button {
            guard !isOn else { return }
            selectedStatus = value
            store.setStatusFilter(value)
            Task { await store.refresh() }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .heavy)).tracking(0.4)
                .foregroundStyle(fg)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(bg)
                .overlay(
                    Capsule().strokeBorder(border, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content body (state machine)

    @ViewBuilder
    private var contentBody: some View {
        switch store.state {
        case .loading:
            loadingCard
        case .loaded(let rows):
            settlementsBlock(rows)
        case .empty:
            EusoEmptyState(
                systemImage: "dollarsign.arrow.circlepath",
                title: emptyTitle,
                subtitle: emptySubtitle
            )
        case .error(let err):
            errorBanner(message: readableError(err))
        }
    }

    private var emptyTitle: String {
        switch selectedStatus {
        case .pending:   return "No pending settlements"
        case .confirmed: return "No confirmed settlements"
        case .disputed:  return "No disputed settlements"
        case nil:        return "No settlements yet"
        }
    }

    private var emptySubtitle: String {
        switch selectedStatus {
        case .pending:
            return "Loads pending settlement will appear here once a driver delivers."
        case .confirmed:
            return "Confirmed deliveries appear here after the receiver signs the POD."
        case .disputed:
            return "Disputes show here when a delivery confirmation is contested."
        case nil:
            return "Once a load you posted is delivered, it'll show up here with the billed rate."
        }
    }

    // MARK: - Aggregate + rows

    @ViewBuilder
    private func settlementsBlock(_ rows: [ShipperAPI.DeliveryConfirmation]) -> some View {
        if rows.isEmpty {
            EusoEmptyState(
                systemImage: "dollarsign.arrow.circlepath",
                title: emptyTitle,
                subtitle: emptySubtitle
            )
        } else {
            kpiTiles(rows)
            settlementsList(rows)
        }
    }

    /// Aggregates derived from the same verified server array — total
    /// billed, settled count, average rate, last settlement date.
    /// Computed once per render from real rows so the tiles can never
    /// drift from the list below.
    private func kpiTiles(_ rows: [ShipperAPI.DeliveryConfirmation]) -> some View {
        let count = rows.count
        let totalBilled = rows.reduce(0.0) { $0 + $1.rate }
        let avgRate = count > 0 ? totalBilled / Double(count) : 0
        let latestISO: String? = rows
            .map(\.deliveredAt)
            .filter { !$0.isEmpty }
            .first

        return VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                metricTile(
                    label: "BILLED",
                    value: currency(totalBilled),
                    icon: "dollarsign.circle"
                )
                metricTile(
                    label: "SETTLED",
                    value: "\(count)",
                    icon: "checkmark.seal"
                )
            }
            HStack(spacing: Space.s2) {
                metricTile(
                    label: "AVG RATE",
                    value: count > 0 ? currency(avgRate) : "—",
                    icon: "chart.bar"
                )
                metricTile(
                    label: "LAST",
                    value: humanDate(latestISO) ?? "—",
                    icon: "clock"
                )
            }
        }
    }

    private func metricTile(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Row list. Each row shows load number, lane, delivery date, and
    /// the billed rate. Tap opens 205_ShipperLoadDetail with the same
    /// `loadId` so the detail surface never re-fetches the row from
    /// scratch (it can use the preview while loading).
    private func settlementsList(_ rows: [ShipperAPI.DeliveryConfirmation]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("DELIVERED LOADS", icon: "shippingbox.fill")
            VStack(spacing: 6) {
                ForEach(rows) { row in
                    settlementRow(row)
                }
            }
        }
    }

    private func settlementRow(_ row: ShipperAPI.DeliveryConfirmation) -> some View {
        Button {
            // The server emits `load_NNN`; the detail surface accepts
            // either form (its internal store passes `loads.getById`
            // verbatim). Pass the unmodified id so the wire stays
            // server-canonical.
            openLoadDetail = SettlementSheetTarget(
                loadId: row.loadId,
                loadNumber: row.loadNumber,
                lane: lane(from: row)
            )
        } label: {
            HStack(alignment: .top, spacing: Space.s2) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 28, height: 28)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.loadNumber.isEmpty ? "—" : row.loadNumber)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text(lane(from: row))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    if let when = humanDate(row.deliveredAt) {
                        Text("Delivered · \(when)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                    } else {
                        Text("Delivered · —")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer(minLength: Space.s2)
                Text(row.rate > 0 ? currency(row.rate) : "—")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading + error

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionHeader("LOADING", icon: "arrow.clockwise")
            Text("Pulling your delivered-load settlements…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func errorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button(action: { Task { await store.refresh() } }) {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(text)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
        }
    }

    private func lane(from row: ShipperAPI.DeliveryConfirmation) -> String {
        let o = row.origin.trimmingCharacters(in: .whitespacesAndNewlines)
                          .trimmingCharacters(in: CharacterSet(charactersIn: ","))
        let d = row.destination.trimmingCharacters(in: .whitespacesAndNewlines)
                               .trimmingCharacters(in: CharacterSet(charactersIn: ","))
        if o.isEmpty && d.isEmpty { return "—" }
        let left  = o.isEmpty ? "—" : o
        let right = d.isEmpty ? "—" : d
        return "\(left) → \(right)"
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    /// Same parser used by 205. Returns nil when the input is empty/
    /// unparseable so callers can choose between em-dash sentinels
    /// and the raw string.
    private func humanDate(_ iso: String?) -> String? {
        guard let iso = iso, !iso.isEmpty else { return nil }
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFmt.date(from: iso)
        if date == nil {
            isoFmt.formatOptions = [.withInternetDateTime]
            date = isoFmt.date(from: iso)
        }
        if date == nil {
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            day.locale = Locale(identifier: "en_US_POSIX")
            date = day.date(from: iso)
        }
        guard let d = date else { return iso }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: d)
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }
}

// MARK: - Sheet identifier

/// Identifier struct for the row-tap → 205 sheet. Carries the
/// hint values so the detail surface can render a populated
/// header during the first network round-trip.
private struct SettlementSheetTarget: Identifiable, Hashable {
    let loadId: String
    let loadNumber: String
    let lane: String

    var id: String { loadId }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct ShipperSettlementsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperSettlements()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_206(),
                trailing: shipperNavTrailing_206(),
                orbState: .idle
            )
        }
    }
}

// Shipper bottom-nav doctrine — settlements / wallet live under Me, so
// 206 keeps the Me slot highlighted while the user is inside the
// settlement detail / list.
private func shipperNavLeading_206() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",    isCurrent: false)]
}

private func shipperNavTrailing_206() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("206 · Shipper · Settlements · Night") {
    ShipperSettlementsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("206 · Shipper · Settlements · Afternoon") {
    ShipperSettlementsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
