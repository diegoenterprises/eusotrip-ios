//
//  047_ArrivalCheckpoint.swift
//  EusoTrip — Lifecycle screen 047 · Arrival Checkpoint.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `047 Arrival Checkpoint.png`. Driver rolled into the home yard;
//  rig is parked. ARRIVED green chip + on-site clock + parked
//  spot + checkpoint summary (closed deadhead vs open post-trip
//  DVIR) + yard-card + 4-row product-aware walkaround gates list.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct ArrivalCheckpoint: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var completed: Set<String> = []

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private let fallbackClock      = "23:16"
    private let fallbackOnSite     = "0:02"
    private let fallbackParked     = "—"
    private let fallbackYard       = "—"
    private let fallbackYardAddr   = "3608 HAWKINS POINT RD · BALTIMORE MD 21226"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                onSiteCard
                checkpointStrip
                yardCard
                walkaroundGates
                esangFooter
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
            // 100th firing · ledger-hygiene sweep — wired no-op chevron.
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
                    Image(systemName: "house.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("ARRIVED · HOME YARD")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· \(ctx.headerKicker)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                    // EUSOTRIP-MODE-BADGE-2026-05-17 — mode chip on lifecycle screen
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
            }
            Spacer(minLength: 0)
            Text(fallbackClock)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    private var onSiteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ON SITE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("ARRIVED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(fallbackOnSite)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("on site")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("@ \(fallbackClock)")
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Parked at \(fallbackParked)")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var checkpointStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ARRIVAL CHECKPOINT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                checkpointCol(state: "CLOSED · DEADHEAD", title: deadheadTitle, sub: "78 mi · 0.3 defect alerts en route", color: Brand.success)
                checkpointCol(state: "OPEN · POST-TRIP DVIR", title: openLegTitle, sub: "49 CFR 396.11 · MC-331 + tractor", color: Brand.warning)
            }
        }
    }

    private var deadheadTitle: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:  return "78 mi Yara York → Curtis Bay"
        case .reefer:                       return "78 mi cold return → home yard"
        case .flatbed:                      return "78 mi flatbed return → home yard"
        case .container, .railIntermodal:   return "78 mi chassis return → ramp"
        case .vesselContainer:              return "78 mi box return → port"
        case .railBulk, .vesselBulk:        return "78 mi bulk return → spur"
        case .dryVan:                       return "78 mi return → home yard"
        }
    }

    private var openLegTitle: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:  return "49 CFR 396.11 · tractor + MC-331"
        case .reefer:                       return "49 CFR 396.11 · reefer unit + tractor"
        case .flatbed:                      return "49 CFR 396.11 · deck + securement"
        case .container, .railIntermodal,
             .vesselContainer:              return "49 CFR 396.11 · chassis + tractor"
        case .railBulk, .vesselBulk:        return "49 CFR 396.11 · bulk trailer + grounding"
        case .dryVan:                       return "49 CFR 396.11 · van + tractor"
        }
    }

    private func checkpointCol(state: String, title: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(color)
            Text(title)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sub)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(2)
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

    private var yardCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    Text("C").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(fallbackYard)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(fallbackYardAddr)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: Space.s2) {
                yardCell(label: "ENTRY",     value: "Gate C · badge OK")
                yardCell(label: "PARKED",    value: "Row 4 · Spot S-14")
                yardCell(label: "GYM TIMER", value: "Started \(fallbackClock)")
            }
            Text("Sleeper \(ctx.vertical.bayWord) 14 keyed · shower + laundry")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func yardCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var walkaroundGates: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("POST-TRIP DVIR · WALKAROUND GATES")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            ForEach(ctx.walkaroundGates) { row in
                Button {
                    if completed.contains(row.id) {
                        completed.remove(row.id)
                    } else {
                        completed.insert(row.id)
                    }
                } label: {
                    HStack(spacing: Space.s3) {
                        rowDot(done: completed.contains(row.id))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(EType.body.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                            Text(row.subtitle)
                                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(completed.contains(row.id) ? "READY" : row.tail)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(completed.contains(row.id) ? Brand.success : palette.textTertiary)
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
        let items = ctx.walkaroundGates
        if items.count >= 2 {
            completed = Set(items.prefix(2).map { $0.id })
        }
    }

    private var esangFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("ESANG · DVIR PROMPTS · SLEEPER BAY 14 HELD · 34-HOUR")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
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

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }
}

struct ArrivalCheckpointScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ArrivalCheckpoint(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_047(),
                      trailing: driverNavTrailing_047(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_047() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_047() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("047 · Arrival Checkpoint · Dark") {
    ArrivalCheckpointScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("047 · Arrival Checkpoint · Light") {
    ArrivalCheckpointScreen(theme: Theme.light).preferredColorScheme(.light)
}
