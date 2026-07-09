//
//  Dpch713_DispatchMe.swift
//  EusoTrip — Dispatch · Me hub.
//
//  2026-05-21 dead-button fix: the Dispatch bottom-nav "Me" slot mapped
//  to "Dpch700" (Home), so tapping Me silently bounced the dispatcher
//  back to the screen they were already on — a functional dead-end. This
//  is the dedicated Dispatch Me hub it should have pointed to all along.
//
//  Visual parity with 350_CarrierMe / 320_MeHome (shipper) / 067A
//  (driver): 56pt gradient-avatar identity hero, LifecycleCard sections,
//  36pt gradient icon circles per row, gradient sign-out CTA.
//
//  Every destination id below is a REAL registered dispatch screen
//  (Dpch700–Dpch712 in ContentView.swift). Routing goes through
//  `.eusoDispatchNavSwap`, which RoleSurfaceRouter observes and gates
//  with `RoleAccess.canRender(role: .dispatch, screenId:)` — all ids
//  here pass that gate, so there are zero dead ends.
//

import SwiftUI

struct DispatchMeScreen: View {
    let theme: Theme.Palette

    @EnvironmentObject private var session: EusoTripSession
    @Environment(\.palette) private var palette
    @State private var showSignOutConfirm: Bool = false

    /// Which hub cards are expanded. Consolidation (fix pack L15-11): the Me tab
    /// rendered 8 always-open sections = ~41 rows in one scroll (with "Comms
    /// hub" duplicated across two sections). Rebuilt into 7 bespoke collapsible
    /// hubs; the Command & Fleet and Fleet+HOS sections merged, the duplicate
    /// Comms hub removed. Operations starts expanded; the rest collapse.
    @State private var expandedHubs: Set<String> = ["operations"]

    var body: some View {
        Shell(theme: theme) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    topBar
                    titleBlock
                    iridescentHairline
                    identityHero
                    EusoCardIssuePanel(
                        title: "EusoCard",
                        subtitle: "Dispatch spend card for fleet exceptions and accessorials"
                    )
                    operationsHub
                    commandFleetHub
                    liveWorkflowsHub
                    exceptionsHub
                    analyticsHub
                    toolsHub
                    settingsHub
                    signOutButton
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                    NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill", isCurrent: false)
                ],
                trailing: [
                    NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                    NavSlot(label: "Me", systemImage: "person.fill", isCurrent: true)
                ],
                orbState: .idle
            )
        }
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Sign out", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign back in to assign loads, triage exceptions and view your driver board.")
        }
    }

    // MARK: - TopBar / Title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · ME")
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
            Text("Dispatch command surface")
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
        let name = session.user?.firstName ?? "Dispatcher"
        return "\(timeOfDay), \(name)"
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
            .padding(.horizontal, -14)
    }

    // MARK: - Identity hero (56pt avatar — parity with 350 / 320 heroes)

    private var identityHero: some View {
        let user = session.user
        let displayName = user?.name ?? "Dispatch user"
        let monogram = monogramFor(displayName)
        return LifecycleCard(accentGradient: true) {
            HStack(alignment: .center, spacing: 10) {
                Text(monogram)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(LinearGradient.diagonal)
                    .clipShape(Circle())
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

    private func monogramFor(_ s: String) -> String {
        let parts = s.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : String(initials.prefix(2))
    }

    // MARK: - Sections — every id is a registered .dispatch screen
    //         (Dpch700–Dpch712), verified against ContentView.swift.

    private var operationsHub: some View {
        hubCard(id: "operations", icon: "antenna.radiowaves.left.and.right",
                title: "Operations",
                summary: "Home · Driver board · Assignment · Triage · Kanban", rowCount: 5) {
            row(label: "Dispatch home",       icon: "house",                  to: "Disp400")
            row(label: "Driver board",        icon: "person.3.fill",          to: "Dpch701")
            row(label: "Load assignment",     icon: "shippingbox.fill",       to: "Dpch702")
            row(label: "Exception triage",    icon: "exclamationmark.triangle", to: "Dpch703")
            row(label: "Kanban board",        icon: "rectangle.split.3x1",    to: "Disp401")
        }
    }

    // COMMAND & FLEET merged with the former FLEET + HOS section (both are
    // fleet-command surfaces). The 740/750/760/770/780 octet variants stay
    // registered for event-context deep links but are not top-level rows here.
    private var commandFleetHub: some View {
        hubCard(id: "commandFleet", icon: "square.grid.2x2",
                title: "Command & Fleet",
                summary: "Command center · Fleet map · HOS · Roster · Scorecard", rowCount: 9) {
            row(label: "Command center", detail: "Active loads, exceptions and assignment pressure", icon: "square.grid.2x2", to: "Dpch714")
            row(label: "Fleet map", detail: "Live vehicle and route visibility", icon: "map", to: "Dpch715")
            row(label: "Performance", detail: "Dispatcher KPI and fleet operating metrics", icon: "chart.line.uptrend.xyaxis", to: "Dpch716")
            row(label: "Driver roster", detail: "Roster identity, availability and compliance entry", icon: "person.3", to: "Dpch404")
            row(label: "AI dispatch assist", detail: "Contextual dispatch actions", icon: "sparkles", to: "533")
            row(label: "Carrier scorecard", detail: "Carrier scoring and company performance", icon: "star.circle", to: "539")
            row(label: "HOS alerts",          icon: "clock.badge.exclamationmark", to: "Dpch704")
            row(label: "Route optimization",  icon: "map",                    to: "Dpch705")
            row(label: "Driver chat",         icon: "bubble.left.and.bubble.right", to: "Dpch706")
        }
    }

    private var liveWorkflowsHub: some View {
        hubCard(id: "liveWorkflows", icon: "point.3.connected.trianglepath.dotted",
                title: "Live Workflows",
                summary: "Driver / shipper / vehicle / settlement reviews · RFP", rowCount: 5) {
            row(label: "Driver performance", detail: "Performance metrics + DQ/HOS context", icon: "gauge.with.dots.needle.67percent", to: "Dpch743")
            row(label: "Shipper scorecard", detail: "Shipper scoring + account identity", icon: "building.2", to: "Dpch750")
            row(label: "Vehicle review", detail: "Fleet stats + vehicle roster", icon: "truck.box", to: "Dpch760")
            row(label: "Settlement review", detail: "Settlement stats and payroll", icon: "dollarsign.circle", to: "Dpch770")
            // "Comms hub" (Dpch721) lives in Exceptions & Resolution — removed
            // the duplicate that used to sit here.
            row(label: "Lane and RFP board", detail: "Lane board, RFP inbox and contract actions", icon: "road.lanes", to: "Dpch790")
        }
    }

    private var exceptionsHub: some View {
        hubCard(id: "exceptions", icon: "exclamationmark.triangle",
                title: "Exceptions & Resolution",
                summary: "Tenders · Comms · Mismatches · Reroutes · Overrides", rowCount: 14) {
            row(label: "Tender queue",        icon: "tray.full",                to: "Dpch720")
            row(label: "Comms hub",           icon: "bubble.left.and.bubble.right", to: "Dpch721")
            row(label: "BOL mismatch",        icon: "doc.on.doc",               to: "Dpch722")
            row(label: "HOS reassignment",    icon: "clock.arrow.2.circlepath", to: "Dpch724")
            row(label: "Cancel load",         icon: "xmark.circle",             to: "Dpch725")
            row(label: "Late pickup",         icon: "clock.badge.exclamationmark", to: "Dpch726")
            row(label: "Dock mismatch",       icon: "rectangle.badge.xmark",    to: "Dpch727")
            row(label: "Yard slots",          icon: "square.grid.3x3",          to: "Dpch730")
            row(label: "Reassignment sheet",  icon: "arrow.triangle.swap",      to: "Dpch731")
            row(label: "Quick-tender",        icon: "bolt",                     to: "Dpch732")
            row(label: "Escort republish",    icon: "shield.lefthalf.filled",   to: "Dpch733")
            row(label: "Weather reroute",     icon: "cloud.sun",                to: "Dpch735")
            row(label: "Reload offer",        icon: "arrow.triangle.2.circlepath", to: "Dpch736")
            row(label: "Fuel-policy override", icon: "fuelpump",                to: "Dpch737")
        }
    }

    private var analyticsHub: some View {
        hubCard(id: "analytics", icon: "chart.line.uptrend.xyaxis",
                title: "Analytics",
                summary: "Daily KPI · Reports · Price book", rowCount: 3) {
            row(label: "Daily KPI",           icon: "chart.bar",              to: "Dpch707")
            row(label: "Reports hub",         icon: "doc.text.magnifyingglass", to: "Dpch712")
            row(label: "Price book",          icon: "tag",                    to: "Dpch711")
        }
    }

    private var toolsHub: some View {
        hubCard(id: "tools", icon: "wrench.and.screwdriver",
                title: "Tools",
                summary: "Bulk upload · Run ticket · Convoy composer", rowCount: 3) {
            row(label: "Bulk upload",         icon: "square.and.arrow.up.on.square", to: "Dpch709")
            row(label: "Run ticket capture",  icon: "camera.viewfinder",      to: "Dpch710")
            row(label: "Convoy composer",     icon: "car.2.fill",             to: "Dpch710A")
        }
    }

    private var settingsHub: some View {
        hubCard(id: "settings", icon: "gearshape.fill",
                title: "Settings & Support",
                summary: "Dispatch preferences", rowCount: 1) {
            row(label: "Dispatch settings", icon: "gearshape", to: "Dpch734")
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

    // MARK: - Hub + row primitives (bespoke collapsible cards, parity with 350)

    /// A collapsible hub card: gradient-icon header with title, one-line summary
    /// and a row-count pill that toggles the body open/closed on tap. Collapsed
    /// by default (except Operations) so the Me tab reads as a clean stack of
    /// hubs rather than a ~40-row flat list.
    @ViewBuilder
    private func hubCard<Content: View>(id: String,
                                        icon: String,
                                        title: String,
                                        summary: String,
                                        rowCount: Int,
                                        @ViewBuilder content: () -> Content) -> some View {
        let isOpen = expandedHubs.contains(id)
        LifecycleCard {
            Button {
                withAnimation(.easeOut(duration: 0.22)) {
                    if isOpen { expandedHubs.remove(id) } else { expandedHubs.insert(id) }
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
    }

    private func row(label: String, detail: String? = nil, icon: String, to screenId: String) -> some View {
        Button(action: { swap(to: screenId) }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func swap(to screenId: String) {
        NotificationCenter.default.post(
            name: .eusoDispatchNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}

#Preview("Dpch713 · Dispatch Me · Dark") {
    DispatchMeScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("Dpch713 · Dispatch Me · Light") {
    DispatchMeScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
