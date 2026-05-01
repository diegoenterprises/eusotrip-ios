//
//  039_BackingAssistReceiver.swift
//  EusoTrip — Lifecycle screen 039 · Backing Assist · Receiver.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `039 Backing Assist Receiver.png`. Driver is reversing onto the
//  receiver's dock with ESANG + supervisor live-mic support. Rear
//  cam cone field + mirror pair + parking-brake countdown ring +
//  left/right clearance tiles + supervisor live-mic card + Hold /
//  Set parking brake CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct BackingAssistReceiver: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isSetting: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma fallback
    private let fallbackClock    = "21:18"
    private let fallbackDock     = "Dock 3"
    private let fallbackHeaderSub = "SPOTTER ACTIVE · SCRUBBED GREEN"
    private let fallbackInsToPad = "8"
    private let fallbackBrakeAt  = "4"
    private let fallbackApproachRate = "0.4"
    private let fallbackLeft     = "22"
    private let fallbackRight    = "9"
    private let fallbackSupervisor = "Reg Hammond · night supervisor"
    private let fallbackSupervisorLine = "Two more inches, hold your wheel — scrubber post on the right at ten-thirty."

    private var dockLabel: String {
        switch ctx.vertical {
        case .truck:  return fallbackDock
        case .rail:   return "Spur 3"
        case .vessel: return "Berth 3"
        }
    }

    private var headerTitle: String {
        "Backing into \(dockLabel) · \(receiverCity)"
    }

    private var receiverCity: String {
        // 116th firing M2 retrofit (2026-04-26): replaced fixture
        // fallback "Yara York PA" with the canonical em-dash sentinel.
        // The screen now renders an honest "—" when the active trip
        // hasn't hydrated yet, never a fabricated city. Doctrine:
        // 0% mock data — sentinel parity with 018/024/038/051/055.
        activeLoad?.deliveryLocation?.cityState ?? "—"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                cameraPane
                brakeRing
                clearancePair
                supervisorCard
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { navBack?() } label: {
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
                    Image(systemName: ctx.product.symbol)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("BACKING ASSIST")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· \(ctx.headerKicker)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                }
                Text(headerTitle)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(fallbackHeaderSub)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(fallbackClock)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text("\(dockLabel.uppercased()) ASSIGNED")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.success)
            }
        }
        .padding(.top, 4)
    }

    private var cameraPane: some View {
        VStack(spacing: Space.s2) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.black)
                    .frame(height: 200)
                GeometryReader { geo in
                    // Target-line + cones
                    Path { p in
                        p.move(to: CGPoint(x: geo.size.width * 0.35, y: 0))
                        p.addLine(to: CGPoint(x: geo.size.width * 0.50, y: geo.size.height))
                    }
                    .stroke(LinearGradient.diagonal.opacity(0.8), lineWidth: 2)
                    Path { p in
                        p.move(to: CGPoint(x: geo.size.width * 0.65, y: 0))
                        p.addLine(to: CGPoint(x: geo.size.width * 0.50, y: geo.size.height))
                    }
                    .stroke(LinearGradient.diagonal.opacity(0.8), lineWidth: 2)
                    Text("TARGET LINE")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white.opacity(0.75))
                        .position(x: geo.size.width * 0.50, y: geo.size.height * 0.44)
                }
                .frame(height: 200)
                HStack {
                    HStack(spacing: 4) {
                        Circle().fill(Brand.danger).frame(width: 5, height: 5)
                        Text("REAR CAM · CONE FIELD")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    Text("\(fallbackInsToPad) in")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, Space.s3)
                .padding(.top, Space.s2)
            }

            HStack(spacing: Space.s2) {
                mirrorBox(label: "LEFT MIRROR", value: fallbackLeft, color: Brand.success)
                mirrorBox(label: "RIGHT MIRROR", value: fallbackRight, color: Brand.warning)
            }
        }
    }

    private func mirrorBox(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("\(value) in")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.25))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var brakeRing: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().stroke(palette.bgCardSoft, lineWidth: 6).frame(width: 64, height: 64)
                Circle()
                    .trim(from: 0, to: 0.55)
                    .stroke(LinearGradient.diagonal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 64, height: 64)
                VStack(spacing: -2) {
                    Text(fallbackInsToPad)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text("IN TO PAD")
                        .font(.system(size: 7, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Set parking brake at \(fallbackBrakeAt) in")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("\(fallbackApproachRate) ft/s APPROACH · \(approachCaption)")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(fallbackApproachRate) ft/s")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("APPROACH")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Approach caption changes with product — hazmat tanker has
    /// scrubber post language; dry-van mentions dock plate etc.
    private var approachCaption: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:   return "scrubber side clear · inches to pad"
        case .reefer:                        return "cold door framed · inch to pad"
        case .flatbed:                       return "crane lane clear · straight-in"
        case .container, .railIntermodal, .vesselContainer:
                                             return "twistlocks aligned · straight-in"
        case .railBulk, .vesselBulk:         return "spur guides aligned · inch to pad"
        case .dryVan:                        return "dock plate ready · inches to rubber"
        }
    }

    private var clearancePair: some View {
        HStack(spacing: Space.s2) {
            clearanceCell(label: "LEFT CLEARANCE", value: fallbackLeft, color: Brand.success)
            clearanceCell(label: "RIGHT CLEARANCE", value: fallbackRight, color: Brand.warning)
        }
    }

    private func clearanceCell(label: String, value: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(color)
                    Text("in")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(color.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var supervisorCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 36, height: 36)
                Text("RH").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(fallbackSupervisor)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(Brand.danger).frame(width: 5, height: 5)
                        Text("LIVE MIC")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(Brand.danger)
                    }
                }
                Text("\"\(fallbackSupervisorLine)\"")
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
                // Stylized audio waveform
                HStack(spacing: 2) {
                    ForEach(0..<24, id: \.self) { i in
                        Capsule()
                            .fill(LinearGradient.diagonal.opacity(0.85))
                            .frame(width: 2, height: [4,8,12,16,18,14,10,6,12,18,14,8,4,10,16,18,12,8,4,6,10,14,16,10][i])
                    }
                }
            }
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

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { navBack?() } label: {
                Text("Hold")
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
                title: "Set parking brake",
                action: { Task { await setBrake() } },
                trailingIcon: "arrow.right",
                isLoading: isSetting
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func setBrake() async {
        isSetting = true
        defer { isSetting = false }
        let keys = ["discharge", "unloading", "connect"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct BackingAssistReceiverScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            BackingAssistReceiver(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_039(),
                      trailing: driverNavTrailing_039(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_039() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_039() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("039 · Backing Assist · Dark") {
    BackingAssistReceiverScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("039 · Backing Assist · Light") {
    BackingAssistReceiverScreen(theme: Theme.light).preferredColorScheme(.light)
}
