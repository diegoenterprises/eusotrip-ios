//
//  049_TaskResult.swift
//  EusoTrip — Lifecycle screen 049 · Task Result.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `049 Task Result.png`. Walkaround DVIR closed; PASS verdict +
//  big telemetry (air-loss / tires / lights), 4-row findings list
//  (each row product-aware), carrier-ops banner, signature row,
//  and View sheet / Submit DVIR CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct TaskResult: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isSubmitting: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private let fallbackClock = "23:28"
    private let fallbackElapsed = "3:51"
    private let fallbackAirLoss = "0.8"
    private let fallbackTires   = "10/10"
    private let fallbackLights  = "21/22"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                heroCard
                metricRow
                findingsList
                carrierBanner
                signatureRow
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
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Brand.success)
                    Text("POST-TRIP DVIR · WALKAROUND CLOSED")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.success)
                }
                Text(closedTitle)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("\(ctx.headerKicker) · \(fallbackElapsed) walkaround elapsed")
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

    private var closedTitle: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:  return "MC-331 + tractor · 49 CFR 396.11"
        case .reefer:                       return "Reefer + tractor · 49 CFR 396.11"
        case .flatbed:                      return "Flatbed + tractor · 49 CFR 396.11"
        case .container, .railIntermodal,
             .vesselContainer:              return "Chassis + tractor · 49 CFR 396.11"
        case .railBulk, .vesselBulk:        return "Bulk trailer + tractor · 49 CFR 396.11"
        case .dryVan:                       return "Van + tractor · 49 CFR 396.11"
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(fallbackAirLoss)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text("PSI / 2 MIN AIR-LOSS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("PASS")
                    .font(.system(size: 12, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            Text("\(fallbackElapsed) walkaround elapsed · all gates verified")
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

    private var metricRow: some View {
        HStack(spacing: Space.s2) {
            metric(label: "AIR-LOSS", value: fallbackAirLoss, sub: "0.5 PSI ORT")
            metric(label: "TIRES",    value: fallbackTires,   sub: "4-6/32\" TREAD")
            metric(label: "LIGHTS",   value: fallbackLights,  sub: "1 MINOR FLAGGED")
        }
    }

    private func metric(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
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

    private var findingsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("FINDINGS · 4 ITEMS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("BRAKES · LIGHTS · TIRES · COUPLER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textSecondary)
            }
            findingRow(title: "Tractor walkaround",                          right: "PASS",   color: Brand.success)
            findingRow(title: trailerSweepTitle,                              right: "0 ppm · PASS", color: Brand.success)
            findingRow(title: placardsRowTitle,                               right: "4/4 · PASS",   color: Brand.success)
            findingRow(title: "Trailer ID light #3 flicker",                  right: "30 day · DEFER", color: Brand.warning, sub: "NOT SAFETY-CRITICAL · WORK ORDER MD-X-4419")
        }
    }

    private var trailerSweepTitle: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:  return "MC-331 trailer sweep · Spectra residual"
        case .reefer:                       return "Reefer set-point + thermograph clean"
        case .flatbed:                      return "Flatbed deck sweep · securement returned"
        case .container, .railIntermodal,
             .vesselContainer:              return "Chassis sweep · twistlocks oiled"
        case .railBulk, .vesselBulk:        return "Bulk trailer sweep · grounding stowed"
        case .dryVan:                       return "Trailer sweep · seal logged"
        }
    }

    private var placardsRowTitle: String {
        if ctx.isHazmat { return "Placards + ERG 125 copy" }
        switch ctx.product {
        case .reefer:                       return "Cold-seal photo logged"
        case .flatbed:                      return "Securement WLL audit"
        case .container, .railIntermodal,
             .vesselContainer:              return "Chassis ID + plate match"
        case .railBulk, .vesselBulk:        return "Waybill + grounding ohms log"
        default:                            return "Trailer seal photo logged"
        }
    }

    private func findingRow(title: String, right: String, color: Color, sub: String? = nil) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                if let sub {
                    Text(sub)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
            Text(right)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(color)
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

    private var carrierBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.textTertiary)
            Text("CARRIER OPS · BALTIMORE · OPS WATCHING GATE CLOSE · RESET CLOCK STARTS ON SUBMISSION")
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var signatureRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Text("ME").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Michael Eusorone")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("CDL-A · HAZMAT N+H+T · TWIC #4419")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text("23:28 ET · tap to sign")
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(LinearGradient.diagonal)
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
            // "View sheet" — secondary CTA. Opens the driver's DVIR
            // history surface (Me > Zeun Mechanics > DVIR), which is
            // where the just-submitted inspection lives once the
            // backend fans LOAD_STATE_CHANGED. Fires through the
            // canonical `esangOpenMeDetail` route so the navigator,
            // analytics, and ESANG voice all route consistently.
            // Also emits a MeAction so the audit trail captures the
            // CTA tap (no silent no-op per the no-dead-buttons rule).
            Button { openInspectionSheet() } label: {
                Text("View sheet")
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
                title: "Submit DVIR",
                action: { Task { await submit() } },
                trailingIcon: "arrow.right",
                isLoading: isSubmitting
            )
        }
    }

    private func openInspectionSheet() {
        MeAction.fire("049.view-inspection-sheet",
                      userInfo: ["loadId": lifecycle.loadId])
        NotificationCenter.default.post(
            name: .esangOpenMeDetail,
            object: "dvir",
            userInfo: ["loadId": lifecycle.loadId]
        )
        // Pop back so the Me sheet has a clean place to land instead of
        // stacking on top of the post-trip surface.
        navBack?()
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let keys = ["next_beat_live", "off_duty", "completed"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct TaskResultScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            TaskResult(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_049(),
                      trailing: driverNavTrailing_049(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_049() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_049() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("049 · Task Result · Dark") {
    TaskResultScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("049 · Task Result · Light") {
    TaskResultScreen(theme: Theme.light).preferredColorScheme(.light)
}
