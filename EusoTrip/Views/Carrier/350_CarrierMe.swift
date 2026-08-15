//
//  350_CarrierMe.swift
//  EusoTrip — Catalyst (Carrier) · Me hub.
//
//  Visual parity with 320_MeHome (shipper) + 067A_DriverMeHubs:
//  56pt gradient-avatar identity hero, LifecycleCard sections,
//  40pt gradient icon circles on each row, gradient sign-out CTA.
//
//  Carrier nav route map binds the "me" bottom-nav slot to "350".
//  Pool = .carrier + .catalyst registry — destination ids audited
//  against ContentView.swift registrations (see comments per
//  section). Fictional / shipper-only ids removed.
//

import SwiftUI

struct CarrierMeScreen: View {
    let theme: Theme.Palette

    @EnvironmentObject private var session: EusoTripSession
    @Environment(\.palette) private var palette
    @State private var showSignOutConfirm: Bool = false

    /// Which hub cards are expanded. Consolidation (fix pack L15-11): the Me tab
    /// used to render 6 always-open sections = ~52 rows in one flat scroll. Now
    /// it presents 6 bespoke collapsible hubs (canonical H1–H7 taxonomy) whose
    /// bodies open on tap, so the default view is a clean stack of hub headers.
    /// Account starts expanded; the rest collapse. Every destination is
    /// preserved — nothing was orphaned to "workspace".
    @SceneStorage("carrier.me.expandedHub") private var expandedHubId: String = "account"
    @SceneStorage("carrier.me.returnAnchor") private var returnAnchor: String = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    topBar
                    titleBlock
                    iridescentHairline
                    identityHero
                    EusoCardIssuePanel(
                        title: "EusoCard",
                        subtitle: "Carrier spend card backed by EusoWallet Treasury"
                    )
                    accountHub
                    complianceHub
                    moneyHub
                    fleetHub
                    operationsHub
                    settingsHub
                    signOutButton
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            .onAppear { restorePosition(using: proxy) }
        }
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Sign out", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign back in to dispatch loads, view drivers and access ELD.")
        }
    }

    // MARK: - TopBar / Title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                EusoTripBrandMark(size: 12)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · ME")
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
            Text("Catalyst command surface")
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
        let name = session.user?.firstName ?? "Catalyst"
        return "\(timeOfDay), \(name)"
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
            .padding(.horizontal, -14)
    }

    // MARK: - Identity hero (56pt avatar + parity with 320 hero)

    private var identityHero: some View {
        let user = session.user
        let displayName = user?.name ?? "Catalyst user"
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

    // MARK: - Hubs (bespoke collapsible cards — canonical H1–H7 taxonomy)
    //
    // CarrierSurface pool = .carrier + .catalyst, .carrier wins on collisions.
    // Each id below was verified against ContentView.swift registrations.
    // Rows were regrouped to the L15-11 taxonomy: fleet-safety CSA / IFTA /
    // DataQ moved from FLEET → Compliance & Docs where they belong; every
    // destination from the old 6 sections is preserved.

    // H1 · Account & Identity
    private var accountHub: some View {
        hubCard(id: "account", icon: "person.crop.circle.fill",
                title: "Account & Identity",
                summary: "Profile · Authority · MC/DOT", rowCount: 2) {
            row(label: "Profile",            icon: "person",                 to: "302C") // .catalyst (own profile)
            row(label: "Authority · MC/DOT", icon: "shield.lefthalf.filled", to: "317")  // .carrier wins
        }
    }

    // H2 · Compliance & Documents
    private var complianceHub: some View {
        hubCard(id: "compliance", icon: "checkmark.shield.fill",
                title: "Compliance & Documents",
                summary: "CSA · IFTA · DataQ · Claims · Insurance", rowCount: 10) {
            row(label: "Compliance dash",   icon: "shield.checkered",              to: "316")  // .carrier
            row(label: "Driver compliance", icon: "person.badge.shield.checkmark", to: "326")  // .catalyst
            row(label: "Driver documents",  icon: "doc.on.doc",                    to: "322")  // .catalyst
            row(label: "Fleet safety · CSA", icon: "shield.lefthalf.filled",       to: "Cat383")  // .catalyst
            row(label: "Fleet IFTA",        icon: "map",                           to: "Cat384")  // .catalyst
            row(label: "Roadside · DataQ",  icon: "doc.text.magnifyingglass",      to: "Cat385")  // .catalyst
            row(label: "Cargo claim",       icon: "exclamationmark.bubble",        to: "Cat389")  // .catalyst
            row(label: "Detention alerts",  icon: "bell.badge",                    to: "Cat391")  // .catalyst
            row(label: "Cargo insurance",   icon: "checkmark.shield",              to: "Cat392")  // .catalyst
            row(label: "Fleet carbon",      icon: "leaf",                          to: "Cat403")  // .catalyst
        }
    }

    // H3 · Money & Wallet
    private var moneyHub: some View {
        hubCard(id: "money", icon: "wallet.pass.fill",
                title: "Money & Wallet",
                summary: "Earnings · Settlements · Bids · Factoring · Rates", rowCount: 12) {
            row(label: "Earnings",      icon: "chart.line.uptrend.xyaxis", to: "312")  // .carrier
            row(label: "Settlements",   icon: "doc.text",                  to: "313")  // .carrier wins
            row(label: "My bids",       icon: "hand.tap",                  to: "308")  // .carrier
            row(label: "Awarded loads", icon: "checkmark.seal",            to: "309")  // .carrier
            row(label: "Marketplace",   icon: "storefront",                to: "306")  // .carrier
            row(label: "Commission engine", icon: "percent",               to: "331")  // .catalyst
            row(label: "Driver pay setup",  icon: "creditcard.and.123",    to: "310")  // .catalyst
            row(label: "Factoring",         icon: "banknote",              to: "Cat394")  // .catalyst
            row(label: "Fuel surcharge schedule", icon: "fuelpump.circle", to: "Cat395")  // .catalyst
            row(label: "Lane rate sheet",   icon: "tablecells",            to: "Cat396")  // .catalyst
            row(label: "Carrier tier",      icon: "star.circle",           to: "Cat397")  // .catalyst
            row(label: "Toll corridor cost", icon: "road.lanes",           to: "Cat399")  // .catalyst
        }
    }

    // H4 · Fleet & Equipment
    private var fleetHub: some View {
        hubCard(id: "fleet", icon: "truck.box.fill",
                title: "Fleet & Equipment",
                summary: "Drivers · Vehicles · ELD · Maintenance · Monitors", rowCount: 16) {
            row(label: "Drivers",                icon: "person.2",            to: "304")  // .carrier
            row(label: "Driver list",            icon: "list.bullet",         to: "319")  // .carrier wins
            row(label: "Vehicles",               icon: "truck.box",           to: "320")  // .carrier wins
            row(label: "ELD · Hours of Service", icon: "clock.badge",         to: "318")  // .carrier
            row(label: "Maintenance",            icon: "wrench.adjustable",   to: "315")  // .carrier
            row(label: "Fuel card",              icon: "fuelpump",            to: "314")  // .carrier
            row(label: "Fuel card · fleet",      icon: "creditcard",          to: "Cat386")  // .catalyst
            row(label: "Reefer fleet monitor",   icon: "thermometer.snowflake", to: "Cat387")  // .catalyst
            row(label: "Tanker fleet monitor",   icon: "drop",                to: "Cat388")  // .catalyst
            row(label: "Convoy · platooning",    icon: "car.2",               to: "Cat400")  // .catalyst
            row(label: "Crew wellness",          icon: "heart.text.square",   to: "Cat401")  // .catalyst
            row(label: "Capacity planner",       icon: "chart.bar",           to: "Cat402")  // .catalyst
            row(label: "Driver performance",     icon: "gauge.with.dots.needle.67percent", to: "323")  // .catalyst
            row(label: "Driver ledger",          icon: "list.bullet.rectangle.portrait", to: "324")  // .catalyst
            row(label: "Driver onboarding",      icon: "person.badge.plus",   to: "325")  // .catalyst
            row(label: "Driver profile",         icon: "person.text.rectangle", to: "321")  // .catalyst
        }
    }

    // H · Operations (kept in Me, collapsed — grouped, not orphaned to workspace)
    private var operationsHub: some View {
        hubCard(id: "operations", icon: "rectangle.3.group.fill",
                title: "Operations",
                summary: "SpectraMatch · Board · Loads · Backhaul · Reports", rowCount: 11) {
            row(label: "Catalyst Home · SpectraMatch", icon: "scope",           to: "500")  // .catalyst
            row(label: "Active matches",                icon: "bolt",            to: "501")  // .catalyst
            row(label: "Dispatch board",                icon: "list.bullet.rectangle", to: "303")  // .carrier
            row(label: "Loads",                          icon: "shippingbox",    to: "301")  // .carrier
            row(label: "EDI messages",                   icon: "arrow.left.arrow.right", to: "Cat390")  // .catalyst
            row(label: "Document ingest",                icon: "doc.badge.plus", to: "Cat393")  // .catalyst
            row(label: "Backhaul optimizer",             icon: "arrow.triangle.2.circlepath", to: "Cat398")  // .catalyst
            row(label: "Matched loads",                  icon: "checkmark.circle", to: "340")  // .catalyst
            row(label: "Find loads",                     icon: "magnifyingglass", to: "341")  // .catalyst
            row(label: "Assigned loads",                 icon: "arrow.right.circle", to: "342")  // .catalyst
            row(label: "Reports",                        icon: "chart.bar.doc.horizontal", to: "307")  // .catalyst
        }
    }

    // H5/H6 · Settings & Support
    private var settingsHub: some View {
        hubCard(id: "settings", icon: "gearshape.fill",
                title: "Settings & Support",
                summary: "App preferences", rowCount: 1) {
            row(label: "App settings",  icon: "gearshape",  to: "311")  // .catalyst
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

    // MARK: - Hub + row primitives (bespoke collapsible cards)

    /// A collapsible hub card: a gradient-icon header with title, one-line
    /// summary and a row-count pill that toggles the row body open/closed on
    /// tap. Collapsed by default (except Account) so the Me tab reads as a
    /// clean stack of hubs rather than a 52-row flat list.
    @ViewBuilder
    private func hubCard<Content: View>(id: String,
                                        icon: String,
                                        title: String,
                                        summary: String,
                                        rowCount: Int,
                                        @ViewBuilder content: () -> Content) -> some View {
        let isOpen = expandedHubId == id
        LifecycleCard {
            Button {
                withAnimation(.easeOut(duration: 0.22)) {
                    expandedHubId = isOpen ? "" : id
                    returnAnchor = "hub-\(id)"
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text(summary)
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    Text("\(rowCount)")
                        .font(.system(size: 10, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(palette.bgCardSoft))
                        .overlay(Capsule().strokeBorder(palette.borderFaint.opacity(0.5)))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                Rectangle()
                    .fill(palette.borderFaint.opacity(0.4))
                    .frame(height: 1)
                    .padding(.vertical, 6)
                VStack(spacing: 6) { content() }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .id("hub-\(id)")
    }

    private func row(label: String, icon: String, to screenId: String) -> some View {
        Button(action: {
            returnAnchor = "row-\(screenId)"
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
        .id("row-\(screenId)")
    }

    private func swap(to screenId: String) {
        NotificationCenter.default.post(
            name: .eusoCarrierNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }

    private func restorePosition(using proxy: ScrollViewProxy) {
        eusoRestoreScrollPosition(
            using: proxy,
            anchor: returnAnchor,
            fallback: "hub-\(expandedHubId.isEmpty ? "account" : expandedHubId)"
        )
    }
}

#Preview("350 · Carrier Me · Dark") {
    CarrierMeScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("350 · Carrier Me · Light") {
    CarrierMeScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
