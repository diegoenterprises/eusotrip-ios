//
//  401_BrokerTenders.swift
//  EusoTrip — Broker · Tenders (brick 401).
//
//  Second brick on the Broker role track (400s). The natural follow-on
//  to 400_BrokerHome — when a broker taps the "Tenders" slot in the
//  bottom nav (or the "Open tenders" card header from 400), this is
//  the full-bleed tenders surface that opens. Until 401 shipped, the
//  Tenders nav slot routed to a `RolePlaceholderScreen` stub; this
//  brick replaces that stub with a real production surface.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §2 (gradient-only
//  accent — no flat Brand.info / Brand.blue fills, no .tint(.blue)),
//  §4 (tokenized spacing / radius / type — Space.s*, Radius.*,
//  EType.*), §5 (palette semantic only — no hard-coded Color.white /
//  Color.black / Color.gray fills outside CTA inverse-text and
//  shadow opacities), §7 (`AnyShapeStyle` wrapping for ternary
//  shape-styles in fill / stroke), §10 (previews compile in
//  isolation — `.task` doesn't run in the preview canvas, so each
//  store stays in `.loading` and never hits the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data,
//  plugged into backend"):
//
//    • Tenders list  → `BrokerOpenTendersStore` (LiveDataStores.swift,
//      shipped in the 99th firing for 400_BrokerHome). 401 reuses the
//      exact store but bumps `limit = 50` so the full board renders,
//      not just the home strip's 10. Backend path:
//      `brokers.getOpenTenders` (input `{ limit: number }`).
//    • Filter chips (All / High Priority / My Network) operate
//      client-side over the loaded array — they never refetch
//      because the server endpoint doesn't currently accept a
//      filter parameter. When `brokers.getOpenTenders` grows
//      `priority` / `network` filters, the chips can flip from
//      client-side predicates to server-side input.
//    • Empty / loading / error states all surface the canonical
//      EusoTrip widgets (`EusoEmptyState`, skeleton tiles, inline
//      retry banner) — never a fabricated tender.
//    • Tap a row → presents 402_BrokerTenderDetail when that brick
//      ships. Until then, the row tap surfaces an
//      `EusoEmptyState(comingSoon: true)` placeholder sheet so the
//      affordance is discoverable but does not lie about depth.
//
//  Wired into `ContentView.ScreenRegistry` as id="401".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Filter chip

/// Client-side filter applied to the loaded tender array. Server-side
/// `brokers.getOpenTenders` does not currently accept a filter
/// parameter — when it does, this enum stays but the predicates
/// migrate into the input shape.
private enum TenderFilter: String, CaseIterable, Identifiable {
    case all
    case highPriority
    case myNetwork

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:          return "All"
        case .highPriority: return "High priority"
        case .myNetwork:    return "My network"
        }
    }

    var glyph: String {
        switch self {
        case .all:          return "tray.full.fill"
        case .highPriority: return "exclamationmark.triangle.fill"
        case .myNetwork:    return "person.2.fill"
        }
    }
}

// MARK: - Screen body

struct BrokerTenders: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var tenders = BrokerOpenTendersStore()
    @State private var filter: TenderFilter = .all

    /// When the user taps a tender row, surface 402_BrokerTenderDetail
    /// with the full preview-hint payload from the row. The 132nd
    /// firing replaced the prior comingSoon placeholder with the real
    /// 402 brick — see the deep documentation header on
    /// `Views/Broker/402_BrokerTenderDetail.swift`.
    @State private var inspectingTender: BrokerAPI.OpenTender?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                filterStrip
                tendersBody
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task {
            // Bump the limit before first fetch so the full board
            // arrives in one round trip. The store keeps `limit` as a
            // mutable property specifically for this kind of caller-
            // driven adjustment.
            tenders.limit = 50
            await tenders.refresh()
        }
        .refreshable {
            tenders.limit = 50
            await tenders.refresh()
        }
        .sheet(item: $inspectingTender) { row in
            tenderDetailSheet(for: row)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.badge.gearshape.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("BROKER · TENDERS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(headline)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(subhead)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    /// Identity-aware headline. Falls back to the role label so the
    /// header never reads as a placeholder.
    private var headline: String {
        if let name = session.user?.firstName, !name.isEmpty {
            return "Tenders, \(name)"
        }
        return "Broker · Tenders"
    }

    /// Live count surfaced in the eyebrow once the fetch resolves.
    /// While loading or in error, the line stays neutral so the
    /// header never lies about an inflight state.
    private var subhead: String {
        switch tenders.state {
        case .loading:
            return "Loading the board…"
        case .loaded(let rows):
            let visible = filteredRows(rows).count
            let total = rows.count
            if filter == .all {
                return "\(total) open tender\(total == 1 ? "" : "s") · awaiting carrier response"
            }
            return "\(visible) of \(total) open · filtered by \(filter.label.lowercased())"
        case .empty:
            return "No open tenders right now"
        case .error:
            return "Couldn't load the tenders board"
        }
    }

    // MARK: - Filter strip

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(TenderFilter.allCases) { f in
                    filterChip(f)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(_ f: TenderFilter) -> some View {
        let active = (filter == f)
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                filter = f
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: f.glyph)
                    .font(.system(size: 10, weight: .heavy))
                Text(f.label)
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(
                active
                ? AnyShapeStyle(Color.white)
                : AnyShapeStyle(palette.textSecondary)
            )
            .background(
                ZStack {
                    if active {
                        Capsule().fill(LinearGradient.diagonal)
                    } else {
                        Capsule().fill(palette.bgCard)
                    }
                }
            )
            .overlay(
                Capsule().strokeBorder(
                    active
                    ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.5))
                    : AnyShapeStyle(palette.borderFaint),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tenders body

    @ViewBuilder
    private var tendersBody: some View {
        switch tenders.state {
        case .loading:
            listSkeleton
        case .loaded(let rows):
            let visible = filteredRows(rows)
            if visible.isEmpty {
                if rows.isEmpty {
                    emptyAllState
                } else {
                    emptyFilteredState
                }
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(visible) { row in
                        tenderRow(row)
                    }
                }
            }
        case .empty:
            emptyAllState
        case .error(let e):
            inlineError(e) { Task { await tenders.refresh() } }
        }
    }

    /// Apply the active client-side filter to the loaded array.
    /// The "high priority" predicate is currently keyed off
    /// `respondingCarriers == 0 && postedAt non-empty` — i.e., a
    /// tender posted but with zero responses is the most urgent
    /// surface to a broker. "My network" is a placeholder
    /// predicate (always returns the unfiltered set today) until
    /// the server tags rows with a `network: "primary" | "spot"`
    /// projection. The placeholder is honest: every row is shown,
    /// no fabrication.
    private func filteredRows(
        _ rows: [BrokerAPI.OpenTender]
    ) -> [BrokerAPI.OpenTender] {
        switch filter {
        case .all:
            return rows
        case .highPriority:
            return rows.filter { $0.respondingCarriers == 0 && !$0.postedAt.isEmpty }
        case .myNetwork:
            // Server doesn't yet tag rows by network. Render the full
            // set so the filter is usable but never fabricates data.
            return rows
        }
    }

    private var emptyAllState: some View {
        EusoEmptyState(
            systemImage: "doc.badge.gearshape",
            title: "No open tenders",
            subtitle: "Post a load and you'll see it here while carriers respond. Tenders awarded to a carrier disappear from this view."
        )
    }

    private var emptyFilteredState: some View {
        EusoEmptyState(
            systemImage: "line.3.horizontal.decrease.circle",
            title: "Nothing matches this filter",
            subtitle: "Try \"All\" to see every open tender."
        )
    }

    // MARK: - Tender row

    private func tenderRow(_ row: BrokerAPI.OpenTender) -> some View {
        Button {
            inspectingTender = row
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                // Priority dot — gradient when zero responses
                // (urgent), neutral otherwise.
                Circle()
                    .fill(
                        row.respondingCarriers == 0
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.tintNeutral)
                    )
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.loadNumber)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(row.origin) → \(row.destination)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                        Text("\(row.respondingCarriers) carrier\(row.respondingCarriers == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        Text("·").foregroundStyle(palette.textTertiary)
                        Text(row.postedAt.isEmpty ? "—" : "posted \(row.postedAt)")
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textTertiary)
                    }
                    if !row.shipper.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(palette.textTertiary)
                            Text(row.shipper)
                                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("OPEN")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(LinearGradient.diagonal)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(
                            Capsule().strokeBorder(
                                LinearGradient.diagonal.opacity(0.5),
                                lineWidth: 1
                            )
                        )
                    if row.targetRate > 0 {
                        Text(dollars(row.targetRate))
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                        Text("TARGET")
                            .font(.system(size: 7, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    } else {
                        Text("—")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tender detail sheet (live 402 brick)

    /// Tap on a tender row presents the real 402_BrokerTenderDetail
    /// surface. The 132nd eusotrip-killers firing replaced the prior
    /// comingSoon placeholder with this live wrapper — every preview
    /// hint from the OpenTender row carries through so the sheet has
    /// paint-1 visible content while `loads.getById` resolves. The
    /// detail view internally renders em-dash sentinels for every
    /// blank server field per §13 no-fake-data doctrine.
    @ViewBuilder
    private func tenderDetailSheet(for row: BrokerAPI.OpenTender) -> some View {
        BrokerTenderDetailScreen(
            theme: palette,
            tenderId: row.id,
            previewLoadNumber: row.loadNumber,
            previewLane: "\(row.origin) → \(row.destination)",
            previewPostedAt: row.postedAt,
            previewRespondingCarriers: row.respondingCarriers,
            previewTargetRate: row.targetRate > 0 ? row.targetRate : nil,
            previewShipper: row.shipper
        )
        .environmentObject(session)
    }

    // MARK: - Shared widgets

    private var listSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 84)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }

    private func inlineError(_ error: Error, retry: @escaping () -> Void) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 1) {
                Text("Couldn't load tenders")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(error.localizedDescription)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: retry) {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Formatting

    private func dollars(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Screen wrapper
//
// 132nd firing note: the prior `TenderInspectIdentity` bridge type
// was removed once the sheet started binding directly on
// `BrokerAPI.OpenTender` (Identifiable + Hashable). The full row
// payload is now what drives the 402 sheet, which lets the detail
// surface render preview hints during the in-flight `loads.getById`.

struct BrokerTendersScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            BrokerTenders()
        } nav: {
            BottomNav(
                leading: brokerNavLeading_401(),
                trailing: brokerNavTrailing_401(),
                orbState: .idle
            )
        }
    }
}

private func brokerNavLeading_401() -> [NavSlot] {
    [NavSlot(label: "Home",    systemImage: "house",                isCurrent: false),
     NavSlot(label: "Tenders", systemImage: "doc.badge.gearshape",  isCurrent: true)]
}

private func brokerNavTrailing_401() -> [NavSlot] {
    [NavSlot(label: "Carriers", systemImage: "person.2", isCurrent: false),
     NavSlot(label: "Me",       systemImage: "person",   isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews compile in isolation.

#Preview("401 · Broker · Tenders · Night") {
    BrokerTendersScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("401 · Broker · Tenders · Afternoon") {
    BrokerTendersScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
