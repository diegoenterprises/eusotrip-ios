//
//  804_AdminMe.swift
//  EusoTrip — Admin · Me hub.
//
//  Visual parity with 350_CarrierMe (catalyst): 56pt gradient-avatar
//  identity hero, LifecycleCard sections, 40pt gradient icon circles
//  on each row, gradient sign-out CTA.
//
//  Admin nav route map binds the "me" bottom-nav slot to "804".
//  Pure nav hub — destination ids audited against the Admin surface
//  registrations (control tower 801, tenants 802). No data/API calls.
//

import SwiftUI

struct AdminMeScreen: View {
    let theme: Theme.Palette

    @EnvironmentObject private var session: EusoTripSession
    @Environment(\.palette) private var palette
    @State private var showSignOutConfirm: Bool = false
    @SceneStorage("admin.me.expandedCategory") private var expandedCategory: String = ""
    @SceneStorage("admin.me.returnAnchor") private var returnAnchor: String = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    topBar
                    titleBlock
                    iridescentHairline
                    identityHero
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
            Text("You'll need to sign back in to access the control tower and tenants.")
        }
    }

    // MARK: - TopBar / Title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                EusoTripBrandMark(size: 12)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ADMIN · ME")
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
            Text("Platform admin surface")
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
        let name = session.user?.firstName ?? "Admin"
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
        let displayName = user?.name ?? "Admin user"
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

    private var operationsSection: some View {
        sectionCard(key: "operations", title: "OPERATIONS", icon: "square.grid.2x2") {
            row(label: "Control tower", icon: "square.grid.3x3", to: "801")
            row(label: "Tenants",       icon: "building.2",      to: "802")
            row(label: "Vessel writes", icon: "ferry.fill", to: "AdminVesselWrites")
        }
    }

    private var supportSection: some View {
        sectionCard(key: "support", title: "SUPPORT", icon: "lifepreserver") {
            eSangRow
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

            if expandedCategory == key {
                Divider().overlay(palette.borderFaint)
                VStack(spacing: 6) {
                    content()
                }
            }
        }
        .id(categoryAnchor(key))
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

    // Help · ESANG row — same row() visual grammar, but taps post the
    // eSang notification rather than swapping the nav surface.
    private var eSangRow: some View {
        Button(action: {
            returnAnchor = rowAnchor("esang")
            NotificationCenter.default.post(
                name: .eusoAdmineSangTapped,
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
        "admin-me-category-\(key)"
    }

    private func rowAnchor(_ key: String) -> String {
        "admin-me-row-\(key)"
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
            name: .eusoAdminNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}

#Preview("804 · Admin · Me · Dark") {
    AdminMeScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("804 · Admin · Me · Light") {
    AdminMeScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
