//
//  205_ShipperLoadDetail.swift
//  EusoTrip — Shipper · Load Detail (brick 205).
//
//  Sixth brick on the Shipper role track (200s). The natural follow-on
//  to 121st's 204 ShipperPostLoad — when a shipper taps a row in the
//  201 Shipper · Loads list, this is the detail surface that opens.
//  Until 205 shipped, 201's row tap surfaced an `EusoEmptyState
//  (comingSoon: true)` placeholder (see 201's `loadDetailPlaceholder
//  Sheet(for:)`). Now that 205 is live, the placeholder is replaced
//  with this real surface.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §2 (gradient-only
//  accent — no flat Brand.info / Brand.blue fills, no .tint(.blue)),
//  §4 (tokenized spacing / radius / type — Space.s*, Radius.*,
//  EType.*), §5 (palette semantic only — no hard-coded Color.white /
//  Color.black / Color.gray fills), §7 (`AnyShapeStyle` wrapping for
//  ternary shape-styles in fill / stroke), §10 (previews compile in
//  isolation — `.task` doesn't run in the preview canvas, so each
//  store stays in `.loading` and never hits the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Load detail   → `ShipperLoadDetailStore`
//      (LiveDataStores.swift, added in this firing) →
//      `loads.getById` (input `{ id: string }`). MCP-verified at
//      `frontend/server/routers/loads.ts:1046`.
//    • Bids preview  → reuses the existing `ShipperBidsStore`
//      (LiveDataStores.swift L3336) → `shippers.getBidsForLoad
//      (loadId)`. MCP-verified at
//      `frontend/server/routers/shippers.ts:358`. The screen renders
//      a 1-line "N bids · highest $X" badge (real values, never a
//      synthesised count) and links over to 203 Shipper · Bids for
//      the full triage UX.
//    • Empty / blank server fields surface as em-dash sentinels
//      ("—") — every nullable column on a freshly-posted draft (no
//      pickup date, no rate yet, no driver assigned, etc.) renders
//      as a neutral em-dash, never a fabricated value.
//    • Server errors surface via `EusoTripAPIError.errorDescription`
//      in an inline banner with a Retry CTA.
//    • Zero synthesised data. Header preview (load number + lane)
//      can come from the caller as a hint so the sheet renders
//      something visible during the first network round-trip — but
//      every detail field below the fold is always live.
//
//  Wired into `ContentView.ScreenRegistry` as id="205".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen body

struct ShipperLoadDetail: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    /// The load id to fetch. Server expects `{ id: string }` per the
    /// Zod input on `loads.getById`. Adapter rows in 201 carry the id
    /// as String already (e.g. `"active-42"` → caller passes `"42"`),
    /// so the screen never reformats.
    let loadId: String

    /// Optional preview header values used while the detail fetch is
    /// in flight. The sheet caller (201's row tap) carries these for
    /// free — passing them through prevents the perceptible "blank
    /// header → real header" flash on first paint. When unavailable,
    /// pass `nil` and the screen renders em-dash sentinels.
    let previewLoadNumber: String?
    let previewLane: String?

    @StateObject private var detailStore = ShipperLoadDetailStore()
    @StateObject private var bidsStore = ShipperBidsStore()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            contentBody
            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
    }

    // MARK: - Header

    /// Always-visible header. Renders from `previewLoadNumber` /
    /// `previewLane` until the live detail row arrives, then swaps in
    /// the server-emitted values verbatim.
    private var header: some View {
        // `state.value` for a Value of type `LoadDetail?` is itself
        // `Value?` (i.e. `LoadDetail??`); `?? nil` flattens that to a
        // single optional so the downstream property reads only need
        // one `?`.
        let live: LoadsAPI.LoadDetail? = detailStore.state.value ?? nil
        let loadNumber = live?.loadNumber ?? previewLoadNumber ?? "—"
        let lane: String = live?.laneDisplay ?? previewLane ?? "—"
        let status = live?.status ?? ""

        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOAD DETAIL")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
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
                    systemImage: "doc.text",
                    title: "Load not found",
                    subtitle: "The load you tapped is no longer in the system. Pull to refresh or pick another load from the list."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "doc.text",
                title: "Load not found",
                subtitle: "The load you tapped is no longer in the system. Pull to refresh or pick another load from the list."
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
        bidsCard(detail)
        notesCard(detail)
    }

    /// Three-tile row: rate, distance, weight. Each tile shows the
    /// canonical formatted display string (em-dash on missing).
    private func metricsRow(_ d: LoadsAPI.LoadDetail) -> some View {
        HStack(spacing: Space.s2) {
            metricTile(label: "RATE",     value: d.rateDisplay,     icon: "dollarsign.circle")
            metricTile(label: "DISTANCE", value: d.distanceDisplay, icon: "map")
            metricTile(label: "WEIGHT",   value: d.weightDisplay,   icon: "scalemass")
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

    /// Pickup / delivery / bidding ends + ETA dates. Em-dash whenever
    /// the column is missing (a freshly-posted draft has no pickup
    /// date, no estimated delivery date, etc.).
    private func scheduleCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("SCHEDULE", icon: "calendar")
            scheduleRow(label: "Pickup",     value: humanDate(d.pickupDate))
            scheduleRow(label: "Delivery",   value: humanDate(d.deliveryDate))
            if d.estimatedDeliveryDate != nil {
                scheduleRow(label: "Est. delivery", value: humanDate(d.estimatedDeliveryDate))
            }
            if d.actualDeliveryDate != nil {
                scheduleRow(label: "Delivered",     value: humanDate(d.actualDeliveryDate))
            }
            if d.biddingEnds != nil {
                scheduleRow(label: "Bidding ends",  value: humanDate(d.biddingEnds))
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
        }
    }

    /// Cargo type, hazmat class, commodity, equipment. Hazmat row
    /// only renders when the load is hazmat (so non-hazmat loads
    /// don't show "Hazmat: —" filler).
    private func cargoCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("CARGO", icon: "shippingbox")
            scheduleRow(label: "Type",     value: humanCargoType(d.cargoType))
            if let commodity = (d.commodity ?? d.commodityName), !commodity.isEmpty {
                scheduleRow(label: "Commodity", value: commodity)
            }
            if let equip = d.equipmentType, !equip.isEmpty {
                scheduleRow(label: "Equipment", value: equip)
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

    /// Bids preview row. Renders the live bid count and highest amount
    /// pulled from `shippers.getBidsForLoad`. Empty list → neutral
    /// "no bids yet" caption (no fabricated count).
    private func bidsCard(_ d: LoadsAPI.LoadDetail) -> some View {
        let rows = bidsStore.state.value ?? []
        let count = rows.count
        let highest = rows.map { $0.amount }.max() ?? 0
        return VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("BIDS", icon: "hand.raised")
            if bidsStore.isLoading && count == 0 {
                Text("Loading bids…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else if count == 0 {
                Text("No bids yet — carriers will surface offers here as they come in.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 6) {
                    Text("\(count) bid\(count == 1 ? "" : "s")")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if highest > 0 {
                        Text("· highest \(currency(highest))")
                            .font(EType.body)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
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

    // MARK: - Loading + error states

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionHeader("LOADING", icon: "arrow.clockwise")
            Text("Pulling the latest from the load record…")
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
        let isActive = activeStatuses.contains(raw.lowercased())
        let style: AnyShapeStyle = isActive
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.tintNeutral)
        let fg: Color = isActive ? .white : palette.textSecondary
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(style)
            .clipShape(Capsule())
    }

    private var activeStatuses: Set<String> {
        ["assigned", "in_transit", "picked_up", "at_pickup", "at_delivery"]
    }

    /// Map the backend's lowercase enum value to a sentence-case label.
    /// Em-dash on empty/nil so a draft cargoType missing from the row
    /// surfaces as a neutral cell.
    private func humanCargoType(_ raw: String?) -> String {
        guard let r = raw, !r.isEmpty else { return "—" }
        switch r.lowercased() {
        case "general":     return "General freight"
        case "hazmat":      return "Hazmat"
        case "petroleum":   return "Petroleum"
        case "gas":         return "Gas"
        case "chemicals":   return "Chemicals"
        case "refrigerated": return "Refrigerated"
        case "container":   return "Container"
        case "bulk":        return "Bulk"
        default:            return r.capitalized
        }
    }

    /// Parse an ISO-8601 date string from the server and render as a
    /// short human-readable form (e.g. "Apr 28 · 09:30"). Em-dash
    /// when nil / empty / unparseable so missing dates always look
    /// like a deliberate sentinel and never an error string.
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
        // Bind ids first; both refreshes are idempotent and safe to
        // run concurrently. The bids store is happy to surface an
        // empty-array result while the detail is still loading.
        detailStore.loadId = loadId
        bidsStore.setLoadId(loadId)
        async let a: Void = detailStore.refresh()
        async let b: Void = bidsStore.refresh()
        _ = await (a, b)
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct ShipperLoadDetailScreen: View {
    let theme: Theme.Palette
    let loadId: String
    let previewLoadNumber: String?
    let previewLane: String?

    var body: some View {
        Shell(theme: theme) {
            ShipperLoadDetail(
                loadId: loadId,
                previewLoadNumber: previewLoadNumber,
                previewLane: previewLane
            )
        } nav: {
            BottomNav(
                leading: shipperNavLeading_205(),
                trailing: shipperNavTrailing_205(),
                orbState: .idle
            )
        }
    }
}

private func shipperNavLeading_205() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",                isCurrent: false),
     NavSlot(label: "Loads", systemImage: "shippingbox.fill",     isCurrent: true)]
}

private func shipperNavTrailing_205() -> [NavSlot] {
    [NavSlot(label: "Bids",  systemImage: "hand.raised",          isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",               isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so each store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("205 · Shipper · Load Detail · Night") {
    ShipperLoadDetailScreen(
        theme: Theme.dark,
        loadId: "0",
        previewLoadNumber: nil,
        previewLane: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.dark)
}

#Preview("205 · Shipper · Load Detail · Afternoon") {
    ShipperLoadDetailScreen(
        theme: Theme.light,
        loadId: "0",
        previewLoadNumber: nil,
        previewLane: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.light)
}
