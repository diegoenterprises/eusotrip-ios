//
//  046_SequencedLegApproach.swift
//  EusoTrip — Lifecycle screen 046 · Sequenced Leg Approach.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `046 Sequenced Leg Approach.png`. Driver is approaching the
//  Catalyst home yard. Surfaces miles + ETA hero, leg-handoff
//  card (closed leg → open off-duty), driver-yard facts, and a
//  4-row product-aware yard-in checklist.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct SequencedLegApproach: View {
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

    private let fallbackClock      = "22:58"
    private let fallbackHero       = "5.4"
    private let fallbackEtaMin     = "16 min"
    private let fallbackArriveBy   = "23:14"
    private let fallbackYard       = "—"
    private let fallbackYardAddr   = "3608 HAWKINS POINT RD · BALTIMORE MD 21226"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                heroCard
                legHandoff
                yardCard
                yardChecklist
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
                    Text("APPROACHING HOME YARD · DEADHEAD")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Arriving at Curtis Bay yard by \(fallbackArriveBy)")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("\(ctx.headerKicker) · 1/1 DAY DONE")
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

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(fallbackHero)
                    .font(.system(size: 50, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("mi")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("· \(fallbackEtaMin)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 4)
                    HStack(spacing: 4) {
                        ForEach(0..<22, id: \.self) { _ in
                            Circle().fill(LinearGradient.diagonal).frame(width: 4, height: 4)
                        }
                    }
                }
                .frame(height: 8)
            }
            .frame(height: 8)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var legHandoff: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            handoffBlock(state: "CLOSED · LEG 1", title: closedLegTitle, sub: "78 mi · 0.3 defect alerts en route", color: Brand.success)
            handoffBlock(state: "OPEN · POST-TRIP DVIR", title: "34-hour reset begins", sub: "Cycle resets 49 CFR 395.3(c) · MC-331", color: Brand.warning)
        }
    }

    private var closedLegTitle: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:  return "NH3 · Baltimore → York PA"
        case .reefer:                       return "Cold · Baltimore → York PA"
        case .flatbed:                      return "Flatbed · Baltimore → York PA"
        case .container, .railIntermodal:   return "Container · Baltimore → York PA"
        case .vesselContainer:              return "Vessel box · Baltimore → York PA"
        case .railBulk, .vesselBulk:        return "Bulk · Baltimore → York PA"
        case .dryVan:                       return "Dry · Baltimore → York PA"
        }
    }

    private func handoffBlock(state: String, title: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(color)
            Text(title)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
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
                yardCell(label: "ENTRY",         value: "Gate C (badge)")
                yardCell(label: "ASSIGNED SPOT", value: "Row 4 · S-14")
                yardCell(label: "PARKED",        value: "Bay 14 · shower + laundry")
                yardCell(label: "SLEEPER BAY",   value: "24/7 · lane 2")
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

    private var yardChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YARD-IN CHECKLIST")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            ForEach(ctx.yardInChecklist) { row in
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
                        Text(completed.contains(row.id) ? "VERIFIED" : row.tail)
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
        let items = ctx.yardInChecklist
        if items.count >= 3 {
            completed = Set(items.prefix(3).map { $0.id })
        }
    }

    private var esangFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("ESANG · SHOWER + BUNK QUEUED · WEATHER CALM · I'LL WAKE")
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

struct SequencedLegApproachScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            SequencedLegApproach(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_046(),
                      trailing: driverNavTrailing_046(),
                      orbState: .idle)
        }
    }
}

// PNG canon at `01 Driver/{Light,Dark}/046 Sequenced Leg Approach.png`
// pins TRIPS current — sequenced load 2 of 2 approaching Buckeye
// Malvern with leg-handoff card (closed Leg 1 / open Leg 2) +
// pre-rack checks. Icon set + trailing slot normalized to canonical
// 010-045 layout.
private func driverNavLeading_046() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: true)]
}
private func driverNavTrailing_046() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

#Preview("046 · Sequenced Leg Approach · Dark") {
    SequencedLegApproachScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("046 · Sequenced Leg Approach · Light") {
    SequencedLegApproachScreen(theme: Theme.light).preferredColorScheme(.light)
}
