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

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private let fallbackClock     = "23:19"
    private let fallbackElapsed   = "3:42"
    private let fallbackStepIndex = "STEP 3 OF 4"

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
                Text("\(ctx.headerKicker) · \(fallbackStepIndex)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(fallbackElapsed)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("ELAPSED")
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

    private var stepBody: String {
        if ctx.isHazmat {
            return "Verify all four sides show the UN1005 ammonia placard (non-flammable gas — green). Confirm the ERG 125 copy is legible and pinned under the driver-side visor. Photograph each side on tap — ESANG archives to the DVIR sheet."
        }
        switch ctx.product {
        case .reefer:
            return "Confirm reefer set-point reads −18°F, return-air within 1°. Pull thermograph trace and stamp into BOL. Photograph the cold-seal before breaking it."
        case .flatbed:
            return "Walk the deck, account for all 12 straps + 2 chains. Audit working load + return securement to crib. Photograph deck condition for DVIR."
        case .container, .railIntermodal, .vesselContainer:
            return "Photograph container ID + chassis plate. Check twistlocks closed, gladhands stowed, lights working. EDI 322 ready to fire on gate-out."
        case .railBulk, .vesselBulk:
            return "Hatches sealed, grounding rod stowed, ohms cap recorded. Sign + close AAR waybill. Photograph trailer for DVIR."
        default:
            return "Photograph driver-side seal in place + log seal number. Sweep trailer interior dry. Close + lock both rear doors."
        }
    }

    private var telemetryRow: some View {
        HStack(spacing: Space.s2) {
            telemetry(label: "AIR-LOSS", primary: "0.8", sub: "1 PSI / 2 MIN")
            telemetry(label: "TIRES", primary: "10/10", sub: "4-6/32\" TREAD")
            telemetry(label: "LIGHTS", primary: "22/22", sub: "MARKER + TURN")
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
            ForEach(ctx.walkaroundGates) { row in
                HStack(spacing: Space.s3) {
                    Image(systemName: row.tail == "PENDING" ? "circle" : "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(row.tail == "PENDING" ? palette.textTertiary : Brand.success)
                    Text(row.title)
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(row.tail == "PENDING" ? palette.textSecondary : palette.textPrimary)
                    Spacer()
                    Text(row.tail)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(row.tail == "PENDING" ? palette.textTertiary : palette.textSecondary)
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

    private var esangFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("ESANG · SUBMIT UNLOCKS BAY 14 · 34-HOUR RESET STARTS · BREAKFAST 06:30 SLOT MGR")
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
