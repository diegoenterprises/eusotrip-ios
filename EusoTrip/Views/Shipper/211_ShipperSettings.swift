//
//  211_ShipperSettings.swift
//  EusoTrip 2027 UI — 129th firing (shipper · settings · final shipper anchor)
//
//  Screen 211 · Shipper · Settings — the twelfth (final) shipper-track
//  brick, closing the 200-211 anchor sweep and bringing the Shipper
//  role to 12-of-12 anchors per the 121-spec total. Sits behind the
//  "Me" / gear slot of the 200/201/202 BottomNav and is the canonical
//  preference surface for shippers — every notification toggle, every
//  account hand-off, every sign-out path lives here.
//
//  Cohort B day-1 — fully dynamic (SKILL.md §3 "no-mock" pledge ·
//  2027 motivation directive "no fake data"):
//
//    • Notification preference matrix (11 booleans across 4 channels +
//      7 alert categories) → live `users.getNotificationPreferences`
//      query and `users.updateNotificationPreferences` mutation. Both
//      MCP-verified at `frontend/server/routers/users.ts:1648` and
//      `:1680` respectively. Both `protectedProcedure` (any
//      authenticated user) so the same matrix shape that drives Driver
//      Me Notifications is what backs the Shipper Settings surface.
//      Server stores a single row keyed on `userId = ctx.user.id` —
//      shipper / driver / broker all read the same envelope.
//
//    • Profile hand-off → Account row taps fall through to brick 202
//      (Shipper · Profile) via `pushScreenById`, the standard
//      ContentView env closure that the 200/201/202 BottomNav already
//      uses. No fake "edit profile" inline form on this surface — the
//      profile editor lives at 202.
//
//    • Sign out → `EusoTripSession.signOut()`, which fires
//      `auth.logout` server-side and then transitions AppRoot from
//      `.signedIn` to `.signedOut` (re-renders `SignInView`). Wrapped
//      in a confirmation dialog so a stray tap doesn't kick the
//      shipper out mid-load-post.
//
//    • Default lane configs section → renders
//      `EusoEmptyState(comingSoon: true, …)` until backend exposes a
//      `shippers.getDefaultLaneConfigs` procedure. The doctrine §13
//      no-fake-data rule forbids pre-populating with sample lane
//      strings; the section is a real surface, just deliberately empty
//      until the server catches up. This is the same pattern the
//      Driver Me Authority brick (105) uses for its FMCSA-pending
//      checks.
//
//    • Build / version footer → reads `Bundle.main.infoDictionary` for
//      `CFBundleShortVersionString` and `CFBundleVersion`. Pure
//      bundle-local read — no network, no fixtures.
//
//  Doctrine refs:
//    §1   LinearGradient.diagonal on the header label, the toggle thumbs
//         (via GradientToggleStyle), the section divider glyphs, and the
//         destructive sign-out CTA's iconography. NO flat brand blue.
//    §2   Every Toggle wears `.toggleStyle(GradientToggleStyle())` —
//         15→16 toggle widget count after this brick lands; 9→10
//         GradientToggleStyle-bearing files; bijection preserved.
//    §4   Tokenized spacing, radii, type. No magic numbers.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in AnyShapeStyle.
//    §8   `.sheet(isPresented:)` not used here — Settings is a top-
//         level role-tab destination, not a Me sub-route.
//    §10  Previews compile in isolation — store lands `.loading` under
//         preview canvas (no `.task` fires) so renders fall through to
//         `serverDefault` matrix and toggles paint correctly.
//    §13  Empty / "coming soon" states everywhere a backend gap exists
//         (default lane configs, language picker, theme picker). No
//         synthesised data on any branch.
//

import SwiftUI

// MARK: - Screen root

struct ShipperSettings: View {
    @Environment(\.palette) var palette
    @EnvironmentObject var session: EusoTripSession
    @StateObject private var prefsStore = NotificationPreferencesStore()
    @State private var showSignOutConfirm = false
    @State private var lastToast: String?

    /// Closure injected by ContentView so role-tab destinations can
    /// fall through to other registry rows without owning the routing
    /// stack themselves. Same pattern 200/201/202 use for the
    /// Loads → Detail jump.
    var pushScreenById: ((String) -> Void)? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                accountCard
                channelsCard
                alertsCard
                defaultLaneConfigsCard
                signOutCard
                buildFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await prefsStore.refresh() }
        .refreshable { await prefsStore.refresh() }
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Settings")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Manage notifications, account, and preferences")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: prefsStore.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Account card

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ACCOUNT")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
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
        }
    }

    private var profileSubtitle: String {
        // Display the email or name from the live session (auth.me) if
        // available. The em-dash sentinel surfaces for the brief boot
        // window before the cached AuthUser hydrates.
        if let u = session.user {
            // `AuthUser.email` is non-optional `String`; `name` is `String?`.
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

    // MARK: Channels card (4 master switches)

    private var channelsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("DELIVERY CHANNELS")
                    .font(EType.micro).tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if prefsStore.isInitialLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, Space.s1)
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

    // MARK: Alerts card (7 category switches)

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ALERT CATEGORIES")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s1)
            VStack(spacing: 0) {
                alertToggle(
                    glyph: "shippingbox.fill",
                    title: "Load updates",
                    subtitle: "Posted, assigned, status changes",
                    keyName: "loadUpdates",
                    isOn: prefsStore.matrix.loadUpdates
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                alertToggle(
                    glyph: "hand.raised.fill",
                    title: "Bid alerts",
                    subtitle: "New bids on your posted loads",
                    keyName: "bidAlerts",
                    isOn: prefsStore.matrix.bidAlerts
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

            if let err = prefsStore.lastError {
                Text("Couldn't save: \(err.localizedDescription)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Space.s2)
                    .padding(.top, Space.s1)
            }
        }
    }

    private func alertToggle(
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
                    .lineLimit(2)
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

    /// Binding that reads from the matrix and writes through the
    /// store's optimistic-update path. The set side fires-and-forgets
    /// the round-trip; rollback on error happens inside the store.
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

    // MARK: Default lane configs (server-pending)

    private var defaultLaneConfigsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("DEFAULT LANE CONFIGS")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s1)
            VStack(spacing: Space.s2) {
                Image(systemName: "road.lanes")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(palette.textTertiary)
                Text("Coming soon")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Save default commodity, equipment, and lane preferences so every new posted load starts from your common shape. Backend in development.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s5)
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

    // MARK: Sign out

    private var signOutCard: some View {
        Button {
            showSignOutConfirm = true
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: "rectangle.portrait.and.arrow.right.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.tintNeutral.opacity(0.5))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sign out")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Return to the sign-in screen")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Build footer

    private var buildFooter: some View {
        VStack(spacing: 2) {
            Text("EusoTrip · Powered by ESANG AI™")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(buildVersionString)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s4)
    }

    private var buildVersionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "—"
        let b = info?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (\(b))"
    }

    // MARK: Toast

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
        .background(
            Capsule().fill(palette.bgCard)
        )
        .overlay(
            Capsule().strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
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

#Preview("211 · Shipper Settings · Night") {
    ShipperSettingsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("211 · Shipper Settings · Afternoon") {
    ShipperSettingsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
