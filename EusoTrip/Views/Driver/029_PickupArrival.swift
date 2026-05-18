//
//  029_PickupArrival.swift
//  EusoTrip — Lifecycle screen 029 · Pickup Arrival (ESANG leading).
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `029 Pickup Arrival.png` (Dark + Light). Rig is parked at the
//  rack, chocks in, grounding being brought up. ESANG walks the
//  driver through the grounding + impedance → 2-valve check →
//  Spectra-Match purity sequence.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct PickupArrival: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverOpenMessages) private var openMessages
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isConfirming: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .afternoon) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Production-clean placeholders.
    // Updated 2026-04-24 (eusotrip-killers ledger-hygiene pass).
    // Live values come from `loads.getById` (facility) +
    // `yardManagement.getMyQueuePosition` (bay/rig state).
    private let fallbackClock   = "—"
    private let fallbackLoadID  = "—"
    private let fallbackFacility = "—"
    private let fallbackBayLine  = "Awaiting bay assignment"
    private let fallbackRigState = "—"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                facilityCard
                esangLeadCard
                spectraHandshake
                eusoshieldRow
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
            // 100th firing · ledger-hygiene sweep — was `Button { }` (no-op
            // chevron). Wires to the env-injected `driverNavBack` closure
            // ContentView publishes; the env key falls back to nil so
            // previews keep building. No-op when phase is `.idle`.
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
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                    Text("RIG PARKED")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.success)
                    Text("· \(activeLoad?.loadNumber ?? fallbackLoadID)")
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text("\(ctx.vertical.pickupWord) · ESANG leading")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("Step 2 of 4 · grounding · ~6 min to first crack")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(fallbackClock)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    private var facilityCard: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(palette.bgCardSoft)
                Image(systemName: "dot.squareshape.split.2x2")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(fallbackFacility)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(fallbackBayLine)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(fallbackRigState)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.success)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var esangLeadCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 26, height: 26)
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                }
                Text("ESANG is leading")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("STEP 2 / 4")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("HAZMAT SAFETY · Class 2.2 NH3")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)

            Divider().overlay(palette.borderFaint)

            VStack(alignment: .leading, spacing: 4) {
                Text("Grounding active · impedance reading")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Strap clamped to tank shell lug. Hold — ESANG is reading impedance to terminal earth. Need ≤ 10 Ω before any valve opens.")
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 4-step mini-checklist
            VStack(spacing: 4) {
                miniStep(title: "Engine off · chocks set", state: .done)
                miniStep(title: "Grounding strap clamped to lug", state: .done)
                miniStep(title: "Impedance check · target < 10Ω", state: .now, tail: "READING")
                miniStep(title: "2-valve check (liquid + vapor)", state: .next, tail: "STEP 3")
                miniStep(title: "Spectra-Match purity confirm", state: .next, tail: "STEP 4")
            }

            // ESANG quote
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading 7.4 ohms and falling. We're inside spec. Stand by for the actual crack, downwind side — I'll call the valve sequence.")
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                    Text("VIA ESANG · HAZMAT SAFETY")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s2)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private enum MiniState { case done, now, next }
    private func miniStep(title: String, state: MiniState, tail: String? = nil) -> some View {
        HStack(spacing: 8) {
            ZStack {
                switch state {
                case .done:
                    Circle().fill(Brand.success.opacity(0.2))
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Brand.success)
                case .now:
                    Circle().fill(LinearGradient.diagonal.opacity(0.2))
                    Circle().stroke(LinearGradient.diagonal, lineWidth: 1.5).frame(width: 10, height: 10)
                case .next:
                    Circle().strokeBorder(palette.borderSoft, lineWidth: 1)
                }
            }
            .frame(width: 18, height: 18)
            Text(title)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(state == .next ? palette.textSecondary : palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let t = tail {
                Text(t)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(state == .now ? Brand.warning : palette.textTertiary)
            }
        }
    }

    private var spectraHandshake: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "waveform.path")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Spectra-Match · sensor handshaking")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("QUEUED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.warning)
                }
                Text("Last reading 99.91% NH3 · target ≥ 99.5%")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var eusoshieldRow: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "shield.checkerboard")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.success)
            Text("EusoShield active · window 17:47 – 06:30")
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text("$5M")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Brand.success)
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var footerActions: some View {
        // Each button extracted into its own computed property so
        // Swift's type-checker doesn't blow up trying to infer the
        // HStack's full TupleView signature in one pass — Release
        // whole-module-optimization couldn't produce a diagnostic
        // for the inline version (cascading from the prior
        // unresolved `EusoTripAPI.X.Y` types in other files).
        HStack(spacing: Space.s3) {
            notifyShackButton
            confirmGroundedButton
        }
    }

    private var notifyShackButton: some View {
        // 100th firing · ledger-hygiene sweep — was no-op. "Notify shack"
        // now opens the canonical dispatch messaging thread for the
        // active load (`messages.ts` per §16 messaging-docs).
        Button(action: notifyShackTapped) {
            notifyShackLabel
        }
    }

    private func notifyShackTapped() {
        // Root cause of the prior Release-only "failed to produce
        // diagnostic" error: `Load.id` is `Int`, not `String`, and
        // `driverOpenMessages` expects `String?`. The inline
        // `openMessages?(activeLoad?.id)` chain forced Swift to coerce
        // `Int?` → `String?` implicitly; the inferencer looped trying
        // to resolve it. Explicit conversion fixes the type-check.
        guard let handler = openMessages else { return }
        let threadId: String? = activeLoad.map { String($0.id) }
        handler(threadId)
    }

    private var notifyShackLabel: some View {
        // Extracted label so Release whole-module-optimization can
        // type-check the chain without timing out (was the source of
        // the "failed to produce diagnostic" Release-only error).
        Text("Notify shack")
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

    private var confirmGroundedButton: some View {
        CTAButton(
            title: "Confirm grounded",
            action: { Task { await confirmGrounded() } },
            trailingIcon: "arrow.right",
            isLoading: isConfirming
        )
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func confirmGrounded() async {
        isConfirming = true
        defer { isConfirming = false }
        let keys = ["loading", "fill", "purity"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct PickupArrivalScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            PickupArrival(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_029(),
                      trailing: driverNavTrailing_029(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_029() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_029() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("029 · Pickup Arrival · Dark") {
    PickupArrivalScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("029 · Pickup Arrival · Light") {
    PickupArrivalScreen(theme: Theme.light).preferredColorScheme(.light)
}
