//
//  048_ArrivalGateTaskActive.swift
//  EusoTrip — Lifecycle screen 048 · Arrival-Gate Task Active.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `048 Arrival-Gate Task Active.png`. Live walkaround task. Big
//  gradient elapsed timer + step indicator + product-aware rig
//  illustration (tanker / reefer / flatbed / box / chassis) +
//  current step copy + 3 telemetry tiles + walkaround gates list
//  + Help / Confirm step CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct ArrivalGateTaskActive: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverShowHelp) private var showHelp
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isConfirming: Bool = false

    /// Gates the driver has actually tapped complete. Completion comes
    /// ONLY from a driver tap (mirrors the merged 046 fix) — no row is
    /// seeded done, nothing auto-marks on appear.
    @State private var completed: Set<String> = []

    /// Device wall clock for the header timestamp — refreshed on appear.
    /// Never a seeded literal.
    @State private var nowDate = Date()

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    /// Universal em-dash sentinel — matches `LiveLoadFacets.dash`; used
    /// for the telemetry tiles, which have no live sensor feed.
    private let dash = LiveLoadFacets.dash

    private static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// Live device clock for the header, e.g. "22:58". Never seeded.
    private var nowClockText: String { Self.clock(nowDate) }

    /// "N OF M CONFIRMED" computed from the REAL tapped-row count —
    /// never a hardcoded full-count.
    private var stepIndexText: String {
        "\(completed.count) OF \(ctx.walkaroundGates.count) CONFIRMED"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                rigBanner
                currentStepCard
                telemetryRow
                gatesList
                esangFooter
                actions
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
                    Image(systemName: "doc.badge.gearshape.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("POST-TRIP DVIR · WALKAROUND ACTIVE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(stepHeading)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("\(ctx.headerKicker) · \(stepIndexText)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    // EUSOTRIP-MODE-BADGE-2026-05-17 — mode chip on lifecycle screen
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                // No live walkaround-elapsed timer source on this screen
                // (no per-task start timestamp is fed to the view), so the
                // hero shows the live device clock rather than a fabricated
                // "3:42" elapsed figure.
                Text(nowClockText)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("NOW")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    private var stepHeading: String {
        if ctx.isHazmat {
            return "Placards + ERG 125 copy under visor"
        }
        switch ctx.product {
        case .reefer:                       return "Reefer set-point + temp trace verified"
        case .flatbed:                      return "Securement returned · WLL audit"
        case .container, .railIntermodal,
             .vesselContainer:              return "Chassis ID + plate match logged"
        case .railBulk, .vesselBulk:        return "Waybill closed · grounding stowed"
        default:                            return "Trailer seal photo logged"
        }
    }

    /// Product-aware rig illustration. Drawn as simple SwiftUI
    /// shapes + an SF Symbol so it renders cleanly in dark + light
    /// without a custom asset for every product.
    private var rigBanner: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(rigLabel)
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
                    rigShape(in: geo.size)
                }
            }
            .frame(height: 110)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var rigLabel: String {
        switch ctx.product {
        case .hazmatTanker:                 return "MC-331 · SIDE L"
        case .vesselTanker:                 return "TANKER · BERTH SIDE"
        case .reefer:                       return "REEFER · DRIVER SIDE"
        case .flatbed:                      return "FLATBED · DECK SIDE"
        case .container, .vesselContainer:  return "CONTAINER · 53' BOX"
        case .railIntermodal:               return "INTERMODAL · CHASSIS"
        case .railBulk, .vesselBulk:        return "BULK TRAILER · SIDE"
        case .dryVan:                       return "53' VAN · SIDE L"
        }
    }

    /// Stylized rig per product. Each draws a tractor cab + a
    /// trailer silhouette appropriate to the product. Wheels are
    /// uniform circles; the trailer body and any product-specific
    /// detail (placard, snowflake, twistlocks, hatches) come from
    /// `productAccent()`.
    @ViewBuilder
    private func rigShape(in size: CGSize) -> some View {
        let cabH: CGFloat   = 26
        let trailerH: CGFloat = trailerHeight
        let trailerY: CGFloat = (size.height / 2) - (trailerH / 2)

        // Cab
        RoundedRectangle(cornerRadius: 4)
            .fill(palette.textSecondary)
            .frame(width: 38, height: cabH)
            .position(x: 32, y: size.height / 2)

        // Trailer body
        trailerBody(width: size.width - 90, height: trailerH)
            .position(x: 32 + 24 + (size.width - 90) / 2 - 2, y: size.height / 2)

        // Wheels
        ForEach([26, 60, size.width - 70, size.width - 50, size.width - 30], id: \.self) { x in
            Circle()
                .fill(palette.textPrimary)
                .frame(width: 10, height: 10)
                .position(x: x, y: size.height - 14)
        }

        // Product accent overlay
        productAccent(in: size, trailerY: trailerY, trailerH: trailerH)

        // Action arrow pointing at the focus area
        Image(systemName: "arrow.down")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(LinearGradient.diagonal)
            .position(x: size.width - 90, y: trailerY - 4)
    }

    private var trailerHeight: CGFloat {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker, .railBulk, .vesselBulk:
            return 28          // cylindrical tank silhouette (drawn as capsule)
        case .flatbed:
            return 8           // thin deck
        default:
            return 36          // box / reefer / chassis container
        }
    }

    @ViewBuilder
    private func trailerBody(width: CGFloat, height: CGFloat) -> some View {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker, .railBulk, .vesselBulk:
            Capsule()
                .fill(LinearGradient.diagonal)
                .frame(width: width, height: height)
        case .flatbed:
            RoundedRectangle(cornerRadius: 2)
                .fill(palette.textSecondary)
                .frame(width: width, height: height)
        default:
            RoundedRectangle(cornerRadius: 4)
                .fill(palette.textSecondary)
                .frame(width: width, height: height)
        }
    }

    @ViewBuilder
    private func productAccent(in size: CGSize, trailerY: CGFloat, trailerH: CGFloat) -> some View {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:
            // Diamond placard glow
            Image(systemName: "diamond.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Brand.warning)
                .position(x: size.width - 80, y: size.height / 2)
        case .reefer:
            // Snowflake
            Image(systemName: "snowflake")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
                .position(x: size.width - 80, y: size.height / 2 - 2)
        case .flatbed:
            // Strap dashes across deck
            ForEach([100, 140, 180, 220, 260], id: \.self) { x in
                Capsule()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 2, height: 14)
                    .position(x: x, y: size.height / 2 - 10)
            }
        case .container, .vesselContainer, .railIntermodal:
            // Twistlock dots at corners
            ForEach([60, size.width - 100], id: \.self) { x in
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 6, height: 6)
                    .position(x: x, y: trailerY + 4)
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 6, height: 6)
                    .position(x: x, y: trailerY + trailerH - 4)
            }
        case .railBulk, .vesselBulk:
            // Hatch dots on top
            ForEach([90, 140, 200, 250], id: \.self) { x in
                Circle()
                    .fill(Brand.warning)
                    .frame(width: 6, height: 6)
                    .position(x: x, y: trailerY - 2)
            }
        case .dryVan:
            // Seal indicator
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
                .position(x: size.width - 80, y: size.height / 2)
        }
    }

    private var currentStepCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CURRENT STEP")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(stepHeading)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(stepBody)
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Task copy for the current walkaround step. HONESTY: load facts
    /// (UN number, set-point, strap count) come from the live
    /// `LifecycleProductContext` facets — each is already em-dash when
    /// the backend hasn't shipped the column — never a seeded
    /// "UN1005" / "-18°F" / "12 straps". The instruction text names the
    /// task + governing standard, which is a fixed regulatory constant.
    private var stepBody: String {
        let f = ctx.facets
        if ctx.isHazmat {
            return "Verify all four sides show the placard for \(f.commodityWithUN) (hazard class \(f.hazardClass)). Confirm the ERG 125 copy is legible and pinned under the driver-side visor. Photograph each side on tap. ESANG archives to the DVIR sheet."
        }
        switch ctx.product {
        case .reefer:
            return "Confirm reefer set-point reads \(f.setPointDisplay), return-air within spec. Pull thermograph trace and stamp into BOL. Photograph the cold-seal before breaking it."
        case .flatbed:
            return "Walk the deck, account for all securement (\(f.securementSummary)). Audit working load + return securement to crib. Photograph deck condition for DVIR."
        case .container, .railIntermodal, .vesselContainer:
            return "Photograph container ID (\(f.containerNumber)) + chassis plate (\(f.chassisNumber)). Check twistlocks closed, gladhands stowed, lights working. EDI 322 ready to fire on gate-out."
        case .railBulk, .vesselBulk:
            return "Hatches sealed, grounding rod stowed, ohms cap recorded. Sign + close AAR waybill (\(f.waybillRegistry)). Photograph trailer for DVIR."
        default:
            return "Photograph driver-side seal in place + log seal number (\(f.sealNumber)). Sweep trailer interior dry. Close + lock both rear doors."
        }
    }

    private var telemetryRow: some View {
        // HONESTY: there is NO live sensor feed wired to this screen, so
        // every reading collapses to the em-dash sentinel. The sub lines
        // stay as the metric's spec/limit (a regulatory constant, not a
        // fabricated reading) — mirrors LifecycleProductContext.loadingMetrics.
        HStack(spacing: Space.s2) {
            telemetry(label: "AIR-LOSS", primary: dash, sub: "1 PSI / 2 MIN")
            telemetry(label: "TIRES", primary: dash, sub: "4-6/32\" TREAD")
            telemetry(label: "LIGHTS", primary: dash, sub: "MARKER + TURN")
        }
    }

    private func telemetry(label: String, primary: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(primary)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            Text(sub)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
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

    private var gatesList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WALKAROUND GATES")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            // HONESTY (mirrors merged 046 fix): rows start UNCHECKED. The
            // green checkmark + "VERIFIED" badge gate ONLY on actual driver
            // completion (the `completed` set), NEVER on the row's tail
            // string. The placards/seal/securement row ships with a "VERIFY"
            // tail (an outstanding task) and must NOT render green until the
            // driver taps it. Tail shows the task's pending verb otherwise.
            ForEach(ctx.walkaroundGates) { row in
                let done = completed.contains(row.id)
                Button {
                    if done { completed.remove(row.id) } else { completed.insert(row.id) }
                } label: {
                    HStack(spacing: Space.s3) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(done ? Brand.success : palette.textTertiary)
                        Text(row.title)
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(done ? palette.textPrimary : palette.textSecondary)
                        Spacer()
                        Text(done ? "VERIFIED" : row.tail)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(done ? Brand.success : palette.textTertiary)
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
                .buttonStyle(.plain)
            }
        }
    }

    private var esangFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            // HONESTY: no live yardManagement source feeds a sleeper-bay
            // assignment or breakfast-slot to this screen, so the copy
            // states the universal post-trip outcome (DVIR submit → reset
            // begins) without a fabricated "BAY 14" / "06:30" number.
            Text("ESANG · SUBMIT DVIR UNLOCKS YOUR SLEEPER BAY · 34-HOUR RESET BEGINS")
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

    private var actions: some View {
        HStack(spacing: Space.s3) {
            Button { showHelp?("arrival-gate-task") } label: {
                Text("Need help?")
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
            .accessibilityLabel("Open ESANG help for arrival-gate task")
            CTAButton(
                title: confirmCta,
                action: { Task { await confirmStep() } },
                leadingIcon: "checkmark.circle.fill",
                isLoading: isConfirming
            )
        }
    }

    private var confirmCta: String {
        if ctx.isHazmat { return "Confirm placards OK" }
        switch ctx.product {
        case .reefer:                       return "Confirm reefer OK"
        case .flatbed:                      return "Confirm securement"
        case .container, .railIntermodal,
             .vesselContainer:              return "Confirm chassis OK"
        case .railBulk, .vesselBulk:        return "Confirm grounding stowed"
        default:                            return "Confirm seal OK"
        }
    }

    private func hydrateLiveTrip() async {
        nowDate = Date()
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func confirmStep() async {
        isConfirming = true
        defer { isConfirming = false }
        let keys = ["dvir_review", "task_result", "submit"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct ArrivalGateTaskActiveScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ArrivalGateTaskActive(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_048(),
                      trailing: driverNavTrailing_048(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_048() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_048() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("048 · Arrival-Gate Task Active · Dark") {
    ArrivalGateTaskActiveScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("048 · Arrival-Gate Task Active · Light") {
    ArrivalGateTaskActiveScreen(theme: Theme.light).preferredColorScheme(.light)
}
