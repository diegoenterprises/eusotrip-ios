//
//  045_DepartingReceiver.swift
//  EusoTrip — Lifecycle screen 045 · Departing Receiver.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `045 Departing Receiver.png`. Driver has cleared the gate;
//  trip is logged. Shows a clear-of-dock card + 3 receiver-side
//  facts + home-yard return preview + Off-duty / Start return
//  CTAs. Universal across products — only the kicker label
//  swaps via `ctx.headerKicker`.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DepartingReceiver: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    /// Drives the "Off-duty" secondary CTA — flips the FMCSA duty
    /// status the same way the ELD picker does, so the post-delivery
    /// "I'm done for the night" tap actually moves the clock instead
    /// of silently popping back to the prior screen.
    @StateObject private var hos = HOSLiveStore()
    @State private var activeLoad: Load?
    @State private var isStartingReturn: Bool = false
    @State private var isGoingOffDuty: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private let fallbackClock      = "22:04"
    private let fallbackFacility   = "—"
    private let fallbackDockNote   = "Clear of dock · 0.3 mi past gate"
    private let fallbackRouteLabel = "On PA-295 southbound · gate arm closed behind · custody receipt sealed"
    private let fallbackElapsed    = "—"
    private let fallbackBolHash    = "—"
    private let fallbackHomeYard   = "—"
    private let fallbackHomeMiles  = "—"
    private let fallbackHomeEta    = ""
    private let fallbackHomeNote   = "HOS window has 2h 48m left — covers the run clean. No fuel stop needed. 10-hr reset starts on arrival."

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                clearCard
                yardCard
                exitFacts
                homeYardCard
                routePreview
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
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("DEPARTING RECEIVER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· \(ctx.headerKicker)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                }
                Text("Departing receiver · \(fallbackFacility)")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("GATE CLEARED · RETURNING TO HOME YARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(fallbackClock)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text("TRIP DONE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.success)
            }
        }
        .padding(.top, 4)
    }

    private var clearCard: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(fallbackDockNote)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(fallbackRouteLabel)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("CLEARED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var yardCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(fallbackFacility.uppercased()) · DOCK 3")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("EXIT STATUS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md).fill(Color.black.opacity(0.7))
                GeometryReader { geo in
                    Path { p in
                        p.move(to: CGPoint(x: geo.size.width * 0.05, y: geo.size.height * 0.7))
                        p.addLine(to: CGPoint(x: geo.size.width * 0.45, y: geo.size.height * 0.7))
                        p.addLine(to: CGPoint(x: geo.size.width * 0.55, y: geo.size.height * 0.4))
                        p.addLine(to: CGPoint(x: geo.size.width * 0.95, y: geo.size.height * 0.4))
                    }
                    .stroke(LinearGradient.diagonal, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 10, height: 10)
                        .position(x: geo.size.width * 0.55, y: geo.size.height * 0.4)
                }
                Text("ROUTE PICK")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var exitFacts: some View {
        HStack(spacing: Space.s2) {
            fact(label: "AT RECEIVER", value: fallbackElapsed,    sub: "ELAPSED")
            fact(label: "BOL HASH",     value: fallbackBolHash,    sub: "SEALED")
            fact(label: "SEAL",         value: "Sealed",            sub: "ESANG · ES-83-A")
        }
    }

    private func fact(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var homeYardCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Home yard · \(fallbackHomeYard)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(fallbackHomeMiles)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text("MI")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(fallbackHomeEta)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.success)
            }
            Text(fallbackHomeNote)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var routePreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ROUTE PREVIEW · \(fallbackHomeMiles) MI · \(fallbackHomeEta)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("EXPAND")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            // Simple stepped chart
            GeometryReader { geo in
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height * 0.7))
                    p.addLine(to: CGPoint(x: geo.size.width * 0.30, y: geo.size.height * 0.7))
                    p.addLine(to: CGPoint(x: geo.size.width * 0.30, y: geo.size.height * 0.40))
                    p.addLine(to: CGPoint(x: geo.size.width * 0.65, y: geo.size.height * 0.40))
                    p.addLine(to: CGPoint(x: geo.size.width * 0.65, y: geo.size.height * 0.55))
                    p.addLine(to: CGPoint(x: geo.size.width * 1.0, y: geo.size.height * 0.55))
                }
                .stroke(LinearGradient.diagonal, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .frame(height: 40)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await goOffDuty() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Off-duty")
                        .font(EType.body.weight(.semibold))
                }
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .opacity(isGoingOffDuty ? 0.6 : 1)
            }
            .disabled(isGoingOffDuty)
            CTAButton(
                title: "Start return",
                action: { Task { await startReturn() } },
                trailingIcon: "arrow.right",
                isLoading: isStartingReturn
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func startReturn() async {
        isStartingReturn = true
        defer { isStartingReturn = false }
        let keys = ["return", "home_yard", "next_beat", "completed"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }

    private func goOffDuty() async {
        isGoingOffDuty = true
        defer { isGoingOffDuty = false }
        MeAction.fire("045.off-duty-tapped",
                      userInfo: ["loadId": lifecycle.loadId])
        let ok = await hos.changeStatus(
            to: .offDuty,
            location: "Past receiver gate",
            remark: "Off-duty after delivery (045)",
            loadId: lifecycle.loadId.isEmpty ? nil : lifecycle.loadId
        )
        // Whether the duty change succeeded or the server rejected it,
        // navBack so the driver lands on the prior surface (lifecycle
        // owns the next-screen advance — Off-duty is a lateral action,
        // not an advance). HOSLiveStore's toast surfaces success/failure
        // independently.
        _ = ok
        navBack?()
    }
}

struct DepartingReceiverScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DepartingReceiver(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_045(),
                      trailing: driverNavTrailing_045(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_045() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_045() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("045 · Departing Receiver · Dark") {
    DepartingReceiverScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("045 · Departing Receiver · Light") {
    DepartingReceiverScreen(theme: Theme.light).preferredColorScheme(.light)
}
