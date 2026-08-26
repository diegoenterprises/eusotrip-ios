//
//  067A_DriverMeHubs.swift
//  EusoTrip — Driver · Me hub (parent → children) mirroring the
//  Shipper 320/320a-g pattern. Founder direction 2026-05-04: "i like
//  how shipper's me section is designed and how it looks and because
//  of how the parent and child relation of the menu items and screens
//  are designed its perfect. i need this for the driver too."
//
//  IA (parent → children — every leaf points at an existing
//  registered driver-role screen, no dead taps):
//
//    067hub  Driver Me Home              (identity + tier + 7 hub cards + sign-out)
//      ├ 067a Account                    (Profile 067 · Authority 105 · Carrier scorecard 085 · Ratings 097)
//      ├ 067b EusoWallet                 (Wallet 069 · Earnings 068/079 · Settlements 070 ·
//      │                                  Payment methods 077 · Payout schedule 078 ·
//      │                                  Tax 071 / 080 · IFTA 090 · Fuel cards 094)
//      ├ 067c Compliance & Safety        (HOS 074 · ELD logs 081 · Violations 082 ·
//      │                                  Safety score 075 · Safety coach 087 ·
//      │                                  DataQs 084 · DQ file 093 · Permits 092 ·
//      │                                  Drug testing → Documents Hub 083)
//      ├ 067d Vehicle & Documents        (Vehicle 073 · Documents Hub 083 · Permits 092 ·
//      │                                  Detention 091 · Rate sheets 104 · Agreements 103)
//      ├ 067e Operations                 (My bids 107 · LoadBoard 108 · Appointments 101 ·
//      │                                  Hot zones 100 · Rate intel 095 · Auto-accept 110 ·
//      │                                  Contacts 102 · EusoTicket 106)
//      ├ 067f The Haul & Intel           (Haul dashboard 060 · Missions 061 · Badges 062 ·
//      │                                  Crates 063 · Leaderboard 064 · Streaks 065 ·
//      │                                  Cosmetics 066)
//      └ 067g Settings & Support         (Training 076 · Support 089 · Incident filer 086 ·
//                                         Freight claims 099 · Emergency ops 098 · ERG 096 ·
//                                         Invite & earn 088 · Sign out)
//
//  All 38 leaf screens already exist + are registered for driver role
//  (verified in ContentView.swift). Cell taps post the canonical
//  `eusoDriverMeNavSwap` notification with the screen id; the
//  surface that hosts the hub listens for it and pushes the screen
//  onto its local navigation stack. Hub-card taps drive the same
//  notification with one of the seven hub child ids.
//

import SwiftUI

// MARK: - Public Screen wrappers (one per IA node)

/// Apple Watch pairing surface — wraps the canonical `MePulseView`
/// (in MeDetailScreens.swift). Registered for BOTH driver and
/// shipper roles so each Me Settings hub can drill into it. Founder
/// report 2026-05-04: "i see no eusotrip pulse settings for either
/// user types right now".
struct PulseSettingsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { MePulseView() } nav: { driverMeHubNav() }
    }
}

struct DriverMeHomeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        // Use the canonical driver Me-tab chrome — same Shell that
        // wraps every driver Me screen. Caller drives back-nav via
        // `eusoDriverMeNavSwap` and the surface's stack.
        Shell(theme: theme) { DriverMeHomeBody() } nav: { driverMeHubNav() }
    }
}

struct DriverMeAccountHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DriverMeHubBody(title: "Account & Profile",
                            subtitle: "Identity · Authority · Carrier · Ratings",
                            sections: DriverMeHubCatalog.account)
        } nav: { driverMeHubNav() }
    }
}

struct DriverMeWalletHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DriverMeHubBody(title: "EusoWallet",
                            subtitle: "Money in, money out",
                            sections: DriverMeHubCatalog.wallet)
        } nav: { driverMeHubNav() }
    }
}

struct DriverMeComplianceHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DriverMeHubBody(title: "Compliance & Safety",
                            subtitle: "HOS · ELD · Violations · Safety · DQ",
                            sections: DriverMeHubCatalog.compliance,
                            // The compliance hub is the "engine that lets a
                            // driver drive compliant" — surface the REAL ELD
                            // connection state above the HOS/ELD rows so the
                            // driver sees an honest connected/disconnected
                            // status (and a Connect CTA) before they drill in.
                            showsELDStatus: true)
        } nav: { driverMeHubNav() }
    }
}

struct DriverMeVehicleHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DriverMeHubBody(title: "Vehicle & Documents",
                            subtitle: "Vehicle · Vault · Permits · Agreements",
                            sections: DriverMeHubCatalog.vehicle)
        } nav: { driverMeHubNav() }
    }
}

struct DriverMeOperationsHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DriverMeHubBody(title: "Operations",
                            subtitle: "Bids · Loads · Appointments · Intel",
                            sections: DriverMeHubCatalog.operations)
        } nav: { driverMeHubNav() }
    }
}

struct DriverMeHaulHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DriverMeHubBody(title: "The Haul & Intel",
                            subtitle: "Missions · Badges · Crates · Leaderboard",
                            sections: DriverMeHubCatalog.haul)
        } nav: { driverMeHubNav() }
    }
}

struct DriverMeSettingsHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DriverMeSettingsHubBody()
        } nav: { driverMeHubNav() }
    }
}

// MARK: - Driver Me hub bottom nav

/// Bottom nav for any screen reached through the Me hub. Same four
/// canonical driver tabs the rest of the app uses, with Me current.
private func driverMeHubNav() -> BottomNav {
    BottomNav(
        leading: [
            NavSlot(label: "Home",   systemImage: "house.fill",        isCurrent: false),
            NavSlot(label: "Trips",  systemImage: "road.lanes",        isCurrent: false),
        ],
        trailing: [
            NavSlot(label: "My Loads", systemImage: "shippingbox.fill",  isCurrent: false),
            NavSlot(label: "Me",     systemImage: "person.fill",       isCurrent: true),
        ],
        orbState: .idle
    )
}

// MARK: - Notification names

extension Notification.Name {
    /// `userInfo["screenId"]` — the driver-role screen registry id to
    /// swap to. Hosted by `DriverMePane` (or a future
    /// `DriverMeSurface`); it owns a small navigation stack so back
    /// nav unwinds to the parent hub. Mirrors `eusoShipperNavSwap`.
    static let eusoDriverMeNavSwap = Notification.Name("eusoDriverMeNavSwap")

    /// Pop one entry off the driver Me navigation stack.
    static let eusoDriverMeNavBack = Notification.Name("eusoDriverMeNavBack")
}

// MARK: - Shared cell-action model

enum DriverMeCellAction {
    case screen(String)
    case fire(String)
    case signOut

    var stableID: String {
        switch self {
        case .screen(let id):
            return "screen:\(id)"
        case .fire(let key):
            return "fire:\(key)"
        case .signOut:
            return "sign-out"
        }
    }
}

struct DriverMeCell: Identifiable {
    let icon: String
    let label: String
    let action: DriverMeCellAction

    var id: String { "\(label)|\(action.stableID)" }
}

struct DriverMeSection {
    let title: String
    let icon: String
    let cells: [DriverMeCell]
}

// MARK: - Hub catalog (parent → children)

/// Single source of truth for driver Me-section navigation. Every
/// screen id below is verified registered for `role: .driver` in
/// ContentView's ScreenRegistry — no dead taps. Adding a row: append
/// here, ensure the target id is registered.
enum DriverMeHubCatalog {
    static let account: [DriverMeSection] = [
        DriverMeSection(title: "IDENTITY", icon: "person.crop.circle", cells: [
            DriverMeCell(icon: "person.circle",       label: "Profile",              action: .screen("067")),
            DriverMeCell(icon: "checkmark.seal.fill", label: "Authority",            action: .screen("105")),
        ]),
        DriverMeSection(title: "REPUTATION", icon: "star.fill", cells: [
            DriverMeCell(icon: "star.fill",     label: "My ratings",         action: .screen("097")),
            DriverMeCell(icon: "chart.bar",     label: "Carrier scorecard",  action: .screen("085")),
        ]),
    ]

    static let wallet: [DriverMeSection] = [
        DriverMeSection(title: "MONEY IN", icon: "arrow.down.circle", cells: [
            DriverMeCell(icon: "wallet.pass.fill",      label: "EusoWallet",          action: .screen("069")),
            DriverMeCell(icon: "dollarsign.circle",     label: "Earnings",            action: .screen("068")),
            DriverMeCell(icon: "chart.line.uptrend.xyaxis", label: "Earnings breakdown", action: .screen("079")),
            DriverMeCell(icon: "creditcard",            label: "Settlements",         action: .screen("070")),
        ]),
        DriverMeSection(title: "MONEY OUT", icon: "arrow.up.circle", cells: [
            DriverMeCell(icon: "creditcard.and.123",    label: "Payment methods",     action: .screen("077")),
            DriverMeCell(icon: "calendar",              label: "Payout schedule",     action: .screen("078")),
            DriverMeCell(icon: "fuelpump",              label: "Fuel cards",          action: .screen("094")),
        ]),
        DriverMeSection(title: "TAXES", icon: "doc.text", cells: [
            DriverMeCell(icon: "doc.text",              label: "Tax overview",        action: .screen("071")),
            DriverMeCell(icon: "doc.append",            label: "Tax documents",       action: .screen("080")),
            DriverMeCell(icon: "chart.bar.doc.horizontal", label: "IFTA",             action: .screen("090")),
        ]),
    ]

    static let compliance: [DriverMeSection] = [
        DriverMeSection(title: "HOURS OF SERVICE", icon: "clock.fill", cells: [
            // Canonical HOS dashboard — same surface the homepage HOS
            // widget opens (019). Keeps Home + Me views in sync per the
            // founder mandate "I like the one on the homescreen, just
            // make sure it is synced."
            DriverMeCell(icon: "speedometer",           label: "HOS dashboard",       action: .screen("019")),
            DriverMeCell(icon: "waveform.path.ecg",     label: "HOS logs",            action: .screen("074")),
            DriverMeCell(icon: "doc.text.magnifyingglass", label: "ELD logs detail",  action: .screen("081")),
            DriverMeCell(icon: "antenna.radiowaves.left.and.right",
                                                          label: "ELD device · connect", action: .screen("074E")),
        ]),
        DriverMeSection(title: "SAFETY", icon: "shield.lefthalf.filled", cells: [
            DriverMeCell(icon: "speedometer",           label: "Safety score",        action: .screen("075")),
            DriverMeCell(icon: "person.fill.checkmark", label: "Safety coach",        action: .screen("087")),
            DriverMeCell(icon: "exclamationmark.triangle", label: "Violations",       action: .screen("082")),
            DriverMeCell(icon: "heart.text.square",     label: "Wellness & fatigue",  action: .screen("162")),
        ]),
        DriverMeSection(title: "DRIVER QUALIFICATION", icon: "checkmark.seal", cells: [
            DriverMeCell(icon: "doc.text",              label: "DQ file",             action: .screen("093")),
            DriverMeCell(icon: "envelope.badge",        label: "DataQs filer",        action: .screen("084")),
            DriverMeCell(icon: "graduationcap",         label: "Training",            action: .screen("076")),
        ]),
    ]

    static let vehicle: [DriverMeSection] = [
        DriverMeSection(title: "VEHICLE", icon: "truck.box", cells: [
            DriverMeCell(icon: "truck.box",             label: "My vehicle",          action: .screen("073")),
            DriverMeCell(icon: "rectangle.on.rectangle", label: "Vehicle card",       action: .screen("057")),
            DriverMeCell(icon: "wrench.and.screwdriver", label: "Vehicle & equipment", action: .screen("059E")),
        ]),
        DriverMeSection(title: "DOCUMENTS", icon: "folder", cells: [
            DriverMeCell(icon: "folder",                label: "Documents Hub",       action: .screen("083")),
            DriverMeCell(icon: "doc.text",              label: "Permits",             action: .screen("092")),
            DriverMeCell(icon: "ticket",                label: "EusoTicket (BOL/POD)", action: .screen("106")),
        ]),
        DriverMeSection(title: "AGREEMENTS", icon: "signature", cells: [
            DriverMeCell(icon: "doc.append",            label: "Agreements",          action: .screen("103")),
            DriverMeCell(icon: "doc.richtext",          label: "Rate sheets",         action: .screen("104")),
        ]),
    ]

    static let operations: [DriverMeSection] = [
        DriverMeSection(title: "BIDDING", icon: "hand.raised", cells: [
            DriverMeCell(icon: "hand.raised.fill",      label: "My bids",             action: .screen("107")),
            DriverMeCell(icon: "shippingbox",           label: "Eusoboards",          action: .fire("driver.loadboard.open")),
            DriverMeCell(icon: "bolt.circle",           label: "Auto-accept rules",   action: .screen("110")),
        ]),
        DriverMeSection(title: "SCHEDULING", icon: "calendar", cells: [
            DriverMeCell(icon: "calendar",              label: "Appointments",        action: .screen("101")),
            DriverMeCell(icon: "clock.arrow.circlepath", label: "Detention",          action: .screen("091")),
            DriverMeCell(icon: "calendar.badge.clock",  label: "Weekly plan",         action: .screen("058")),
            DriverMeCell(icon: "list.bullet.rectangle", label: "Trips history",       action: .screen("059")),
        ]),
        DriverMeSection(title: "MARKET INTEL", icon: "flame", cells: [
            DriverMeCell(icon: "flame.fill",            label: "Hot zones",           action: .screen("100")),
            DriverMeCell(icon: "chart.line.uptrend.xyaxis", label: "Rate intel",      action: .screen("095")),
        ]),
        DriverMeSection(title: "PEOPLE", icon: "person.3.fill", cells: [
            DriverMeCell(icon: "phone.fill",            label: "Contacts",            action: .screen("102")),
        ]),
    ]

    static let haul: [DriverMeSection] = [
        DriverMeSection(title: "DASHBOARD", icon: "trophy.fill", cells: [
            DriverMeCell(icon: "trophy.fill",           label: "The Haul · Dashboard", action: .screen("060")),
            DriverMeCell(icon: "bubble.left.and.bubble.right.fill",
                                                          label: "Lobby",               action: .screen("060L")),
        ]),
        DriverMeSection(title: "GAME LOOP", icon: "flag.fill", cells: [
            DriverMeCell(icon: "flag.fill",             label: "Missions",            action: .screen("061")),
            DriverMeCell(icon: "rosette",               label: "Badges",              action: .screen("062")),
            DriverMeCell(icon: "shippingbox.fill",      label: "Crates",              action: .screen("063")),
            DriverMeCell(icon: "flame.fill",            label: "Streaks",             action: .screen("065")),
            DriverMeCell(icon: "gift.fill",             label: "Bonus tracker",       action: .screen("111")),
        ]),
        DriverMeSection(title: "COMMUNITY", icon: "person.3.fill", cells: [
            DriverMeCell(icon: "list.number",           label: "Leaderboard",         action: .screen("064")),
            DriverMeCell(icon: "sparkles",              label: "Cosmetics",           action: .screen("066")),
        ]),
    ]
}

// MARK: - Top hub: 067hub Driver Me Home

private struct DriverMeHomeBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var profile: DriverProfileStore
    /// Drives the in-app ProfileEditView sheet so name / phone /
    /// email edits land via `profile.updateProfile` instead of
    /// going through some other path.
    @State private var showProfileEdit: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                hero

                hubCard(icon: "person.crop.circle.fill",
                        title: "Account & Profile",
                        subtitle: "Identity · Authority · Ratings",
                        screenId: "067a")
                hubCard(icon: "wallet.pass.fill",
                        title: "EusoWallet",
                        subtitle: "Earnings · Settlements · Payment methods · Tax",
                        screenId: "067b")
                hubCard(icon: "shield.lefthalf.filled",
                        title: "Compliance & Safety",
                        subtitle: "HOS · ELD · Violations · Safety · DQ",
                        screenId: "067c")
                hubCard(icon: "truck.box.fill",
                        title: "Vehicle & Documents",
                        subtitle: "Vehicle · Vault · Permits · Agreements",
                        screenId: "067d")
                hubCard(icon: "rectangle.3.group.fill",
                        title: "Operations",
                        subtitle: "Bids · Loads · Appointments · Hot Zones",
                        screenId: "067e")
                hubCard(icon: "trophy.fill",
                        title: "The Haul & Intel",
                        subtitle: "Missions · Badges · Crates · Leaderboard",
                        screenId: "067f")
                hubCard(icon: "gearshape.fill",
                        title: "Settings & Support",
                        subtitle: "Training · Support · Emergency · Referrals",
                        screenId: "067g")

                signOutCell()

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .sheet(isPresented: $showProfileEdit) {
            ProfileEditView()
                .environmentObject(profile)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                EditableProfileAvatar(size: 64)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName())
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    HStack(spacing: 4) {
                        Text("Driver")
                            .font(EType.body)
                            .foregroundStyle(palette.textSecondary)
                        // Pencil → opens ProfileEditView sheet so
                        // name / email / phone edits persist via
                        // profile.updateProfile.
                        Button {
                            showProfileEdit = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(LinearGradient.diagonal)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit profile")
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }


    /// Card-style hub button — opens its child via the canonical
    /// `eusoDriverMeNavSwap` notification.
    private func hubCard(icon: String, title: String, subtitle: String, screenId: String) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoDriverMeNavSwap, object: nil,
                userInfo: ["screenId": screenId]
            )
        } label: {
            LifecycleCard {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .foregroundStyle(.white)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Text(subtitle)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
        }.buttonStyle(.plain)
    }

    private func signOutCell() -> some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoDriverMeNavSwap, object: nil,
                userInfo: ["screenId": "_logout"]
            )
        } label: {
            LifecycleCard {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                    Text("Sign out")
                        .font(EType.body)
                        .foregroundStyle(.red)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
        }.buttonStyle(.plain)
    }

    private func displayName() -> String {
        let first = profile.firstName.trimmingCharacters(in: .whitespaces)
        let last = profile.lastName.trimmingCharacters(in: .whitespaces)
        let combined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return combined.isEmpty ? "Welcome" : combined
    }

}

// MARK: - Generic hub child body

private struct DriverMeHubBody: View {
    let title: String
    let subtitle: String
    let sections: [DriverMeSection]
    /// When true, renders the honest ELD-connection status card above the
    /// catalog sections (compliance hub only). Reads the real
    /// `ELDIntegrationStore` — never a fabricated "connected".
    var showsELDStatus: Bool = false

    @Environment(\.palette) private var palette
    @SceneStorage("driver.me.child.expandedSection") private var expandedSection = ""
    @SceneStorage("driver.me.child.returnAnchor") private var returnAnchor = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    if showsELDStatus {
                        ELDComplianceStatusCard()
                    }
                    ForEach(sections, id: \.title) { section in
                        cellGroup(section)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }
            .onAppear {
                restoreReturnPosition(using: proxy)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    NotificationCenter.default.post(name: .eusoDriverMeNavBack, object: nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back").font(EType.caption)
                    }.foregroundStyle(palette.textSecondary)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            Text(title)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.7)
            Text(subtitle)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2).minimumScaleFactor(0.85)
        }
    }

    private func cellGroup(_ section: DriverMeSection) -> some View {
        let sectionID = sectionAnchor(section)
        let isExpanded = expandedSection == sectionID

        return LifecycleCard {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSection = isExpanded ? "" : sectionID
                    returnAnchor = ""
                }
            } label: {
                HStack {
                    LifecycleSection(label: section.title, icon: section.icon)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(section.cells) { cell in
                    let rowID = rowAnchor(cell, in: section)
                    Button {
                        expandedSection = sectionID
                        returnAnchor = rowID
                        handle(cell.action)
                    } label: {
                        HStack {
                            Image(systemName: cell.icon).foregroundStyle(LinearGradient.diagonal)
                            Text(cell.label).font(EType.body).foregroundStyle(palette.textPrimary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(rowID)
                }
            }
        }
        .id(sectionID)
    }

    private var hubAnchorPrefix: String {
        "driver.me.\(title)"
    }

    private func sectionAnchor(_ section: DriverMeSection) -> String {
        "\(hubAnchorPrefix).section.\(section.title)"
    }

    private func rowAnchor(_ cell: DriverMeCell, in section: DriverMeSection) -> String {
        "\(sectionAnchor(section)).row.\(cell.id)"
    }

    private func restoreReturnPosition(using proxy: ScrollViewProxy) {
        guard !returnAnchor.isEmpty,
              sections.contains(where: { sectionAnchor($0) == expandedSection }) else { return }
        eusoRestoreScrollPosition(
            using: proxy,
            anchor: returnAnchor,
            fallback: expandedSection
        )
    }

    private func handle(_ action: DriverMeCellAction) {
        switch action {
        case .screen(let id):
            NotificationCenter.default.post(
                name: .eusoDriverMeNavSwap, object: nil,
                userInfo: ["screenId": id]
            )
        case .fire(let key):
            MeAction.fire(key)
        case .signOut:
            NotificationCenter.default.post(
                name: .eusoDriverMeNavSwap, object: nil,
                userInfo: ["screenId": "_logout"]
            )
        }
    }
}

// MARK: - ELD compliance status card (compliance hub header)

/// Honest ELD-connection status for the Compliance & Safety hub. This is
/// the "engine that lets a driver drive compliant" — so it must tell the
/// truth: it reads the REAL connection state off `ELDIntegrationStore`
/// (server `eld.getConnectionStatus`) and renders either a connected
/// state (named provider, §395 vendor-sourced) or an honest
/// "No ELD connected" state with a real Connect CTA that drills into the
/// existing 074E ELD-connect screen. It NEVER fabricates "connected".
private struct ELDComplianceStatusCard: View {
    @Environment(\.palette) private var palette
    @StateObject private var eld = ELDIntegrationStore()

    var body: some View {
        LifecycleCard(accentWarning: !eld.isLoading && !eld.isConnected,
                      accentGradient: eld.isConnected) {
            VStack(alignment: .leading, spacing: 10) {
                LifecycleSection(label: "ELECTRONIC LOGGING DEVICE", icon: "antenna.radiowaves.left.and.right")
                if eld.isLoading && eld.connection == nil {
                    loadingRow
                } else if eld.isConnected {
                    connectedRow
                } else {
                    disconnectedRow
                }
            }
        }
        .eusoRefreshTask { await eld.bootstrap() }
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text("Checking ELD connection…")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// Real connected state — names the live vendor so the §395 claim is
    /// verifiable, not asserted.
    private var connectedRow: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(palette.tintSuccess).frame(width: 36, height: 36)
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(LinearGradient.diagonal)
                    .font(.system(size: 16, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(connectedTitle)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Duty-status clocks, logs and violations are vendor-sourced. 49 CFR §395 compliant.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            StatusPill(text: "Connected", kind: .success)
        }
    }

    private var connectedTitle: String {
        if let slug = eld.primaryConnectedSlug,
           let provider = eld.provider(for: slug) {
            return "\(provider.name) connected"
        }
        return "ELD connected"
    }

    /// Honest disconnected state — accurate copy + a working Connect CTA
    /// that opens the canonical 074E ELD-connect screen.
    private var disconnectedRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Brand.warning.opacity(0.14)).frame(width: 36, height: 36)
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(Brand.warning)
                        .font(.system(size: 15, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("No ELD connected")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("HOS is self-reported until you link a device. Connect your ELD so logs are vendor-sourced for roadside inspections.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                StatusPill(text: "Not connected", kind: .neutral)
            }
            Button {
                // Drill into the existing 074E ELD-connect screen through the
                // canonical Me-hub nav swap — same path every compliance leaf
                // uses, so back-nav unwinds cleanly to this hub.
                NotificationCenter.default.post(
                    name: .eusoDriverMeNavSwap, object: nil,
                    userInfo: ["screenId": "074E"]
                )
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Connect ELD device")
                        .font(EType.body).fontWeight(.semibold)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Settings & Support hub (067g)

private struct DriverMeSettingsHubBody: View {
    @Environment(\.palette) private var palette
    @SceneStorage("driver.me.settings.expandedSection") private var expandedSection = ""
    @SceneStorage("driver.me.settings.returnAnchor") private var returnAnchor = ""

    private let sections: [DriverMeSection] = [
        DriverMeSection(title: "DEVICES & SYNC", icon: "applewatch", cells: [
            DriverMeCell(icon: "applewatch", label: "EusoTrip Pulse (Apple Watch)", action: .screen("PULSE")),
        ]),
        DriverMeSection(title: "TRAINING & SUPPORT", icon: "graduationcap", cells: [
            DriverMeCell(icon: "graduationcap", label: "Training", action: .screen("076")),
            DriverMeCell(icon: "lifepreserver", label: "Support", action: .screen("089")),
            DriverMeCell(icon: "person.2", label: "Invite & earn", action: .screen("088")),
        ]),
        DriverMeSection(title: "EMERGENCY & CLAIMS", icon: "exclamationmark.shield", cells: [
            DriverMeCell(icon: "exclamationmark.shield.fill", label: "Emergency ops", action: .screen("098")),
            DriverMeCell(icon: "doc.text.fill", label: "Incident filer", action: .screen("086")),
            DriverMeCell(icon: "exclamationmark.bubble", label: "Freight claims", action: .screen("099")),
            DriverMeCell(icon: "book.closed", label: "ERG (hazmat)", action: .screen("096")),
        ]),
        DriverMeSection(title: "ACCOUNT", icon: "person.crop.circle", cells: [
            DriverMeCell(icon: "rectangle.portrait.and.arrow.right", label: "Sign out", action: .signOut),
        ]),
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    RoleSettingsAccessCard()
                    ForEach(sections, id: \.title) { section in
                        settingsGroup(section)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }
            .onAppear {
                guard !returnAnchor.isEmpty,
                      sections.contains(where: { sectionAnchor($0) == expandedSection }) else { return }
                eusoRestoreScrollPosition(
                    using: proxy,
                    anchor: returnAnchor,
                    fallback: expandedSection
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    NotificationCenter.default.post(name: .eusoDriverMeNavBack, object: nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back").font(EType.caption)
                    }.foregroundStyle(palette.textSecondary)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            Text("Settings & Support")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.7)
            Text("Training · Support · Emergency · Account")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func settingsGroup(_ section: DriverMeSection) -> some View {
        let sectionID = sectionAnchor(section)
        let isExpanded = expandedSection == sectionID

        return LifecycleCard {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSection = isExpanded ? "" : sectionID
                    returnAnchor = ""
                }
            } label: {
                HStack {
                    LifecycleSection(label: section.title, icon: section.icon)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(section.cells) { cell in
                    let rowID = rowAnchor(cell, in: section)
                    Button {
                        expandedSection = sectionID
                        returnAnchor = rowID
                        handle(cell.action)
                    } label: {
                        HStack {
                            Image(systemName: cell.icon)
                                .foregroundStyle(cell.action.stableID == "sign-out" ? AnyShapeStyle(.red) : AnyShapeStyle(LinearGradient.diagonal))
                            Text(cell.label)
                                .font(EType.body)
                                .foregroundStyle(cell.action.stableID == "sign-out" ? AnyShapeStyle(.red) : AnyShapeStyle(palette.textPrimary))
                            Spacer(minLength: 0)
                            if cell.action.stableID != "sign-out" {
                                Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(rowID)
                }
            }
        }
        .id(sectionID)
    }

    private func sectionAnchor(_ section: DriverMeSection) -> String {
        "driver.me.settings.section.\(section.title)"
    }

    private func rowAnchor(_ cell: DriverMeCell, in section: DriverMeSection) -> String {
        "\(sectionAnchor(section)).row.\(cell.id)"
    }

    private func handle(_ action: DriverMeCellAction) {
        switch action {
        case .screen(let id):
            NotificationCenter.default.post(
                name: .eusoDriverMeNavSwap, object: nil,
                userInfo: ["screenId": id]
            )
        case .fire(let key):
            MeAction.fire(key)
        case .signOut:
            NotificationCenter.default.post(
                name: .eusoDriverMeNavSwap, object: nil,
                userInfo: ["screenId": "_logout"]
            )
        }
    }
}

// MARK: - DriverMeSurface — screen-stack host for the Me tab

/// Hosts the driver Me hub stack. Owns a `[String]` navigation stack;
/// pushes on `eusoDriverMeNavSwap`, pops on `eusoDriverMeNavBack`.
/// Renders the screen at the top of the stack out of `ScreenRegistry`,
/// so leaf taps from any hub child drill into the existing 060-110
/// driver Me screens. Mirrors the `ShipperSurface` pattern (back
/// overlay, tab semantics, RBAC gate).
struct DriverMeSurface: View {
    let palette: Theme.Palette

    @EnvironmentObject var session: EusoTripSession
    @Environment(\.driverNavHandler) private var driverNavHandler
    @State private var screenStack: [String] = ["067hub"]

    /// Captured from `.eusoDriverMeNavSwap` userInfo when a leaf needs a
    /// real entity id (e.g. 107 My Bids → 109 Bid Detail carries the
    /// load). When non-nil and the current screen is 109 we construct
    /// `MeBidDetailScreen(theme:loadId:)` with the live id instead of the
    /// registry's `loadId: 0` sentinel — mirrors `ShipperSurface.activeLoadId`.
    /// Without this the bid-detail chain always rendered empty.
    @State private var activeLoadId: Int? = nil

    private var currentScreenId: String { screenStack.last ?? "067hub" }

    private var current: ProductionScreen {
        // 109 Bid Detail mounts with the load captured from the row tap
        // so the counter chain is the real one, not the `loadId: 0` seed.
        if currentScreenId == "109", let loadId = activeLoadId {
            return ProductionScreen(id: "109",
                                    title: "Me · Bid Detail",
                                    role: .driver) { p in
                AnyView(MeBidDetailScreen(theme: p, loadId: loadId))
            }
        }
        return ScreenRegistry.forRole(.driver).first { $0.id == currentScreenId }
            ?? ScreenRegistry.forRole(.driver).first { $0.id == "067hub" }
            ?? ProductionScreen(id: "067hub",
                                title: "Driver · Me Home",
                                role: .driver) { p in
                                    AnyView(DriverMeHomeScreen(theme: p))
                                }
    }

    /// Hub child screens that ship their own header back chevron —
    /// suppressing the surface overlay for these prevents the
    /// double-back collision the founder flagged. Every other
    /// pushed leaf (HOS logs detail, ELD detail, ERG, etc) gets the
    /// surface overlay so a one-tap back is always available.
    ///
    /// The eight `067*` hub screens render their own `.eusoDriverMeNavBack`
    /// chevron in `DriverMeHubBody.header` / `DriverMeSettingsHubBody.header`.
    /// `019` (HOS), `064` (The Haul Leaderboard) and `162` (Wellness &
    /// Fatigue) are leaf screens that ALSO bake their own header chevron —
    /// each was double-rendering the surface overlay on top of their own bar
    /// (and their own bar called a dead `dismiss()` in this push context).
    /// Their chevrons now post `.eusoDriverMeNavBack` (see their top bars),
    /// so they belong in this set to suppress the surface overlay and leave
    /// exactly one working back button.
    private static let driverScreensWithOwnBack: Set<String> = [
        "067hub", "067a", "067b", "067c", "067d", "067e", "067f", "067g",
        "019", "064", "162",
    ]

    var body: some View {
        current.view(palette)
            .id("driver-me-\(currentScreenId)")
            .eusoRefreshSurface("driver:me:\(currentScreenId)")
            .transition(.opacity)
            // Inside the Me stack, the ONLY back mechanism is this
            // surface's `.eusoDriverMeNavBack` pop. A couple of pushed
            // leaves (019 HOS, 064 Leaderboard) also live on the Home
            // lifecycle and reach for the app-wide `\.driverNavBack`
            // (→ `trip.stepBack()`) in their top bars. Null that env here
            // so their chevron's `navBack?()` is a no-op in the Me context
            // — otherwise tapping back would silently walk `trip.phase`
            // backward and land the driver on the wrong Home screen the
            // next time they open the Home tab. Their `.eusoDriverMeNavBack`
            // post (fired alongside) does the real pop.
            .environment(\.driverNavBack, nil)
            .overlay(alignment: .topLeading) {
                // Re-introduces a single canonical surface back
                // chevron for any driver-Me leaf that doesn't ship
                // its own header back. Resolves "no back button on
                // The Haul Leaderboard / ERG / etc" reports without
                // touching every leaf file.
                if screenStack.count > 1,
                   !Self.driverScreensWithOwnBack.contains(currentScreenId) {
                    Button {
                        NotificationCenter.default.post(
                            name: .eusoDriverMeNavBack, object: nil
                        )
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.55), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 12)
                    .padding(.top, 8)
                    .accessibilityLabel("Back")
                }
            }
            .modifier(EusoEdgeSwipeBack(
                isEnabled: screenStack.count > 1,
                onBack: {
                    NotificationCenter.default.post(
                        name: .eusoDriverMeNavBack, object: nil
                    )
                }
            ))
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoDriverMeNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
                if id == "108" {
                    // 108 is a legacy Driver-Me deep link. The single
                    // production Eusoboards surface now lives in the
                    // Driver Trips tab, so route old pushes there instead
                    // of showing a second loadboard rendition.
                    screenStack = ["067hub"]
                    driverNavHandler?("Trips")
                    return
                }
                if id == "_logout" {
                    // Sign-out is owned by the session layer; surface
                    // the request via the existing logout post so any
                    // listener (auth coordinator) can handle it.
                    NotificationCenter.default.post(name: Notification.Name("eusoLogoutRequested"), object: nil)
                    return
                }
                guard RoleAccess.canRender(role: .driver, screenId: id) else {
                    screenStack = ["067hub"]
                    return
                }
                // Capture the load id a detail leaf needs (109 Bid
                // Detail). Nil it on any other swap so a stale load
                // never leaks into a later bare open of the same screen.
                if id == "109",
                   let raw = note.userInfo?["loadId"] as? String,
                   let lid = Int(raw) {
                    activeLoadId = lid
                } else if id != "109" {
                    activeLoadId = nil
                }
                withAnimation(.easeInOut(duration: 0.22)) {
                    if id == "067hub" {
                        screenStack = ["067hub"]
                    } else if screenStack.last != id {
                        screenStack.append(id)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoDriverMeNavBack)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) {
                    if screenStack.count > 1 {
                        let popped = screenStack.removeLast()
                        // Drop the captured load when leaving Bid Detail
                        // so a re-open without a fresh id can't show a
                        // stale chain.
                        if popped == "109" { activeLoadId = nil }
                    }
                }
            }
    }
}

// MARK: - Previews

#Preview("067hub · Driver Me · Night")     { DriverMeHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).environmentObject(DriverProfileStore()).preferredColorScheme(.dark) }
#Preview("067hub · Driver Me · Afternoon") { DriverMeHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).environmentObject(DriverProfileStore()).preferredColorScheme(.light) }
#Preview("067a · Account · Night")         { DriverMeAccountHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("067b · Wallet · Night")          { DriverMeWalletHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("067c · Compliance · Night")      { DriverMeComplianceHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("067d · Vehicle · Night")         { DriverMeVehicleHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("067e · Operations · Night")      { DriverMeOperationsHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("067f · Haul · Night")            { DriverMeHaulHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("067g · Settings · Night")        { DriverMeSettingsHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
