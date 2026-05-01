//
//  042_DisconnectAndVerify.swift
//  EusoTrip — Lifecycle screen 042 · Disconnect & Verify.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `042 Disconnect and Verify.png`. Driver is at the dry-disconnect
//  ring (or trailer-side disconnect for non-tanker products) with
//  ESANG narrating the step. Animated coupler ring graphic + 3
//  pressure/vapor/bond tiles + 4-step ladder + supervisor live mic
//  + Help / Confirm uncoupled CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DisconnectAndVerify: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverShowHelp) private var showHelp
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

    // Production-clean placeholders. Updated 2026-04-24
    // (eusotrip-killers ledger-hygiene pass). Live readings come from
    // `tankMonitor.getDisconnectSnapshot` once the bay-ops sensor stack
    // ships — until then, em-dashes only.
    private let fallbackClock = "—"
    private let fallbackPressure = "—"
    private let fallbackVapor    = "—"
    private let fallbackBond     = "—"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                couplerRing
                stepCard
                metricRow
                ladderCard
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
            // 100th firing · ledger-hygiene sweep — wired no-op chevron to
            // `driverNavBack` so back-nav walks the lifecycle phase backward.
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
                Text("Disconnecting \(ctx.isHazmat ? "NH3 line" : "trailer") · Dock 3")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("COUPLER UNHOOK · SPOTTER ON WATCH")
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

    private var couplerRing: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("COUPLER RING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
            }
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Color.black.opacity(0.7))
                GeometryReader { geo in
                    HStack(spacing: 4) {
                        Capsule().fill(palette.textSecondary).frame(width: geo.size.width * 0.25, height: 12)
                        Capsule()
                            .fill(LinearGradient.diagonal)
                            .frame(width: geo.size.width * 0.40, height: 18)
                        Capsule().fill(palette.textSecondary).frame(width: geo.size.width * 0.25, height: 12)
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
            Text(ctx.isHazmat ? "Spin off the dry-disconnect coupler" : "Lift trailer off dock plate")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(ctx.isHazmat
                 ? "Two-handed grip on the ring, counter-clockwise. Pressure-equalize port should be open before the ring leaves the threads."
                 : "Pull dock plate. Verify the dock door has cleared the trailer top before easing off the rubber.")
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
            metric(label: "PRESSURE", value: fallbackPressure, unit: "psi")
            metric(label: "VAPOR",    value: fallbackVapor,    unit: "psig")
            metric(label: "ESD BOND", value: fallbackBond,     unit: "")
        }
    }

    private func metric(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
            }
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

    private var ladderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DISCONNECT LADDER · \(ctx.isHazmat ? "NH3 CLOSED-LOOP" : "RECEIVER")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("STEP 1 OF 4 GO")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            ForEach(ctx.disconnectLadder) { step in
                HStack(spacing: Space.s3) {
                    Image(systemName: stepIcon(step.state))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(stepColor(step.state))
                    Text(step.title)
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(step.state == "next" ? palette.textSecondary : palette.textPrimary)
                    Spacer()
                    Text(step.timestamp ?? (step.state == "now" ? "NOW" : ""))
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(stepColor(step.state))
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
        }
    }

    private func stepIcon(_ state: String) -> String {
        switch state {
        case "done": return "checkmark.circle.fill"
        case "now":  return "smallcircle.fill.circle.fill"
        default:     return "circle"
        }
    }
    private func stepColor(_ state: String) -> Color {
        switch state {
        case "done": return Brand.success
        case "now":  return Brand.warning
        default:     return palette.textTertiary
        }
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
                Text("\"Two more turns and she's clear — keep your face out of the gap.\"")
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
            // 100th firing · ledger-hygiene sweep — was no-op. Wires to
            // env-injected `driverShowHelp` with a context-tagged topic
            // ("disconnect-and-verify"). Falls through if env not registered.
            Button { showHelp?("disconnect-and-verify") } label: {
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
                title: "Confirm uncoupled",
                action: { Task { await confirmUncoupled() } },
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

    private func confirmUncoupled() async {
        isConfirming = true
        defer { isConfirming = false }
        let keys = ["disconnect_confirmed", "stowed", "released"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct DisconnectAndVerifyScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DisconnectAndVerify(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_042(),
                      trailing: driverNavTrailing_042(),
                      orbState: .idle)
        }
    }
}

// PNG canon at `01 Driver/{Light,Dark}/042 Disconnect and Verify.png`
// pins TRIPS current — dry-break uncouple step 2 of 4 with VRC sleeve
// clear + ESD bond continuity LIVE + spotter watching. Icon set +
// trailing slot normalized to canonical 010-041 layout.
private func driverNavLeading_042() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: true)]
}
private func driverNavTrailing_042() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

#Preview("042 · Disconnect & Verify · Dark") {
    DisconnectAndVerifyScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("042 · Disconnect & Verify · Light") {
    DisconnectAndVerifyScreen(theme: Theme.light).preferredColorScheme(.light)
}
