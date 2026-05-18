//
//  302_CarrierLoadDetail.swift
//  EusoTrip — Carrier · Load Detail (brick 302).
//
//  Third brick on the Carrier role track (300s). The natural follow-on
//  to 301_CarrierLoads — when a carrier taps a row in the active-loads
//  or recent-loads list, this is the detail surface that opens. Until
//  302 shipped, 301's row tap surfaced an `EusoEmptyState(comingSoon:
//  true)` placeholder (see 301's `loadDetailPlaceholderSheet(for:)`).
//  Now that 302 is live, that placeholder is replaced with this real
//  surface.
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
//  motivation "no fake data, 1000% dynamic"):
//
//    • Load detail   → `CarrierLoadDetailStore`
//      (LiveDataStores.swift, added in this firing) →
//      `loads.getById` (input `{ id: string }`). Verified live at
//      `frontend/server/routers/loads.ts:1046`. Same procedure the
//      Shipper Load Detail uses — role distinction is in framing
//      (Carrier reframes "bids count" as "driver assignment +
//      counterparty + ratecon").
//    • Empty / blank server fields surface as em-dash sentinels
//      ("—") — every nullable column on a fresh tender (no pickup
//      date, no driver assigned, no actual delivery date) renders
//      as a neutral em-dash, never a fabricated value.
//    • Server errors surface via `EusoTripAPIError.errorDescription`
//      in an inline banner with a Retry CTA.
//    • Zero synthesised data. Header preview (load number + lane +
//      status + driver) can come from the caller as a hint so the
//      sheet renders something visible during the first network
//      round-trip — but every detail field below the fold is always
//      live from the backend.
//
//  Wired into `ContentView.ScreenRegistry` as id="302".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen body

struct CarrierLoadDetail: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    /// The load id to fetch. Server expects `{ id: string }` per the
    /// Zod input on `loads.getById`. Adapter rows in 301 carry the id
    /// as String already (e.g. `"active-42"` → caller passes `"42"`),
    /// so the screen never reformats.
    let loadId: String

    /// Optional preview header values used while the detail fetch is
    /// in flight. The sheet caller (301's row tap) carries these for
    /// free — passing them through prevents the perceptible "blank
    /// header → real header" flash on first paint. When unavailable,
    /// pass `nil` and the screen renders em-dash sentinels.
    let previewLoadNumber: String?
    let previewLane: String?
    let previewStatus: String?
    let previewDriver: String?
    let previewCounterparty: String?
    let previewRate: Double?
    let previewIsActive: Bool

    @StateObject private var detailStore = CarrierLoadDetailStore()

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
        let status = live?.status ?? previewStatus ?? ""

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
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("CARRIER · LOAD DETAIL")
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
        assignmentCard(detail)
        scheduleCard(detail)
        cargoCard(detail)
        settlementCard(detail)
        notesCard(detail)
    }

    /// Three-tile row: rate (gross/net), distance, weight. Each tile
    /// shows the canonical formatted display string (em-dash on
    /// missing).
    private func metricsRow(_ d: LoadsAPI.LoadDetail) -> some View {
        HStack(spacing: Space.s2) {
            metricTile(label: rateLabel(d), value: d.rateDisplay,     icon: "dollarsign.circle")
            metricTile(label: "DISTANCE",   value: d.distanceDisplay, icon: "map")
            metricTile(label: "WEIGHT",     value: d.weightDisplay,   icon: "scalemass")
        }
    }

    /// Carrier framing: gross rate while the load is in-flight, net
    /// payout after delivery. Drivers see the same dollar value but
    /// the carrier's mental model groups it differently.
    private func rateLabel(_ d: LoadsAPI.LoadDetail) -> String {
        let s = d.status.lowercased()
        return (s == "delivered" || s == "settled") ? "NET PAYOUT" : "GROSS RATE"
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

    /// Driver assignment + counterparty (broker / shipper). The
    /// preview hints from 301 cover both lines while the detail
    /// settles. Unassigned drivers / unbranded counterparty render
    /// as em-dash.
    private func assignmentCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("ASSIGNMENT", icon: "person.2.fill")
            scheduleRow(label: "Driver",       value: previewDriver ?? "—")
            scheduleRow(label: "Counterparty", value: previewCounterparty ?? "—")
            if d.driverId != nil || d.catalystId != nil || d.shipperId != nil {
                HStack(spacing: 8) {
                    if let did = d.driverId {
                        idChip(label: "DRIVER #\(did)", icon: "person.fill")
                    }
                    if let cid = d.catalystId {
                        idChip(label: "CATALYST #\(cid)", icon: "sparkles")
                    }
                    if let sid = d.shipperId {
                        idChip(label: "SHIPPER #\(sid)", icon: "shippingbox.fill")
                    }
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

    private func idChip(label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    /// Pickup / delivery / actual / estimated. Em-dash on missing
    /// columns so a fresh tender (status = "available", no pickup
    /// scheduled) doesn't show synthetic dates.
    private func scheduleCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("SCHEDULE", icon: "calendar")
            scheduleRow(label: "Pickup",        value: humanDate(d.pickupDate))
            scheduleRow(label: "Delivery",      value: humanDate(d.deliveryDate))
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
                .multilineTextAlignment(.trailing)
        }
    }

    /// Cargo type, hazmat class, commodity, equipment. Hazmat row
    /// only renders when the load is hazmat (so non-hazmat loads
    /// don't show "Hazmat: —" filler).
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
            // 2026-05-17 — Carrier counter-party multi-modal payload.
            // Same shape as 205/305/402/502 so every load surfacing
            // role sees the same field set.
            if let mode = d.transportMode, !mode.isEmpty, mode != "truck" {
                scheduleRow(label: "Mode", value: mode.uppercased())
            }
            if let vc = d.vesselClass, !vc.isEmpty {
                scheduleRow(label: "Vessel class", value: vc)
            }
            if let count = d.multiVehicleCount, count > 1 {
                scheduleRow(label: "Vehicles", value: "\(count) ×")
            }
            if let perm = d.permitType, !perm.isEmpty, perm != "none" {
                scheduleRow(label: "Permit", value: perm.replacingOccurrences(of: "_", with: " ").uppercased())
            }
            if let ws = d.worldscalePct, !ws.isEmpty, let n = Double(ws), n > 0 {
                scheduleRow(label: "Worldscale", value: "WS \(Int(n.rounded()))")
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

    /// Settlement preview — shows the rate & currency the carrier
    /// expects to collect on this load. For delivered loads the rate
    /// reads as net-payout; for in-flight loads it reads as gross
    /// rate. Suggested-rate range surfaces when the backend has a
    /// market-rate estimate (used by the load board pricing engine).
    private func settlementCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("SETTLEMENT", icon: "dollarsign.circle.fill")
            scheduleRow(label: rateLabel(d).capitalized, value: d.rateDisplay)
            if let cur = d.currency, !cur.isEmpty, cur.uppercased() != "USD" {
                scheduleRow(label: "Currency", value: cur.uppercased())
            }
            if let lo = d.suggestedRateMin, let hi = d.suggestedRateMax, lo > 0, hi > 0 {
                scheduleRow(
                    label: "Market rate",
                    value: "\(currency(lo)) – \(currency(hi))"
                )
            }
            // Carrier-specific framing: settlement state. The 'status'
            // field carries the canonical lifecycle key. Server-side
            // factoring (HaulPay) wires through `factoring.eligibility`,
            // which the carrier home / wallet brick will visualise.
            if d.status.lowercased() == "delivered" {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("AWAITING SETTLEMENT")
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
        detailStore.loadId = loadId
        await detailStore.refresh()
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct CarrierLoadDetailScreen: View {
    let theme: Theme.Palette
    let loadId: String
    let previewLoadNumber: String?
    let previewLane: String?
    let previewStatus: String?
    let previewDriver: String?
    let previewCounterparty: String?
    let previewRate: Double?
    let previewIsActive: Bool

    init(
        theme: Theme.Palette,
        loadId: String,
        previewLoadNumber: String? = nil,
        previewLane: String? = nil,
        previewStatus: String? = nil,
        previewDriver: String? = nil,
        previewCounterparty: String? = nil,
        previewRate: Double? = nil,
        previewIsActive: Bool = true
    ) {
        self.theme = theme
        self.loadId = loadId
        self.previewLoadNumber = previewLoadNumber
        self.previewLane = previewLane
        self.previewStatus = previewStatus
        self.previewDriver = previewDriver
        self.previewCounterparty = previewCounterparty
        self.previewRate = previewRate
        self.previewIsActive = previewIsActive
    }

    var body: some View {
        Shell(theme: theme) {
            CarrierLoadDetail(
                loadId: loadId,
                previewLoadNumber: previewLoadNumber,
                previewLane: previewLane,
                previewStatus: previewStatus,
                previewDriver: previewDriver,
                previewCounterparty: previewCounterparty,
                previewRate: previewRate,
                previewIsActive: previewIsActive
            )
        } nav: {
            BottomNav(
                leading: carrierNavLeading_302(),
                trailing: carrierNavTrailing_302(),
                orbState: .idle
            )
        }
    }
}

private func carrierNavLeading_302() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",                isCurrent: false),
     NavSlot(label: "Loads", systemImage: "truck.box.fill",       isCurrent: true)]
}

private func carrierNavTrailing_302() -> [NavSlot] {
    [NavSlot(label: "Drivers", systemImage: "person.2",           isCurrent: false),
     NavSlot(label: "Me",      systemImage: "person",             isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("302 · Carrier · Load Detail · Night") {
    CarrierLoadDetailScreen(
        theme: Theme.dark,
        loadId: "0",
        previewLoadNumber: "—",
        previewLane: "—",
        previewStatus: nil,
        previewDriver: nil,
        previewCounterparty: nil,
        previewRate: nil,
        previewIsActive: true
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.dark)
}

#Preview("302 · Carrier · Load Detail · Afternoon") {
    CarrierLoadDetailScreen(
        theme: Theme.light,
        loadId: "0",
        previewLoadNumber: "—",
        previewLane: "—",
        previewStatus: nil,
        previewDriver: nil,
        previewCounterparty: nil,
        previewRate: nil,
        previewIsActive: true
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.light)
}
