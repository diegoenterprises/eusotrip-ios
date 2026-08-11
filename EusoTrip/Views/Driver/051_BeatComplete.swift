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
//  ── Honest-binding pass (zero fabrication) ───────────────────────
//  • HOS hero line + HOS status tile bind to the live `hos.getStatus`
//    snapshot (drivingRemaining / onDutyRemaining / cycleRemaining
//    hours). The previous hard-coded "0/11/14" / "HOS 0/11/14" was a
//    fabrication and is gone — em-dash until the snapshot lands.
//  • Lane + Load ID bind to `loads.getById` decoded with the CORRECTED
//    wire shape proven in DL133/DL126: top-level `id: String?` (server
//    sends `String(load.id)`; decoding as Int throws typeMismatch and
//    blanks the whole screen) + nested {city,state} pickup/delivery
//    objects (NOT flat) + real driver/catalyst/shipper PARTY objects.
//    The old fixture switch leaked third-party customer brand
//    identifiers (a distributor → fertilizer-plant lane) into the
//    production path; that ledger-hygiene violation is removed.
//  • Weather + Fuel have no live source → honest em-dash, never faked.
//  • Every prior `?? <invented literal>` (EUSO-load#, 42°F, 92%) and
//    every hardcoded persona is dropped; values with no live source
//    render "-"/"—".
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
    @State private var loadCtx: BCLoadCtx?
    @State private var hos: HOSStatus?
    @State private var isStartingPrehaul: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .afternoon) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Corrected `loads.getById` decode shape
    //
    // Proven in DL133_DriverCELM04DVIRContinuationOctet /
    // DL126_DriverCELM04Septet. The server serializes `id` as
    // `String(load.id)` and `distance` as a Number; `pickupLocation` /
    // `deliveryLocation` are nested {city,state} objects (the server
    // sends "" — not nil — when a piece is missing); driver / catalyst
    // / shipper are PARTY objects carrying the human-readable carrier /
    // driver names. Decoding the top-level id as Int throws typeMismatch
    // and fails the WHOLE decode → blank screen.
    struct BCLoadCtx: Decodable, Hashable {
        let id: String?              // String on the wire (String(load.id))
        let loadNumber: String?
        let pickupLocation: BCLoc?   // nested {city,state}, NOT flat
        let deliveryLocation: BCLoc?
        let rate: String?            // DECIMAL → String on the wire
        let distance: Double?        // resolved Number on the wire
        let equipmentType: String?
        let driver: BCParty?
        let catalyst: BCParty?
        let shipper: BCParty?
        struct BCLoc: Decodable, Hashable {
            let city: String?
            let state: String?
        }
        struct BCParty: Decodable, Hashable {
            let id: Int?             // party (user/company) id is numeric
            let name: String?
            let initials: String?
            let companyName: String?
            let mcNumber: String?
            let dotNumber: String?
        }
    }

    // MARK: - Honest display constants
    //
    // The morning hero copy is register-flavor chrome, not load data —
    // it carries no fabricated business value. Anything that *would* be
    // a load- or telemetry-derived value (clock, off-duty total, HOS,
    // weather, fuel, lane, load#, depart, ETA) resolves live below and
    // collapses to an honest em-dash when no source has shipped.
    private let emDash = "—"
    private let dash   = "-"

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
                    Text("RESET RETURNED")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
            }
            Spacer(minLength: 0)
            // No live wall-clock telemetry source on this surface — the
            // duty clock comes from HOS below, not a fabricated string.
            Text(emDash)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    // The big hero number is the driver's remaining 70/8-day cycle from
    // the live HOS snapshot — the clearest "you have a fresh reset"
    // signal — rendered em-dash until the snapshot lands. The previous
    // "34:00" + "HOS 0/11/14" pair was hand-typed and is removed.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(hos?.cycleRemainingDisplay ?? emDash)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("cycle left · \(hosLineDisplay)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                if let h = hos, h.canDrive {
                    Text("RESET COMPLETE")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.success)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
                }
            }
            Text("Beat complete")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(heroSubline)
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

    /// "drive 7h 22m · on-duty 11h 48m" from the live snapshot; em-dash
    /// until `hos.getStatus` lands.
    private var hosLineDisplay: String {
        guard let h = hos else { return emDash }
        return "drive \(h.drivingRemainingDisplay) · on-duty \(h.onDutyRemainingDisplay)"
    }

    /// Honest hero subline: leads with the live lane when present,
    /// otherwise the next queued action — never a fabricated weather or
    /// depart-time string.
    private var heroSubline: String {
        if let lane = laneDisplay { return "Next tender · \(lane)" }
        return "Next tender waiting · pre-trip checklist loads on tap"
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
                Text("Day plan · \(loadNumberDisplay)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("ACCEPTED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
            }
            Text("LEG 1 OF 1 · \(laneDisplay ?? emDash)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                planRow(label: "COMMODITY",   value: ctx.beatCommodityDescriptor)
                planRow(label: "CARRIER",      value: carrierDisplay)
                planRow(label: "DISTANCE",     value: distanceDisplay)
                planRow(label: "LOAD ID",      value: loadNumberDisplay)
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

    // MARK: - Live display helpers (honest em-dash fallback)

    /// Server sends "" (not nil) for missing city/state pieces, so the
    /// compactMap filters empties before joining. Nested {city,state}
    /// per the corrected getById shape — never the old fixture switch.
    private var laneDisplay: String? {
        let o = [loadCtx?.pickupLocation?.city, loadCtx?.pickupLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        let d = [loadCtx?.deliveryLocation?.city, loadCtx?.deliveryLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        guard !o.isEmpty || !d.isEmpty else { return nil }
        return "\(o.isEmpty ? emDash : o) → \(d.isEmpty ? emDash : d)"
    }

    private var loadNumberDisplay: String { loadCtx?.loadNumber ?? dash }

    /// Carrier-of-record from the live catalyst PARTY object.
    private var carrierDisplay: String {
        loadCtx?.catalyst?.companyName ?? loadCtx?.catalyst?.name ?? dash
    }

    /// "620 mi" from the live `distance` Double; em-dash when missing.
    private var distanceDisplay: String {
        guard let d = loadCtx?.distance, d > 0 else { return emDash }
        return "\(Int(d.rounded())) mi"
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

    // HOS tile binds the live drive/on-duty/cycle remaining hours.
    // Weather + Fuel have no telemetry source on this surface → honest
    // em-dash (never the old "42°F" / "92%" fabrications).
    private var statusTiles: some View {
        HStack(spacing: Space.s2) {
            tile(label: "HOS",
                 primary: hos.map { "\($0.drivingRemainingDisplay)" } ?? emDash,
                 sub: hos != nil ? "DRIVE REMAINING" : "AWAITING ELD")
            tile(label: "WEATHER", primary: emDash, sub: "NO SOURCE")
            tile(label: "FUEL",    primary: emDash, sub: "NO SOURCE")
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
            Text("ESANG · NEXT TENDER QUEUED · PRE-TRIP CHECKLIST LOADS ON TAP")
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

        // Live HOS snapshot — drives the hero cycle number + HOS tile.
        hos = try? await EusoTripAPI.shared.hos.getStatus()

        guard !lifecycle.loadId.isEmpty else { return }

        // Legacy `Load` record powers the LifecycleProductContext
        // (commodity descriptor + beat queue), which already routes
        // every per-load segment through honest em-dash facets.
        if let n = Int(lifecycle.loadId) {
            activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
        }

        // Lane + load# + carrier name decode with the CORRECTED shape:
        // top-level id String?, nested {city,state}, party objects. The
        // server's Zod input is `{ id: string }`.
        struct In: Encodable { let id: String }
        loadCtx = try? await EusoTripAPI.shared.query(
            "loads.getById", input: In(id: lifecycle.loadId)
        )
    }

    private func startPretrip() async {
        isStartingPrehaul = true
        defer { isStartingPrehaul = false }
        // The driver is starting the pre-trip now, so the 10-minute nudge is
        // about a thing that has already happened. Cancel it — a reminder that
        // outlives its obligation is a lie with a timer on it. This is the
        // cancellation that never existed: removePendingNotificationRequests
        // had zero call sites anywhere in the app.
        ReminderScheduler.cancel(kind: "pretrip", subject: String(lifecycle.loadId))
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
        // Deterministic id keyed on the load: snoozing twice replaces rather
        // than stacks, and starting the pre-trip can cancel it. The previous
        // identifier embedded a timestamp, so the request could never be named
        // again and the nudge fired even after the driver had already begun.
        ReminderScheduler.schedule(
            kind: "pretrip",
            subject: String(lifecycle.loadId),
            title: "Pre-trip nudge",
            body: "10-minute snooze is up. Ready to start your pre-trip?",
            after: 10 * 60,
            category: "load_update",
            userInfo: ["loadId": lifecycle.loadId, "route": "eld"]
        )
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
    RoleNav.driverLeading(current: .trips)
}
private func driverNavTrailing_051() -> [NavSlot] {
    RoleNav.driverTrailing(current: .none)
}

#Preview("051 · Beat Complete · Dark") {
    BeatCompleteScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("051 · Beat Complete · Light") {
    BeatCompleteScreen(theme: Theme.light).preferredColorScheme(.light)
}
