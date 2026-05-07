//
//  350_CarrierMe.swift
//  EusoTrip — Catalyst (Carrier) · Me hub.
//
//  Carrier-side Me surface. Mirror of shipper 320_MeHome / driver
//  067_MeProfile at MVP scope: identity hero + hub-card sections
//  linking to every existing Carrier (.carrier registry) surface +
//  sign-out. Lands the founder ask "catalyst profile has no sign out
//  button" + "make sure all necessary screens outside of active load
//  and load board is accessible".
//
//  Routes via `eusoCarrierNavSwap` (CarrierNavController). The "me"
//  bottom-nav slot now points here (id "350"); previously pointed to
//  "300" (CarrierHome) which is why no Me content surfaced.
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
                // Support section omitted — Help/Settings/Notifications/
                // Legal screens are currently registered .shipper-only and
                // are NOT addressable from CarrierSurface (its pool is
                // .carrier + .catalyst). Will come back when carrier-side
                // analogues ship.
                signOutButton
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
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
            Text(session.user?.companyId ?? session.user?.name ?? "—")
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
            Text("Eusotrans / catalyst command surface")
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
        let name = session.user?.firstName ?? session.user?.name?.split(separator: " ").first.map(String.init) ?? "Catalyst"
        return "\(timeOfDay), \(name)"
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: - Identity hero

    private var identityHero: some View {
        let user = session.user
        let monogram = monogramFor(user?.name ?? "?")
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text(monogram)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(user?.name ?? "Carrier user")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                if let cid = user?.companyId, !cid.isEmpty {
                    Text("companyId · \(cid)")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                }
                if let email = user?.email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onTapGesture { swap(to: "321") }   // 321 Catalyst Driver Profile (own profile view)
    }

    private func monogramFor(_ s: String) -> String {
        let parts = s.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : String(initials.prefix(2))
    }

    // MARK: - Sections

    private var accountSection: some View {
        // Verified destinations (CarrierSurface pool = .carrier + .catalyst):
        //   321 — Catalyst Driver Profile (.catalyst, no .carrier collision)
        //   317 — Carrier Authority (.carrier wins over Catalyst Compliance)
        //
        // Edit-profile is intentionally omitted: 322 in the merged pool
        // resolves to Catalyst Driver Documents, NOT a profile editor.
        // When a carrier-side ProfileEdit screen ships it can be added
        // here with its real registry id.
        section(title: "ACCOUNT", icon: "person.crop.square") {
            row(label: "Profile",            icon: "person",                  to: "321")
            row(label: "Authority · MC/DOT", icon: "shield.lefthalf.filled",  to: "317")
        }
    }

    private var operationsSection: some View {
        section(title: "OPERATIONS", icon: "antenna.radiowaves.left.and.right") {
            row(label: "Catalyst Home · SpectraMatch", icon: "scope",  to: "500")
            row(label: "Active matches",                icon: "bolt",   to: "501")
            row(label: "Dispatch board",                icon: "list.bullet.rectangle", to: "303")
            row(label: "Loads",                          icon: "shippingbox", to: "301")
        }
    }

    private var fleetSection: some View {
        section(title: "FLEET", icon: "person.2") {
            row(label: "Drivers",         icon: "person.2",            to: "304")
            row(label: "Driver list",     icon: "list.bullet",         to: "319")
            row(label: "Vehicles",        icon: "truck.box",           to: "320")
            row(label: "ELD · Hours of Service", icon: "clock.badge",  to: "318")
            row(label: "Maintenance",     icon: "wrench.adjustable",   to: "315")
            row(label: "Fuel card",       icon: "fuelpump",            to: "314")
        }
    }

    private var financialsSection: some View {
        section(title: "FINANCIALS", icon: "dollarsign.circle") {
            row(label: "Earnings",         icon: "chart.line.uptrend.xyaxis", to: "312")
            row(label: "Settlements",      icon: "doc.text",                  to: "313")
            row(label: "My bids",          icon: "hand.tap",                  to: "308")
            row(label: "Awarded loads",    icon: "checkmark.seal",            to: "309")
            row(label: "Marketplace",      icon: "storefront",                to: "306")
        }
    }

    private var complianceSection: some View {
        // Verified destinations:
        //   316 — Carrier Compliance Dash (.carrier)
        //   326 — Catalyst Driver Compliance (.catalyst, no .carrier collision)
        //   322 — Catalyst Driver Documents (.catalyst, no .carrier collision)
        //
        // "Driver scorecard" + "Catalyst compliance" are intentionally
        // omitted — the .carrier registrations for 320 + 317 win the
        // pool ordering, so those ids resolve to Vehicles List +
        // Authority instead of the catalyst variants. They'll come
        // back when carrier-specific scorecard / compliance ids are
        // assigned.
        section(title: "COMPLIANCE", icon: "checkmark.shield") {
            row(label: "Compliance dash",   icon: "shield.checkered",                   to: "316")
            row(label: "Driver compliance", icon: "person.badge.shield.checkmark",      to: "326")
            row(label: "Driver documents",  icon: "doc.on.doc",                         to: "322")
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

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(title: String,
                                        icon: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(title)
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textPrimary)
            }
            VStack(spacing: 1) {
                content()
            }
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func row(label: String, icon: String, to screenId: String) -> some View {
        Button(action: { swap(to: screenId) }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 22)
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 13)
            .background(palette.bgCard)
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
