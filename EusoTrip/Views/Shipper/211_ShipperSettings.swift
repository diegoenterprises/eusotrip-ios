//
//  211_ShipperSettings.swift
//  EusoTrip 2027 UI — Shipper · Settings (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/211_ShipperSettings.swift. Diego Usoro / Eusorone
//  Technologies (companyId 1) is the persona. Lane templates anchor
//  the MATRIX-50-2026-04-26 batch — row 1 Houston → Dallas · MC-306
//  hazmat (UN1203 gasoline) and row 2 LA → Phoenix · 53' Reefer 38°F
//  (fresh berries). Hazmat exception alert sub-line cites
//  UN1203 · UN1005 · UN1267 verbatim per §11.4.
//
//  Layout (top → bottom):
//    1. TopBar       ✦ SHIPPER · SETTINGS / DIEGO USORO · v2.8.1
//    2. Title block  Settings / Notifications · lane templates · security · about
//    3. IridescentHairline
//    4. ACCOUNT card (Profile / Posted loads / Payment methods / Working carriers)
//    5. NOTIFICATIONS · CHANNELS card (Email / Push / SMS / In-app)
//    6. NOTIFICATIONS · ALERTS card   (Load / Bid / Payments / Messages / Missions / Promo / Weekly)
//    7. LANE TEMPLATES · {N} card     (live rows + "+ New template" gradient CTA)
//    8. SECURITY card                  (Two-factor auth · Active sessions)
//    9. ABOUT card                     (MiniOrb + version + doctrine pointer + → chevron)
//   10. Sign-out                       (ghost capsule · danger-red border + label)
//
//  Real wiring preserved: `users.{getNotificationPreferences,
//  updateNotificationPreferences}` via NotificationPreferencesStore;
//  `loadTemplates.list` via LoadTemplatesListStore;
//  `EusoTripSession.signOut()` for the destructive sign-out path;
//  `pushScreenById` for fall-through to brick 202 / 201 / 208 / 209.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2105 — auth.tfaStatus + auth.{tfaEnable,tfaDisable} not
//                yet shipped. Two-factor row uses §11 canon copy
//                until the procedure lands.
//    EUSO-2106 — auth.listSessions + auth.revokeSession not yet
//                shipped. Active-sessions row uses Diego's actual
//                device triad (iPhone 17 Pro Max · MacBook Pro ·
//                iPad mini) per §11 persona canon, count = 3.
//
//  Doctrine refs: §2 ME-tab nav (handled by ContentView); §3
//  numbers-first copy ("DIEGO USORO · v2.8.1" / version build / "3");
//  §4.3 single iridescent hairline; §11 / §11.2 / §11.4 Diego canon
//  + MATRIX-50; §17.2 GradientToggleStyle paint contract; §19.2
//  file-scoped MiniOrb helper; §20.4 no dead buttons (lane-template
//  / security / about taps post NotificationCenter notifications);
//  §22.2 textTertiary counter color encodes informational status.
//

import SwiftUI

// MARK: - Screen root

struct ShipperSettings: View {
    @Environment(\.palette) var palette
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var session: EusoTripSession
    @StateObject private var prefsStore = NotificationPreferencesStore()
    @StateObject private var laneTemplatesStore = LoadTemplatesListStore()
    @State private var showSignOutConfirm = false
    @State private var lastToast: String?
    /// Drives the in-app About sheet presented from `tapAbout()`.
    /// Replaces the prior openURL("https://app.eusotrip.com/about")
    /// stub.
    @State private var showAboutSheet: Bool = false

    /// Closure injected by ContentView so role-tab destinations can
    /// fall through to other registry rows without owning the routing
    /// stack themselves. Same pattern 200/201/202 use for the
    /// Loads → Detail jump.
    var pushScreenById: ((String) -> Void)? = nil

    // §11 Diego canon — persona-and-build identification eyebrow.
    private let counterEyebrow = "DIEGO USORO · v\(Self.shortVersion)"

    // §11 ABOUT-row copy. Build number reads from Bundle at runtime
    // so the displayed version stays honest, but the doctrine pointer
    // is verbatim wireframe canon.
    private static var shortVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "2.8.1"
    }
    private static var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "4821"
    }
    private var aboutHeadline: String {
        "EusoTrip 2027 · v\(Self.shortVersion) (build \(Self.buildNumber))"
    }
    private let aboutSub = "Doctrine §11 Diego canon · MATRIX-50-2026-04-26 active"

    // §11.4 SECURITY card placeholder copy (EUSO-2105 / EUSO-2106).
    // Mirrors Diego's actual device stack per persona canon — never
    // synthesised, never anonymised. Will be replaced with live
    // `auth.tfaStatus` + `auth.listSessions` data on those procedures.
    private let twoFactorStatus     = "Active · authenticator · SMS backup"
    private let activeSessionsCount = 3
    private let activeSessionsList  = "iPhone 17 Pro Max · MacBook Pro · iPad mini"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s3)
                IridescentHairline()
                    .padding(.top, Space.s3)

                accountSection
                    .padding(.top, Space.s5)

                notificationsChannelsSection
                    .padding(.top, Space.s5)

                notificationsAlertsSection
                    .padding(.top, Space.s4)

                laneTemplatesSection
                    .padding(.top, Space.s5)

                securitySection
                    .padding(.top, Space.s5)

                aboutCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)

                signOutButton
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)
                    .padding(.bottom, Space.s8)
            }
        }
        .task {
            async let a: Void = prefsStore.refresh()
            async let b: Void = laneTemplatesStore.refresh()
            _ = await (a, b)
        }
        .refreshable {
            async let a: Void = prefsStore.refresh()
            async let b: Void = laneTemplatesStore.refresh()
            _ = await (a, b)
        }
        .sheet(isPresented: $showAboutSheet) {
            ShipperSettingsAboutSheet(
                version: Self.shortVersion,
                build: Self.buildNumber
            )
            .eusoSheetX()
        }
        .overlay(alignment: .bottom) {
            if let toast = lastToast {
                toastView(toast)
                    .padding(.bottom, Space.s6)
                    .padding(.horizontal, Space.s4)
                    .transition(.opacity)
            }
        }
        .confirmationDialog(
            "Sign out of EusoTrip?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll be returned to the sign-in screen. Your in-flight loads stay live on the platform.")
        }
    }

    // MARK: - TopBar (gradient eyebrow on the left, neutral persona
    //          counter on the right — same anatomy as 207 / 208 / 209
    //          / 210 / 213 / 215 / 217 / 218 / 219 / 228).

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · SETTINGS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            // §22.2 counter color encodes screen-status — textTertiary
            // (informational persona+build identification, not action-
            // pressing).
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel("Diego Usoro, EusoTrip version \(Self.shortVersion)")
        }
        .padding(.horizontal, Space.s5)
    }

    // MARK: - Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Notifications · lane templates · security · about")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    // MARK: - Section label (eyebrow micro caption)

    @ViewBuilder
    private func sectionLabel(_ text: String, accessory: String? = nil) -> some View {
        HStack {
            Text(text)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            if let accessory {
                Text(accessory)
                    .font(EType.micro)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    // MARK: - ACCOUNT (preserved from prior wiring — pushScreenById
    //          fall-through into brick 202 / 201 / 208 / 209)

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("ACCOUNT")
            VStack(spacing: 0) {
                accountRow(
                    glyph: "person.crop.circle.fill",
                    title: "Profile",
                    subtitle: profileSubtitle,
                    action: { pushScreenById?("202") }
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                accountRow(
                    glyph: "doc.text.fill",
                    title: "Posted loads",
                    subtitle: "Manage every load on the board",
                    action: { pushScreenById?("201") }
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                accountRow(
                    glyph: "creditcard.fill",
                    title: "Payment methods",
                    subtitle: "Cards and bank accounts",
                    action: { pushScreenById?("208") }
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                accountRow(
                    glyph: "person.2.fill",
                    title: "Working carriers",
                    subtitle: "Top 10 directory",
                    action: { pushScreenById?("209") }
                )
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .padding(.horizontal, Space.s5)
        }
    }

    private var profileSubtitle: String {
        if let u = session.user {
            if !u.email.isEmpty { return u.email }
            if let name = u.name, !name.isEmpty { return name }
        }
        return "—"
    }

    private func accountRow(
        glyph: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.5))
                    Image(systemName: glyph)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - NOTIFICATIONS · CHANNELS (4 master switches — backed by
    //          users.getNotificationPreferences)

    private var notificationsChannelsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("NOTIFICATIONS · CHANNELS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if prefsStore.isInitialLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, Space.s5)

            VStack(spacing: 0) {
                channelToggle(
                    glyph: "envelope.fill",
                    title: "Email",
                    subtitle: "Digest summaries and time-critical alerts",
                    keyName: "emailNotifications",
                    isOn: prefsStore.matrix.emailNotifications
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                channelToggle(
                    glyph: "iphone.radiowaves.left.and.right",
                    title: "Push",
                    subtitle: "Realtime push notifications to this device",
                    keyName: "pushNotifications",
                    isOn: prefsStore.matrix.pushNotifications
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                channelToggle(
                    glyph: "message.fill",
                    title: "SMS",
                    subtitle: "Text messages for urgent load events",
                    keyName: "smsNotifications",
                    isOn: prefsStore.matrix.smsNotifications
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                channelToggle(
                    glyph: "bell.badge.fill",
                    title: "In-app",
                    subtitle: "Banner toasts inside EusoTrip",
                    keyName: "inAppNotifications",
                    isOn: prefsStore.matrix.inAppNotifications
                )
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .padding(.horizontal, Space.s5)
        }
    }

    private func channelToggle(
        glyph: String,
        title: String,
        subtitle: String,
        keyName: String,
        isOn: Bool
    ) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.5))
                Image(systemName: glyph)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: bindingFor(keyName: keyName, currentValue: isOn))
                .labelsHidden()
                .toggleStyle(GradientToggleStyle())
                .disabled(prefsStore.inflight.contains(keyName))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    // MARK: - NOTIFICATIONS · ALERTS (7 category switches — backed by
    //          the same matrix as channels)

    private var notificationsAlertsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("NOTIFICATIONS · ALERTS")
            VStack(spacing: 0) {
                alertToggle(
                    glyph: "shippingbox.fill",
                    title: "Load updates",
                    subtitle: "Posted → Bidding → Awarded → Pickup → In transit → Delivery",
                    keyName: "loadUpdates",
                    isOn: prefsStore.matrix.loadUpdates
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                alertToggle(
                    glyph: "hand.raised.fill",
                    title: "Bid received",
                    subtitle: "Push · email · in-app · ESang ping",
                    keyName: "bidAlerts",
                    isOn: prefsStore.matrix.bidAlerts
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                alertToggle(
                    glyph: "exclamationmark.triangle.fill",
                    title: "Hazmat exception alerts",
                    subtitle: "UN1203 · UN1005 · UN1267 · escort GPS divergence",
                    keyName: "loadUpdates",
                    isOn: prefsStore.matrix.loadUpdates,
                    readOnlyHint: true
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                alertToggle(
                    glyph: "dollarsign.circle.fill",
                    title: "Payments",
                    subtitle: "Settlements, payouts, invoices",
                    keyName: "paymentAlerts",
                    isOn: prefsStore.matrix.paymentAlerts
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                alertToggle(
                    glyph: "bubble.left.and.bubble.right.fill",
                    title: "Messages",
                    subtitle: "New chat messages from carriers and dispatch",
                    keyName: "messageAlerts",
                    isOn: prefsStore.matrix.messageAlerts
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                alertToggle(
                    glyph: "trophy.fill",
                    title: "Missions",
                    subtitle: "Streaks, badges, and crate drops",
                    keyName: "missionAlerts",
                    isOn: prefsStore.matrix.missionAlerts
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                alertToggle(
                    glyph: "megaphone.fill",
                    title: "Promotional",
                    subtitle: "Marketing, referrals, new features",
                    keyName: "promotionalAlerts",
                    isOn: prefsStore.matrix.promotionalAlerts
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                alertToggle(
                    glyph: "calendar",
                    title: "Weekly digest",
                    subtitle: "Monday email summary",
                    keyName: "weeklyDigest",
                    isOn: prefsStore.matrix.weeklyDigest
                )
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .padding(.horizontal, Space.s5)

            if let err = prefsStore.lastError {
                Text("Couldn't save: \(err.localizedDescription)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s1)
            }
        }
    }

    private func alertToggle(
        glyph: String,
        title: String,
        subtitle: String,
        keyName: String,
        isOn: Bool,
        readOnlyHint: Bool = false
    ) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.5))
                Image(systemName: glyph)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Toggle("", isOn: bindingFor(keyName: keyName, currentValue: isOn))
                .labelsHidden()
                .toggleStyle(GradientToggleStyle())
                .disabled(readOnlyHint || prefsStore.inflight.contains(keyName))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    /// Binding that reads from the matrix and writes through the
    /// store's optimistic-update path. Rollback on error happens
    /// inside the store.
    private func bindingFor(keyName: String, currentValue: Bool) -> Binding<Bool> {
        Binding(
            get: { currentValue },
            set: { newValue in
                Task {
                    await prefsStore.setPreference(keyName: keyName, value: newValue)
                    if prefsStore.lastError == nil {
                        flashToast("Saved")
                    }
                }
            }
        )
    }

    // MARK: - LANE TEMPLATES (live store + "+ New template" gradient row)

    private var laneTemplatesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("LANE TEMPLATES", accessory: laneTemplateCountAccessory)
            laneTemplatesContent
                .padding(.horizontal, Space.s5)
        }
    }

    private var laneTemplateCountAccessory: String? {
        if case .loaded(let rows) = laneTemplatesStore.state {
            return rows.isEmpty ? nil : "\(rows.count) saved"
        }
        return nil
    }

    @ViewBuilder
    private var laneTemplatesContent: some View {
        switch laneTemplatesStore.state {
        case .loading:
            laneTemplatesPlaceholder(
                icon: "road.lanes",
                title: "Loading saved configs…",
                subtitle: nil,
                showSpinner: true,
                showAddRow: false
            )
        case .empty:
            laneTemplatesPlaceholder(
                icon: "road.lanes",
                title: "No saved lane configs yet",
                subtitle: "Save a recurring lane (Houston → Dallas · MC-306 · UN1203 / LA → Phoenix · 53' Reefer 38°F) when posting a load and it'll show up here.",
                showSpinner: false,
                showAddRow: true
            )
        case .error(let err):
            laneTemplatesPlaceholder(
                icon: "exclamationmark.triangle",
                title: "Couldn't load configs",
                subtitle: err.localizedDescription,
                showSpinner: false,
                showAddRow: true
            )
        case .loaded(let rows):
            VStack(spacing: 0) {
                ForEach(rows, id: \.id) { t in
                    laneTemplateRow(t)
                    Divider().overlay(palette.borderFaint).padding(.leading, Space.s4)
                }
                newTemplateRow
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
        }
    }

    private func laneTemplatesPlaceholder(icon: String,
                                          title: String,
                                          subtitle: String?,
                                          showSpinner: Bool,
                                          showAddRow: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: Space.s2) {
                if showSpinner {
                    ProgressView().controlSize(.regular)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(palette.textTertiary)
                }
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.s4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s5)

            if showAddRow {
                Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                newTemplateRow
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func laneTemplateRow(_ t: LoadTemplatesAPI.Template) -> some View {
        Button(action: { tapLaneTemplate(t) }) {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient.diagonal.opacity(0.15))
                    Image(systemName: t.isFavorite == true ? "star.fill" : "road.lanes")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if let lane = laneSubtitle(t) {
                        Text(lane)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    if let meta = templateMeta(t) {
                        Text(meta)
                            .font(EType.mono(.caption))
                            .tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Space.s2)
                if let used = t.useCount, used > 0 {
                    Text("\(used) reposts")
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var newTemplateRow: some View {
        Button(action: tapNewTemplate) {
            HStack(spacing: Space.s2) {
                Text("+ New template")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create new lane template")
    }

    private func laneSubtitle(_ t: LoadTemplatesAPI.Template) -> String? {
        let oCity = t.origin?.city
        let oState = t.origin?.state
        let dCity = t.destination?.city
        let dState = t.destination?.state
        let lhs: String? = {
            if let c = oCity, !c.isEmpty, let s = oState, !s.isEmpty { return "\(c), \(s)" }
            return oCity ?? oState
        }()
        let rhs: String? = {
            if let c = dCity, !c.isEmpty, let s = dState, !s.isEmpty { return "\(c), \(s)" }
            return dCity ?? dState
        }()
        switch (lhs, rhs) {
        case (let l?, let r?): return "\(l) → \(r)"
        case (let l?, nil):    return "\(l) → —"
        case (nil, let r?):    return "— → \(r)"
        case (nil, nil):       return nil
        }
    }

    private func templateMeta(_ t: LoadTemplatesAPI.Template) -> String? {
        var parts: [String] = []
        if let cargo = t.cargoType, !cargo.isEmpty {
            parts.append(cargo.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        if let eq = t.equipmentType, !eq.isEmpty {
            parts.append(eq)
        }
        if let rate = t.rate, !rate.isEmpty {
            let suffix: String
            switch t.rateType ?? "flat" {
            case "per_mile":   suffix = "/mi"
            case "per_barrel": suffix = "/bbl"
            case "per_gallon": suffix = "/gal"
            case "per_ton":    suffix = "/ton"
            default:           suffix = ""
            }
            parts.append("$\(rate)\(suffix)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - SECURITY (2FA + active sessions; backend pending)

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("SECURITY")
            VStack(spacing: 0) {
                twoFactorRow
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                sessionsRow
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .padding(.horizontal, Space.s5)
        }
    }

    private var twoFactorRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.5))
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Two-factor auth")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(twoFactorStatus)
                    .font(EType.caption)
                    .foregroundStyle(Brand.success)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
            Button(action: tapManage2FA) {
                Text("Manage")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Manage two-factor authentication")
        }
    }

    private var sessionsRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.5))
                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Active sessions · \(activeSessionsCount)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(activeSessionsList)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            Spacer()
            Button(action: tapViewSessions) {
                Text("View")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View active sessions")
        }
    }

    // MARK: - ABOUT card (mini-orb + version + doctrine pointer + chevron)

    private var aboutCard: some View {
        Button(action: tapAbout) {
            HStack(alignment: .center, spacing: 12) {
                MiniOrb()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(aboutHeadline)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(aboutSub)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 58)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(aboutHeadline). \(aboutSub).")
    }

    // MARK: - Sign-out (ghost capsule, danger-red border + label)

    private var signOutButton: some View {
        Button(action: { showSignOutConfirm = true }) {
            ZStack {
                Capsule().fill(palette.bgCard)
                Capsule()
                    .strokeBorder(Brand.danger.opacity(0.30), lineWidth: 1)
                Text("Sign out")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Brand.danger)
            }
            .frame(height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sign out")
        .accessibilityHint("Logs you out of Eusorone Technologies and returns to the sign-in screen.")
    }

    // MARK: - Notification posts (§20.4 — wireframe-defined names)

    private func tapLaneTemplate(_ t: LoadTemplatesAPI.Template) {
        // Real action: jump to 204 Post Load with the template id so
        // the post-load wizard pre-fills from the saved lane. The
        // wizard listens for `templateId` in eusoShipperNavSwap
        // userInfo. Replaces the prior openURL("…/templates/{id}").
        NotificationCenter.default.post(
            name: .eusoShipperSettingsLaneTemplateRow,
            object: nil,
            userInfo: [
                "source": "211_ShipperSettings",
                "templateId": t.id,
                "shipperCompanyId": 1
            ]
        )
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "204", "templateId": t.id]
        )
    }

    private func tapNewTemplate() {
        // Real action: jump to 204 Post Load. The wizard's "Save as
        // template" toggle persists the just-typed lane as a fresh
        // template via `loadTemplates.create`. Replaces the prior
        // openURL("…/templates/new").
        NotificationCenter.default.post(
            name: .eusoShipperSettingsLaneTemplateAdd,
            object: nil,
            userInfo: [
                "source": "211_ShipperSettings",
                "shipperCompanyId": 1
            ]
        )
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "204", "saveAsTemplate": true]
        )
    }

    private func tapManage2FA() {
        // Real action: 2FA is enterprise-managed pending the
        // auth.tfaEnable / tfaDisable / tfaStatus build-out
        // (EUSO-2105). For now, surface a real mail composer to
        // security@eusotrip.com so the founder + ops team can
        // co-ordinate the enrolment. No more dead 404 link.
        NotificationCenter.default.post(
            name: .eusoShipperSettingsSecurityManage,
            object: nil,
            userInfo: [
                "source": "211_ShipperSettings",
                "subject": "tfa",
                "shipperCompanyId": 1
            ]
        )
        // Founder doctrine 2026-05-07: Settings rows route to the
        // in-app management screens, never mailto. 345 is the
        // canonical 2FA management surface (TwoFactorManageScreen).
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap,
            object: nil,
            userInfo: ["screenId": "345"]
        )
    }

    private func tapViewSessions() {
        // Real action: same enterprise-managed pattern as 2FA above.
        // Composes a mail to ops with the device hint so the founder
        // can request a session audit. Replaces the prior
        // openURL("…/security/sessions").
        NotificationCenter.default.post(
            name: .eusoShipperSettingsSecuritySessions,
            object: nil,
            userInfo: [
                "source": "211_ShipperSettings",
                "shipperCompanyId": 1
            ]
        )
        // 344 is the in-app SecuritySessionsScreen — lists active
        // sessions, lets the user revoke any. Same canonical
        // surface the web platform shows.
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap,
            object: nil,
            userInfo: ["screenId": "344"]
        )
    }

    private func tapAbout() {
        // Real action: present an in-app About sheet showing version,
        // build, copyright, and quick links to privacy + terms +
        // support. Drives a SwiftUI `.sheet(isPresented:)` flag on
        // the screen body. Replaces openURL("…/about") which 404'd.
        NotificationCenter.default.post(
            name: .eusoShipperSettingsAbout,
            object: nil,
            userInfo: [
                "source": "211_ShipperSettings",
                "build": Self.buildNumber,
                "version": Self.shortVersion,
                "shipperCompanyId": 1
            ]
        )
        showAboutSheet = true
    }

    // MARK: - Toast

    private func flashToast(_ msg: String) {
        withAnimation(.easeInOut(duration: 0.18)) { lastToast = msg }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.22)) { lastToast = nil }
            }
        }
    }

    private func toastView(_ msg: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LinearGradient.diagonal)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(Capsule().fill(palette.bgCard))
        .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

// MARK: - MiniOrb (32pt gradient diagonal + specular highlight overlay
//          — file-scoped per §19.2; mirrors the SVG About row's
//          miniature ESang orb composition)

private struct MiniOrb: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient.diagonal)
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.75), .white.opacity(0)],
                    center: .init(x: 0.35, y: 0.30),
                    startRadius: 0, endRadius: 18
                ))
                .frame(width: 22, height: 22)
                .offset(x: -3, y: -3)
                .blendMode(.plusLighter)
        }
    }
}

// MARK: - NotificationCenter names (§20.4 no dead buttons)

extension Notification.Name {
    /// Lane-template row tap — opens the template-detail sheet for
    /// edit / archive / repost.
    static let eusoShipperSettingsLaneTemplateRow    = Notification.Name("eusoShipperSettingsLaneTemplateRow")
    /// "+ New template" CTA tap — opens the template-create sheet.
    static let eusoShipperSettingsLaneTemplateAdd    = Notification.Name("eusoShipperSettingsLaneTemplateAdd")
    /// 2FA "Manage" link tap — opens the auth-management sheet
    /// (`auth.tfaStatus` + `tfaEnable` + `tfaDisable` + recovery codes).
    static let eusoShipperSettingsSecurityManage     = Notification.Name("eusoShipperSettingsSecurityManage")
    /// Sessions "View" link tap — opens the session-list sheet
    /// (`auth.listSessions` + per-row `revokeSession`).
    static let eusoShipperSettingsSecuritySessions   = Notification.Name("eusoShipperSettingsSecuritySessions")
    /// About-card tap — opens the about-detail sheet.
    static let eusoShipperSettingsAbout              = Notification.Name("eusoShipperSettingsAbout")
}

// MARK: - ContentView entry point

struct ShipperSettingsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        ZStack {
            theme.bgPage.ignoresSafeArea()
            ShipperSettings()
                .environment(\.palette, theme)
        }
    }
}

// MARK: - Previews

#Preview("211 · Shipper Settings · Dark") {
    ShipperSettingsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("211 · Shipper Settings · Light") {
    ShipperSettingsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

/// In-app About sheet — replaces the prior openURL("…/about") stub.
/// Shows version + build, copyright, and quick-tap links to the
/// privacy policy / terms / support email. Tapped at the founder's
/// 2026-05-05 dead-button audit.
private struct ShipperSettingsAboutSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let version: String
    let build: String

    @State private var presentingLegalDoc: LegalDoc? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "shippingbox.fill")
                        .resizable().scaledToFit()
                        .frame(width: 56, height: 56)
                        .foregroundStyle(LinearGradient.diagonal)
                        .padding(.top, 24)
                    Text("EusoTrip")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Version \(version) (\(build))")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                    Text("Eusorone Technologies, Inc.")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)

                    LifecycleCard {
                        VStack(spacing: 0) {
                            // Founder doctrine 2026-05-07: legal docs
                            // render IN-APP (LegalDocSheet) with the
                            // embedded EusoTrip-canonical text. No
                            // more web hand-offs for terms / privacy.
                            row(icon: "doc.text", label: "Privacy Policy") {
                                presentingLegalDoc = .privacyPolicy
                            }
                            Divider().overlay(palette.borderFaint)
                            row(icon: "doc.text", label: "Terms of Service") {
                                presentingLegalDoc = .termsOfService
                            }
                            Divider().overlay(palette.borderFaint)
                            row(icon: "envelope.fill", label: "Email support") {
                                if let u = URL(string: "mailto:support@eusotrip.com") { openURL(u) }
                            }
                            Divider().overlay(palette.borderFaint)
                            row(icon: "globe", label: "eusotrip.com") {
                                if let u = URL(string: "https://eusotrip.com") { openURL(u) }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 56)

                    Text("Powered by ESANG AI™")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, 56)

                    Color.clear.frame(height: 32)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $presentingLegalDoc) { doc in
                LegalDocSheet(doc: doc)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func row(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).foregroundStyle(LinearGradient.diagonal)
                Text(label).font(EType.body).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
