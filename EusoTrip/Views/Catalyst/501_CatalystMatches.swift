//
//  501_CatalystMatches.swift
//  EusoTrip — Catalyst · Matches (brick 501).
//
//  Second brick on the Catalyst role track (500s). The natural follow-on
//  to 500_CatalystHome — when a catalyst taps the "Matches" slot in the
//  bottom nav (or the "View all" CTA on the home's active-matches card),
//  this is the full-bleed match-board surface that opens. Until 501
//  shipped, the Matches nav slot routed to a `RolePlaceholderScreen`
//  stub; this brick replaces that stub with a real production surface.
//
//  Direct mirror of `Views/Broker/401_BrokerTenders.swift` shipped in
//  the 132nd-prep firing. Same scaffolding (header, filter strip,
//  list body, skeleton, empty/error states), reframed around the
//  SpectraMatch fit-score envelope rather than open-tender flow:
//
//    • Broker `OpenTender.respondingCarriers` → Catalyst
//      `ActiveMatch.candidateCount` (SpectraMatch carriers in the
//      autopilot scoring fan-out, not bidder count).
//    • Broker `targetRate` (dollars) → Catalyst `bestFitScore`
//      (0.0–1.0 SpectraMatch confidence; rendered as a percent).
//    • Broker `shipper` row → Catalyst `agentName` (one of the 52
//      Autopilot 7-layer cortex agents per backend §16 intelligence
//      slice; empty when the catalyst is running the match
//      manually).
//    • Filter chips reframed: All / High Fit / Stalled. "High Fit"
//      surfaces matches with bestFitScore ≥ 0.85 (Autopilot
//      confidence threshold). "Stalled" surfaces matches with
//      candidateCount == 0 — the autopilot fanned out but no
//      carrier scored, the catalyst probably wants to intervene.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §2 (gradient-only
//  accent — no flat Brand.info / Brand.blue fills, no .tint(.blue)),
//  §4 (tokenized spacing / radius / type — Space.s*, Radius.*,
//  EType.*), §5 (palette semantic only — no hard-coded Color.white /
//  Color.black / Color.gray fills outside CTA inverse-text and
//  shadow opacities), §7 (`AnyShapeStyle` wrapping for ternary
//  shape-styles in fill / stroke), §10 (previews compile in
//  isolation — `.task` doesn't run in the preview canvas, so the
//  store stays in `.loading` and never hits the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data,
//  plugged into backend"):
//
//    • Matches list → `CatalystActiveMatchesStore` (LiveDataStores.swift,
//      shipped in the 102nd firing for 500_CatalystHome). 501 reuses
//      the exact store but bumps `limit = 50` so the full match-board
//      renders, not just the home strip's 10. Backend path:
//      `catalysts.getActiveMatches` (input `{ limit: number }`).
//    • Filter chips (All / High Fit / Stalled) operate client-side
//      over the loaded array — they never refetch because the server
//      endpoint doesn't currently accept a filter parameter. When
//      `catalysts.getActiveMatches` grows `minFit` / `stalled`
//      filters, the chips can flip from client-side predicates to
//      server-side input.
//    • Empty / loading / error states all surface the canonical
//      EusoTrip widgets (`EusoEmptyState`, skeleton tiles, inline
//      retry banner) — never a fabricated match.
//    • Tap a row → presents the real 502_CatalystMatchDetail sheet
//      (shipped 2026-04-27 in the 136th firing). Every preview
//      hint from the ActiveMatch row (loadNumber, lane, startedAt,
//      candidateCount, bestFitScore, agentName) carries through so
//      the sheet has paint-1 visible content while `loads.getById`
//      resolves. Candidate shortlist + override-to-manual CTA on
//      502 render as honest placeholders until
//      `catalysts.getMatchCandidates` / `catalysts.overrideMatch`
//      ship server-side.
//
//  Wired into `ContentView.ScreenRegistry` as id="501".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Filter chip
//
// Client-side filter applied to the loaded match array. Server-side
// `catalysts.getActiveMatches` does not currently accept a filter
// parameter — when it does, this enum stays but the predicates
// migrate into the input shape.

private enum MatchFilter: String, CaseIterable, Identifiable {
    case all
    case highFit
    case stalled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:     return "All"
        case .highFit: return "High fit"
        case .stalled: return "Stalled"
        }
    }

    var glyph: String {
        switch self {
        case .all:     return "scope"
        case .highFit: return "checkmark.seal.fill"
        case .stalled: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Screen body

struct CatalystMatches: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var matches = CatalystActiveMatchesStore()
    @State private var filter: MatchFilter = .all

    /// When the user taps a match row, surface the live 502
    /// CatalystMatchDetail sheet (shipped 2026-04-27 in the 136th
    /// firing). Identifiable on the row drives sheet item-binding
    /// so the sheet recreates fresh on each tap.
    @State private var inspectingMatch: CatalystAPI.ActiveMatch?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                filterStrip
                matchesBody
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task {
            // Bump the limit before first fetch so the full board
            // arrives in one round trip. The store keeps `limit`
            // as a mutable property specifically for this kind of
            // caller-driven adjustment (mirrors the 401 broker
            // tenders pattern).
            matches.limit = 50
            await matches.refresh()
        }
        .refreshable {
            matches.limit = 50
            await matches.refresh()
        }
        .sheet(item: $inspectingMatch) { row in
            matchDetailSheet(for: row)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // RealtimeService WebSocket: refresh the matches board the
        // moment SpectraMatch fires a fresh candidate, a carrier
        // accepts/rejects a tender, or a load gets reassigned. The
        // dashboard never lies about what's live.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task {
                matches.limit = 50
                await matches.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task {
                matches.limit = 50
                await matches.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task {
                matches.limit = 50
                await matches.refresh()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "scope")
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
                    Text("CATALYST · MATCHES")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(headline)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.75)
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
            return "Matches, \(name)"
        }
        return "Catalyst · Matches"
    }

    /// Live count surfaced in the eyebrow once the fetch resolves.
    /// While loading or in error, the line stays neutral so the
    /// header never lies about an inflight state.
    private var subhead: String {
        switch matches.state {
        case .loading:
            return "Loading the match board…"
        case .loaded(let rows):
            let visible = filteredRows(rows).count
            let total = rows.count
            if filter == .all {
                return "\(total) live match\(total == 1 ? "" : "es") · SpectraMatch in the loop"
            }
            return "\(visible) of \(total) live · filtered by \(filter.label.lowercased())"
        case .empty:
            return "No live matches right now"
        case .error:
            return "Couldn't load the match board"
        }
    }

    // MARK: - Filter strip

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(MatchFilter.allCases) { f in
                    filterChip(f)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(_ f: MatchFilter) -> some View {
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

    // MARK: - Matches body

    @ViewBuilder
    private var matchesBody: some View {
        switch matches.state {
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
                        matchRow(row)
                    }
                }
            }
        case .empty:
            emptyAllState
        case .error(let e):
            inlineError(e) { Task { await matches.refresh() } }
        }
    }

    /// Apply the active client-side filter to the loaded array.
    /// "High fit" surfaces matches with `bestFitScore >= 0.85`
    /// (the Autopilot 7-layer cortex's high-confidence threshold
    /// per backend §16 intelligence slice). "Stalled" surfaces
    /// matches with `candidateCount == 0` — SpectraMatch fanned
    /// out across the network but nobody scored, so the catalyst
    /// probably wants to widen the radius or override to manual.
    private func filteredRows(
        _ rows: [CatalystAPI.ActiveMatch]
    ) -> [CatalystAPI.ActiveMatch] {
        switch filter {
        case .all:
            return rows
        case .highFit:
            return rows.filter { $0.bestFitScore >= 0.85 }
        case .stalled:
            return rows.filter { $0.candidateCount == 0 }
        }
    }

    private var emptyAllState: some View {
        EusoEmptyState(
            systemImage: "scope",
            title: "No live matches",
            subtitle: "Start an autopilot agent and you'll see its match candidates ladder up here in real time. SpectraMatch will fan out across the carrier network and score the best fit."
        )
    }

    private var emptyFilteredState: some View {
        EusoEmptyState(
            systemImage: "line.3.horizontal.decrease.circle",
            title: "Nothing matches this filter",
            subtitle: "Try \"All\" to see every live match."
        )
    }

    // MARK: - Match row

    private func matchRow(_ row: CatalystAPI.ActiveMatch) -> some View {
        Button {
            inspectingMatch = row
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                // Status dot — gradient when stalled (candidateCount
                // == 0, urgent), neutral otherwise. Mirrors the
                // 401 broker tender priority dot.
                Circle()
                    .fill(
                        row.candidateCount == 0
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.tintNeutral)
                    )
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.loadNumber)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        // 2026-05-17 — Mode badge on Catalyst match row.
                        // ActiveMatch wire shape already decodes the field;
                        // server projection landing in a future firing
                        // will light up rail / vessel / barge matches.
                        LoadModeBadge(modeRaw: row.transportMode,
                                      multiVehicleCount: row.multiVehicleCount,
                                      compact: true)
                    }
                    Text("\(row.origin) → \(row.destination)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                        Text("\(row.candidateCount) candidate\(row.candidateCount == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        Text("·").foregroundStyle(palette.textTertiary)
                        Text(row.startedAt.isEmpty ? "—" : "started \(row.startedAt)")
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textTertiary)
                    }
                    if !row.agentName.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.circle.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(palette.textTertiary)
                            Text(row.agentName)
                                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(LinearGradient.diagonal)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(
                            Capsule().strokeBorder(
                                LinearGradient.diagonal.opacity(0.5),
                                lineWidth: 1
                            )
                        )
                    if row.bestFitScore > 0 {
                        Text(fitScore(row.bestFitScore))
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                        Text("BEST FIT")
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

    // MARK: - Match detail sheet (live 502 brick)

    /// Tap on a match row presents the real 502_CatalystMatchDetail
    /// surface. The 136th eusotrip-killers firing replaced the prior
    /// `matchDetailComingSoonSheet` placeholder with this live wrapper
    /// — every preview hint from the ActiveMatch row carries through
    /// so the sheet has paint-1 visible content while
    /// `loads.getById` resolves. The detail view internally renders
    /// em-dash sentinels for every blank server field per §13
    /// no-fake-data doctrine. Candidate shortlist + override-to-
    /// manual CTA render as honest placeholders until
    /// `catalysts.getMatchCandidates` / `catalysts.overrideMatch`
    /// ship server-side.
    @ViewBuilder
    private func matchDetailSheet(for row: CatalystAPI.ActiveMatch) -> some View {
        CatalystMatchDetailScreen(
            theme: palette,
            matchId: row.id,
            previewLoadNumber: row.loadNumber,
            previewLane: "\(row.origin) → \(row.destination)",
            previewStartedAt: row.startedAt,
            previewCandidateCount: row.candidateCount,
            previewBestFitScore: row.bestFitScore > 0 ? row.bestFitScore : nil,
            previewAgentName: row.agentName.isEmpty ? nil : row.agentName
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
                Text("Couldn't load matches")
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

    /// SpectraMatch fit score (0.0–1.0) → "92%" presentation form.
    /// Mirrors the format used on 500_CatalystHome so the same
    /// envelope reads identically in both places.
    private func fitScore(_ v: Double) -> String {
        let clamped = min(max(v, 0), 1)
        let pct = Int((clamped * 100).rounded())
        return "\(pct)%"
    }
}

// MARK: - Screen wrapper

struct CatalystMatchesScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            CatalystMatches()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_501(),
                trailing: catalystNavTrailing_501(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_501() -> [NavSlot] {
    [NavSlot(label: "Home",    systemImage: "house",        isCurrent: false),
     NavSlot(label: "Matches", systemImage: "scope",        isCurrent: true)]
}

private func catalystNavTrailing_501() -> [NavSlot] {
    [NavSlot(label: "Network", systemImage: "person.2",     isCurrent: false),
     NavSlot(label: "Me",      systemImage: "person",       isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews compile in isolation.

#Preview("501 · Catalyst · Matches · Night") {
    CatalystMatchesScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("501 · Catalyst · Matches · Afternoon") {
    CatalystMatchesScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
