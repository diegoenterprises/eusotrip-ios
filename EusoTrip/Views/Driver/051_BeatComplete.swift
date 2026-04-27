//
//  051_BeatComplete.swift
//  EusoTrip — Lifecycle screen 051 · Beat Complete (final pivot).
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `051 Beat Complete.png`. The 34-hour off-duty reset has
//  returned. Big morning hero + reset-complete chip + day plan
//  card with product-aware commodity descriptor + 3 status tiles
//  (HOS / weather / fuel) + 3-row product-aware queued list +
//  ESANG voice strip + Snooze / Start pre-trip CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import UserNotifications

struct BeatComplete: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isStartingPrehaul: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .afternoon) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private let fallbackClock        = "09:30"
    private let fallbackOffDutyTotal = "34:00"
    private let fallbackHosLine      = "HOS 0/11/14"
    private let fallbackGreeting     = "—"
    private let fallbackCadence      = "New tender waiting · depart 10:15 · weather 42°F scattered"
    private let fallbackDate         = "2026-04-19"
    private let fallbackDepart       = "10:15 from yard"
    private let fallbackEta          = "—"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                heroCard
                dayPlanCard
                statusTiles
                queuedList
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
                    Text("SUNDAY · RESET RETURNED")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
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
            HStack {
                Text(fallbackOffDutyTotal)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("off-duty · \(fallbackHosLine)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("RESET COMPLETE")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
            }
            Text(fallbackGreeting)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(fallbackCadence)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var dayPlanCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                    Image(systemName: "house.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("Day plan · \(fallbackDate)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("ACCEPTED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
            }
            Text("LEG 1 OF 1 · \(legLabel)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                planRow(label: "COMMODITY",   value: ctx.beatCommodityDescriptor)
                planRow(label: "DEPART",      value: fallbackDepart)
                planRow(label: "ETA RECEIVER", value: fallbackEta)
                planRow(label: "LOAD ID",     value: activeLoad?.loadNumber ?? "EUSO-2026-04-19-004640")
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // M2 doctrine — em-dash sentinel until LifecycleProductContext exposes
    // `pickupOriginLabel` / `dropoffDestinationLabel` from the live Load record.
    // The previous fixture switch leaked customer brand identifiers (Walmart,
    // Univar, Yara, Curtis Bay, etc.) into the production-path UI, which is a
    // ledger-hygiene violation. We render "—" for the Walmart-specific cases
    // (.reefer, .dryVan) per the 111th firing's deferred-low-risk recommendation;
    // the remaining vertical fixtures stay until the broader LifecycleProductContext
    // rewrite (pending; see 111th firing report Branch C / explicit non-recommendation).
    private var legLabel: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:  return "Univar Curtis Bay → Yara York"
        case .reefer:                       return "—"
        case .flatbed:                      return "Birmingham Steel → Houston yard"
        case .container, .vesselContainer:  return "Curtis Bay port → Norfolk ramp"
        case .railIntermodal:               return "Ramp → Curtis Bay port"
        case .railBulk, .vesselBulk:        return "Spur 3 → Texas City"
        case .dryVan:                       return "—"
        }
    }

    private func planRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 6)
    }

    private var statusTiles: some View {
        HStack(spacing: Space.s2) {
            tile(label: "HOS", primary: "0/11/14",  sub: "FRESH · RESET ON 0")
            tile(label: "WEATHER", primary: "42°F", sub: "SCATTERED SHOWERS")
            tile(label: "FUEL",   primary: "92%",   sub: "TOPPED SAT NIGHT")
        }
    }

    private func tile(label: String, primary: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(primary)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            Text(sub)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
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

    private var queuedList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("QUEUED FOR THIS BEAT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            ForEach(ctx.beatQueue) { row in
                HStack(spacing: Space.s3) {
                    Image(systemName: "circle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text(row.subtitle)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(row.tail)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
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
            Text("ESANG · TENDER IS HOT · I PULLED ROUTES + WEATHER · PRE-TRIP CHECKLIST LOADED ON TAP")
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
            Spacer()
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
            Button { snooze10Min() } label: {
                Text("Snooze 10 min")
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
                title: "Start pre-trip",
                action: { Task { await startPretrip() } },
                trailingIcon: "arrow.right",
                isLoading: isStartingPrehaul
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func startPretrip() async {
        isStartingPrehaul = true
        defer { isStartingPrehaul = false }
        let keys = ["pretrip", "approach", "assigned"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }

    /// Schedules a local push 10 minutes out as the pre-trip nudge,
    /// then drops the driver back to the prior surface so they aren't
    /// stuck on this screen waiting. The notification fires through
    /// `UNUserNotificationCenter` so it reliably surfaces even when the
    /// app is backgrounded — which is the whole point of "snooze."
    /// Reuses the canonical Me-action so analytics + audit capture
    /// every snooze press.
    private func snooze10Min() {
        MeAction.fire("051.snooze-10min",
                      userInfo: ["loadId": lifecycle.loadId])
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            // Skip the schedule call entirely if the driver hasn't
            // granted notification permission — there's no graceful
            // fallback besides "we asked but they said no", and we
            // don't want to nudge the system permission UI from a
            // mid-trip CTA. The audit trail still recorded the tap.
            guard settings.authorizationStatus == .authorized
                  || settings.authorizationStatus == .provisional else {
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Pre-trip nudge"
            content.body  = "10-minute snooze is up. Ready to start your pre-trip?"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)
            let req = UNNotificationRequest(
                identifier: "eusotrip.051.snooze.\(Int(Date().timeIntervalSince1970))",
                content: content,
                trigger: trigger
            )
            center.add(req) { _ in }
        }
        navBack?()
    }
}

struct BeatCompleteScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            BeatComplete(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_051(),
                      trailing: driverNavTrailing_051(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_051() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_051() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("051 · Beat Complete · Dark") {
    BeatCompleteScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("051 · Beat Complete · Light") {
    BeatCompleteScreen(theme: Theme.light).preferredColorScheme(.light)
}
