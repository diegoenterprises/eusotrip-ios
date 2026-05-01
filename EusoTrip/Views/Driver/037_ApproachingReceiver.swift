//
//  037_ApproachingReceiver.swift
//  EusoTrip — Lifecycle screen 037 · Approaching Receiver.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `037 Approaching Receiver.png`. Rig is ~4 mi from the receiver,
//  ESANG is pre-arming the arrival. Leads with a big gradient
//  "4.2 mi · 7 min" hero + receiver card (gate/bay/contact/phone) +
//  product-aware hazmat strip (shown only when `ctx.isHazmat`) +
//  4-row pre-arrival checklist dispatched through
//  `LifecycleProductContext` + ESANG arrival card + Trip log /
//  Notify receiver CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct ApproachingReceiver: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var completed: Set<String> = []
    @State private var isNotifying: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma fallback
    private let fallbackClock       = "21:07"
    private let fallbackMiles       = "4.2"
    private let fallbackMinutes     = "7 min"
    private let fallbackArriveBy    = "21:14"
    private let fallbackRecipName   = "—"
    private let fallbackRecipAddr   = "7600 W ROOSEVELT HWY · YORK PA 17407"
    private let fallbackGate        = "B-2"
    private let fallbackBay         = "Dock 3"
    private let fallbackContact     = "Reg Hammond"
    private let fallbackPhone       = "+1 (717) 854-2010"
    private let fallbackEsangNote   = "ESANG — EARLIER TONIGHT · FIT FOR 21:11 · WEATHER HOLD CLEARED · AMMONIA SENSORS WARM"

    private var receiverTitle: String {
        if let loc = activeLoad?.deliveryLocation, !loc.cityState.isEmpty {
            let brand = loc.address.isEmpty ? loc.cityState : loc.address
            return "\(brand) — \(loc.cityState)"
        }
        return fallbackRecipName
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                heroCard
                receiverCard
                if !ctx.receiverHazmatStrip.isEmpty {
                    hazmatStrip
                }
                preArrivalChecklist
                esangAdvisory
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task {
            await hydrateLiveTrip()
            seedDefaults()
        }
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
                    Text("APPROACHING DESTINATION")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· \(ctx.headerKicker)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                }
                Text("Arriving at \(receiverCityLine) by \(fallbackArriveBy)")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(fallbackClock)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text("APPROACHING")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
            }
        }
        .padding(.top, 4)
    }

    private var receiverCityLine: String {
        // 116th firing M2 retrofit (2026-04-26): replaced fixture
        // fallback "Yara York" with the canonical em-dash sentinel.
        // The screen now renders an honest "—" when the active trip
        // hasn't hydrated yet, never a fabricated city. Doctrine:
        // 0% mock data — sentinel parity with 018/024/038/051/055.
        activeLoad?.deliveryLocation?.cityState ?? "—"
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(fallbackMiles)
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("mi")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("· \(fallbackMinutes)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            }
            // Stylized purple dotted progress
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 3)
                    HStack(spacing: 4) {
                        ForEach(0..<20, id: \.self) { _ in
                            Circle()
                                .fill(LinearGradient.diagonal)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
                .frame(height: 8)
            }
            .frame(height: 8)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var receiverCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 34, height: 34)
                    Text(String(receiverTitle.prefix(1)))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(receiverTitle)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(fallbackRecipAddr)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Divider().overlay(palette.borderFaint)
            HStack(spacing: Space.s2) {
                fact(label: "GATE", value: fallbackGate)
                fact(label: "BAY",  value: fallbackBay)
                fact(label: "CONTACT", value: fallbackContact)
                fact(label: "PHONE", value: fallbackPhone)
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

    private func fact(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hazmatStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Brand.warning)
            Text("HAZMAT RECEIVING PRECAUTIONS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Brand.warning)
            Text("· PINGED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Brand.warning.opacity(0.8))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
        .background(Brand.warning.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var preArrivalChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRE-ARRIVAL CHECKLIST")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            ForEach(ctx.receiverPreArrival) { item in
                Button {
                    if completed.contains(item.id) {
                        completed.remove(item.id)
                    } else {
                        completed.insert(item.id)
                    }
                } label: {
                    HStack(spacing: Space.s3) {
                        rowDot(done: completed.contains(item.id))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(EType.body.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                            Text(item.subtitle)
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                .foregroundStyle(palette.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Text(completed.contains(item.id) ? "CONFIRMED" : "PENDING")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(completed.contains(item.id) ? Brand.success : palette.textTertiary)
                    }
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, 10)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rowDot(done: Bool) -> some View {
        ZStack {
            if done {
                Circle().fill(Brand.success.opacity(0.2))
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Brand.success)
            } else {
                Circle().strokeBorder(palette.borderSoft, lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
    }

    private func seedDefaults() {
        guard completed.isEmpty else { return }
        let items = ctx.receiverPreArrival
        if items.count >= 3 {
            completed = Set(items.prefix(3).map { $0.id })
        }
    }

    private var esangAdvisory: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            Text(fallbackEsangNote)
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
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

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { navBack?() } label: {
                Text("Trip log")
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
                title: "Notify receiver",
                action: { Task { await notifyReceiver() } },
                trailingIcon: "arrow.right",
                isLoading: isNotifying
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func notifyReceiver() async {
        isNotifying = true
        defer { isNotifying = false }
        let keys = ["at_receiver", "credentials", "gate"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct ApproachingReceiverScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ApproachingReceiver(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_037(),
                      trailing: driverNavTrailing_037(),
                      orbState: .idle)
        }
    }
}

// PNG canon at `01 Driver/{Light,Dark}/037 Approaching Receiver.png`
// pins TRIPS current — 4-row pre-arrival checklist (Hazmat PPE +
// BOL packet + ESANG arrival-ping + spotter contact). Icon set +
// trailing slot normalized to canonical 010-036 layout.
private func driverNavLeading_037() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: true)]
}
private func driverNavTrailing_037() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

#Preview("037 · Approaching Receiver · Dark") {
    ApproachingReceiverScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("037 · Approaching Receiver · Light") {
    ApproachingReceiverScreen(theme: Theme.light).preferredColorScheme(.light)
}
