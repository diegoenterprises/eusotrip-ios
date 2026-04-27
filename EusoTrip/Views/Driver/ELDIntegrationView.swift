//
//  ELDIntegrationView.swift
//  EusoTrip
//
//  Native-iOS counterpart of the web `ELDConnectionPanel`. Lets a fleet
//  driver / catalyst admin connect an Electronic Logging Device provider
//  (Samsara, Motive, Geotab, Powerfleet, Zonar, Lytx, Netradyne, Verizon
//  Connect, Azuga, Solera, or Trimble / PeopleNet) to EusoTrip so the
//  in-app HOS clocks read real-time duty status straight from the ELD
//  vendor instead of being self-reported.
//
//  Surface anatomy (top-to-bottom):
//    1. Connection status card    — green pill when connected, neutral
//       otherwise; shows the currently-linked provider name.
//    2. "Read-only symbiotic"     — shield badge reinforcing that
//       connection does not grant EusoTrip write access to the ELD.
//    3. Provider picker grid      — 2-column LazyVGrid of provider tiles
//       (name, satisfaction score, feature chips, brand-color accent).
//    4. API-key input card        — SecureField with reveal toggle,
//       Connect / Disconnect button, inline error + success banners.
//    5. FMCSA compliance footer   — 49 CFR 395 HOS limits (pulled live
//       from the server's getProviderConfig), so the UI stays in sync
//       if rulemaking ever nudges the numbers.
//
//  Credential policy:
//    • The API key is never cached on-device. We POST it to
//      `eld.connectProvider`, the server upserts into
//      `integrationConnections`, and we wipe the draft field
//      immediately on success.
//    • The key field ships as SecureField by default and only reveals
//      on explicit toggle — prevents the driver's bunk-mate from
//      reading the fleet API key off a bright phone screen.
//    • A successful Connect triggers an immediate `refresh()` so the
//      header pill flips to Connected without the driver having to
//      pull-to-refresh.
//

import SwiftUI

struct ELDIntegrationView: View {

    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ELDIntegrationStore()

    // 2-column provider grid. 12pt gap matches the MetricTile pairs the
    // rest of the Me surface uses, so the ELD screen feels like part of
    // the same family.
    private let gridColumns = [
        GridItem(.flexible(), spacing: Space.s3),
        GridItem(.flexible(), spacing: Space.s3),
    ]

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                // `TileStack` (not VStack) gives the five cards the app-wide
                // cafe-door entrance — status, symbiotic notice, picker,
                // key field, compliance footer each swing in from an
                // alternating side per the uniform TileReveal contract.
                TileStack(alignment: .leading, spacing: Space.s4) {
                    statusCard
                    symbioticNotice
                    providerGridCard
                    apiKeyCard
                    complianceFooter
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s6)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("ELD Integration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task { await store.bootstrap() }
            .refreshable { await store.refresh() }
            .overlay(alignment: .top) { bannerOverlay }
        }
        // Outer screen-surface fade so the whole sheet lands with the
        // EusoTrip uniform feel on top of the per-card stagger.
        .screenTileRoot()
    }

    // MARK: - Sections

    /// Connection status card — the single most important bit of feedback
    /// on the screen. When connected, the pill is green, the provider
    /// name is spelled out, and we render the brand-color accent bar so
    /// the driver sees which ELD is currently feeding their clocks.
    @ViewBuilder
    private var statusCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("CONNECTION STATUS")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(
                        text: store.isConnected ? "Connected" : "Not connected",
                        kind: store.isConnected ? .success : .neutral
                    )
                }

                Text(headlineText)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(store.isConnected
                                     ? AnyShapeStyle(LinearGradient.diagonal)
                                     : AnyShapeStyle(palette.textPrimary))
                    .lineLimit(2)

                Text(subheadlineText)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)

                if store.isConnected,
                   let slug = store.primaryConnectedSlug,
                   let provider = store.provider(for: slug) {
                    HStack(spacing: Space.s2) {
                        Rectangle()
                            .fill(brandColor(provider))
                            .frame(width: 3, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        Text(provider.name)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Button("Disconnect") {
                            Task { await store.disconnect(slug: slug) }
                        }
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(Brand.danger)
                        .disabled(store.isMutating)
                    }
                    .padding(.top, Space.s2)
                }
            }
        }
    }

    /// "Read-only symbiotic connection" shield notice. This is a policy
    /// statement — we never write back to the ELD provider. Required
    /// copy to give fleet owners confidence in exposing their API key
    /// to a third-party platform.
    @ViewBuilder
    private var symbioticNotice: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text("Read-only symbiotic connection")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("EusoTrip pulls HOS, GPS, and DVIR records from your ELD. We never send status changes or commands back to the vendor.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    /// Provider picker. Renders every registry entry returned by
    /// `eld.getAllProviders` — sorted by satisfaction desc (the server
    /// already returns them in that order). Selection state is owned by
    /// the store so it survives sheet dismiss/re-open.
    @ViewBuilder
    private var providerGridCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("SUPPORTED PROVIDERS")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(store.providers.count)")
                        .font(EType.micro.monospacedDigit())
                        .foregroundStyle(palette.textTertiary)
                }
                if store.providers.isEmpty {
                    if store.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.s5)
                    } else {
                        Text("Couldn't load the provider catalog. Pull to refresh.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .padding(.vertical, Space.s3)
                    }
                } else {
                    LazyVGrid(columns: gridColumns, spacing: Space.s3) {
                        ForEach(store.providers) { provider in
                            providerTile(provider)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func providerTile(_ provider: ELDProvider) -> some View {
        let selected = store.selectedSlug == provider.slug
        let connected = store.connection?.providers.contains(provider.slug) == true

        Button {
            // Switching providers resets the API-key draft so we don't
            // accidentally submit the Samsara token against Motive. The
            // server would reject it anyway but a clean slate avoids
            // user confusion.
            if store.selectedSlug != provider.slug {
                store.selectedSlug = provider.slug
                store.apiKeyDraft = ""
                store.apiKeyRevealed = false
            }
        } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(provider.name)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    if connected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Brand.success)
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                if let score = provider.satisfaction {
                    Text("\(score)% satisfaction")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
                if let feats = provider.features, !feats.isEmpty {
                    // Show up to three feature chips — Samsara has 7+ and
                    // the tile gets cluttered fast. Keep it to the three
                    // the driver cares about most (GPS / HOS / DVIR) at
                    // the top of every provider's array anyway.
                    HStack(spacing: 4) {
                        ForEach(Array(feats.prefix(3)), id: \.self) { f in
                            Text(f)
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(0.3)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.tintNeutral)
                                .foregroundStyle(palette.textSecondary)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
                // Brand accent bar at the bottom — pinned at 2pt so it
                // feels like a keyboard-inspired underline rather than
                // a full-tile fill.
                Rectangle()
                    .fill(brandColor(provider))
                    .frame(height: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
                    .padding(.top, Space.s1)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(
                        selected ? LinearGradient.diagonal : LinearGradient(colors: [palette.borderFaint, palette.borderFaint], startPoint: .leading, endPoint: .trailing),
                        lineWidth: selected ? 1.6 : 1.0
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    /// API-key input card. Paired with the provider tile selection
    /// so the title reads "Connect <Provider>" and the hint text
    /// points at the right vendor dashboard.
    @ViewBuilder
    private var apiKeyCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(apiKeyCardTitle.uppercased())
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)

                Text(apiKeyCardHint)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)

                HStack(spacing: Space.s2) {
                    Group {
                        if store.apiKeyRevealed {
                            TextField("API key or bearer token", text: $store.apiKeyDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                        } else {
                            SecureField("API key or bearer token", text: $store.apiKeyDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                        }
                    }
                    .font(EType.body.monospacedDigit())
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s3)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md)
                                .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))

                    Button {
                        store.apiKeyRevealed.toggle()
                    } label: {
                        Image(systemName: store.apiKeyRevealed ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(palette.bgCardSoft)
                            .overlay(RoundedRectangle(cornerRadius: Radius.md)
                                        .strokeBorder(palette.borderFaint))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                    .buttonStyle(.plain)
                }

                CTAButton(title: ctaTitle) {
                    Task {
                        if store.isConnected,
                           let slug = store.primaryConnectedSlug,
                           store.selectedSlug == slug,
                           store.apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                            // "Connect" label became "Update key" — but if
                            // the user tapped without entering a key,
                            // treat it as a disconnect intent.
                            await store.disconnect(slug: slug)
                        } else {
                            await store.connect()
                        }
                    }
                }
                .disabled(store.isMutating || store.selectedSlug == nil)
                .opacity(store.isMutating || store.selectedSlug == nil ? 0.6 : 1.0)

                if store.isMutating {
                    HStack(spacing: Space.s2) {
                        ProgressView().scaleEffect(0.7)
                        Text("Talking to the server…")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
    }

    /// FMCSA 49 CFR 395 compliance footer. Pulls the HOS limit constants
    /// from `eld.getProviderConfig` so the displayed numbers track any
    /// server-side rulemaking update automatically.
    @ViewBuilder
    private var complianceFooter: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("FMCSA COMPLIANCE · 49 CFR 395")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    // Doctrine §2.1 gradient-not-blue: FMCSA compliance seal is a
                    // brand-accent verification mark — must render the blue→magenta
                    // gradient, not flat Brand.info. 32nd firing hygiene sweep.
                    .foregroundStyle(LinearGradient.diagonal)
            }
            if let limits = store.config?.hosLimits {
                VStack(alignment: .leading, spacing: 4) {
                    complianceRow("Max driving", minutes: limits.maxDrivingMinutes)
                    complianceRow("Max on-duty window", minutes: limits.maxOnDutyMinutes)
                    complianceRow("Break after", minutes: limits.breakRequiredAfterMinutes)
                    complianceRow("60-hour cycle (7-day)", minutes: limits.cycle7DayMinutes)
                    complianceRow("70-hour cycle (8-day)", minutes: limits.cycle8DayMinutes)
                    complianceRow("Min off-duty (reset)", minutes: limits.minOffDutyMinutes)
                }
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            } else {
                Text("Hours-of-Service limits enforced: 11-hour driving, 14-hour shift, 30-minute break after 8 hours, and 60/70-hour rolling cycle per 49 CFR 395.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Text("Once connected, your duty-status clocks, violations, and daily logs are sourced directly from your ELD vendor — no self-reporting gaps.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 2)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    @ViewBuilder
    private func complianceRow(_ label: String, minutes: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(Self.formatMinutes(minutes))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var bannerOverlay: some View {
        VStack(spacing: Space.s2) {
            if let msg = store.successMessage {
                banner(msg, kind: .success)
            }
            if let msg = store.errorMessage {
                banner(msg, kind: .warning)
            }
        }
        .padding(.top, Space.s3)
        .padding(.horizontal, Space.s4)
        .animation(.easeInOut(duration: 0.2), value: store.successMessage)
        .animation(.easeInOut(duration: 0.2), value: store.errorMessage)
    }

    @ViewBuilder
    private func banner(_ text: String, kind: StatusPill.Kind) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(kind == .success ? Brand.success : Brand.warning)
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 2)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Copy helpers

    private var headlineText: String {
        if store.isConnected,
           let slug = store.primaryConnectedSlug,
           let p = store.provider(for: slug) {
            return "\(p.name) is live · HOS flowing from vendor"
        }
        return "Connect your ELD to unlock real-time HOS"
    }

    private var subheadlineText: String {
        if store.isConnected {
            return "Duty-status clocks, 30-min break signals, and violations are sourced directly from the ELD. Self-reporting is disabled."
        }
        return "Your API key stays server-side — EusoTrip never stores it in the app. Select your provider below."
    }

    private var apiKeyCardTitle: String {
        guard let slug = store.selectedSlug,
              let provider = store.provider(for: slug) else {
            return "API key"
        }
        let connected = store.connection?.providers.contains(slug) == true
        return connected ? "Replace \(provider.name) key" : "Connect \(provider.name)"
    }

    private var apiKeyCardHint: String {
        guard let slug = store.selectedSlug,
              let provider = store.provider(for: slug) else {
            return "Pick a provider to see where to find your key."
        }
        switch provider.slug {
        case "samsara":
            return "Admin → Settings → API Tokens (read-only scopes: GPS, HOS, DVIR)."
        case "motive":
            return "Admin Hub → Apps & Integrations → API Keys."
        case "geotab":
            return "Database Admin → System → System Settings → API User."
        case "powerfleet":
            return "Platform Admin → Integrations → API Keys."
        case "zonar":
            return "Ground Traffic Control → Settings → API Management."
        case "lytx":
            return "DriveCam Admin → Settings → API Integration."
        case "netradyne":
            return "Driveri Portal → Admin → API Credentials."
        case "verizon_connect":
            return "Verizon Connect Reveal → Admin → API Keys."
        case "azuga":
            return "Azuga FleetMobile Admin → Settings → API."
        case "solera":
            return "Omnitracs One → Tenant Settings → API Keys."
        case "trimble":
            return "PeopleNet Fleet Manager → Admin → API Credentials."
        default:
            return "Find the read-only API token in your \(provider.name) admin dashboard."
        }
    }

    private var ctaTitle: String {
        if store.isMutating { return "Working…" }
        guard let slug = store.selectedSlug else { return "Connect" }
        let alreadyConnected = store.connection?.providers.contains(slug) == true
        return alreadyConnected ? "Update key" : "Connect"
    }

    // MARK: - Utilities

    /// Parse the ELD brand hex string into a SwiftUI Color. Falls back
    /// to a neutral palette tint if the server sends something unexpected.
    /// Doctrine §2.1 gradient-not-blue: fallback must not be a flat Brand.blue —
    /// palette.textSecondary is the canonical neutral tint. 32nd firing hygiene.
    private func brandColor(_ provider: ELDProvider) -> Color {
        guard let hex = provider.logoColor, let c = Color(hexString: hex) else {
            return palette.textSecondary
        }
        return c
    }

    private static func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}

// MARK: - Hex parser

private extension Color {
    /// Minimal `#RRGGBB` / `#RRGGBBAA` parser. The ELD registry ships
    /// brand colors as hex strings (e.g. Samsara #1A73E8) and SwiftUI
    /// doesn't ship a built-in init for this.
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else {
            return nil
        }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255.0
            g = Double((v >> 16) & 0xFF) / 255.0
            b = Double((v >> 8) & 0xFF) / 255.0
            a = Double(v & 0xFF) / 255.0
        } else {
            r = Double((v >> 16) & 0xFF) / 255.0
            g = Double((v >> 8) & 0xFF) / 255.0
            b = Double(v & 0xFF) / 255.0
            a = 1.0
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ELD Integration") {
    ELDIntegrationView()
        .environment(\.palette, Theme.dark)
}
#endif
