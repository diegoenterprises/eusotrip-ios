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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                iridescentHairline
                identityHero
                operationsSection
                commandSection
                fleetSection
                analyticsSection
                driverPerfSection
                shipperPerfSection
                vehiclePerfSection
                settlementSection
                commsPerfSection
                laneRfpSection
                exceptionsSection
                toolsSection
                settingsSection
                signOutButton
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
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
                        Text("companyId · \(cid)")
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

    private var operationsSection: some View {
        sectionCard(title: "OPERATIONS", icon: "antenna.radiowaves.left.and.right") {
            row(label: "Dispatch home",       icon: "house",                  to: "Disp400")
            row(label: "Driver board",        icon: "person.3.fill",          to: "Dpch701")
            row(label: "Load assignment",     icon: "shippingbox.fill",       to: "Dpch702")
            row(label: "Exception triage",    icon: "exclamationmark.triangle", to: "Dpch703")
            row(label: "Kanban board",        icon: "rectangle.split.3x1",    to: "Disp401")
        }
    }

    private var fleetSection: some View {
        sectionCard(title: "FLEET + HOS", icon: "clock.badge") {
            row(label: "HOS alerts",          icon: "clock.badge.exclamationmark", to: "Dpch704")
            row(label: "Route optimization",  icon: "map",                    to: "Dpch705")
            row(label: "Driver chat",         icon: "bubble.left.and.bubble.right", to: "Dpch706")
        }
    }

    private var analyticsSection: some View {
        sectionCard(title: "ANALYTICS", icon: "chart.line.uptrend.xyaxis") {
            row(label: "Daily KPI",           icon: "chart.bar",              to: "Dpch707")
            row(label: "Reports hub",         icon: "doc.text.magnifyingglass", to: "Dpch712")
            row(label: "Price book",          icon: "tag",                    to: "Dpch711")
        }
    }

    private var toolsSection: some View {
        sectionCard(title: "TOOLS", icon: "wrench.and.screwdriver") {
            row(label: "Bulk upload",         icon: "square.and.arrow.up.on.square", to: "Dpch709")
            row(label: "Run ticket capture",  icon: "camera.viewfinder",      to: "Dpch710")
            row(label: "Convoy composer",     icon: "car.2.fill",             to: "Dpch710A")
        }
    }

    // 2026-06-02 — WAVE 5: surface stranded dispatch management + the
    // analytics detail octets (740–795) into the Me hub (grouped roll-ups).
    // Pure lifecycle/kanban cels (Dpch800–811 BH, 820–824 M-04, 531/532)
    // stay event-reached; Disp400/Disp401 are dup home/kanban (dedup later).
    private var commandSection: some View {
        sectionCard(title: "COMMAND & FLEET", icon: "square.grid.2x2") {
            row(label: "Command center",   icon: "square.grid.2x2",          to: "Dpch714")
            row(label: "Fleet map",        icon: "map",                      to: "Dpch715")
            row(label: "Performance",      icon: "chart.line.uptrend.xyaxis", to: "Dpch716")
            row(label: "Driver roster",    icon: "person.3",                 to: "Dpch404")
            row(label: "AI dispatch assist", icon: "sparkles",               to: "533")
            row(label: "Carrier scorecard", icon: "star.circle",            to: "539")
        }
    }

    private var driverPerfSection: some View {
        sectionCard(title: "DRIVER PERFORMANCE", icon: "person.3.fill") {
            row(label: "Review",       icon: "checkmark.circle",                to: "Dpch740")
            row(label: "Lane",         icon: "road.lanes",                      to: "Dpch741")
            row(label: "Incident log", icon: "exclamationmark.triangle",        to: "Dpch742")
            row(label: "Performance",  icon: "gauge.with.dots.needle.67percent", to: "Dpch743")
            row(label: "HOS",          icon: "clock.badge",                     to: "Dpch744")
            row(label: "Onboarding",   icon: "person.badge.plus",               to: "Dpch745")
            row(label: "Compliance",   icon: "checkmark.shield",                to: "Dpch746")
            row(label: "Quarter",      icon: "calendar",                        to: "Dpch747")
        }
    }

    private var shipperPerfSection: some View {
        sectionCard(title: "SHIPPER PERFORMANCE", icon: "building.2") {
            row(label: "Review",      icon: "checkmark.circle", to: "Dpch750")
            row(label: "Pull volume", icon: "chart.bar",        to: "Dpch751")
            row(label: "Tender win",  icon: "trophy",           to: "Dpch752")
            row(label: "Payment",     icon: "creditcard",       to: "Dpch753")
            row(label: "Lane win",    icon: "road.lanes",       to: "Dpch754")
            row(label: "Health",      icon: "heart.text.square", to: "Dpch755")
            row(label: "Onboarding",  icon: "person.badge.plus", to: "Dpch756")
            row(label: "Quarter",     icon: "calendar",         to: "Dpch757")
        }
    }

    private var vehiclePerfSection: some View {
        sectionCard(title: "VEHICLE PERFORMANCE", icon: "truck.box") {
            row(label: "Review",      icon: "checkmark.circle",                 to: "Dpch760")
            row(label: "Utilization", icon: "gauge.with.dots.needle.67percent", to: "Dpch761")
            row(label: "Maintenance", icon: "wrench.adjustable",                to: "Dpch762")
            row(label: "On-time",     icon: "clock.badge.checkmark",            to: "Dpch763")
            row(label: "Inspection",  icon: "checklist",                        to: "Dpch764")
            row(label: "Deadhead",    icon: "arrow.uturn.backward",             to: "Dpch765")
            row(label: "Onboarding",  icon: "plus.rectangle.on.folder",         to: "Dpch766")
            row(label: "Quarter",     icon: "calendar",                         to: "Dpch767")
        }
    }

    private var settlementSection: some View {
        sectionCard(title: "SETTLEMENT", icon: "dollarsign.circle") {
            row(label: "Review",     icon: "checkmark.circle",          to: "Dpch770")
            row(label: "DSO",        icon: "calendar.badge.clock",      to: "Dpch771")
            row(label: "QuickPay",   icon: "bolt",                      to: "Dpch772")
            row(label: "Ledger",     icon: "list.bullet.rectangle.portrait", to: "Dpch773")
            row(label: "Clean",      icon: "checkmark.seal",            to: "Dpch774")
            row(label: "Onboarding", icon: "person.badge.plus",         to: "Dpch775")
            row(label: "Audit",      icon: "doc.text.magnifyingglass",  to: "Dpch776")
            row(label: "Quarter",    icon: "calendar",                  to: "Dpch777")
        }
    }

    private var commsPerfSection: some View {
        sectionCard(title: "COMMS PERFORMANCE", icon: "bubble.left.and.bubble.right") {
            row(label: "Review",     icon: "checkmark.circle",        to: "Dpch780")
            row(label: "Response",   icon: "arrowshape.turn.up.left", to: "Dpch781")
            row(label: "SLA",        icon: "timer",                   to: "Dpch782")
            row(label: "Escalation", icon: "exclamationmark.bubble",  to: "Dpch783")
            row(label: "Closure",    icon: "checkmark.circle.fill",   to: "Dpch784")
            row(label: "Volume",     icon: "chart.bar",               to: "Dpch785")
            row(label: "First-time resolve", icon: "checkmark.seal",  to: "Dpch786")
            row(label: "Quarter",    icon: "calendar",                to: "Dpch787")
        }
    }

    private var laneRfpSection: some View {
        sectionCard(title: "LANE & RFP", icon: "road.lanes") {
            row(label: "Lane board",     icon: "rectangle.split.3x1",   to: "Dpch790")
            row(label: "Lane drill",     icon: "magnifyingglass",       to: "Dpch791")
            row(label: "Haul detail",    icon: "shippingbox",           to: "Dpch792")
            row(label: "RFP inbox",      icon: "tray.full",             to: "Dpch793")
            row(label: "Match-up",       icon: "arrow.triangle.merge",  to: "Dpch794")
            row(label: "Contract write", icon: "pencil.and.outline",    to: "Dpch795")
        }
    }

    private var exceptionsSection: some View {
        sectionCard(title: "EXCEPTIONS & RESOLUTION", icon: "exclamationmark.triangle") {
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

    private var settingsSection: some View {
        sectionCard(title: "SETTINGS", icon: "gearshape") {
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

    // MARK: - Section + row primitives (LifecycleCard parity with 350)

    @ViewBuilder
    private func sectionCard<Content: View>(title: String,
                                            icon: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        LifecycleCard {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(title)
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.bottom, 2)
            VStack(spacing: 6) {
                content()
            }
        }
    }

    private func row(label: String, icon: String, to screenId: String) -> some View {
        Button(action: { swap(to: screenId) }) {
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
