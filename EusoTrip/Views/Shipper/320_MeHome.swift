//
//  320_MeHome.swift
//  EusoTrip — Shipper · ME tab home + hub child screens (Arc J).
//
//  IA (parent → children):
//    320  Me Home          (identity hero + tier + 7 hub cards + sign-out)
//      ├ 320a Account hub   (Profile, Edit profile, Tier detail)
//      ├ 320b Wallet hub    (Wallet, Settlements, Payment methods, Statements,
//      │                    Apple Pay, Reports, Sustainability)
//      ├ 320c Operations    (Control Tower, Live Tracking, Recurring,
//      │                    Allocations, Hot Zones, Hardware Capabilities)
//      ├ 320d Network       (Partner Directory, Catalyst Scorecards,
//      │                    Catalyst Directory, Contacts, Contracts, RFPs,
//      │                    Agreements)
//      ├ 320e Compliance    (Compliance Dash, Document Center, BOLs,
//      │                    Freight Claims, Insurance, FMCSA SAFER,
//      │                    Hazmat Audit)
//      ├ 320f Intel         (Shipper Intel, The Haul, Disputes)
//      └ 320g Settings      (Settings, Notification prefs, ESANG prefs,
//                           Help, Legal, Sign out)
//
//  Every cell drills via `eusoShipperNavSwap` to a registered shipper-role
//  screen — no dead taps.
//

import SwiftUI

// MARK: - Public Screen wrappers (one per hub IA node)

struct MeHomeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        wrapShipperScreen(palette: theme, currentSlot: .me) { MeHomeBody() }
    }
}

struct MeAccountHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        wrapShipperScreen(palette: theme, currentSlot: .me) {
            MeHubBody(title: "Account & Profile",
                      subtitle: "Identity · KYB · Tier",
                      sections: MeHubCatalog.account)
        }
    }
}

struct MeWalletHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        wrapShipperScreen(palette: theme, currentSlot: .me) {
            MeHubBody(title: "EusoWallet",
                      subtitle: "Money in, money out",
                      sections: MeHubCatalog.wallet)
        }
    }
}

struct MeOperationsHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        wrapShipperScreen(palette: theme, currentSlot: .me) {
            MeHubBody(title: "Operations",
                      subtitle: "Control tower · Tracking · Hot zones",
                      sections: MeHubCatalog.operations)
        }
    }
}

struct MeNetworkHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        wrapShipperScreen(palette: theme, currentSlot: .me) {
            MeHubBody(title: "Network",
                      subtitle: "Partners · Scorecards · Contracts",
                      sections: MeHubCatalog.network)
        }
    }
}

struct MeComplianceHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        wrapShipperScreen(palette: theme, currentSlot: .me) {
            MeHubBody(title: "Compliance & Documents",
                      subtitle: "Compliance · Insurance · FMCSA · Hazmat · Docs",
                      sections: MeHubCatalog.compliance)
        }
    }
}

struct MeIntelHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        wrapShipperScreen(palette: theme, currentSlot: .me) { MeIntelHubBody() }
    }
}

struct MeSettingsHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        wrapShipperScreen(palette: theme, currentSlot: .me) { MeSettingsHubBody() }
    }
}

// MARK: - Shared cell-action model

/// Cell taps either drill into a registered shipper screen via the
/// `eusoShipperNavSwap` notification, surface a `MeDetailContainer`
/// route as a sheet (news, haul, disputes), open the hardware
/// capabilities sheet, or sign the user out.
enum MeCellAction {
    case screen(String)
    case detail(MeDetailRoute)
    case hardwareCapabilities
    case signOut
}

struct MeCell: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let action: MeCellAction
}

struct MeSection {
    let title: String
    let icon: String
    let cells: [MeCell]
}

// MARK: - Hub catalog (parent → children mapping)

/// Single source of truth for hub child screens. Every screen ID points
/// at a registered shipper-role screen — see ScreenRegistry registrations
/// in ContentView.swift. Adding a cell: add the row here, ensure the
/// target ID is registered for `role: .shipper`.
enum MeHubCatalog {
    static let account: [MeSection] = [
        MeSection(title: "IDENTITY", icon: "person.crop.circle", cells: [
            MeCell(icon: "person.circle",     label: "Profile",        action: .screen("202")),
            MeCell(icon: "pencil.circle",     label: "Edit profile",   action: .screen("322")),
        ]),
        MeSection(title: "TIER & STATUS", icon: "rosette", cells: [
            MeCell(icon: "rosette",           label: "Tier detail",    action: .screen("323")),
            MeCell(icon: "checkmark.shield",  label: "Verifications",  action: .screen("216")),
        ]),
    ]

    static let wallet: [MeSection] = [
        MeSection(title: "MONEY IN", icon: "arrow.down.circle", cells: [
            MeCell(icon: "wallet.pass.fill",     label: "EusoWallet",       action: .screen("290")),
            MeCell(icon: "creditcard",           label: "Settlements",      action: .screen("206")),
            MeCell(icon: "doc.text",             label: "Statements",       action: .screen("297")),
        ]),
        MeSection(title: "MONEY OUT", icon: "arrow.up.circle", cells: [
            MeCell(icon: "creditcard.and.123",   label: "Payment methods",  action: .screen("295")),
            MeCell(icon: "applelogo",            label: "Apple Pay wallet", action: .screen("239")),
        ]),
        MeSection(title: "REPORTING", icon: "chart.bar", cells: [
            MeCell(icon: "chart.bar",            label: "Reports",          action: .screen("207")),
            MeCell(icon: "leaf",                 label: "Sustainability",   action: .screen("214")),
            MeCell(icon: "chart.line.uptrend.xyaxis", label: "Analytics deep-dive", action: .screen("210")),
        ]),
    ]

    static let operations: [MeSection] = [
        MeSection(title: "VISIBILITY", icon: "eye", cells: [
            MeCell(icon: "rectangle.3.group",    label: "Control Tower",       action: .screen("212")),
            MeCell(icon: "location.viewfinder",  label: "Live tracking",       action: .screen("222")),
            MeCell(icon: "flame",                label: "Hot zones",           action: .screen("225")),
            MeCell(icon: "chart.line.uptrend.xyaxis", label: "Market intelligence", action: .screen("233")),
        ]),
        MeSection(title: "EXECUTION", icon: "arrow.triangle.branch", cells: [
            MeCell(icon: "arrow.clockwise",      label: "Recurring loads",     action: .screen("221")),
            MeCell(icon: "rectangle.split.3x1",  label: "Allocations",         action: .screen("229")),
            MeCell(icon: "calendar",             label: "Weekly allocations",  action: .screen("230b")),
            MeCell(icon: "list.bullet.rectangle", label: "Dispatch control",   action: .screen("218")),
        ]),
        MeSection(title: "TERMINAL OPS", icon: "antenna.radiowaves.left.and.right", cells: [
            MeCell(icon: "dot.radiowaves.left.and.right", label: "Hardware capabilities", action: .hardwareCapabilities),
        ]),
    ]

    static let network: [MeSection] = [
        MeSection(title: "PARTNERS", icon: "person.3.fill", cells: [
            MeCell(icon: "building.2",        label: "Partner directory",   action: .screen("224")),
            MeCell(icon: "person.3.fill",     label: "Catalyst directory",  action: .screen("280")),
            MeCell(icon: "star.fill",         label: "Catalyst scorecards", action: .screen("213")),
            MeCell(icon: "phone.fill",        label: "Contacts",            action: .screen("209")),
        ]),
        MeSection(title: "CONTRACTS & BIDS", icon: "doc.append", cells: [
            MeCell(icon: "doc.text.image",    label: "RFP & bids",          action: .screen("215")),
            MeCell(icon: "doc.append",        label: "Contracts",           action: .screen("217")),
            MeCell(icon: "signature",         label: "Agreements",          action: .screen("223")),
            MeCell(icon: "dollarsign.circle", label: "Rate board",          action: .screen("220")),
        ]),
    ]

    static let compliance: [MeSection] = [
        MeSection(title: "COMPLIANCE", icon: "shield.lefthalf.filled", cells: [
            MeCell(icon: "shield.lefthalf.filled", label: "Compliance dashboard", action: .screen("216")),
            MeCell(icon: "checkmark.shield",       label: "Insurance",           action: .screen("325")),
            MeCell(icon: "doc.text",               label: "FMCSA SAFER",         action: .screen("326")),
            MeCell(icon: "triangle.fill",          label: "Hazmat audit",        action: .screen("327")),
        ]),
        MeSection(title: "DOCUMENTS", icon: "folder", cells: [
            MeCell(icon: "folder",                label: "Document center", action: .screen("226")),
            MeCell(icon: "doc.fill",              label: "BOLs",            action: .screen("228")),
            MeCell(icon: "exclamationmark.bubble", label: "Freight claims", action: .screen("219")),
        ]),
    ]
}

// MARK: - Top hub: 320 Me Home

private struct MeHomeBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @State private var profile: ShipperAPI.Profile? = nil
    @State private var stats: ShipperAPI.Stats? = nil
    @State private var loading = true
    /// Inline load-error surface. Was a `/* tolerate */` no-op that
    /// left the profile screen blank on network failure with no hint.
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let p = profile { hero(p) }
                if let s = stats { tierCard(s) }
                if let err = loadError {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.danger)
                        Text(err)
                            .font(EType.caption)
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button {
                            Task { await load() }
                        } label: {
                            Text("RETRY")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Brand.danger))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Brand.danger.opacity(0.45))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                hubCard(icon: "person.crop.circle.fill",
                        title: "Account & Profile",
                        subtitle: "Identity · Tier · Verifications",
                        screenId: "320a")
                hubCard(icon: "wallet.pass.fill",
                        title: "EusoWallet",
                        subtitle: "Wallet · Settlements · Payment methods · Statements",
                        screenId: "320b")
                hubCard(icon: "rectangle.3.group.fill",
                        title: "Operations",
                        subtitle: "Control Tower · Tracking · Recurring · Hot Zones",
                        screenId: "320c")
                hubCard(icon: "person.3.fill",
                        title: "Network",
                        subtitle: "Partners · Scorecards · Contacts · Contracts · RFPs",
                        screenId: "320d")
                hubCard(icon: "shield.lefthalf.filled",
                        title: "Compliance & Documents",
                        subtitle: "Compliance · Insurance · FMCSA · Hazmat · Docs",
                        screenId: "320e")
                hubCard(icon: "newspaper.fill",
                        title: "Intel & The Haul",
                        subtitle: "Shipper news · Haul lobby · Disputes",
                        screenId: "320f")
                hubCard(icon: "gearshape.fill",
                        title: "Settings",
                        subtitle: "App · ESANG prefs · Help · Legal",
                        screenId: "320g")

                signOutCell()

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private func hero(_ p: ShipperAPI.Profile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Avatar — tappable to present the photo picker so
                // shippers can change their company/personal photo.
                // Founder reported 2026-05-04: "profile picture on me
                // screen at the top circled cant change anything
                // picture wise". The previous bare ZStack had no tap
                // gesture at all; now wraps a Button that posts the
                // canonical `eusoShipperAvatarPickRequested`
                // notification — `ShipperSurface` listens and
                // presents `PhotosPicker`.
                Button {
                    NotificationCenter.default.post(
                        name: .eusoShipperAvatarPickRequested,
                        object: nil
                    )
                } label: {
                    Text(initials(p.companyName.isEmpty ? p.contactName : p.companyName))
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                        // 56pt avatar — 64 was visually overpowering
                        // the company-name lockup when the company
                        // string was long ("EUSORONE TECHNOLOGIES,
                        // INC.").
                        .frame(width: 56, height: 56)
                        .background(LinearGradient.diagonal)
                        .clipShape(Circle())
                        .overlay(alignment: .bottomTrailing) {
                            // Camera affordance — visual cue that the
                            // avatar is interactive.
                            Image(systemName: "camera.fill")
                                .font(.system(size: 9, weight: .heavy))
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
                    // Long company names ("EUSORONE TECHNOLOGIES, INC.")
                    // were wrapping to 2-3 lines and pushing the rest
                    // of the hero off the visible region. lineLimit(2)
                    // + minimumScaleFactor lets the type adapt.
                    Text(dashIfEmpty(p.companyName))
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                    Text(dashIfEmpty(p.contactName))
                        .font(EType.body)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("USDOT \(dashIfEmpty(p.dotNumber)) · MC \(dashIfEmpty(p.mcNumber))")
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
            if p.verified {
                Text("VERIFIED").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }
        }
    }

    private func tierCard(_ s: ShipperAPI.Stats) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "TIER", icon: "rosette")
            LifecycleRow(label: "Total loads",        value: "\(s.totalLoads)")
            LifecycleRow(label: "Total spend",        value: "$\(s.totalSpend)")
            LifecycleRow(label: "On-time delivery",   value: "\(s.onTimeDeliveryRate)%")
            LifecycleRow(label: "Preferred catalysts", value: "\(s.preferredCatalysts)")
        }
    }

    /// Big tappable hub card — visually distinct from a leaf cell so
    /// the user reads it as "open this section" not "fire this action."
    private func hubCard(icon: String, title: String, subtitle: String, screenId: String) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap, object: nil,
                userInfo: ["screenId": screenId]
            )
        } label: {
            LifecycleCard {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 40, height: 40)
                        Image(systemName: icon).foregroundStyle(.white).font(.system(size: 18, weight: .semibold))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 16, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        Text(subtitle).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                }
                .padding(.vertical, 4)
            }
        }.buttonStyle(.plain)
    }

    private func signOutCell() -> some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap, object: nil,
                userInfo: ["screenId": "_logout"]
            )
        } label: {
            LifecycleCard {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right").foregroundStyle(.red)
                    Text("Sign out").font(EType.body).foregroundStyle(.red)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
        }.buttonStyle(.plain)
    }

    private func initials(_ s: String) -> String {
        s.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
    }

    private func load() async {
        loadError = nil
        do {
            async let p: ShipperAPI.Profile = EusoTripAPI.shared.shipper.getProfile()
            async let st: ShipperAPI.Stats   = EusoTripAPI.shared.shipper.getStats()
            profile = try await p
            stats = (try? await st)
        } catch let apiErr as EusoTripAPIError {
            loadError = apiErr.errorDescription ?? "Couldn't load your profile."
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Generic hub child body (Account / Wallet / Operations / Network / Compliance)

private struct MeHubBody: View {
    let title: String
    let subtitle: String
    let sections: [MeSection]

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @State private var detailRoute: MeDetailRoute? = nil
    @State private var showHardwareCaps: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                hubHeader
                ForEach(sections.indices, id: \.self) { i in
                    let section = sections[i]
                    cellGroup(title: section.title, icon: section.icon, cells: section.cells)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .sheet(item: $detailRoute) { route in
            MeDetailContainer(route: route)
                .environment(\.palette, palette)
                .eusoSheetX()
        }
        .sheet(isPresented: $showHardwareCaps) {
            HardwareCapabilitiesView()
                .environment(\.palette, palette)
                .environmentObject(session)
        }
    }

    private var hubHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    NotificationCenter.default.post(
                        name: .eusoShipperNavSwap, object: nil,
                        userInfo: ["screenId": "320"]
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Me").font(EType.caption)
                    }.foregroundStyle(palette.textSecondary)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            Text(title).font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(subtitle).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func cellGroup(title: String, icon: String, cells: [MeCell]) -> some View {
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

    private func handle(_ action: MeCellAction) {
        switch action {
        case .screen(let id):
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap, object: nil,
                userInfo: ["screenId": id]
            )
        case .detail(let route):
            detailRoute = route
        case .hardwareCapabilities:
            showHardwareCaps = true
        case .signOut:
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap, object: nil,
                userInfo: ["screenId": "_logout"]
            )
        }
    }
}

// MARK: - Intel hub (320f)

private struct MeIntelHubBody: View {
    @Environment(\.palette) private var palette
    @State private var detailRoute: MeDetailRoute? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                LifecycleCard {
                    LifecycleSection(label: "FEEDS", icon: "newspaper.fill")
                    row(icon: "newspaper.fill",         label: "Shipper Intel", route: .news)
                    row(icon: "trophy.fill",            label: "The Haul",      route: .haul)
                    row(icon: "exclamationmark.bubble", label: "Disputes",      route: .disputes)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .sheet(item: $detailRoute) { route in
            MeDetailContainer(route: route)
                .environment(\.palette, palette)
                .eusoSheetX()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    NotificationCenter.default.post(
                        name: .eusoShipperNavSwap, object: nil,
                        userInfo: ["screenId": "320"]
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Me").font(EType.caption)
                    }.foregroundStyle(palette.textSecondary)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            Text("Intel & The Haul").font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Role-aware news feed · Gamification lobby · Disputes")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func row(icon: String, label: String, route: MeDetailRoute) -> some View {
        Button { detailRoute = route } label: {
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

// MARK: - Settings hub (320g)

private struct MeSettingsHubBody: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header

                LifecycleCard {
                    LifecycleSection(label: "APP", icon: "gearshape.fill")
                    cell(icon: "gear",        label: "Shipper settings", screenId: "211")
                    cell(icon: "house",       label: "Settings home",    screenId: "340")
                    cell(icon: "bell",        label: "Notifications",    screenId: "343")
                }

                LifecycleCard {
                    LifecycleSection(label: "ESANG", icon: "sparkles")
                    cell(icon: "sparkles",        label: "ESANG preferences", screenId: "319")
                }

                LifecycleCard {
                    LifecycleSection(label: "DEVICES & SYNC", icon: "applewatch")
                    cell(icon: "applewatch",      label: "EusoTrip Pulse (Apple Watch)", screenId: "PULSE")
                }

                LifecycleCard {
                    LifecycleSection(label: "SUPPORT", icon: "questionmark.circle")
                    cell(icon: "questionmark.circle", label: "Help & support", screenId: "347")
                    cell(icon: "doc.plaintext",       label: "Legal",          screenId: "348")
                }

                LifecycleCard {
                    LifecycleSection(label: "ACCOUNT", icon: "person.crop.circle")
                    Button {
                        NotificationCenter.default.post(
                            name: .eusoShipperNavSwap, object: nil,
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
                    NotificationCenter.default.post(
                        name: .eusoShipperNavSwap, object: nil,
                        userInfo: ["screenId": "320"]
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Me").font(EType.caption)
                    }.foregroundStyle(palette.textSecondary)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            Text("Settings").font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("App · ESANG · Support · Account")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func cell(icon: String, label: String, screenId: String) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap, object: nil,
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

// MARK: - Previews

#Preview("320 · Me · Night")     { MeHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("320 · Me · Afternoon") { MeHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("320a · Account · Night")    { MeAccountHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("320a · Account · Afternoon") { MeAccountHubScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("320b · Wallet · Night")     { MeWalletHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("320b · Wallet · Afternoon") { MeWalletHubScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("320c · Operations · Night")     { MeOperationsHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("320c · Operations · Afternoon") { MeOperationsHubScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("320d · Network · Night")     { MeNetworkHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("320d · Network · Afternoon") { MeNetworkHubScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("320e · Compliance · Night")     { MeComplianceHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("320e · Compliance · Afternoon") { MeComplianceHubScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("320f · Intel · Night")     { MeIntelHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("320f · Intel · Afternoon") { MeIntelHubScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("320g · Settings · Night")     { MeSettingsHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("320g · Settings · Afternoon") { MeSettingsHubScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
