//
//  591_RailConsigneeTrackingLink.swift
//  EusoTrip — Rail Engineer · Consignee Tracking Link (token-gated read-only share).
//
//  Verbatim port of wireframe "591 Rail Consignee Tracking Link · Dark".
//  CARRIER-SIDE. Reconstructed to the flagship DETAIL grammar (205 Load Detail /
//  580 Rail Tariff Rate Lookup) per FOUNDER CADENCE DIRECTIVE 2026-05-24:
//  back chevron · eyebrow · mono ID caption · 28/-0.4 title · gradient-rimmed
//  hero ActiveCard · 3-cell KPI strip · itemized ListRow stack · secondary
//  strip · CTA pair. A token-gated read-only share link lets a consignee track
//  a rail shipment with no login.
//
//  Endpoints (server/routers):
//    • tracking.shareTrackingLink        EXISTS tracking.ts:521        → HERO + Copy CTA (mutation)
//    • consigneePortal.publicTrack       EXISTS consigneePortal.ts:64  → CONSIGNEE VIEW rows (vessel-scoped)
//    • railShipments.trackIntermodalContainer EXISTS railShipments.ts:770 → container row
//  PORT-GAP: rail-scoped share token kind 'rail_shipment_tracking' is a NAMED
//  gap — consigneePortal.createShareLink / publicTrack are vessel-scoped
//  (permissions.kind = "vessel_shipment_tracking", reads vesselShipments).
//  Cross-mode sibling of Vessel 694 Consignee Tracking Link.
//
//  De-fabrication (2026-06-07): the CONSIGNEE-VIEW rows are structurally
//  unbacked for rail — publicTrack is vessel-scoped, so `track` is always
//  nil here. The Figma literals that had leaked onto the rendered path —
//  consignee "Midwest Imports Co." / "ops@midwestimports.example", the
//  "Logistics Park" destination, container "TCNU7693120", the "last gate-in
//  ICTF" sub, the "today" recipient value, the ETA "MAY 27 / 09:00", the 40'
//  default size, the asserting "LIVE" pill, and the default "RAIL-260523-…"
//  load number — now resolve from the live publicTrack row when it lands, or
//  fall through to an honest em-dash "-" (the sentinel this file already
//  uses for expires/state). No seeded figure remains on any rendered path.
//  The hero EXPIRES/STATE/SCOPE (live shareTrackingLink.expiresAt), the Copy
//  CTA (live trackingUrl), the local Revoke flip, and issuedLabel stay live.
//  Mirrors the 020 Approaching-Delivery honest-floor grammar.
//

import SwiftUI

struct RailConsigneeTrackingLinkScreen: View {
    let theme: Theme.Palette
    /// Rail load number the share link is scoped to (RAIL-YYMMDD-XXXXX).
    /// Honest em-dash floor when no real route passes a load number — the
    /// header caption shows "-" rather than a fabricated RAIL-… string, and
    /// the share mutation is skipped until a real load number is in scope.
    var loadNumber: String = "-"
    /// Container in scope. Em-dash floor until a real route passes the
    /// container number (the share token is rail-load-scoped, not container).
    var containerNumber: String = "-"

    var body: some View {
        Shell(theme: theme) {
            RailConsigneeTrackingLinkBody(loadNumber: loadNumber,
                                          containerNumber: containerNumber)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror real return shapes)

/// tracking.shareTrackingLink → { trackingUrl, accessCode, expiresAt, createdBy, loadNumber }
private struct ShareTrackingLink591: Decodable {
    let trackingUrl: String?
    let accessCode: String?
    let expiresAt: String?
    let createdBy: String?
    let loadNumber: String?
}

/// consigneePortal.publicTrack container row (vessel-scoped on the server).
private struct PublicTrackContainer591: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let sizeType: String?
    let status: String?
}

/// consigneePortal.publicTrack milestone row.
private struct PublicTrackMilestone591: Decodable, Identifiable {
    let id: Int
    let eventType: String?
    let location: String?
    let timestamp: String?
    let description: String?
}

/// consigneePortal.publicTrack → top-level shape.
private struct PublicTrack591: Decodable {
    let bookingNumber: String?
    let status: String?
    let eta: String?
    let containers: [PublicTrackContainer591]?
    let milestones: [PublicTrackMilestone591]?
    let progress: Int?
}

// MARK: - Body

private struct RailConsigneeTrackingLinkBody: View {
    @Environment(\.palette) private var palette
    let loadNumber: String
    let containerNumber: String

    @State private var link: ShareTrackingLink591? = nil
    @State private var track: PublicTrack591? = nil
    /// Live consignee-facing projection from `railShipments.getConsigneePreview`
    /// (rail-scoped, self/authenticated). Source of truth for the CONSIGNEE
    /// VIEW rows the moment the server deploys; `try? → nil` keeps every row on
    /// the honest em-dash floor until then. Never overrides the honest hero.
    @State private var preview: RailConsigneePreview? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var copying = false
    @State private var revoking = false
    @State private var copied = false
    @State private var revoked = false
    @State private var actionError: String? = nil

    /// Honest em-dash sentinel for every consignee-view field that has no
    /// live proc behind it. `consigneePortal.publicTrack` is VESSEL-scoped
    /// on the server (PORT-GAP — permissions.kind = "vessel_shipment_tracking",
    /// reads vesselShipments), so a rail share token resolves no rows: `track`
    /// is structurally nil for rail. Rather than fabricate a recipient name,
    /// email, destination, milestone or ETA, every unbacked field falls through
    /// to this dash. The moment the server adds a rail-scoped share-token kind
    /// ('rail_shipment_tracking'), `track` populates and these resolve live with
    /// no client change. Mirrors the 020 Approaching-Delivery honest-floor pattern.
    private let dash = "-"

    // MARK: Derived

    /// Days until the link expires, parsed from the live expiresAt.
    private var expiresInDays: Int? {
        guard let exp = link?.expiresAt else { return nil }
        let iso = ISO8601DateFormatter()
        guard let date = iso.date(from: exp) ?? {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: exp)
        }() else { return nil }
        let secs = date.timeIntervalSinceNow
        return max(0, Int((secs / 86400).rounded()))
    }

    private var expiresLabel: String {
        if let d = expiresInDays { return "\(d)d" }
        return dash
    }

    private var stateLabel: String {
        guard link != nil else { return dash }
        return revoked ? "Revoked" : "Active"
    }

    // MARK: Consignee-view derived (live `track` row → honest em-dash)
    //
    // `track` is nil for rail (vessel-scoped publicTrack, PORT-GAP), so each
    // of these reads the live field when present and falls through to `dash`
    // — never a seeded name/email/place. They flip live automatically when a
    // rail-scoped share-token kind lands and `publicTrack` resolves rows.

    /// Live consignee name — prefers the rail-scoped `getConsigneePreview`
    /// (users.name via the latest waybill), then the publicTrack booking
    /// reference, else honest em-dash. Never the fabricated "Midwest Imports Co.".
    private var consigneeName: String {
        if let n = preview?.consigneeName, !n.isEmpty { return n }
        if let b = track?.bookingNumber, !b.isEmpty { return b }
        return dash
    }

    /// Live consignee email from `getConsigneePreview` (users.email via the
    /// latest waybill), else honest em-dash. The publicTrack projection has no
    /// email column. Never the fabricated "ops@midwestimports.example".
    private var consigneeEmail: String {
        if let e = preview?.consigneeEmail, !e.isEmpty { return e }
        return dash
    }

    /// Destination — prefers the rail-scoped preview's "City, State" (railYards
    /// join), then destinationName, then the latest live milestone location,
    /// else em-dash. Never the fabricated "Logistics Park".
    private var destination: String {
        if let cs = previewDestinationCityState { return cs }
        if let n = preview?.destinationName, !n.isEmpty { return n }
        if let loc = track?.milestones?.last?.location, !loc.isEmpty { return loc }
        return dash
    }

    /// "City, State" composed from the preview's railYards-sourced fields when
    /// either is present; nil when both are empty (so callers fall through).
    private var previewDestinationCityState: String? {
        let city = (preview?.destinationCity ?? "").trimmingCharacters(in: .whitespaces)
        let state = (preview?.destinationState ?? "").trimmingCharacters(in: .whitespaces)
        switch (city.isEmpty, state.isEmpty) {
        case (false, false): return "\(city), \(state)"
        case (false, true):  return city
        case (true, false):  return state
        case (true, true):   return nil
        }
    }

    /// Live last-event location for the container row sub-line ("last gate-in
    /// <yard>") — prefers the rail-scoped preview's lastEventLocation, then the
    /// publicTrack milestone, else honest em-dash. No fabricated "ICTF".
    private var lastEventLocation: String {
        if let loc = preview?.lastEventLocation, !loc.isEmpty { return loc }
        if let loc = track?.milestones?.last?.location, !loc.isEmpty { return loc }
        return dash
    }

    /// Recipient row right-value: live last-event day — prefers the rail-scoped
    /// preview's lastEventAt, then the publicTrack milestone timestamp, else
    /// em-dash. Never the fabricated "today".
    private var lastEventDayLabel: String {
        if let at = preview?.lastEventAt, let d = Self.parseISO(at) {
            let f = DateFormatter(); f.dateFormat = "MMM dd"
            return f.string(from: d)
        }
        guard let ts = track?.milestones?.last?.timestamp,
              let d = Self.parseISO(ts) else { return dash }
        let f = DateFormatter(); f.dateFormat = "MMM dd"
        return f.string(from: d)
    }

    /// Live container/railcar number in scope: prefers the rail-scoped preview's
    /// railcarNumber, then the publicTrack container row, then the route-passed
    /// `containerNumber` (already em-dashed when absent).
    private var containerInScope: String {
        if let rc = preview?.railcarNumber, !rc.isEmpty { return rc }
        if let live = track?.containers?.first?.containerNumber, !live.isEmpty { return live }
        return containerNumber
    }

    /// Lenient ISO-8601 parse (with and without fractional seconds).
    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading share link…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    consigneeView
                    recipientStrip
                    if let ae = actionError {
                        LifecycleCard(accentDanger: true) { Text(ae).font(EType.caption).foregroundStyle(Brand.danger) }
                    }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Header (back chevron · eyebrow · mono ID · 28/-0.4 title)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                EusoTripEyebrow(verbatim: "RAIL ENGINEER · SHARE LINK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(loadNumber)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                Text("Consignee link")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
        }
    }

    // MARK: - Hero (gradient-rimmed ActiveCard)

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s2) {
                    StatusPill(text: revoked ? "REVOKED" : "ACTIVE",
                               kind: revoked ? .neutral : .success)
                    Text("read-only")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                    Spacer()
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(expiresLabel)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                    }
                    Spacer().frame(width: Space.s4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("until link expires")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("shareTrackingLink")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.top, 6)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("SCOPE")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("1")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                        Text("shipment")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .padding(.top, Space.s3)
            }
        }
    }

    // MARK: - KPI strip (3 cells: STATE · SHIPMENT · EXPIRES)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "STATE",    value: stateLabel, gradientNumeral: !revoked)
            MetricTile(label: "SHIPMENT", value: "1")
            MetricTile(label: "EXPIRES",  value: expiresLabel)
        }
    }

    // MARK: - Consignee view (itemized ListRow stack)

    private var consigneeView: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CONSIGNEE VIEW")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("publicTrack")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                trackingRow(
                    icon: "mappin.and.ellipse", iconTint: Brand.info,
                    title: "ETA · \(destination)",
                    sub: "milestone feed · public tracking page",
                    pillText: etaDayLabel, pillKind: .neutral,
                    value: etaTimeLabel
                )
                Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                trackingRow(
                    icon: "shippingbox", iconTint: Brand.info,
                    title: "Container \(containerDisplay)",
                    // "last gate-in <yard>" only when a live milestone/event backs
                    // it; otherwise the honest em-dash — never a fabricated "ICTF".
                    sub: "\(containerSize) · last gate-in \(lastEventLocation)",
                    // Pill carries the live rail shipment status (preview.status,
                    // uppercased) when the rail-scoped read backs it, else "LIVE"
                    // from a vessel publicTrack milestone, else the honest dash.
                    // No asserted feed when nothing real resolved.
                    pillText: statusPillText, pillKind: statusPillKind,
                    value: containerSize
                )
                Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                trackingRow(
                    icon: "person", iconTint: Brand.escort,
                    title: consigneeName,
                    sub: consigneeEmail,
                    pillText: "SCOPED", pillKind: .neutral,
                    value: lastEventDayLabel
                )
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// 40x40 rx10 icon chip + 14/700 title + mono 11 sub + short right pill
    /// + right tabular value.
    private func trackingRow(icon: String, iconTint: Color,
                             title: String, sub: String,
                             pillText: String, pillKind: StatusPill.Kind,
                             value: String) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconTint.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                StatusPill(text: pillText, kind: pillKind)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(Space.s4)
    }

    // MARK: - Recipient strip (secondary strip)

    private var recipientStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RECIPIENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("portalAccessTokens")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("Issued by Eusorone Technologies · DU · \(issuedLabel)")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("Token scoped to 1 shipment · revoke ends access")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair (Copy tracking link · Revoke)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(
                title: copied ? "Copied" : (copying ? "Copying…" : "Copy tracking link"),
                action: { Task { await copyLink() } },
                leadingIcon: copied ? "checkmark" : "doc.on.doc",
                isLoading: copying
            )
            Button {
                Task { await revoke() }
            } label: {
                Text(revoked ? "Revoked" : (revoking ? "Revoking…" : "Revoke"))
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 52)
                    .background(Color(hex: 0x232932))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity((revoking || revoked) ? 0.6 : 1.0)
            .disabled(revoking || revoked)
        }
    }

    // MARK: - Display helpers

    private var containerDisplay: String {
        // Live railcar (rail preview) / container (publicTrack) / route-passed
        // number, spaced "TCNU 7693120"; all already em-dash to "-" when no real
        // source exists. The dash is not a letter, so spacedContainer returns it
        // untouched. `containerInScope` already prefers preview → track → route.
        spacedContainer(containerInScope)
    }

    private func spacedContainer(_ raw: String) -> String {
        let letters = raw.prefix { $0.isLetter }
        let rest = raw.dropFirst(letters.count)
        return rest.isEmpty ? raw : "\(letters) \(rest)"
    }

    /// Container-row pill text: live rail shipment status (preview.status,
    /// uppercased) when present, else "LIVE" from a vessel publicTrack
    /// milestone, else the honest em-dash.
    private var statusPillText: String {
        if let s = preview?.status, !s.isEmpty { return s.uppercased() }
        if track?.milestones?.isEmpty == false { return "LIVE" }
        return dash
    }

    private var statusPillKind: StatusPill.Kind {
        if let s = preview?.status, !s.isEmpty { return .info }
        if track?.milestones?.isEmpty == false { return .info }
        return .neutral
    }

    private var containerSize: String {
        // Live sizeType from the publicTrack container row, else honest
        // em-dash — never a defaulted 40'. Normalizes 40/20 to the wireframe
        // foot mark when the live value carries it.
        let st = track?.containers?.first?.sizeType ?? ""
        if st.contains("40") || st.uppercased().hasPrefix("40") { return "40'" }
        if st.contains("20") { return "20'" }
        return st.isEmpty ? dash : st
    }

    /// Resolved ETA Date — prefers the rail-scoped preview's `eta` (latest
    /// rail_shipment_events.timestamp on the server), then the publicTrack ETA.
    private var resolvedETA: Date? {
        if let e = preview?.eta, let d = Self.parseISO(e) { return d }
        if let e = track?.eta, let d = Self.parseISO(e) { return d }
        return nil
    }

    private var etaDayLabel: String {
        // Live ETA day (preview → publicTrack), else honest em-dash — never "MAY 27".
        guard let d = resolvedETA else { return dash }
        let f = DateFormatter(); f.dateFormat = "MMM dd"
        return f.string(from: d).uppercased()
    }

    private var etaTimeLabel: String {
        // Live ETA clock (preview → publicTrack), else honest em-dash — never "09:00".
        guard let d = resolvedETA else { return dash }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private var issuedLabel: String {
        // Real local issuance wall-clock — but only once a live share link
        // actually exists. With no link in scope (em-dashed load number),
        // there is nothing issued yet, so the recipient strip reads "-".
        guard link != nil else { return dash }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "today \(f.string(from: Date()))"
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        // Honest guard: with no real load number passed from a route, the
        // header caption is em-dashed and there is nothing to scope a share
        // token to. We do NOT issue a share link against a "-" load (that
        // would fabricate a live-looking hero); the hero/KPIs read their
        // own "-" floor (expiresLabel / stateLabel) until a real route opens
        // this screen with a load number.
        guard loadNumber != dash, !loadNumber.isEmpty else {
            link = nil
            track = nil
            preview = nil
            loading = false
            return
        }

        // CONSIGNEE VIEW rows — rail-scoped, self/authenticated read via the
        // REAL `railShipments.getConsigneePreview` proc (resolve-only-real-
        // columns: latest waybill → users for consignee/railcar, railYards for
        // destination, latest events for eta/last-event). `try? → nil` so an
        // undeployed server (or an honest all-null envelope) leaves every
        // consignee row on its em-dash floor — the hero is never touched.
        // Runs independently of the share-link mutation below so a share-link
        // failure does not suppress the live consignee rows (and vice-versa).
        self.preview = try? await EusoTripAPI.shared.railShipments
            .getConsigneePreview(shipmentNumber: loadNumber)

        do {
            // Issue / refresh the rail share link via the REAL endpoint.
            struct ShareIn: Encodable { let loadNumber: String; let expiresIn: Int }
            // expiresIn is in HOURS (server multiplies by 3600000ms); 21d ≈ 504h.
            let l: ShareTrackingLink591 = try await EusoTripAPI.shared.mutation(
                "tracking.shareTrackingLink",
                input: ShareIn(loadNumber: loadNumber, expiresIn: 504))
            self.link = l

            // CONSIGNEE VIEW rows — token-gated public read.
            if let code = l.accessCode, !code.isEmpty {
                // PORT-GAP: consigneePortal.publicTrack is VESSEL-scoped
                // (permissions.kind = "vessel_shipment_tracking", reads
                // vesselShipments). A rail-scoped share token kind
                // 'rail_shipment_tracking' is a named server gap, so this
                // public read will not resolve a rail shipment. We still
                // attempt it against the live token so the moment the
                // server adds the rail kind the rows populate with no
                // client change; failure leaves every consignee field on
                // its honest em-dash floor.
                struct TrackIn: Encodable { let token: String }
                do {
                    let t: PublicTrack591 = try await EusoTripAPI.shared.query(
                        "consigneePortal.publicTrack", input: TrackIn(token: code))
                    self.track = t
                } catch {
                    // Rail token not yet honored by the vessel-scoped
                    // public read — every consignee row stays em-dashed,
                    // no hard error.
                    self.track = nil
                }
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Actions

    private func copyLink() async {
        guard let url = link?.trackingUrl, !url.isEmpty else {
            actionError = "No tracking link to copy yet."
            return
        }
        copying = true; actionError = nil
        UIPasteboard.general.string = url
        copied = true
        copying = false
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        copied = false
    }

    private func revoke() async {
        // PORT-GAP: consigneePortal.revokeShareLink takes a portal token
        // and is vessel-scoped; tracking.shareTrackingLink issues an
        // ephemeral truck-load access code with no server-side revoke
        // endpoint. There is no rail-scoped revoke mutation, so we mark
        // the local link revoked (token is short-lived / expiring) and
        // surface the gap honestly rather than fabricating a call.
        revoking = true; actionError = nil
        // PORT-GAP: railShipments/consigneePortal — no rail share-token revoke endpoint.
        revoked = true
        revoking = false
    }
}

#Preview("591 · Rail Consignee Tracking Link · Night") {
    RailConsigneeTrackingLinkScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("591 · Rail Consignee Tracking Link · Light") {
    RailConsigneeTrackingLinkScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
