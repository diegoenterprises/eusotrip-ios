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

    /// Device wall clock for the header / on-site timestamps — refreshed
    /// on appear. Never a seeded literal.
    @State private var nowDate = Date()

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// Honest em-dash for any field with no live source.
    private let dash = "—"

    // MARK: - Live data bindings (honest em-dash when no source)

    /// Header / on-site "now" clock — live device wall time.
    private var nowClockText: String { Self.clock(nowDate) }

    /// True only when the load's own status says the rig has reached
    /// the delivery/terminal. Gates the green "ARRIVED" chip; never
    /// asserted unconditionally.
    private var hasArrived: Bool {
        guard let s = activeLoad?.status.lowercased() else { return false }
        return ["at_delivery", "unloading", "delivered"].contains(s)
    }

    /// Home-yard name — the delivery/terminal facility city+state on the
    /// load, else em-dash. No fabricated yard name.
    private var yardName: String {
        let cs = activeLoad?.deliveryLocation?.cityState ?? ""
        return cs.isEmpty ? dash : cs
    }

    /// Home-yard address composed from the delivery location, else
    /// em-dash. No fabricated street literal.
    private var yardAddress: String {
        guard let loc = activeLoad?.deliveryLocation else { return dash }
        var parts: [String] = []
        if !loc.address.isEmpty { parts.append(loc.address.uppercased()) }
        if !loc.city.isEmpty    { parts.append(loc.city.uppercased()) }
        if !loc.state.isEmpty   { parts.append(loc.state.uppercased()) }
        if !loc.zipCode.isEmpty { parts.append(loc.zipCode) }
        return parts.isEmpty ? dash : parts.joined(separator: " · ")
    }

    /// First letter of the home-yard city for the avatar monogram,
    /// else a neutral dot. Never a hardcoded "C".
    private var yardMonogram: String {
        if let c = activeLoad?.deliveryLocation?.city.first { return String(c).uppercased() }
        return "·"
    }

    /// Closed-leg distance sub-line — the load's own routed distance
    /// when the wire carries it, else em-dash. No fabricated mileage
    /// and no fabricated defect count.
    private var closedLegSub: String {
        guard let raw = activeLoad?.distance, let d = Double(raw), d > 0 else { return dash }
        let unit = (activeLoad?.distanceUnit ?? "mi").lowercased()
        let suffix = unit.contains("km") ? "km" : "mi"
        return String(format: "%.0f %@", d, suffix)
    }

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
        .eusoRefreshTask {
            await hydrateLiveTrip()
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
            Text(nowClockText)
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
                // Green "ARRIVED" chip only when the load status actually
                // says the rig reached the delivery/terminal; otherwise a
                // neutral "EN ROUTE" chip. Never asserted unconditionally.
                Text(hasArrived ? "ARRIVED" : "EN ROUTE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(hasArrived ? Brand.success : palette.textTertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().stroke((hasArrived ? Brand.success : palette.textTertiary).opacity(0.5), lineWidth: 1))
            }
            HStack(alignment: .firstTextBaseline) {
                // On-site elapsed timer has no live source — em-dash.
                Text(dash)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("on site")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("@ \(nowClockText)")
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
            }
            // Parked spot has no wired yard-management source — em-dash.
            Text("Parked at \(dash)")
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
                checkpointCol(state: "CLOSED · DEADHEAD", title: deadheadTitle, sub: closedLegSub, color: Brand.success)
                checkpointCol(state: "OPEN · POST-TRIP DVIR", title: openLegTitle, sub: "49 CFR 396.11 · MC-331 + tractor", color: Brand.warning)
            }
        }
    }

    /// Closed-deadhead title — the real pickup→delivery city pair from
    /// the active load, prefixed by the product-aware return word. No
    /// fabricated mileage or endpoints; em-dash when no load lane.
    private var deadheadTitle: String {
        let origin = activeLoad?.pickupLocation?.cityState ?? ""
        let dest   = activeLoad?.deliveryLocation?.cityState ?? ""
        let lane: String
        if !origin.isEmpty && !dest.isEmpty { lane = "\(origin) → \(dest)" }
        else if !dest.isEmpty               { lane = "→ \(dest)" }
        else if !origin.isEmpty             { lane = origin }
        else                                { return dash }
        return "\(deadheadWord) \(lane)"
    }

    /// Product-aware word for the closed-deadhead return leg.
    private var deadheadWord: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:  return "Tanker return"
        case .reefer:                       return "Cold return"
        case .flatbed:                      return "Flatbed return"
        case .container, .railIntermodal:   return "Chassis return"
        case .vesselContainer:              return "Box return"
        case .railBulk, .vesselBulk:        return "Bulk return"
        case .dryVan:                       return "Return"
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
                    Text(yardMonogram).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(yardName)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(yardAddress)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            // No wired yard-management source — gate/row/spot/timer render
            // an honest em-dash rather than a fabricated assignment.
            HStack(spacing: Space.s2) {
                yardCell(label: "ENTRY",     value: dash)
                yardCell(label: "PARKED",    value: dash)
                yardCell(label: "GYM TIMER", value: dash)
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
        nowDate = Date()
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
    RoleNav.driverLeading(current: .trips)
}
private func driverNavTrailing_047() -> [NavSlot] {
    RoleNav.driverTrailing(current: .none)
}

#Preview("047 · Arrival Checkpoint · Dark") {
    ArrivalCheckpointScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("047 · Arrival Checkpoint · Light") {
    ArrivalCheckpointScreen(theme: Theme.light).preferredColorScheme(.light)
}
