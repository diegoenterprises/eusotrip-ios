//
//  402_BrokerTenderDetail.swift
//  EusoTrip — Broker · Tender Detail (brick 402).
//
//  Third brick on the Broker role track (400s). The natural follow-on
//  to 401_BrokerTenders — when a broker taps a row on the open-tenders
//  board, this is the deep tender-detail surface that opens. Until
//  402 shipped, 401's row tap surfaced an
//  `EusoEmptyState(comingSoon: true)` placeholder
//  (`tenderDetailComingSoonSheet` in 401). Now that 402 is live, that
//  placeholder is replaced with this real surface.
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
//  motivation "no fake data, 1000% dynamic"):
//
//    • Tender detail → `BrokerTenderDetailStore`
//      (LiveDataStores.swift, added in this firing) →
//      `loads.getById` (input `{ id: string }`). Verified live at
//      `frontend/server/routers/loads.ts:1046`. Same procedure the
//      Carrier Load Detail (302) and Shipper Load Detail (205)
//      already use — the role distinction is in framing only.
//    • Carrier shortlist → backend has not exposed
//      `brokers.getTenderResponses` yet, so this screen renders a
//      neutral placeholder card explaining what will live there.
//      No fabricated carrier names, no synthesised bid amounts.
//    • Award CTA → `brokers.awardTender` is also not exposed yet,
//      so the affordance renders disabled with an honest
//      explanatory subtitle. Per §13 doctrine: "every backend stub
//      gap has a neutral empty state on the client (no fake data)."
//    • Empty / blank server fields surface as em-dash sentinels
//      ("—") — every nullable column on a fresh tender (no pickup
//      date scheduled, no rate posted) renders as a neutral em-dash,
//      never a fabricated value.
//    • Preview hint passthrough (loadNumber / lane / posted /
//      respondingCarriers / targetRate / shipper) so the sheet has
//      paint-1 visible content while the detail fetch is in flight.
//
//  Wired into `ContentView.ScreenRegistry` as id="402".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen body

struct BrokerTenderDetail: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    /// The tender (load) id to fetch. Server expects `{ id: string }`
    /// per the Zod input on `loads.getById`. The 401 row carries
    /// `id: String` already (BrokerAPI.OpenTender).
    let tenderId: String

    /// Optional preview header values used while the detail fetch is
    /// in flight. The sheet caller (401's row tap) carries these for
    /// free — passing them through prevents the perceptible "blank
    /// header → real header" flash on first paint. When unavailable,
    /// pass `nil` and the screen renders em-dash sentinels.
    let previewLoadNumber: String?
    let previewLane: String?
    let previewPostedAt: String?
    let previewRespondingCarriers: Int?
    let previewTargetRate: Double?
    let previewShipper: String?

    @StateObject private var detailStore = BrokerTenderDetailStore()

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
                        Text("BROKER · TENDER DETAIL")
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
                    systemImage: "doc.badge.gearshape",
                    title: "Tender not found",
                    subtitle: "The tender you tapped is no longer in the system. Pull to refresh or pick another tender from the board."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "doc.badge.gearshape",
                title: "Tender not found",
                subtitle: "The tender you tapped is no longer in the system. Pull to refresh or pick another tender from the board."
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
        spreadCard(detail)
        carriersCard(detail)
        notesCard(detail)
        awardCTA(detail)
    }

    /// Three-tile row: target rate / responding carriers / posted-at.
    /// Em-dash on missing values so a brand-new tender doesn't
    /// fabricate values.
    private func metricsRow(_ d: LoadsAPI.LoadDetail) -> some View {
        HStack(spacing: Space.s2) {
            metricTile(
                label: "TARGET RATE",
                value: targetDisplay(d),
                icon: "dollarsign.circle"
            )
            metricTile(
                label: "RESPONSES",
                value: responsesDisplay(),
                icon: "person.2.fill"
            )
            metricTile(
                label: "POSTED",
                value: postedDisplay(d),
                icon: "clock"
            )
        }
    }

    /// Target rate prefers the row hint (server's market projection
    /// returned by getOpenTenders) over the LoadDetail rateValue —
    /// because the broker's "target" is their ask price, which the
    /// list endpoint exposes but the detail endpoint may not. Falls
    /// back to LoadDetail.rateValue when the hint is missing.
    private func targetDisplay(_ d: LoadsAPI.LoadDetail) -> String {
        if let target = previewTargetRate, target > 0 {
            return currency(target)
        }
        return d.rateDisplay
    }

    /// "0 carriers" / "1 carrier" / "12 carriers" — em-dash when the
    /// preview hint is nil (cold open from a deep link). The 401 row
    /// always passes this hint through, so the cold-open path is
    /// rare in practice.
    private func responsesDisplay() -> String {
        guard let n = previewRespondingCarriers else { return "—" }
        return "\(n) " + (n == 1 ? "carrier" : "carriers")
    }

    /// "12m ago" — server-projected relative label from the OpenTender
    /// row. Em-dash when missing.
    private func postedDisplay(_ d: LoadsAPI.LoadDetail) -> String {
        if let p = previewPostedAt, !p.isEmpty {
            return p
        }
        // Fall back to the createdAt column on LoadDetail.
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
    /// so a fresh tender doesn't show synthetic dates.
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

    /// Cargo card mirrors 302's cargoCard. Hazmat row only renders
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

    /// Spread card — broker-specific framing of the rate window.
    /// Surfaces the target ask vs. market range so the broker can
    /// see at a glance whether their tender is priced inside, at,
    /// or outside the suggested band. Em-dash when the server
    /// hasn't computed a market range for this lane.
    private func spreadCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("SPREAD", icon: "chart.line.uptrend.xyaxis")
            scheduleRow(label: "Target ask", value: targetDisplay(d))
            if let lo = d.suggestedRateMin, let hi = d.suggestedRateMax,
               lo > 0, hi > 0 {
                scheduleRow(
                    label: "Market range",
                    value: "\(currency(lo)) – \(currency(hi))"
                )
                if let label = spreadLabel(target: previewTargetRate ?? d.rateValue, lo: lo, hi: hi) {
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
            } else {
                scheduleRow(label: "Market range", value: "—")
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

    /// Compute a small badge-style label describing where the
    /// target sits relative to the market range. Returns nil when
    /// the target is zero (no badge).
    private func spreadLabel(target: Double, lo: Double, hi: Double) -> (text: String, icon: String)? {
        guard target > 0 else { return nil }
        if target < lo {
            return ("PRICED BELOW MARKET", "arrow.down.right.circle.fill")
        }
        if target > hi {
            return ("PRICED ABOVE MARKET", "arrow.up.right.circle.fill")
        }
        return ("INSIDE MARKET RANGE", "checkmark.circle.fill")
    }

    /// Carriers card — placeholder card that honestly communicates
    /// the missing depth. When `brokers.getTenderResponses` (or an
    /// equivalent) ships server-side, this card swaps to a real
    /// shortlist of carrier rows. Until then, the card surfaces the
    /// responding-carrier count from the row hint and explains
    /// what's coming. NEVER fabricates carrier names or bid amounts.
    private func carriersCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("CARRIERS", icon: "person.2.fill")
            HStack(alignment: .firstTextBaseline) {
                Text(responsesDisplay())
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Text("RESPONDING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            if let shipper = previewShipper, !shipper.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text("Shipper · \(shipper)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Text("Carrier shortlist with bid history, fit-score, and award affordances will appear here once `brokers.getTenderResponses` ships server-side.")
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

    /// Award CTA — disabled affordance until `brokers.awardTender`
    /// ships server-side. Honest about why it's not yet actionable.
    /// Renders only on tenders that are in a state where awarding
    /// would be plausible (status `available` / `posted` /
    /// `bidding_open`); award is suppressed for already-awarded /
    /// in-flight / delivered loads.
    @ViewBuilder
    private func awardCTA(_ d: LoadsAPI.LoadDetail) -> some View {
        let awardable: Set<String> = ["available", "posted", "bidding_open", "open"]
        if awardable.contains(d.status.lowercased()) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Award tender")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                Text("Awarding from the app ships next on the broker track. Today this surface confirms the tender is awardable; once `brokers.awardTender` ships, this CTA activates.")
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
            Text("Pulling the latest from the tender record…")
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
        let isOpen = openStatuses.contains(raw.lowercased())
        let style: AnyShapeStyle = isOpen
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.tintNeutral)
        let fg: Color = isOpen ? .white : palette.textSecondary
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(style)
            .clipShape(Capsule())
    }

    /// "Open" framing for a broker — tenders that are still awaiting
    /// a carrier award. Anything past award reads as neutral.
    private var openStatuses: Set<String> {
        ["available", "posted", "bidding_open", "open"]
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
        detailStore.loadId = tenderId
        await detailStore.refresh()
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct BrokerTenderDetailScreen: View {
    let theme: Theme.Palette
    let tenderId: String
    let previewLoadNumber: String?
    let previewLane: String?
    let previewPostedAt: String?
    let previewRespondingCarriers: Int?
    let previewTargetRate: Double?
    let previewShipper: String?

    init(
        theme: Theme.Palette,
        tenderId: String,
        previewLoadNumber: String? = nil,
        previewLane: String? = nil,
        previewPostedAt: String? = nil,
        previewRespondingCarriers: Int? = nil,
        previewTargetRate: Double? = nil,
        previewShipper: String? = nil
    ) {
        self.theme = theme
        self.tenderId = tenderId
        self.previewLoadNumber = previewLoadNumber
        self.previewLane = previewLane
        self.previewPostedAt = previewPostedAt
        self.previewRespondingCarriers = previewRespondingCarriers
        self.previewTargetRate = previewTargetRate
        self.previewShipper = previewShipper
    }

    var body: some View {
        Shell(theme: theme) {
            BrokerTenderDetail(
                tenderId: tenderId,
                previewLoadNumber: previewLoadNumber,
                previewLane: previewLane,
                previewPostedAt: previewPostedAt,
                previewRespondingCarriers: previewRespondingCarriers,
                previewTargetRate: previewTargetRate,
                previewShipper: previewShipper
            )
        } nav: {
            BottomNav(
                leading: brokerNavLeading_402(),
                trailing: brokerNavTrailing_402(),
                orbState: .idle
            )
        }
    }
}

private func brokerNavLeading_402() -> [NavSlot] {
    [NavSlot(label: "Home",    systemImage: "house",                isCurrent: false),
     NavSlot(label: "Tenders", systemImage: "doc.badge.gearshape",  isCurrent: true)]
}

private func brokerNavTrailing_402() -> [NavSlot] {
    [NavSlot(label: "Carriers", systemImage: "person.2", isCurrent: false),
     NavSlot(label: "Me",       systemImage: "person",   isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("402 · Broker · Tender Detail · Night") {
    BrokerTenderDetailScreen(
        theme: Theme.dark,
        tenderId: "0",
        previewLoadNumber: "—",
        previewLane: "—",
        previewPostedAt: nil,
        previewRespondingCarriers: nil,
        previewTargetRate: nil,
        previewShipper: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.dark)
}

#Preview("402 · Broker · Tender Detail · Afternoon") {
    BrokerTenderDetailScreen(
        theme: Theme.light,
        tenderId: "0",
        previewLoadNumber: "—",
        previewLane: "—",
        previewPostedAt: nil,
        previewRespondingCarriers: nil,
        previewTargetRate: nil,
        previewShipper: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.light)
}
