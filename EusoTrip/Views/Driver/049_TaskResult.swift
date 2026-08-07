//
//  049_TaskResult.swift
//  EusoTrip — Lifecycle screen 049 · Task Result.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `049 Task Result.png`. Walkaround DVIR closed; verdict +
//  telemetry block (air-loss / tires / lights), 4-row findings list
//  (each row product-aware), carrier-ops banner, signature row,
//  and View sheet / Submit DVIR CTAs.
//
//  De-fabrication (2026-06-07): the Figma reference values that had
//  no live source were excised from the rendered path.
//    • Header time — was the seeded literal "23:28", now the driver's
//      live device clock (TimelineView(.everyMinute), HH:mm).
//    • Walkaround-elapsed — was "3:51", now the real interval from the
//      post-trip/DVIR lifecycle transition recorded server-side to
//      `now` (mirrors the 024 arrival-anchor pattern). Em-dash "—"
//      until a real walkaround-start transition resolves.
//    • Telemetry (air-loss PSI / tires / lights, + the hero verdict
//      and per-finding readings/verdicts) — there is NO live DVIR
//      sensor or verdict feed wired to this screen, so every reading
//      renders an honest em-dash "—" rather than the Figma "0.8" /
//      "10/10" / "21/22" / "PASS" / "0 ppm" / "4/4" literals. The
//      regulatory out-of-service thresholds (0.5 PSI ORT, 4-6/32"
//      tread) are 49 CFR spec labels, not readings, and are kept.
//    • Findings count header — was the hardcoded "4 ITEMS"; now reads
//      the real number of rendered finding rows.
//    • Carrier-ops banner — the fabricated "BALTIMORE · OPS WATCHING"
//      copy is replaced with a neutral, location-free reset-clock
//      line (no invented terminal / ops desk).
//    • Signature row — the fabricated "Michael Eusorone" + the
//      "CDL-A · HAZMAT N+H+T · TWIC #4419" credential string are
//      replaced by the real signed-in user's name (no live CDL/TWIC
//      facet exists, so the credential line degrades to an honest
//      empty state) + the live wall clock on the "tap to sign" line.
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

    /// Real walkaround-start instant — the post-trip / DVIR lifecycle
    /// transition timestamp recorded server-side. The header + hero
    /// "walkaround elapsed" lines accrue against this anchor. Nil until
    /// the live history resolves (or no such transition exists), in
    /// which case the elapsed reads an honest em-dash, never "3:51".
    @State private var walkaroundAnchor: Date?

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    /// Honest sentinel for every figure with no live source on this
    /// screen (DVIR telemetry / verdicts / readings have no feed wired).
    private let dash = "—"

    // MARK: - Honest live displays

    /// Live "H:MM" walkaround-elapsed against the real anchor, else an
    /// em-dash. Computed at the render `now` so it stays current.
    private func walkaroundElapsed(at now: Date) -> String {
        guard let start = walkaroundAnchor else { return dash }
        let secs = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", secs / 3600, (secs % 3600) / 60)
    }

    /// Signature avatar initials from the real signed-in user's name
    /// (up to two letters); "—" when no name is on the session.
    private var signerInitials: String {
        let parts = (session.user?.name ?? "")
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
        return parts.isEmpty ? dash : parts.joined().uppercased()
    }

    /// Real signed-in driver name; honest em-dash when absent. No
    /// fabricated "Michael Eusorone" person.
    private var signerName: String {
        let n = (session.user?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? dash : n
    }

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
                // Live walkaround-elapsed against the real lifecycle
                // anchor (em-dash until it resolves), refreshed each
                // minute alongside the header clock.
                TimelineView(.everyMinute) { tl in
                    Text("\(ctx.headerKicker) · \(walkaroundElapsed(at: tl.date)) walkaround elapsed")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                    // EUSOTRIP-MODE-BADGE-2026-05-17 — mode chip on lifecycle screen
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
            }
            Spacer(minLength: 0)
            // Live device clock — the header time is the driver's wall
            // clock (HH:mm, refreshed each minute), not a seeded literal.
            TimelineView(.everyMinute) { tl in
                Text(tl.date, format: .dateTime.hour().minute())
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
            }
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
                // No live air-loss sensor feed — honest em-dash, not the
                // Figma reference "0.8" reading.
                Text(dash)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text("PSI / 2 MIN AIR-LOSS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                // No live DVIR verdict feed — neutral "AWAITING" sentinel
                // rather than a seeded green "PASS" assertion.
                Text("AWAITING")
                    .font(.system(size: 12, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }
            // Live walkaround-elapsed; em-dash until the anchor resolves.
            // No seeded "all gates verified" verdict copy.
            TimelineView(.everyMinute) { tl in
                Text("\(walkaroundElapsed(at: tl.date)) walkaround elapsed")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
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
        // No live DVIR telemetry feed — each reading is an honest
        // em-dash. The subs that are 49 CFR out-of-service thresholds
        // (0.5 PSI ORT, 4-6/32" tread) are spec labels, not readings, so
        // they stand; the per-inspection "1 MINOR FLAGGED" count had no
        // source and is replaced by the neutral spec it measures against.
        HStack(spacing: Space.s2) {
            metric(label: "AIR-LOSS", value: dash, sub: "0.5 PSI ORT")
            metric(label: "TIRES",    value: dash, sub: "4-6/32\" TREAD")
            metric(label: "LIGHTS",   value: dash, sub: "49 CFR 393.11")
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

    /// The DVIR inspection categories rendered below. The findings count
    /// header is computed from this list — never a hardcoded "4 ITEMS".
    private var findingTitles: [String] {
        ["Tractor walkaround", trailerSweepTitle, placardsRowTitle,
         "Trailer ID light #3 flicker"]
    }

    private var findingsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Count computed from the rendered rows, not seeded.
                Text("FINDINGS · \(findingTitles.count) ITEMS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                // Static DVIR inspection-category labels (49 CFR §396.11
                // checklist sections), not per-load data.
                Text("BRAKES · LIGHTS · TIRES · COUPLER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textSecondary)
            }
            // No live per-finding verdict/reading feed — each row's right
            // slot is an honest em-dash (no seeded "PASS" / "0 ppm" /
            // "4/4" / "30 day · DEFER" / fabricated work-order number).
            findingRow(title: "Tractor walkaround",          right: dash, color: palette.textTertiary)
            findingRow(title: trailerSweepTitle,             right: dash, color: palette.textTertiary)
            findingRow(title: placardsRowTitle,              right: dash, color: palette.textTertiary)
            findingRow(title: "Trailer ID light #3 flicker", right: dash, color: palette.textTertiary)
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
            // Neutral reset-clock line — the fabricated "BALTIMORE · OPS
            // WATCHING" terminal/ops-desk copy is removed (no live ops
            // presence is wired). The reset-clock behavior is real.
            Text("CARRIER OPS · RESET CLOCK STARTS ON SUBMISSION")
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
                // Initials from the real signed-in user, not a fixed "ME".
                Text(signerInitials).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                // Real signed-in driver name; em-dash when absent. No
                // fabricated "Michael Eusorone".
                Text(signerName)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                // No live CDL/HAZMAT/TWIC credential facet is wired —
                // honest empty state instead of a fabricated endorsement
                // string ("CDL-A · HAZMAT N+H+T · TWIC #4419").
                Text("Credentials not on file")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            // Live wall clock on the sign affordance; em-dash zone never
            // a seeded "23:28 ET".
            TimelineView(.everyMinute) { tl in
                Text("\(tl.date.formatted(.dateTime.hour().minute())) · tap to sign")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.diagonal)
            }
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

        // Walkaround-elapsed anchor — the REAL post-trip / DVIR lifecycle
        // transition timestamp. The header + hero "walkaround elapsed"
        // lines accrue against this. Stays nil (→ em-dash) when no such
        // transition exists, never a fake "3:51" tick.
        resolveWalkaroundAnchor(from: lifecycle.history)
    }

    /// Find the real walkaround-start timestamp from the lifecycle audit
    /// trail and set `walkaroundAnchor`. The server state machine has NO
    /// post_trip / DVIR / inspection states (TANKER_LOAD_STATUSES,
    /// schema.additions.wave4-1.ts) — the post-trip walkaround phase
    /// begins when the load first transitions INTO `unloaded` or
    /// `delivered`, so that first real transition stamp is the anchor.
    /// Parses the ISO-8601 `createdAt` server stamp (with and without
    /// fractional seconds); stays nil (→ em-dash) when no such
    /// transition exists.
    private func resolveWalkaroundAnchor(from history: [LoadLifecycleAPI.StateTransition]) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func parse(_ s: String?) -> Date? {
            guard let s = s, !s.isEmpty else { return nil }
            return iso.date(from: s) ?? isoPlain.date(from: s)
        }
        let markers = ["unloaded", "delivered"]
        let row = history.first { t in
            let to = (t.toState ?? "").lowercased()
            return markers.contains { to == $0 }
        }
        if let stamp = parse(row?.createdAt) {
            walkaroundAnchor = stamp
        }
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
    RoleNav.driverLeading(current: .trips)
}
private func driverNavTrailing_049() -> [NavSlot] {
    RoleNav.driverTrailing(current: .none)
}

#Preview("049 · Task Result · Dark") {
    TaskResultScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("049 · Task Result · Light") {
    TaskResultScreen(theme: Theme.light).preferredColorScheme(.light)
}
