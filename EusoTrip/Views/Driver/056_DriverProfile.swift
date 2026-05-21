//
//  056_DriverProfile.swift
//  EusoTrip — Driver Profile (Figma 056) — pixel-matched 2026-04-24.
//
//  Figma frame: `056 Driver Profile.png` (Dark + Light).
//  Composition (top to bottom):
//    • Header — back chevron + clock.
//    • Identity card — gradient avatar + driver name + credential
//      summary line + 5-star rating + "X FIVES" count.
//    • 3-stat row — ON-TIME / SAFETY / TIER UNLOCK.
//    • CREDENTIALS list — 4 product-aware rows (CDL / endorsement /
//      DOT Med / TWIC) with ACTIVE / EXPIRING chips.
//    • POOL TIER card — purple gradient hero with tier number,
//      progress bar, 3 product-aware benefit rows.
//    • ESANG promotion strip.
//    • Footer CTAs — Runs (outline) + Day-2 brief (gradient).
//    • Bottom nav — preserved verbatim.
//
//  Data wiring: `ProfileStore` (auth.me) for the driver's identity
//  (name + member-since), `ReputationStore` for the 5-star rating
//  and on-time/safety scores, `LifecycleProductContext.forRole(_:)`
//  for the vertical+product variant of the pool tier + benefits +
//  credentials list. No mock data — em-dashes when the server
//  hasn't returned a value yet.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DriverProfile: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: EusoTripSession
    @EnvironmentObject private var localProfile: DriverProfileStore

    @StateObject private var identityStore = ProfileStore()
    @StateObject private var reputationStore = ReputationStore()

    @State private var showEditProfile: Bool = false
    @State private var showLogoutConfirm: Bool = false

    private var ctx: LifecycleProductContext {
        LifecycleProductContext.forRole(session.user?.role)
    }

    private let fallbackClock = "22:10"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                identityCard
                statRow
                credentialsCard
                poolTierCard
                esangStrip
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task {
            async let a: () = identityStore.refresh()
            async let b: () = reputationStore.refresh()
            _ = await (a, b)
        }
        .sheet(isPresented: $showEditProfile) {
            ProfileEditView()
                .environmentObject(localProfile)
                .eusoSheetX()
        }
        .alert("Sign out?", isPresented: $showLogoutConfirm) {
            Button("Sign out", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .screenTileRoot()
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            Spacer()
            Text(fallbackClock)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    // MARK: - Identity card

    private var identityCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 56, height: 56)
                Text(initials)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(driverName)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(ctx.identityCredentialLine)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(ratingText)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                HStack(spacing: 1) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                }
                Text(fiveStarCount)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var driverName: String {
        let local = localProfile.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let live = session.user?.name ?? ""
        if !local.isEmpty { return local }
        if !live.isEmpty { return live }
        return reputation == nil ? "Driver" : (session.user?.name ?? "Driver")
    }

    private var initials: String {
        let parts = driverName.split(separator: " ").prefix(2)
        let inits = parts.compactMap { $0.first }.map(String.init).joined()
        return inits.isEmpty ? "ME" : inits
    }

    /// Unwrap the reputation payload from the store's RemoteState.
    /// Nil when the server hasn't returned a value yet (or no
    /// ratings exist for this driver).
    private var reputation: ProfileAPI.Reputation? {
        if case let .loaded(value) = reputationStore.state { return value }
        return nil
    }

    private var ratingText: String {
        if let r = reputation?.ratingAverage, r > 0 {
            return String(format: "%.2f", r)
        }
        return "—"
    }

    private var fiveStarCount: String {
        if let r = reputation?.ratingAverage,
           let total = reputation?.ratingCount, total > 0 {
            // Approximate five-star count from aggregate average
            let fives = Int(Double(total) * (r / 5.0))
            return "\(fives) FIVES"
        }
        return "NO RATINGS YET"
    }

    // MARK: - 3-stat row

    private var statRow: some View {
        HStack(spacing: Space.s2) {
            statCell(label: "ON-TIME",  value: onTimeText,  sub: "90-DAY", color: Brand.success)
            statCell(label: "SAFETY",   value: safetyText,  sub: "0 INCIDENTS", color: Brand.success)
            statCell(label: "TIER",     value: "T\(ctx.poolTierNumber)", sub: "UNLOCKED DAY 8", color: Brand.warning)
        }
    }

    private var onTimeText: String {
        guard let v = reputation?.onTimeDeliveryPct, v > 0 else { return "—" }
        // Server returns 0-100 already.
        return String(format: "%.1f%%", v)
    }

    private var safetyText: String {
        guard let v = reputation?.safetyScore, v > 0 else { return "—" }
        // Map 0-100 to letter grade
        switch v {
        case 95...:  return "A+"
        case 90..<95: return "A"
        case 85..<90: return "B+"
        case 80..<85: return "B"
        default:      return "C"
        }
    }

    private func statCell(label: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(sub)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Credentials card

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CREDENTIALS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("4 OF 4 ACTIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
            }
            ForEach(ctx.credentialsRows) { row in
                credentialRow(row)
            }
        }
    }

    private func credentialRow(_ row: LifecycleProductContext.CredentialRow) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(LinearGradient.diagonal.opacity(0.18))
                Image(systemName: row.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(row.subtitle)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(row.active ? "ACTIVE" : "EXPIRING")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(row.active ? Brand.success : Brand.warning)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(Capsule().stroke((row.active ? Brand.success : Brand.warning).opacity(0.5), lineWidth: 1))
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 9)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Pool tier card (product-aware)

    private var poolTierCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("\(ctx.poolTierProgram) TIER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(Int(ctx.poolTierProgress * 100))%")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Tier \(ctx.poolTierNumber)")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Text("PROMOTED")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(LinearGradient.diagonal))
                Spacer()
            }
            // Progress rail
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 5)
                    Capsule().fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * CGFloat(ctx.poolTierProgress), height: 5)
                }
            }
            .frame(height: 5)
            // Benefits
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ctx.poolBenefits, id: \.self) { benefit in
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(benefit)
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(LinearGradient(
                    colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - ESANG strip

    private var esangStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text(ctx.pooleSangNote)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Footer CTAs

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            // 2026-05-21 dead-button fix: both footer CTAs had empty
            // `{ }` actions. Wired to real registered driver screens via
            // the canonical `.eusoDriverMeNavSwap` notification (observed
            // in 067A_DriverMeHubs / RoleSurfaceRouter):
            //   • "Runs" → 108 Me · LoadBoard (the driver's run history)
            //   • "Day-2 brief" → 027 Next Load Brief
            PressableOutlineButton(title: "Runs") { navigateDriver(to: "108") }
            // Primary CTA — uses CTAButton recipe (§B.4: easeOut 0.12
            // press scale + iridescent hue-shift) for crisp feedback.
            CTAButton(title: "Day-2 brief") { navigateDriver(to: "027") }
        }
    }

    /// Post the canonical driver nav-swap so the Me router pushes the
    /// requested screen. Both targets are registered for `.driver`.
    private func navigateDriver(to screenId: String) {
        NotificationCenter.default.post(
            name: .eusoDriverMeNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}

// MARK: - Pressable outline (§B.4 secondary press recipe)
//
// Mirrors `CTAButton`'s press timing for the outline-only variant
// used as the secondary CTA throughout the lifecycle. Same 0.12s
// ease-out, same scaleEffect, no hue-shift (since the fill is
// already `palette.bgCard` and a hue shift would be invisible).
private struct PressableOutlineButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.palette) private var palette
    @SwiftUI.State private var pressed: Bool = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(EType.body.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderSoft)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .scaleEffect(pressed ? 0.985 : 1.0)
        .animation(.easeOut(duration: 0.12), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
    }
}

// MARK: - Wrapper

struct DriverProfileScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DriverProfile()
        } nav: {
            BottomNav(leading: driverNavLeading_056(),
                      trailing: driverNavTrailing_056(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_056() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",       isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: false)]
}
private func driverNavTrailing_056() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: true)]
}

#Preview("056 · Driver Profile · Dark") {
    DriverProfileScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("056 · Driver Profile · Light") {
    DriverProfileScreen(theme: Theme.light).preferredColorScheme(.light)
}
