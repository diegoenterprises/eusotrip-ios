//
//  023_BackingIn.swift
//  EusoTrip — Lifecycle screen 023 · Backing In.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `023 Backing In.png` (Dark + Light). Fires when the driver is
//  actively backing into the assigned door. Live rear IR canvas,
//  three distance tiles (driver-side / center-rear / blind-side),
//  alignment bar, live-mic / spotter advisory card, Pull up & redo
//  / Set brakes CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct BackingIn: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isConfirming: Bool = false

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma fallback
    private let fallbackDoor          = "12"
    private let fallbackAisle         = "Aisle 2 · night receiving"
    private let fallbackTrailer       = "—"
    private let fallbackCameraStamp   = "00:32:48"
    private let fallbackCameraId      = "cam-R · 1080p"
    private let fallbackDriverSide    = "28\""
    private let fallbackCenterRear    = "3' 1\""
    private let fallbackBlindSide     = "11\""
    private let fallbackAlignmentDeg  = "+3°"
    private let fallbackAlignmentNote = "too sharp"

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                cameraCanvas
                distanceTiles
                alignmentCard
                advisoryCard
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { /* upstream back */ } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("BACKING IN")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· DOOR \(fallbackDoor)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                }
                Text("\(ctx.defaultApproach) · \(fallbackAisle)")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(fallbackTrailer)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button { /* pause live feed */ } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
        }
        .padding(.top, 4)
    }

    // MARK: Camera canvas

    private var cameraCanvas: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color.black)
                .frame(height: 220)

            // IR-grey horizon
            GeometryReader { geo in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#2C2F36"), Color(hex: "#121419")],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(height: geo.size.height * 0.55)
                    .offset(y: 18)
                // Dock outline (stylized)
                Rectangle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.2)
                    .frame(width: geo.size.width * 0.45, height: geo.size.height * 0.32)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.50)
                // Target line
                Rectangle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: geo.size.width * 0.45, height: 3)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.66)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            // Top overlay — LIVE + DOOR 12 + cam id
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(Brand.danger).frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(Brand.danger)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                Text("DOOR \(fallbackDoor)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text("REAR · IR")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s2)

            // Bottom overlay — timestamp + cam id
            VStack {
                Spacer()
                HStack {
                    Text(fallbackCameraStamp)
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text(fallbackCameraId)
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, Space.s3)
                .padding(.bottom, Space.s2)
            }
        }
        .frame(height: 220)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Distance tiles

    private var distanceTiles: some View {
        HStack(spacing: Space.s2) {
            distanceTile(label: "DRIVER-SIDE", value: fallbackDriverSide, sub: "clear", color: Brand.success)
            distanceTile(label: "CENTER REAR", value: fallbackCenterRear, sub: "to dock rubber", color: palette.textPrimary)
            distanceTile(label: "BLIND-SIDE",  value: fallbackBlindSide,  sub: "narrow", color: Brand.warning)
        }
    }

    private func distanceTile(label: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(sub)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
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

    // MARK: Alignment card

    private var alignmentCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ALIGNMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(fallbackAlignmentDeg) \(fallbackAlignmentNote)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Brand.warning)
            }
            GeometryReader { geo in
                ZStack {
                    Capsule()
                        .fill(palette.bgCardSoft)
                        .frame(height: 6)
                    // Center tick
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(width: 1, height: 14)
                        .position(x: geo.size.width / 2, y: 10)
                    // Actual alignment marker
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 12, height: 12)
                        .position(x: geo.size.width * 0.60, y: 10)
                }
            }
            .frame(height: 20)
            HStack {
                Text("-5°")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("0°")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("+5°")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Advisory

    private var advisoryCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 32, height: 32)
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("Counter-steer, hold it. Blind-side is \(fallbackBlindSide). Straighten to ±1° before you close the last foot. No spotter overnight — re-pull if you aren't square.")
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Footer CTAs

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { /* upstream pull-up handler */ } label: {
                Text("Pull up & redo")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }

            CTAButton(
                title: "Set brakes",
                action: { Task { await setBrakes() } },
                isLoading: isConfirming
            )
        }
    }

    // MARK: Hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func setBrakes() async {
        isConfirming = true
        defer { isConfirming = false }
        let forwardKeys = ["unloading", "discharge", "dockset"]
        let candidate = lifecycle.availableTransitions.first { t in
            let to = t.to.lowercased()
            return forwardKeys.contains(where: { to.contains($0) })
        } ?? lifecycle.availableTransitions.first
        if let transition = candidate {
            _ = await lifecycle.execute(transition)
        }
        advance?()
    }
}

struct BackingInScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            BackingIn(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_023(),
                      trailing: driverNavTrailing_023(),
                      orbState: .idle)
        }
    }
}

// PNG canon at `01 Driver/{Light,Dark}/023 Backing In.png` pins
// TRIPS current on lifecycle Ring 3. Icon set + trailing slot
// normalized to canonical 010-022 layout.
private func driverNavLeading_023() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: true)]
}
private func driverNavTrailing_023() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

#Preview("023 · Backing In · Dark") {
    BackingInScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("023 · Backing In · Light") {
    BackingInScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
