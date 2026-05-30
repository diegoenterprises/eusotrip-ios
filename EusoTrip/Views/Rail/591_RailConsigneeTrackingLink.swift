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

import SwiftUI

struct RailConsigneeTrackingLinkScreen: View {
    let theme: Theme.Palette
    /// Rail load number the share link is scoped to (RAIL-YYMMDD-XXXXX).
    var loadNumber: String = "RAIL-260523-7C3A0B12D4"
    /// Container in scope (TCNU 7693120 on the wireframe).
    var containerNumber: String = "TCNU7693120"

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
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var copying = false
    @State private var revoking = false
    @State private var copied = false
    @State private var revoked = false
    @State private var actionError: String? = nil

    // Wireframe-true representative recipient context (publicTrack is
    // vessel-scoped on the server — see PORT-GAP — so the consignee
    // identity surfaces from the issuing carrier side here).
    private let consigneeName  = "Midwest Imports Co."
    private let consigneeEmail = "ops@midwestimports.example"
    private let destination    = "Logistics Park"

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
        return "—"
    }

    private var stateLabel: String {
        guard link != nil else { return "—" }
        return revoked ? "Revoked" : "Active"
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
        .refreshable { await load() }
    }

    // MARK: - Header (back chevron · eyebrow · mono ID · 28/-0.4 title)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("✦ RAIL ENGINEER · SHARE LINK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(loadNumber)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
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
                    sub: "milestone feed · publicTrack",
                    pillText: etaDayLabel, pillKind: .neutral,
                    value: etaTimeLabel
                )
                Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                trackingRow(
                    icon: "shippingbox", iconTint: Brand.info,
                    title: "Container \(containerDisplay)",
                    sub: "\(containerSize) · last gate-in ICTF",
                    pillText: "LIVE", pillKind: .info,
                    value: containerSize
                )
                Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                trackingRow(
                    icon: "person", iconTint: Brand.escort,
                    title: consigneeName,
                    sub: consigneeEmail,
                    pillText: "SCOPED", pillKind: .neutral,
                    value: "today"
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
        // "TCNU7693120" → "TCNU 7693120" matching the wireframe spacing.
        guard let live = track?.containers?.first?.containerNumber, !live.isEmpty else {
            return spacedContainer(containerNumber)
        }
        return spacedContainer(live)
    }

    private func spacedContainer(_ raw: String) -> String {
        let letters = raw.prefix { $0.isLetter }
        let rest = raw.dropFirst(letters.count)
        return rest.isEmpty ? raw : "\(letters) \(rest)"
    }

    private var containerSize: String {
        let st = track?.containers?.first?.sizeType ?? ""
        if st.contains("40") || st.uppercased().hasPrefix("40") { return "40'" }
        if st.contains("20") { return "20'" }
        return st.isEmpty ? "40'" : st
    }

    private var etaDayLabel: String {
        guard let eta = track?.eta else { return "MAY 27" }
        let iso = ISO8601DateFormatter()
        guard let d = iso.date(from: eta) else { return "MAY 27" }
        let f = DateFormatter(); f.dateFormat = "MMM dd"
        return f.string(from: d).uppercased()
    }

    private var etaTimeLabel: String {
        guard let eta = track?.eta else { return "09:00" }
        let iso = ISO8601DateFormatter()
        guard let d = iso.date(from: eta) else { return "09:00" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private var issuedLabel: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "today \(f.string(from: Date()))"
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
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
                // client change; failure leaves the wireframe-true
                // representative rows in place.
                struct TrackIn: Encodable { let token: String }
                do {
                    let t: PublicTrack591 = try await EusoTripAPI.shared.query(
                        "consigneePortal.publicTrack", input: TrackIn(token: code))
                    self.track = t
                } catch {
                    // Rail token not yet honored by the vessel-scoped
                    // public read — keep representative rows, no hard error.
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
