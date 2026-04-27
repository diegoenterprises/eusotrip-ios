//
//  502_CatalystMatchDetail.swift
//  EusoTrip — Catalyst · Match Detail (brick 502).
//
//  Third brick on the Catalyst role track (500s). The natural follow-on
//  to 501_CatalystMatches — when a catalyst taps a row on the
//  active-matches board, this is the deep match-detail surface that
//  opens. Until 502 shipped, 501's row tap surfaced an
//  `EusoEmptyState(comingSoon: true)` placeholder
//  (`matchDetailComingSoonSheet` in 501). Now that 502 is live, that
//  placeholder is replaced with this real surface and Catalyst depth
//  matches the structural depth of Carrier (300/301/302) and Broker
//  (400/401/402): three production screens per role.
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
//    • Match detail → `CatalystMatchDetailStore`
//      (LiveDataStores.swift, added in this firing) →
//      `loads.getById` (input `{ id: string }`). Verified live at
//      `frontend/server/routers/loads.ts:1046`. Same procedure the
//      Broker Tender Detail (402), Carrier Load Detail (302), and
//      Shipper Load Detail (205) already use — the role distinction
//      is in framing only.
//    • Candidate shortlist → backend has not exposed
//      `catalysts.getMatchCandidates` yet, so this screen renders a
//      neutral placeholder card explaining what will live there.
//      No fabricated carrier names, no synthesised fit scores per
//      candidate.
//    • Override-to-manual CTA → `catalysts.overrideMatch` is also
//      not exposed yet, so the affordance renders disabled with an
//      honest explanatory subtitle. Per §13 doctrine: "every
//      backend stub gap has a neutral empty state on the client
//      (no fake data)."
//    • Empty / blank server fields surface as em-dash sentinels
//      ("—") — every nullable column on a fresh match (no pickup
//      date scheduled, no rate posted, no agent attached) renders
//      as a neutral em-dash, never a fabricated value.
//    • Preview hint passthrough (loadNumber / lane / startedAt /
//      candidateCount / bestFitScore / agentName) so the sheet
//      has paint-1 visible content while the detail fetch is in
//      flight. Mirrors the 402_BrokerTenderDetail preview-hint
//      pattern.
//
//  Wired into `ContentView.ScreenRegistry` as id="502".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen body

struct CatalystMatchDetail: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    /// The match (load) id to fetch. Server expects `{ id: string }`
    /// per the Zod input on `loads.getById`. The 501 row carries
    /// `id: String` already (CatalystAPI.ActiveMatch).
    let matchId: String

    /// Optional preview header values used while the detail fetch is
    /// in flight. The sheet caller (501's row tap) carries these for
    /// free — passing them through prevents the perceptible "blank
    /// header → real header" flash on first paint. When unavailable,
    /// pass `nil` and the screen renders em-dash sentinels.
    let previewLoadNumber: String?
    let previewLane: String?
    let previewStartedAt: String?
    let previewCandidateCount: Int?
    let previewBestFitScore: Double?
    let previewAgentName: String?

    @StateObject private var detailStore = CatalystMatchDetailStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                contentBody
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
    }

    // MARK: - Header
    //
    // Always-visible header. Renders from preview hints until the live
    // detail row arrives, then swaps in the server-emitted values.

    private var header: some View {
        let live: LoadsAPI.LoadDetail? = detailStore.state.value ?? nil
        let loadNumber = live?.loadNumber ?? previewLoadNumber ?? "—"
        let lane: String = live?.laneDisplay ?? previewLane ?? "—"
        let status = live?.status ?? ""

        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
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
                        Text("CATALYST · MATCH DETAIL")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Text(loadNumber)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 0)
                if !status.isEmpty {
                    statusPill(status)
                }
            }
            Text(lane)
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Content body (state machine)

    @ViewBuilder
    private var contentBody: some View {
        switch detailStore.state {
        case .loading:
            loadingCard
        case .loaded(let opt):
            if let detail = opt {
                detailCards(for: detail)
            } else {
                EusoEmptyState(
                    systemImage: "scope",
                    title: "Match not found",
                    subtitle: "The match you tapped is no longer in the system. Pull to refresh or pick another match from the board."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "scope",
                title: "Match not found",
                subtitle: "The match you tapped is no longer in the system. Pull to refresh or pick another match from the board."
            )
        case .error(let err):
            errorBanner(message: readableError(err))
        }
    }

    // MARK: - Detail cards (live data)

    @ViewBuilder
    private func detailCards(for detail: LoadsAPI.LoadDetail) -> some View {
        metricsRow(detail)
        scheduleCard(detail)
        cargoCard(detail)
        spectraMatchCard(detail)
        candidatesCard(detail)
        notesCard(detail)
        overrideCTA(detail)
    }

    /// Three-tile row: best fit / candidates / started.
    /// Em-dash on missing values so a brand-new match doesn't
    /// fabricate values.
    private func metricsRow(_ d: LoadsAPI.LoadDetail) -> some View {
        HStack(spacing: Space.s2) {
            metricTile(
                label: "BEST FIT",
                value: bestFitDisplay(),
                icon: "sparkles"
            )
            metricTile(
                label: "CANDIDATES",
                value: candidatesDisplay(),
                icon: "person.2.fill"
            )
            metricTile(
                label: "STARTED",
                value: startedDisplay(d),
                icon: "clock"
            )
        }
    }

    /// SpectraMatch fit score (0.0–1.0) → "92%" presentation form.
    /// Mirrors the format used on 500/501 so the same envelope reads
    /// identically across the Catalyst track. Em-dash when the row
    /// hint is missing or zero (no carrier scored yet).
    private func bestFitDisplay() -> String {
        guard let v = previewBestFitScore, v > 0 else { return "—" }
        let clamped = min(max(v, 0), 1)
        let pct = Int((clamped * 100).rounded())
        return "\(pct)%"
    }

    /// "0 candidates" / "1 candidate" / "12 candidates" — em-dash
    /// when the preview hint is nil (cold open from a deep link).
    /// The 501 row always passes this hint through, so the cold-open
    /// path is rare in practice.
    private func candidatesDisplay() -> String {
        guard let n = previewCandidateCount else { return "—" }
        return "\(n) " + (n == 1 ? "candidate" : "candidates")
    }

    /// "started 2m" — server-projected relative label from the
    /// ActiveMatch row. Falls back to the LoadDetail.createdAt
    /// when the row hint is missing. Em-dash when both are absent.
    private func startedDisplay(_ d: LoadsAPI.LoadDetail) -> String {
        if let s = previewStartedAt, !s.isEmpty {
            return s
        }
        return humanDate(d.createdAt)
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

    /// Pickup / delivery / bidding-ends. Em-dash on missing columns
    /// so a fresh match doesn't show synthetic dates.
    private func scheduleCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("SCHEDULE", icon: "calendar")
            scheduleRow(label: "Pickup",       value: humanDate(d.pickupDate))
            scheduleRow(label: "Delivery",     value: humanDate(d.deliveryDate))
            if d.biddingEnds != nil {
                scheduleRow(label: "Bidding ends", value: humanDate(d.biddingEnds))
            }
            if d.estimatedDeliveryDate != nil {
                scheduleRow(label: "Est. delivery", value: humanDate(d.estimatedDeliveryDate))
            }
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

    private func scheduleRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: Space.s2)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Cargo card mirrors 402's cargoCard. Hazmat row only renders
    /// when the load is hazmat (so non-hazmat loads don't show
    /// "Hazmat: —" filler).
    private func cargoCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("CARGO", icon: "shippingbox")
            scheduleRow(label: "Type", value: humanCargoType(d.cargoType))
            if let commodity = (d.commodity ?? d.commodityName), !commodity.isEmpty {
                scheduleRow(label: "Commodity", value: commodity)
            }
            if let equip = d.equipmentType, !equip.isEmpty {
                scheduleRow(label: "Equipment", value: equip)
            }
            if let w = d.weightDisplay as String?, w != "—" {
                scheduleRow(label: "Weight", value: w)
            }
            if let dist = d.distanceDisplay as String?, dist != "—" {
                scheduleRow(label: "Distance", value: dist)
            }
            if let hz = d.hazmatClass, !hz.isEmpty {
                scheduleRow(label: "Hazmat class", value: hz)
                if let un = d.unNumber, !un.isEmpty {
                    scheduleRow(label: "UN number", value: un)
                }
                if let g = d.ergGuide {
                    scheduleRow(label: "ERG guide", value: "#\(g)")
                }
            }
            if d.spectraMatchVerified == true {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SPECTRA-MATCH VERIFIED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .padding(.top, 2)
            }
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

    /// SpectraMatch card — catalyst-specific framing of the autopilot
    /// envelope. Surfaces fit score, agent in the loop, and a
    /// posture badge that interprets the score relative to the
    /// Autopilot 7-layer cortex high-confidence threshold (0.85).
    /// Em-dash when the server hasn't scored a candidate yet.
    private func spectraMatchCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("SPECTRAMATCH", icon: "wand.and.stars")
            scheduleRow(label: "Best fit",  value: bestFitDisplay())
            scheduleRow(
                label: "Agent",
                value: (previewAgentName?.isEmpty == false ? previewAgentName! : "Manual")
            )
            if let label = fitPosture(previewBestFitScore ?? 0) {
                HStack(spacing: 6) {
                    Image(systemName: label.icon)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(label.text)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .padding(.top, 2)
            }
            // If the server has computed a market range for this
            // lane, surface it as context — useful when the catalyst
            // is choosing whether to override to a manual price.
            if let lo = d.suggestedRateMin, let hi = d.suggestedRateMax,
               lo > 0, hi > 0 {
                scheduleRow(
                    label: "Lane market",
                    value: "\(currency(lo)) – \(currency(hi))"
                )
            }
            if let cur = d.currency, !cur.isEmpty, cur.uppercased() != "USD" {
                scheduleRow(label: "Currency", value: cur.uppercased())
            }
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

    /// Compute a small badge-style label describing the fit score's
    /// posture relative to the Autopilot high-confidence band (0.85).
    /// Returns nil when the score is zero (no badge).
    private func fitPosture(_ score: Double) -> (text: String, icon: String)? {
        guard score > 0 else { return nil }
        if score >= 0.85 {
            return ("HIGH-CONFIDENCE FIT", "checkmark.circle.fill")
        }
        if score >= 0.6 {
            return ("MODERATE FIT", "exclamationmark.circle.fill")
        }
        return ("LOW FIT — CONSIDER OVERRIDE", "arrow.triangle.swap")
    }

    /// Candidates card — placeholder card that honestly communicates
    /// the missing depth. When `catalysts.getMatchCandidates` (or an
    /// equivalent) ships server-side, this card swaps to a real
    /// shortlist of candidate carrier rows with per-candidate fit
    /// scores. Until then, the card surfaces the candidate count
    /// from the row hint and explains what's coming. NEVER fabricates
    /// carrier names or per-candidate scores.
    private func candidatesCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("CANDIDATES", icon: "person.2.fill")
            HStack(alignment: .firstTextBaseline) {
                Text(candidatesDisplay())
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Text("SCORED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            if let agent = previewAgentName, !agent.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text("Agent · \(agent)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Text("Per-candidate scoring rubric, agent breakdown, and fit-score history will appear here once `catalysts.getMatchCandidates` ships server-side.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
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

    /// Notes block — only renders when the load actually carries
    /// special-instructions text from the server. Drafts with no
    /// notes get the section omitted entirely (no "—" filler).
    @ViewBuilder
    private func notesCard(_ d: LoadsAPI.LoadDetail) -> some View {
        if let notes = d.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("NOTES", icon: "text.alignleft")
                Text(notes)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
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
    }

    /// Override-to-manual CTA — disabled affordance until
    /// `catalysts.overrideMatch` ships server-side. Honest about
    /// why it's not yet actionable. Renders only on matches that
    /// are in a state where overriding would be plausible (status
    /// `available` / `posted` / `bidding_open` / `matching`); the
    /// CTA is suppressed for already-locked / in-flight / delivered
    /// matches.
    @ViewBuilder
    private func overrideCTA(_ d: LoadsAPI.LoadDetail) -> some View {
        let overridable: Set<String> = ["available", "posted", "bidding_open", "open", "matching"]
        if overridable.contains(d.status.lowercased()) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Override to manual")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                Text("Manual override pulls the match out of SpectraMatch and lets the catalyst pick a carrier directly. Today this surface confirms the match is overridable; once `catalysts.overrideMatch` ships, this CTA activates.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: - Loading + error states

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionHeader("LOADING", icon: "arrow.clockwise")
            Text("Pulling the latest from the match record…")
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
            Button(action: { Task { await refreshAll() } }) {
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

    private func statusPill(_ raw: String) -> some View {
        let label = raw.replacingOccurrences(of: "_", with: " ").uppercased()
        let isLive = liveStatuses.contains(raw.lowercased())
        let style: AnyShapeStyle = isLive
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.tintNeutral)
        let fg: Color = isLive ? .white : palette.textSecondary
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(style)
            .clipShape(Capsule())
    }

    /// "Live" framing for a catalyst — matches that are still in
    /// the autopilot loop. Anything past assignment reads as neutral.
    private var liveStatuses: Set<String> {
        ["available", "posted", "bidding_open", "open", "matching"]
    }

    /// Map the backend's lowercase enum value to a sentence-case label.
    /// Em-dash on empty/nil so a draft cargoType missing from the row
    /// surfaces as a neutral cell.
    private func humanCargoType(_ raw: String?) -> String {
        guard let r = raw, !r.isEmpty else { return "—" }
        switch r.lowercased() {
        case "general":      return "General freight"
        case "hazmat":       return "Hazmat"
        case "petroleum":    return "Petroleum"
        case "gas":          return "Gas"
        case "chemicals":    return "Chemicals"
        case "refrigerated": return "Refrigerated"
        case "container":    return "Container"
        case "bulk":         return "Bulk"
        default:             return r.capitalized
        }
    }

    /// Parse an ISO-8601 date string from the server and render as a
    /// short human-readable form (e.g. "Apr 28 · 09:30"). Em-dash
    /// when nil / empty / unparseable so missing dates always look
    /// like a deliberate sentinel.
    private func humanDate(_ iso: String?) -> String {
        guard let iso = iso, !iso.isEmpty else { return "—" }
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFmt.date(from: iso)
        if date == nil {
            isoFmt.formatOptions = [.withInternetDateTime]
            date = isoFmt.date(from: iso)
        }
        if date == nil {
            // Server occasionally hands back YYYY-MM-DD only.
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            day.locale = Locale(identifier: "en_US_POSIX")
            date = day.date(from: iso)
        }
        guard let d = date else { return iso }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d · HH:mm"
        return fmt.string(from: d)
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }

    private func refreshAll() async {
        detailStore.loadId = matchId
        await detailStore.refresh()
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct CatalystMatchDetailScreen: View {
    let theme: Theme.Palette
    let matchId: String
    let previewLoadNumber: String?
    let previewLane: String?
    let previewStartedAt: String?
    let previewCandidateCount: Int?
    let previewBestFitScore: Double?
    let previewAgentName: String?

    init(
        theme: Theme.Palette,
        matchId: String,
        previewLoadNumber: String? = nil,
        previewLane: String? = nil,
        previewStartedAt: String? = nil,
        previewCandidateCount: Int? = nil,
        previewBestFitScore: Double? = nil,
        previewAgentName: String? = nil
    ) {
        self.theme = theme
        self.matchId = matchId
        self.previewLoadNumber = previewLoadNumber
        self.previewLane = previewLane
        self.previewStartedAt = previewStartedAt
        self.previewCandidateCount = previewCandidateCount
        self.previewBestFitScore = previewBestFitScore
        self.previewAgentName = previewAgentName
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystMatchDetail(
                matchId: matchId,
                previewLoadNumber: previewLoadNumber,
                previewLane: previewLane,
                previewStartedAt: previewStartedAt,
                previewCandidateCount: previewCandidateCount,
                previewBestFitScore: previewBestFitScore,
                previewAgentName: previewAgentName
            )
        } nav: {
            BottomNav(
                leading: catalystNavLeading_502(),
                trailing: catalystNavTrailing_502(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_502() -> [NavSlot] {
    [NavSlot(label: "Home",    systemImage: "house",   isCurrent: false),
     NavSlot(label: "Matches", systemImage: "scope",   isCurrent: true)]
}

private func catalystNavTrailing_502() -> [NavSlot] {
    [NavSlot(label: "Network", systemImage: "person.2", isCurrent: false),
     NavSlot(label: "Me",      systemImage: "person",   isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("502 · Catalyst · Match Detail · Night") {
    CatalystMatchDetailScreen(
        theme: Theme.dark,
        matchId: "0",
        previewLoadNumber: "—",
        previewLane: "—",
        previewStartedAt: nil,
        previewCandidateCount: nil,
        previewBestFitScore: nil,
        previewAgentName: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.dark)
}

#Preview("502 · Catalyst · Match Detail · Afternoon") {
    CatalystMatchDetailScreen(
        theme: Theme.light,
        matchId: "0",
        previewLoadNumber: "—",
        previewLane: "—",
        previewStartedAt: nil,
        previewCandidateCount: nil,
        previewBestFitScore: nil,
        previewAgentName: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.light)
}
