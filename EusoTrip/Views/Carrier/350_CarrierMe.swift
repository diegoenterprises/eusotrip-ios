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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                iridescentHairline
                identityHero
                accountSection
                operationsSection
                fleetSection
                financialsSection
                complianceSection
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
            Text("You'll need to sign back in to dispatch loads, view drivers, and access ELD.")
        }
    }

    // MARK: - TopBar / Title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · ME")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(session.user?.companyId.map { "companyId · \($0)" } ?? "—")
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

    // MARK: - Sections (LifecycleCard chrome — visual parity with 320)
    //
    // CarrierSurface pool = .carrier + .catalyst, .carrier wins on
    // collisions. Each id below was verified against ContentView.swift
    // registrations on 2026-05-07. Shipper-only ids and fictional ids
    // removed.

    private var accountSection: some View {
        sectionCard(title: "ACCOUNT", icon: "person.crop.square") {
            row(label: "Profile",            icon: "person",                 to: "321")  // .catalyst
            row(label: "Authority · MC/DOT", icon: "shield.lefthalf.filled", to: "317")  // .carrier wins
        }
    }

    private var operationsSection: some View {
        sectionCard(title: "OPERATIONS", icon: "antenna.radiowaves.left.and.right") {
            row(label: "Catalyst Home · SpectraMatch", icon: "scope",           to: "500")  // .catalyst
            row(label: "Active matches",                icon: "bolt",            to: "501")  // .catalyst
            row(label: "Dispatch board",                icon: "list.bullet.rectangle", to: "303")  // .carrier
            row(label: "Loads",                          icon: "shippingbox",    to: "301")  // .carrier
        }
    }

    private var fleetSection: some View {
        sectionCard(title: "FLEET", icon: "person.2") {
            row(label: "Drivers",                icon: "person.2",            to: "304")  // .carrier
            row(label: "Driver list",            icon: "list.bullet",         to: "319")  // .carrier wins
            row(label: "Vehicles",               icon: "truck.box",           to: "320")  // .carrier wins
            row(label: "ELD · Hours of Service", icon: "clock.badge",         to: "318")  // .carrier
            row(label: "Maintenance",            icon: "wrench.adjustable",   to: "315")  // .carrier
            row(label: "Fuel card",              icon: "fuelpump",            to: "314")  // .carrier
        }
    }

    private var financialsSection: some View {
        sectionCard(title: "FINANCIALS", icon: "dollarsign.circle") {
            row(label: "Earnings",      icon: "chart.line.uptrend.xyaxis", to: "312")  // .carrier
            row(label: "Settlements",   icon: "doc.text",                  to: "313")  // .carrier wins
            row(label: "My bids",       icon: "hand.tap",                  to: "308")  // .carrier
            row(label: "Awarded loads", icon: "checkmark.seal",            to: "309")  // .carrier
            row(label: "Marketplace",   icon: "storefront",                to: "306")  // .carrier
        }
    }

    private var complianceSection: some View {
        sectionCard(title: "COMPLIANCE", icon: "checkmark.shield") {
            row(label: "Compliance dash",   icon: "shield.checkered",                   to: "316")  // .carrier
            row(label: "Driver compliance", icon: "person.badge.shield.checkmark",      to: "326")  // .catalyst
            row(label: "Driver documents",  icon: "doc.on.doc",                         to: "322")  // .catalyst
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
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, Space.s3)
    }

    // MARK: - Section + row primitives (LifecycleCard parity)

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
            name: .eusoCarrierNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
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
