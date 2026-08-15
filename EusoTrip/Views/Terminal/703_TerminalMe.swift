//
//  703_TerminalMe.swift
//  EusoTrip — Terminal · Me hub.
//
//  Visual parity with 350_CarrierMe (catalyst) + 320_MeHome (shipper):
//  56pt gradient-avatar identity hero, LifecycleCard sections,
//  40pt gradient icon circles on each row, gradient sign-out CTA.
//
//  Terminal nav route map binds the "me" bottom-nav slot to "703".
//  Pure nav hub — no load()/EusoTripAPI. Destination ids audited
//  against the Terminal surface registrations (700/701/702). The
//  SUPPORT row posts `.eusoTerminaleSangTapped` to open ESANG;
//  every other row posts `.eusoTerminalNavSwap` with the screenId.
//

import SwiftUI

struct TerminalMeScreen: View {
    let theme: Theme.Palette

    @EnvironmentObject private var session: EusoTripSession
    @Environment(\.palette) private var palette
    @State private var showSignOutConfirm: Bool = false
    @SceneStorage("terminal.me.expandedCategory") private var expandedCategory: String = ""
    @SceneStorage("terminal.me.returnAnchor") private var returnAnchor: String = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    topBar
                    titleBlock
                    iridescentHairline
                    identityHero
                    accessCardSection
                    walletSection
                    operationsSection
                    supportSection
                    signOutButton
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            .onAppear { restoreScrollPosition(using: proxy) }
        }
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Sign out", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign back in to manage the gate queue and yard.")
        }
    }

    // MARK: - TopBar / Title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                EusoTripBrandMark(size: 12)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("TERMINAL · ME")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(session.user?.companyId.map { "companyId · \($0)" } ?? "-")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0).foregroundStyle(palette.textTertiary).lineLimit(1)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Terminal command surface")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String = {
            switch hour {
            case 5..<12:  return "Good morning"
            case 12..<17: return "Good afternoon"
            case 17..<22: return "Good evening"
            default:      return "Welcome back"
            }
        }()
        let name = session.user?.firstName ?? "Terminal"
        return "\(timeOfDay), \(name)"
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
            .padding(.horizontal, -14)
    }

    // MARK: - Identity hero (56pt avatar + parity with 350/320 hero)

    private var identityHero: some View {
        let user = session.user
        let displayName = user?.name ?? "Terminal user"
        return LifecycleCard(accentGradient: true) {
            HStack(alignment: .center, spacing: 10) {
                EditableProfileAvatar(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if let email = user?.email, !email.isEmpty {
                        Text(email)
                            .font(EType.body)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    if let cid = user?.companyId, !cid.isEmpty {
                        Text("Company ID · \(cid)")
                            .font(EType.mono(.micro)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Sections (LifecycleCard chrome — visual parity with 350)
    //
    // Pure nav hub. Each id below maps to a registered Terminal surface
    // screen (701 gate queue, 702 yard map).

    private var operationsSection: some View {
        sectionCard(key: "operations", title: "OPERATIONS", icon: "shippingbox") {
            row(label: "Gate queue", icon: "arrow.left.arrow.right", to: "701")
            row(label: "Yard map",   icon: "map",                    to: "702")
            row(label: "Register container", icon: "shippingbox.fill", to: "TerminalVesselWrites")
        }
    }

    // MARK: - Access card section
    //
    // Two sides of the staff ACCESS CARD, grounded in the real
    // `staffAccessTokens` grant (server terminals.ts):
    //   • HOLDER  — "Add access card to Wallet": mints the themed Apple Wallet
    //     access pass for THIS staff member's temporary access token. Presents
    //     the shared WalletCardPickerView in access mode (AddAccessCardButton).
    //   • CONTROLLER — "Access control · scan": opens the scanner/verify surface
    //     so an access controller can verify a scanned card honestly. A pushed
    //     leaf via .eusoTerminalNavSwap → "TerminalAccessScan".

    private var accessCardSection: some View {
        sectionCard(key: "access", title: "ACCESS CARD", icon: "lock.shield") {
            // Holder side — the AddAccessCardButton owns the picker-sheet.
            AddAccessCardButton {
                accessRowChrome(label: "Add access card to Wallet",
                                icon: "wallet.pass",
                                trailingSystemImage: "plus.circle")
            }
            .simultaneousGesture(TapGesture().onEnded {
                returnAnchor = rowAnchor("access-wallet")
            })
            .id(rowAnchor("access-wallet"))
            // Controller side — push the scanner/verify surface.
            row(label: "Access control · scan", icon: "qrcode.viewfinder", to: "TerminalAccessScan")
        }
    }

    /// Row chrome matching `row(...)` but used inside the AddAccessCardButton
    /// label (which owns the tap, so this isn't a nav `Button`).
    private func accessRowChrome(label: String, icon: String, trailingSystemImage: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
            }
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            Image(systemName: trailingSystemImage)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var supportSection: some View {
        sectionCard(key: "support", title: "SUPPORT", icon: "lifepreserver") {
            eSangRow
        }
    }

    private var walletSection: some View {
        VStack(spacing: Space.s3) {
            LifecycleCard {
                categoryHeader(key: "wallet", title: "WALLET", icon: "creditcard")
            }
            .id(categoryAnchor("wallet"))

            if expandedCategory == "wallet" {
                EusoCardIssuePanel(
                    title: "Terminal EusoCard",
                    subtitle: "Virtual card for terminal operations spend"
                )
                .id("terminal-me-row-eusocard")
            }
        }
    }

    // MARK: - Sign out

    private var signOutButton: some View {
        Button(action: { showSignOutConfirm = true }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.square")
                    .font(.system(size: 13, weight: .heavy))
                Text("Sign out")
                    .font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, Space.s3)
    }

    // MARK: - Section + row primitives (LifecycleCard parity)

    @ViewBuilder
    private func sectionCard<Content: View>(key: String,
                                            title: String,
                                            icon: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        LifecycleCard {
            categoryHeader(key: key, title: title, icon: icon)
            if expandedCategory == key {
                Divider().overlay(palette.borderFaint)
                VStack(spacing: 6) {
                    content()
                }
            }
        }
        .id(categoryAnchor(key))
    }

    private func categoryHeader(key: String, title: String, icon: String) -> some View {
        Button(action: { toggleCategory(key) }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(title)
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: expandedCategory == key ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expandedCategory == key ? "Expanded" : "Collapsed")
    }

    private func row(label: String, icon: String, to screenId: String) -> some View {
        Button(action: {
            returnAnchor = rowAnchor(screenId)
            swap(to: screenId)
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                }
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .id(rowAnchor(screenId))
    }

    private var eSangRow: some View {
        Button(action: {
            returnAnchor = rowAnchor("esang")
            NotificationCenter.default.post(
                name: .eusoTerminaleSangTapped,
                object: nil
            )
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 36, height: 36)
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                }
                Text("Help · ESANG")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .id(rowAnchor("esang"))
    }

    private func toggleCategory(_ key: String) {
        returnAnchor = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedCategory = expandedCategory == key ? "" : key
        }
    }

    private func categoryAnchor(_ key: String) -> String {
        "terminal-me-category-\(key)"
    }

    private func rowAnchor(_ key: String) -> String {
        "terminal-me-row-\(key)"
    }

    private func restoreScrollPosition(using proxy: ScrollViewProxy) {
        guard !expandedCategory.isEmpty, !returnAnchor.isEmpty else { return }
        eusoRestoreScrollPosition(
            using: proxy,
            anchor: returnAnchor,
            fallback: categoryAnchor(expandedCategory)
        )
    }

    private func swap(to screenId: String) {
        NotificationCenter.default.post(
            name: .eusoTerminalNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}

#Preview("703 · Terminal · Me · Dark") {
    TerminalMeScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("703 · Terminal · Me · Light") {
    TerminalMeScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
