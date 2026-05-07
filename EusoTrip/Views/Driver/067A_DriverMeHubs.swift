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
import PhotosUI

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
                            sections: DriverMeHubCatalog.compliance)
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
            NavSlot(label: "Trips",  systemImage: "shippingbox.fill",  isCurrent: false),
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
    case signOut
}

struct DriverMeCell: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let action: DriverMeCellAction
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
            DriverMeCell(icon: "shippingbox",           label: "Eusoboards",          action: .screen("108")),
            DriverMeCell(icon: "bolt.circle",           label: "Auto-accept rules",   action: .screen("110")),
        ]),
        DriverMeSection(title: "SCHEDULING", icon: "calendar", cells: [
            DriverMeCell(icon: "calendar",              label: "Appointments",        action: .screen("101")),
            DriverMeCell(icon: "clock.arrow.circlepath", label: "Detention",          action: .screen("091")),
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
    /// Avatar PhotosPicker trigger — replaces the prior dead avatar
    /// where the founder reported "no longer a place to change
    /// profile name or edit picture." Tapping the avatar surfaces
    /// the system Photos picker; the picked Data is uploaded via
    /// `profile.updateAvatar` and the new URL persists across
    /// device restarts.
    @State private var avatarPickerItem: PhotosPickerItem? = nil
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
        .onChange(of: avatarPickerItem) { _, item in
            guard let item else { return }
            Task { await uploadAvatar(item: item) }
        }
        .sheet(isPresented: $showProfileEdit) {
            ProfileEditView()
                .environmentObject(profile)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Tappable avatar — opens PhotosPicker so the driver
                // can change their profile photo. Replaces the
                // previously dead avatar circle.
                PhotosPicker(selection: $avatarPickerItem,
                             matching: .images,
                             photoLibrary: .shared()) {
                    let initials = profileInitials()
                    Text(initials)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(LinearGradient.diagonal)
                        .clipShape(Circle())
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(Circle().fill(palette.bgCard))
                                .overlay(Circle().strokeBorder(palette.borderFaint))
                                .offset(x: 2, y: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change profile photo")

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

    /// Compress + base64-encode the picked photo, upload via
    /// `profile.updateAvatar`, and reseat the local store so the new
    /// image renders without a manual reload.
    private func uploadAvatar(item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              !data.isEmpty else { return }
        // Re-encode to JPEG ≤ 200KB so the data-URL stays reasonable.
        var jpeg = data
        if let img = UIImage(data: data) {
            var quality: CGFloat = 0.85
            while quality > 0.3 {
                if let d = img.jpegData(compressionQuality: quality), d.count <= 200_000 {
                    jpeg = d
                    break
                }
                quality -= 0.1
            }
        }
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        struct In: Encodable { let imageData: String }
        struct Out: Decodable { let success: Bool?; let url: String? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "profile.updateAvatar", input: In(imageData: dataURL)
            )
            await profile.refreshFromServer()
        } catch { /* surface via toast in a follow-up */ }
        avatarPickerItem = nil
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

    private func profileInitials() -> String {
        let parts = [profile.firstName, profile.lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let chars = parts.compactMap { $0.first }.map(String.init)
        let derived = chars.joined().uppercased()
        return derived.isEmpty ? "DU" : derived
    }
}

// MARK: - Generic hub child body

private struct DriverMeHubBody: View {
    let title: String
    let subtitle: String
    let sections: [DriverMeSection]

    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                ForEach(sections.indices, id: \.self) { i in
                    let section = sections[i]
                    cellGroup(title: section.title, icon: section.icon, cells: section.cells)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
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

    private func cellGroup(title: String, icon: String, cells: [DriverMeCell]) -> some View {
        LifecycleCard {
            LifecycleSection(label: title, icon: icon)
            ForEach(cells) { cell in
                Button {
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
                }.buttonStyle(.plain)
            }
        }
    }

    private func handle(_ action: DriverMeCellAction) {
        switch action {
        case .screen(let id):
            NotificationCenter.default.post(
                name: .eusoDriverMeNavSwap, object: nil,
                userInfo: ["screenId": id]
            )
        case .signOut:
            NotificationCenter.default.post(
                name: .eusoDriverMeNavSwap, object: nil,
                userInfo: ["screenId": "_logout"]
            )
        }
    }
}

// MARK: - Settings & Support hub (067g)

private struct DriverMeSettingsHubBody: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header

                LifecycleCard {
                    LifecycleSection(label: "DEVICES & SYNC", icon: "applewatch")
                    cell(icon: "applewatch",           label: "EusoTrip Pulse (Apple Watch)", screenId: "PULSE")
                }

                LifecycleCard {
                    LifecycleSection(label: "TRAINING & SUPPORT", icon: "graduationcap")
                    cell(icon: "graduationcap",        label: "Training",            screenId: "076")
                    cell(icon: "lifepreserver",        label: "Support",             screenId: "089")
                    cell(icon: "person.2",             label: "Invite & earn",       screenId: "088")
                }

                LifecycleCard {
                    LifecycleSection(label: "EMERGENCY & CLAIMS", icon: "exclamationmark.shield")
                    cell(icon: "exclamationmark.shield.fill", label: "Emergency ops", screenId: "098")
                    cell(icon: "doc.text.fill",        label: "Incident filer",      screenId: "086")
                    cell(icon: "exclamationmark.bubble", label: "Freight claims",    screenId: "099")
                    cell(icon: "book.closed",          label: "ERG (hazmat)",        screenId: "096")
                }

                LifecycleCard {
                    LifecycleSection(label: "ACCOUNT", icon: "person.crop.circle")
                    Button {
                        NotificationCenter.default.post(
                            name: .eusoDriverMeNavSwap, object: nil,
                            userInfo: ["screenId": "_logout"]
                        )
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right").foregroundStyle(.red)
                            Text("Sign out").font(EType.body).foregroundStyle(.red)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
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

    private func cell(icon: String, label: String, screenId: String) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoDriverMeNavSwap, object: nil,
                userInfo: ["screenId": screenId]
            )
        } label: {
            HStack {
                Image(systemName: icon).foregroundStyle(LinearGradient.diagonal)
                Text(label).font(EType.body).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
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
    @State private var screenStack: [String] = ["067hub"]

    private var currentScreenId: String { screenStack.last ?? "067hub" }

    private var current: ProductionScreen {
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
    /// pushed leaf (HOS logs detail, ELD detail, Haul leaderboard,
    /// ERG, etc) gets the surface overlay so a one-tap back is
    /// always available.
    private static let driverScreensWithOwnBack: Set<String> = [
        "067hub", "067a", "067b", "067c", "067d", "067e", "067f", "067g",
    ]

    var body: some View {
        current.view(palette)
            .id("driver-me-\(currentScreenId)")
            .transition(.opacity)
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
            .onReceive(NotificationCenter.default.publisher(
                for: .eusoDriverMeNavSwap)) { note in
                guard let id = note.userInfo?["screenId"] as? String else { return }
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
                        screenStack.removeLast()
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
