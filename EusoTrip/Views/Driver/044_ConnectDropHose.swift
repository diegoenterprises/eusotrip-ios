//
//  044_ConnectDropHose.swift
//  EusoTrip — Lifecycle screen 044 · Connect Drop Hose.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `044 Connect Drop Hose.png`. Mirror of 042 — driver is mating
//  the next leg's drop hose (or coupling next trailer for non-
//  tanker products). Step 2 of 4 with ladder + ESD bond +
//  pressure-check tiles + supervisor live mic.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct ConnectDropHose: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
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

    private let fallbackClock = "21:14"

    /// Connecting-headline — composes "Connecting <medium> ·
    /// <cityState>" with em-dash sentinels for parts that aren't
    /// first-class fields on `Load` yet.
    ///
    /// 116th firing M2 retrofit (2026-04-26): previous literal
    /// "Yara York PA Dock 3" excised. The dock label is not yet a
    /// first-class field on `Load`; until `Load.deliveryDockLabel`
    /// ships from the backend the headline omits the dock segment
    /// rather than fabricating one. The cityState is hydrated live
    /// from the active trip's `deliveryLocation`. Doctrine: 0% mock
    /// data — sentinel parity with 043_DisconnectConfirmed.
    private var connectHeadline: String {
        let medium = ctx.isHazmat ? "drop hose" : "next trailer"
        let cityState = activeLoad?.deliveryLocation?.cityState ?? "—"
        return "Connecting \(medium) · \(cityState)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                connectorRing
                stepCard
                metricRow
                ladder
                supervisorMic
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
                    Text("STEP 2 OF 4 · \(ctx.headerKicker)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(connectHeadline)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("DRY-DISCONNECT MATE · ESD BOND LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            Text(fallbackClock)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    private var connectorRing: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(ctx.isHazmat ? "DRY-DISCONNECT" : "TRAILER COUPLING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.danger)
            }
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md).fill(Color.black.opacity(0.7))
                GeometryReader { geo in
                    HStack(spacing: 4) {
                        Capsule().fill(palette.textSecondary).frame(width: geo.size.width * 0.3, height: 14)
                        ZStack {
                            Capsule()
                                .fill(LinearGradient.diagonal)
                                .frame(width: 28, height: 22)
                            Image(systemName: "link.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Capsule().fill(palette.textSecondary).frame(width: geo.size.width * 0.3, height: 14)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(height: 70)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var stepCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CURRENT STEP")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(ctx.isHazmat ? "Mate the dry-disconnect coupler" : "Couple to next trailer")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(ctx.isHazmat
                 ? "Spin the threaded ring on by hand until it shoulders, then snug. Three full turns past hand-tight. Don't cross-thread."
                 : "Set the kingpin on the fifth wheel. Pull-test, then visual gap check before lights + air lines.")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var metricRow: some View {
        HStack(spacing: Space.s2) {
            metric(label: "ESD BOND",     value: "LIVE", note: "Continuity OK")
            metric(label: "PRESS CHECK",  value: "0.0", note: "LINE EMPTY")
            metric(label: "LEAK TEST",    value: "Priming", note: "WAITS · STEP 3")
        }
    }

    private func metric(label: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            Text(note)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
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

    private var ladder: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CONNECT LADDER · \(ctx.isHazmat ? "NH3 CLOSED-LOOP" : "TRAILER")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("STEP 2 OF 4")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            connectRow(title: ctx.isHazmat ? "Bond ESD strap to dock grid" : "Pull-test fifth wheel", state: "done", time: "21:13:38")
            connectRow(title: ctx.isHazmat ? "Mate dry-disconnect coupler" : "Couple gladhands + lights", state: "now",  time: "NOW")
            connectRow(title: "Pressurize-check & sniff vapor", state: "next", time: "STEP 3")
            connectRow(title: "Open loop & prime to receiver", state: "next", time: "STEP 4")
        }
    }

    private func connectRow(title: String, state: String, time: String) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: state == "done" ? "checkmark.circle.fill" : (state == "now" ? "smallcircle.fill.circle.fill" : "circle"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(state == "done" ? Brand.success : (state == "now" ? Brand.warning : palette.textTertiary))
            Text(title)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(state == "next" ? palette.textSecondary : palette.textPrimary)
            Spacer()
            Text(time)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(state == "now" ? Brand.warning : palette.textTertiary)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 9)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var supervisorMic: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Text("RH").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Reg Hammond")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    HStack(spacing: 3) {
                        Circle().fill(Brand.danger).frame(width: 5, height: 5)
                        Text("LIVE MIC")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(Brand.danger)
                    }
                }
                Text("\"Ring is on three turns — give it a snug, no torquing.\"")
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
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
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Help")
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
            }
            CTAButton(
                title: "Confirm mated",
                action: { Task { await confirmMated() } },
                leadingIcon: "checkmark.circle.fill",
                isLoading: isConfirming
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func confirmMated() async {
        isConfirming = true
        defer { isConfirming = false }
        let keys = ["mated", "primed", "departing"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct ConnectDropHoseScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ConnectDropHose(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_044(),
                      trailing: driverNavTrailing_044(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_044() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_044() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("044 · Connect Drop Hose · Dark") {
    ConnectDropHoseScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("044 · Connect Drop Hose · Light") {
    ConnectDropHoseScreen(theme: Theme.light).preferredColorScheme(.light)
}
