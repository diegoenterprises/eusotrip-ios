//
//  903_ComplianceMe.swift
//  EusoTrip — Compliance · Me hub.
//
//  Visual parity with 350_CarrierMe (Catalyst) + 320_MeHome (shipper):
//  56pt gradient-avatar identity hero, LifecycleCard sections,
//  40pt gradient icon circles on each row, gradient sign-out CTA.
//
//  Pure nav hub — no load()/EusoTripAPI. Compliance nav route map binds
//  the "me" bottom-nav slot to "903". Destination ids audited against
//  ContentView.swift registrations. Rows post .eusoComplianceNavSwap;
//  the SUPPORT row posts .eusoComplianceeSangTapped (ESANG).
//

import SwiftUI

struct ComplianceMeScreen: View {
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
                complianceSection
                toolsSection
                supportSection
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
            Text("You'll need to sign back in to review expiring docs and violations.")
        }
    }

    // MARK: - TopBar / Title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("COMPLIANCE · ME")
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
            Text("Compliance command surface")
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
        let name = session.user?.firstName ?? "Compliance"
        return "\(timeOfDay), \(name)"
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
            .padding(.horizontal, -14)
    }

    // MARK: - Identity hero (56pt avatar + parity with 350 hero)

    private var identityHero: some View {
        let user = session.user
        let displayName = user?.name ?? "Compliance user"
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

    private var complianceSection: some View {
        sectionCard(title: "COMPLIANCE", icon: "checkmark.shield") {
            row(label: "Expiring docs", icon: "calendar.badge.exclamationmark", to: "901")
            row(label: "Violations",    icon: "exclamationmark.triangle",       to: "902")
        }
    }

    private var toolsSection: some View {
        sectionCard(title: "TOOLS", icon: "wrench.and.screwdriver") {
            row(label: "Segregation agent", icon: "shippingbox.and.arrow.backward", to: "904")
        }
    }

    private var supportSection: some View {
        sectionCard(title: "SUPPORT", icon: "lifepreserver") {
            eSangRow()
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

    // ESANG support row — same row() grammar (40pt gradient icon circle,
    // label, chevron) but its action posts the eSang notification.
    private func eSangRow() -> some View {
        Button(action: { tapESang() }) {
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
    }

    private func swap(to screenId: String) {
        NotificationCenter.default.post(
            name: .eusoComplianceNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }

    private func tapESang() {
        NotificationCenter.default.post(
            name: .eusoComplianceeSangTapped,
            object: nil
        )
    }
}

#Preview("903 · Compliance · Me · Dark") {
    ComplianceMeScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("903 · Compliance · Me · Light") {
    ComplianceMeScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
