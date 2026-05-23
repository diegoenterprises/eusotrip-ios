//
//  035_EnRouteDrive.swift
//  EusoTrip 2027 UI — Wave 2 (main haul · turn-by-turn)
//
//  Screen 035 · En Route Drive — the driver has departed the pickup (034)
//  and is now on the main haul. Turn-by-turn is live, the route polyline
//  is painted as the iridescent brand gradient, ESANG is quiet but ready,
//  the EusoShield in-transit binder is live and surfaced as a status chip,
//  and a hazmat reroute note confirms the tunnel/viaduct that was skipped
//  when the binder was written. The screen is map-first: the nav banner,
//  map controls, speed limit card, and bottom summary card all float on
//  the map canvas and the driver's only primary actions are:
//      • Exit (red) — stop nav + open exception flow
//      • Mute/voice — toggle ESANG voice coaching
//
//  Moment (Dark):  22:42 local, I-83 N after Curtis Bay. 1.4 mi to exit 4
//                  for Forrest Ave → Shrewsbury PA, then merge right onto
//                  I-83 N. Current speed 58 mph, limit 65. ETA 21:14, 52
//                  mi remaining, 1h 32m drive. HOS 6h 12m drive left.
//                  EusoShield $5M NH₃ binder live. Fort McHenry Tunnel
//                  skipped by routing.
//  Moment (Light): 10:14 local, US-30 W after Lancaster PA. 0.6 mi to
//                  exit 286 for Old Rt 30 → Gap PA, then continue US-30
//                  W. Current speed 53 mph, limit 55. ETA 10:42, 16 mi
//                  remaining, 28m drive. HOS 8h 48m drive left.
//                  EusoShield $2M gasoline binder live. Lincoln Hwy
//                  Viaduct skipped by routing.
//
//  93rd-firing visible-copy retrofit (Cohort A → Cohort B under M2):
//
//      Mirrors the 92nd-firing pass on 036 ESANG Smart Stop. All
//      register-keyed Figma fixtures (turn distances, exit chips,
//      lane shields, hard-coded speeds, ETA strings, hazmat reroute
//      vignettes, binder value vignettes) become live-or-neutral:
//
//        clockTime         — live wall-clock HH:mm
//        hosDriveLeft      — live HOSLiveStore.status.drivingRemaining
//        hazmatReroute     — already ctx-driven (hides on non-hazmat)
//        shieldValue       — already ctx-driven (per-product binder)
//        turnDistance/exit/headline/subhead/waypointShield
//                          — em-dash placeholders until HERE Routing
//                            turn-by-turn data lands in the screen
//        speedLimit/currentSpeed
//                          — em-dash placeholders until ELD/CoreLocation
//                            speed wires in
//        etaBig/etaSub     — em-dash placeholders until HERE Routing
//                            ETA lands
//        crossStreetLabels — em-dash placeholders (97th-firing finish).
//                            Was the last register-keyed text fixture
//                            on this screen ("West Aire Rd"/"Old
//                            Lincoln Hwy" etc.); awaiting HERE Routing
//                            cross-street annotations.
//
//      Result: in production with a live load + active HOS, the
//      screen renders live wall-clock, live HOS bank, ctx-driven
//      hazmat band, ctx-driven binder coverage, plus the live HERE
//      EnRouteRoadIntelStrip / HereCurrentLocationChip /
//      HereTypicalSpeedChip already attached. Without those signals,
//      the floating cards render em-dash placeholders — never
//      fixture data, never Figma vignettes.
//
//  Doctrine refs:
//    §2  nav invariants — no secondary chrome; BottomNav with Trips current.
//    §4.3 iridescent hairline → the route polyline IS the hairline on this
//         screen; gradient stroke, diagonal topLeading→bottomTrailing.
//    §6   dual register; both Dark + Light previews at the bottom.
//    §7   breathe density; map is the canvas, discs and cards float.
//    §8   Driver rhythm — turn banner → map → speed + summary card.
//    §11  visible copy is store-driven, not Figma-keyed. Cohort B under M2.
//
//  93rd firing (initial M2 retrofit).
//  97th firing (cross-street label finish — closes the last borderline
//               register-keyed text fixture; M2 strict 0 / borderline 0).
//

import SwiftUI

// MARK: - Screen

struct EnRouteDrive: View {
    @Environment(\.palette) var palette
    @Environment(\.lifecycleExit) private var lifecycleExit
    @Environment(\.driverToggleVoiceMute) private var toggleVoiceMute
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @StateObject private var hos = HOSLiveStore()
    @State private var activeLoad: Load?

    enum Register { case dark, light }
    let register: Register

    // Invariants (shared across both registers)
    private let loadBinderId = "ESO-89xxxxxxx"

    /// Vertical + product dispatcher. Hazmat reroute, binder coverage,
    /// and any product-aware copy on this screen reads from `ctx` so
    /// a dry-van load never paints a tunnel-skip banner and a reefer
    /// load surfaces cold-chain trace instead of an NH3 binder figure.
    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: live or neutral copy (§11) — 93rd firing M2 retrofit
    //
    // Each accessor below is one of two states:
    //   (a) LIVE — derived from the wall-clock, HOSLiveStore, ctx, or
    //       a HERE strip already attached to the screen.
    //   (b) NEUTRAL — em-dash placeholder when the upstream signal
    //       (HERE Routing turn-by-turn / ELD speed / live ETA) hasn't
    //       wired into the floating card yet.
    //
    // No more `register == .dark ? "Figma dark" : "Figma light"`. The
    // screen looks identical in both registers — the palette is what
    // makes register-aware visual decisions, not copy.

    /// Live wall-clock in `HH:mm`, recomputed when the body draws.
    private var clockTime: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    /// Em-dash until HERE Routing turn-by-turn lands in the card.
    private var turnDistance: String         { "—" }
    private var turnDistanceUnit: String     { "mi" }
    /// Em-dash until HERE Routing returns the next exit / waypoint.
    private var exitChip: String             { "—" }
    private var turnHeadline: String         { "Awaiting live route" }
    private var turnSubhead: String          { "TURN-BY-TURN PENDING" }
    private var thenPillText: String         { "THEN" }
    private var waypointShield: String       { "—" }

    /// Hazmat reroute callout — ctx-driven. Returns empty for
    /// non-hazmat loads so the band hides. Empty when no live load
    /// either (the band is meaningless without a hazmat context).
    private var hazmatReroute: String { ctx.enRouteHazmatBand }

    /// Em-dash until ELD speed signal wires in.
    private var speedLimit: String   { "—" }
    private var currentSpeed: String { "—" }
    /// Em-dash until HERE Routing ETA wires into the bottom card.
    private var etaBig: String       { "—" }
    private var etaSub: String       { "AWAITING LIVE ETA" }

    /// Live HOS drive bank from HOSLiveStore. `drivingRemaining` is
    /// hours-remaining-in-the-11h drive window (Double). Uses the
    /// model's own `drivingRemainingDisplay` formatter so the same
    /// "Xh YYm" string the HOS dashboard renders shows up here.
    /// Em-dash until the store hydrates a status snapshot.
    private var hosDriveLeft: String {
        hos.status?.drivingRemainingDisplay ?? "—"
    }

    /// In-transit binder summary — product-aware at runtime, neutral
    /// "binder" placeholder when no live load is hydrated.
    private var shieldValue: String {
        guard activeLoad != nil else { return "BINDER —" }
        return ctx.enRouteBinderValue
    }

    // Ping position, normalized to the map frame
    private var pingX: CGFloat { register == .dark ? 0.50 : 0.48 }
    private var pingY: CGFloat { register == .dark ? 0.68 : 0.66 }

    var body: some View {
        ZStack(alignment: .top) {
            // Map canvas — fills the whole screen behind every overlay
            mapBackground
                .frame(height: 760)
                .clipped()

            // Floating top: turn banner + THEN preview pill + hazmat band + road intel
            VStack(spacing: 10) {
                turnBanner
                    .padding(.horizontal, 14)
                thenPreviewPill
                    .padding(.leading, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !hazmatReroute.isEmpty {
                    hazmatBand
                        .padding(.horizontal, 14)
                }
                // HERE Dynamic Map Content — live Real-Time Traffic,
                // Road Alerts (incidents), and Safety Cameras. Chips
                // hide per-layer when HERE returns nothing.
                EnRouteRoadIntelStrip()
                    .padding(.horizontal, 14)
                Spacer()
            }
            .padding(.top, 8)

            // Right rail of map control discs
            VStack {
                Spacer().frame(height: 260)
                HStack {
                    Spacer()
                    mapControlRail
                        .padding(.trailing, 14)
                }
                Spacer()
            }

            // Speed limit + speedometer (bottom-left over the map)
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    speedCluster
                        .padding(.leading, 14)
                        .padding(.bottom, 6)
                    Spacer()
                }
                .padding(.bottom, 160)
            }

            // Bottom summary card (ETA + mute + Exit + HOS/Shield chips)
            VStack(spacing: 6) {
                Spacer()
                // HERE reverse-geocode chip — surfaces the live cross-
                // street + city under the summary so the driver sees
                // where ESANG actually thinks they are. Hides cleanly
                // when location is denied or HERE returns empty.
                HereCurrentLocationChip()
                    .padding(.horizontal, 14)
                // HERE Traffic Analytics — typical speed for the live
                // viewport, anchoring the driver's self-pacing against
                // the corridor's historical pattern.
                HereTypicalSpeedChip()
                    .padding(.horizontal, 14)
                bottomSummaryCard
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8) // nav clearance handled by Shell
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("En route drive")
        // Uniform cafe-door entrance.
        .screenTileRoot()
        .task { await hydrateLiveTrip() }
    }

    private func hydrateLiveTrip() async {
        // HOS bootstrap runs in parallel with the lifecycle/load hydrate
        // so the bottom-card HOS pill paints as soon as either signal
        // lands. Both are idempotent — safe to call on every appearance.
        async let hosBoot: () = hos.bootstrap()
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        if !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) {
            activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
        }
        _ = await hosBoot
    }

    // MARK: Turn-by-turn banner

    private var turnBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            // Big right-turn arrow
            Image(systemName: "arrow.turn.up.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            // Distance + exit chip + headline + subhead
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(turnDistance)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Text(turnDistanceUnit)
                            .font(EType.mono(.caption)).tracking(0.5)
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    Text(exitChip)
                        .font(EType.mono(.micro)).tracking(0.6)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                Text(turnHeadline)
                    .font(EType.body).fontWeight(.semibold)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(turnSubhead)
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing ESANG orb — small, gradient
            Circle()
                .fill(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Brand.magenta.opacity(0.45), radius: 10, y: 4)
                .accessibilityLabel("ESANG AI")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(LinearGradient.diagonal)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        // Doctrine §2.1 — dual-shadow brand glow. The turn-card surface
        // uses LinearGradient.diagonal (blue→magenta) for the fill, so the
        // drop shadow is split into blue (-x) + magenta (+x) halves to
        // carry the same gradient feel through the shadow as through
        // the fill. Mirrors the pattern at DriverTabPanes:733/895 and
        // activeTripMap:426-429.
        .shadow(color: Brand.blue.opacity(0.32), radius: 16, x: -2, y: 6)
        .shadow(color: Brand.magenta.opacity(0.32), radius: 16, x: 2, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("In \(turnDistance) miles, \(turnHeadline), \(turnSubhead)")
    }

    // MARK: THEN preview pill

    private var thenPreviewPill: some View {
        HStack(spacing: 6) {
            Text(thenPillText)
                .font(EType.mono(.micro)).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
            Image(systemName: "arrow.turn.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.pill)
                .strokeBorder(palette.borderSoft)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
    }

    // MARK: Hazmat reroute band

    private var hazmatBand: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
            Text(hazmatReroute)
                .font(EType.mono(.micro)).tracking(0.8)
                .fontWeight(.semibold)
                .foregroundStyle(Color.white)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(
            LinearGradient(
                colors: [Brand.danger, Brand.warning],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.pill)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
        .shadow(color: Brand.danger.opacity(0.28), radius: 10, y: 3)
    }

    // MARK: Map control rail (right edge)

    private var mapControlRail: some View {
        VStack(spacing: 10) {
            glassDisc("magnifyingglass", label: "Search along route")
            glassDisc("speaker.wave.2.fill", label: "Toggle voice coaching")
            glassDisc("location.north.circle.fill", label: "Re-center map")
            glassDisc("exclamationmark.triangle.fill",
                      label: "ESANG alerts",
                      tinted: true)
        }
    }

    @ViewBuilder
    private func glassDisc(_ systemName: String, label: String, tinted: Bool = false) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .strokeBorder(palette.borderSoft, lineWidth: 1)
            if tinted {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityLabel(label)
    }

    // MARK: Speed limit + speedometer

    private var speedCluster: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Speed limit sign (white card, black text)
            VStack(spacing: 2) {
                Text("LIMIT")
                    .font(EType.mono(.micro)).tracking(0.7)
                    .foregroundStyle(Color.black.opacity(0.7))
                Text(speedLimit)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black)
            }
            .frame(width: 54, height: 68)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(Color.black.opacity(0.22), lineWidth: 3)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .accessibilityLabel("Speed limit \(speedLimit) miles per hour")

            // Live speed (big numeric + MPH)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(currentSpeed)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Text("MPH")
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(palette.borderSoft)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .accessibilityLabel("Current speed \(currentSpeed) miles per hour")
        }
    }

    // MARK: Bottom summary card

    private var bottomSummaryCard: some View {
        VStack(spacing: 10) {
            // ETA row
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(etaBig)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(etaSub)
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                // Voice mute toggle
                Button { toggleVoiceMute?() } label: {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(palette.bgCardSoft)
                        .overlay(
                            Circle().strokeBorder(palette.borderSoft)
                        )
                        .clipShape(Circle())
                }
                .accessibilityLabel("Mute voice coaching")

                // Exit (red)
                Button { lifecycleExit?() } label: {
                    Text("Exit")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(Brand.danger)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
                        .shadow(color: Brand.danger.opacity(0.35), radius: 8, y: 3)
                }
                .accessibilityLabel("Exit navigation")
            }

            // Status chips row
            HStack(spacing: 8) {
                statusChip(
                    kicker: "HOS DRIVE LEFT",
                    value: hosDriveLeft,
                    tone: .success
                )
                statusChip(
                    kicker: "EUSOSHIELD LIVE",
                    value: shieldValue,
                    tone: .brand
                )
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderSoft)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
    }

    private enum ChipTone { case success, brand }

    @ViewBuilder
    private func statusChip(kicker: String, value: String, tone: ChipTone) -> some View {
        let strokeStyle: AnyShapeStyle = (tone == .brand)
            ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.55))
            : AnyShapeStyle(Brand.success.opacity(0.45))
        let kickerColor: Color = (tone == .brand) ? palette.textSecondary : Brand.success
        let valueColor: AnyShapeStyle = (tone == .brand)
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.textPrimary)

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker)
                    .font(EType.mono(.micro)).tracking(0.7)
                    .foregroundStyle(kickerColor)
                Text(value)
                    .font(EType.bodyStrong)
                    .foregroundStyle(valueColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(strokeStyle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: Map background

    private var mapBackground: some View {
        ZStack {
            // Backdrop — register-specific ground color
            Rectangle()
                .fill(register == .dark
                      ? AnyShapeStyle(
                        RadialGradient(
                            colors: [Color(hex: "#0C1322"), Color(hex: "#080B13"), Color(hex: "#05060A")],
                            center: .init(x: 0.55, y: 0.45),
                            startRadius: 80, endRadius: 720
                        )
                      )
                      : AnyShapeStyle(
                        LinearGradient(
                            colors: [Color(hex: "#EEE7DC"), Color(hex: "#F1EBE1"), Color(hex: "#F5F1E8")],
                            startPoint: .top, endPoint: .bottom
                        )
                      )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Faint street grid — horizontal + vertical streets
            Canvas { ctx, size in
                let strokeColor: Color = register == .dark
                    ? Color.white.opacity(0.035)
                    : Color.black.opacity(0.05)
                let step: CGFloat = 52
                var x: CGFloat = 0
                while x < size.width {
                    ctx.stroke(Path { $0.move(to: .init(x: x, y: 0)); $0.addLine(to: .init(x: x, y: size.height)) },
                               with: .color(strokeColor), lineWidth: 1)
                    x += step
                }
                var y: CGFloat = 0
                while y < size.height {
                    ctx.stroke(Path { $0.move(to: .init(x: 0, y: y)); $0.addLine(to: .init(x: size.width, y: y)) },
                               with: .color(strokeColor), lineWidth: 1)
                    y += step
                }
            }

            // Cross-street labels scattered along the vertical corridor.
            // M2 cleanup (97th firing): register-keyed fixtures (e.g. "West Aire Rd"/"Old Lincoln Hwy")
            // were inherited Figma vignettes — replaced with em-dash neutrals until HERE Routing
            // turn-by-turn cross-street labels land for this screen. The four positions are
            // preserved so the visual rhythm of the decorative corridor stays consistent.
            GeometryReader { geo in
                crossStreetLabel(text: "—",
                                 at: .init(x: geo.size.width * 0.18, y: geo.size.height * 0.18))
                crossStreetLabel(text: "—",
                                 at: .init(x: geo.size.width * 0.78, y: geo.size.height * 0.40))
                crossStreetLabel(text: "—",
                                 at: .init(x: geo.size.width * 0.20, y: geo.size.height * 0.56))
                crossStreetLabel(text: "—",
                                 at: .init(x: geo.size.width * 0.78, y: geo.size.height * 0.64))
            }

            // Route polyline — the iridescent hairline as a vertical corridor
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                // Lower (traveled / current corridor) — solid gradient
                Path { p in
                    p.move(to: .init(x: w * 0.50, y: h * 0.98))
                    p.addQuadCurve(to: .init(x: w * 0.52, y: h * 0.78),
                                   control: .init(x: w * 0.46, y: h * 0.88))
                    p.addQuadCurve(to: .init(x: w * 0.50, y: h * 0.60),
                                   control: .init(x: w * 0.54, y: h * 0.70))
                }
                .stroke(LinearGradient.diagonal,
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))

                // Upper (remaining) — slightly thinner, same gradient
                Path { p in
                    p.move(to: .init(x: w * 0.50, y: h * 0.60))
                    p.addQuadCurve(to: .init(x: w * 0.48, y: h * 0.40),
                                   control: .init(x: w * 0.52, y: h * 0.50))
                    p.addQuadCurve(to: .init(x: w * 0.56, y: h * 0.20),
                                   control: .init(x: w * 0.46, y: h * 0.30))
                    p.addQuadCurve(to: .init(x: w * 0.62, y: h * 0.05),
                                   control: .init(x: w * 0.60, y: h * 0.12))
                }
                .stroke(LinearGradient.diagonal,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))

                // Inner highlight — thin white-ish line riding the gradient
                Path { p in
                    p.move(to: .init(x: w * 0.50, y: h * 0.98))
                    p.addQuadCurve(to: .init(x: w * 0.52, y: h * 0.78),
                                   control: .init(x: w * 0.46, y: h * 0.88))
                    p.addQuadCurve(to: .init(x: w * 0.50, y: h * 0.60),
                                   control: .init(x: w * 0.54, y: h * 0.70))
                    p.addQuadCurve(to: .init(x: w * 0.48, y: h * 0.40),
                                   control: .init(x: w * 0.52, y: h * 0.50))
                    p.addQuadCurve(to: .init(x: w * 0.56, y: h * 0.20),
                                   control: .init(x: w * 0.46, y: h * 0.30))
                    p.addQuadCurve(to: .init(x: w * 0.62, y: h * 0.05),
                                   control: .init(x: w * 0.60, y: h * 0.12))
                }
                .stroke(Color.white.opacity(register == .dark ? 0.18 : 0.35),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // Direction arrowheads along the remaining path
                ForEach(0..<3, id: \.self) { i in
                    let frac = 0.35 - Double(i) * 0.10
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .position(x: w * 0.52, y: h * CGFloat(frac))
                }
            }

            // Interstate shield waypoint pill (center of the map)
            GeometryReader { geo in
                Text(waypointShield)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.black.opacity(0.4), lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                    .position(x: geo.size.width * 0.50, y: geo.size.height * 0.30)
            }

            // Current-position ping
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal.opacity(0.25))
                        .frame(width: 42, height: 42)
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().strokeBorder(
                                register == .dark ? palette.bgPage : Color.white,
                                lineWidth: 2.5)
                        )
                        .shadow(color: Brand.blue.opacity(register == .dark ? 0.55 : 0.30), radius: 12)
                    // Heading chevron
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                .position(x: geo.size.width * pingX, y: geo.size.height * pingY)
            }
        }
    }

    @ViewBuilder
    private func crossStreetLabel(text: String, at point: CGPoint) -> some View {
        Text(text)
            .font(EType.mono(.micro)).tracking(0.3)
            .foregroundStyle(palette.textTertiary)
            .position(point)
    }
}

// MARK: - Wrapper

struct EnRouteDriveScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            EnRouteDrive(register: theme.bgPage == Theme.dark.bgPage ? .dark : .light)
        } nav: {
            BottomNav(leading: driverNavLeading_035(),
                      trailing: driverNavTrailing_035(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_035() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",     isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box", isCurrent: true)]
}
private func driverNavTrailing_035() -> [NavSlot] {
    [NavSlot(label: DriverTab.wallet.label, systemImage: DriverTab.wallet.systemImage, isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",     isCurrent: false)]
}

// MARK: - Previews

#Preview("035 · En Route Drive · Dark") {
    EnRouteDriveScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("035 · En Route Drive · Light") {
    EnRouteDriveScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
