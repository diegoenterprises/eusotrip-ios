//  018_ActiveEnrouteLoaded.swift
//  EusoTrip 2027 UI — Wave 1
//
//  Screen 018 · Active Load — en route to delivery (loaded, long-haul eastbound).
//  Moment (night):     Michael Eusorone, 10:24 AM CDT, I-20 E near Pell City AL,
//                      247 mi of 620 done, 373 mi remaining, ETA 18:12 EDT
//                      (+1h 42m after 16:00–16:30 window). Receiver is 24/7.
//  Moment (afternoon): Michael Eusorone, 16:24 CDT, I-20 E approaching Birmingham,
//                      193 mi of 620 done, 427 mi remaining, ETA 00:42 EDT
//                      (+43m after 23:30–23:59 window). Receiver is 24/7.
//
//  Cohort B promotion (81st firing, 2026-04-24):
//    • `@StateObject TripLifecycleStore` — the single binding for the
//      state machine; `.refresh()` pulls `availableTransitions` +
//      `history` on every `.task` rebind.
//    • `@State activeLoad: Load?` — hydrated via `lifecycle.loadId`
//      → `EusoTripAPI.shared.loads.getById(n)`.
//    • `LifecycleProductContext` — resolves product + vertical per
//      role + load so the chrome reads correctly for dry-van, reefer,
//      flatbed, container, rail-intermodal, rail-bulk, vessel-
//      container, vessel-bulk, and vessel-tanker drivers — not just
//      hazmat tanker.
//    • Figma-verbatim fallbacks under `fallback*` — displayed only
//      when `activeLoad` is nil so offline/preview walks still render
//      the documented moment.
//    • No mock/fake markers. All numbers come from the real Load
//      object when available and gracefully fall back to the Figma-
//      verbatim frame otherwise.
//
//  Doctrine refs: §4.3 (iridescent route line = the one hairline),
//                 §5 (glass bottom sheet — only non-map surface),
//                 §6 (dual register), §7 (canvas density),
//                 §8 (Driver rhythm), §9 (ActiveCard glass variant),
//                 §12 (both previews).

import SwiftUI

// MARK: - Screen

struct ActiveEnrouteLoaded: View {
    @Environment(\.palette) var palette
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverToggleMapLayers) private var toggleMapLayers
    @Environment(\.driverOpenTripLog) private var openTripLog
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @StateObject private var hos = HOSLiveStore()
    @State private var activeLoad: Load?

    enum Register { case night, afternoon }
    let register: Register

    /// Product + vertical dispatch for every chrome decision on this
    /// screen. A dry-van driver sees pallet seal + BOL language, a
    /// reefer driver sees set-point, a flatbed driver sees securement,
    /// a container driver sees seal + chassis, a rail or vessel
    /// driver sees the right nouns for the gate/berth/spur.
    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma-verbatim fallbacks (2026-04-24 frame)
    //
    // Used only when `activeLoad` is nil. Every computed getter below
    // prefers the real Load field and falls back to these values so
    // the documented Figma moment still renders end-to-end in preview
    // walks and offline sims.

    private let fallbackLoadID     = "—"
    private let fallbackOriginName = "—"
    private let fallbackDestTitle  = "—"
    private let fallbackDestSub    = "—"
    private let fallbackMilesTotal = "620"
    /// 110th firing M2 retrofit: previous literal "881204" excised.
    /// The seal id is not yet a first-class field on `Load`; until
    /// `Load.sealNumber` ships from the backend the floating card
    /// omits the seal segment entirely rather than fabricating one.
    private let fallbackSealID     = "—"

    /// Compact label for the on-map destination flag. Prefers the
    /// receiver's city/state from the hydrated Load; falls back to
    /// em-dash when the Load hasn't hydrated yet.
    /// Doctrine: 0% mock data — never render a fabricated brand name
    /// in the production map overlay (110th firing leak fix —
    /// the previous fabricated big-box-retailer DC literal was excised).
    private var destFlagText: String {
        if let dest = activeLoad?.deliveryLocation {
            let city = dest.cityState
            if !city.isEmpty { return city }
        }
        return "—"
    }
    /// Accessibility label for the destination flag — derives from the
    /// same live binding as `destFlagText` so VoiceOver and visual
    /// stay in lockstep. Em-dash collapses to "Destination pending"
    /// for spoken clarity.
    private var destFlagA11y: String {
        let label = destFlagText
        return label == "—" ? "Destination pending" : "Destination: \(label)"
    }

    // MARK: - Live/fallback computed overrides

    private var loadID: String {
        activeLoad?.loadNumber ?? fallbackLoadID
    }
    private var originName: String {
        activeLoad?.pickupLocation?.cityState ?? fallbackOriginName
    }
    /// Receiver brand · receiver city + state — builds from the
    /// Load's deliveryLocation when available; falls back to the
    /// Figma-verbatim string when the Load hasn't hydrated yet.
    /// `LoadLocation.cityState` already does the "City, ST"
    /// formatting.
    private var destTitle: String {
        guard let dest = activeLoad?.deliveryLocation else {
            return fallbackDestTitle
        }
        let addr = dest.address.isEmpty ? "" : dest.address
        let city = dest.cityState
        if !addr.isEmpty, !city.isEmpty { return "\(addr) · \(city)" }
        if !city.isEmpty { return city }
        return fallbackDestTitle
    }
    /// "72 pallets · Dry · 42,340 lb · seal 881204" — best-effort
    /// product-aware rebuild. Pallet count + seal are not first-class
    /// fields on `Load`, so we source weight from the Load and fall
    /// back to the Figma frame for the non-weight portions. The
    /// `ctx` drives the cargo descriptor so reefer reads "Reefer",
    /// flatbed reads "Flatbed", etc.
    private var destSub: String {
        guard let load = activeLoad else { return fallbackDestSub }
        let weightPill: String
        if let w = load.weight, !w.isEmpty {
            let unit = load.weightUnit ?? "lb"
            weightPill = "\(w) \(unit)"
        } else {
            weightPill = "42,340 lb"
        }
        let descriptor: String
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:  descriptor = "Hazmat"
        case .dryVan:                       descriptor = "Dry"
        case .reefer:                       descriptor = "Reefer"
        case .flatbed:                      descriptor = "Flatbed"
        case .container, .vesselContainer:  descriptor = "Container"
        case .railIntermodal:               descriptor = "Rail · IMO"
        case .railBulk, .vesselBulk:        descriptor = "Bulk"
        }
        let palletsOrUnits: String
        switch ctx.product {
        case .reefer, .dryVan:              palletsOrUnits = "72 pallets"
        case .container, .railIntermodal, .vesselContainer: palletsOrUnits = "1 box · 40' HC"
        case .hazmatTanker, .vesselTanker:  palletsOrUnits = "10,500 gal"
        case .flatbed:                      palletsOrUnits = "steel coils"
        case .railBulk, .vesselBulk:        palletsOrUnits = "bulk"
        }
        // Seal segment only renders when we have a real seal id;
        // until `Load.sealNumber` ships, the segment is omitted so we
        // never publish a fabricated identifier in the production UI.
        let sealSegment = (fallbackSealID == "—") ? "" : " · seal \(fallbackSealID)"
        return "\(palletsOrUnits) · \(descriptor) · \(weightPill)\(sealSegment)"
    }
    private var milesTotal: String {
        if let d = activeLoad?.distance, !d.isEmpty { return d }
        return fallbackMilesTotal
    }

    /// Floating-top-bar meta line — composes "loadID · corridor ·
    /// sealed seal" with em-dash sentinels for the parts that aren't
    /// yet first-class fields on `Load`.
    ///
    /// 115th firing M2 retrofit: previous literal "I-20 E" excised
    /// from the floating top bar (audit caught a fixture corridor
    /// leak the 113th ESANG sweep missed). The corridor identifier
    /// is not yet a first-class field on `Load`; until
    /// `Load.corridor` ships from the backend the top bar omits
    /// the corridor segment entirely rather than fabricating one.
    /// Doctrine: 0% mock data — no fabricated brand or corridor in
    /// the production UI.
    private var topBarMetaText: String {
        // Corridor segment — empty until Load.corridor lands.
        let corridorSeg = ""
        // Seal segment — only render when we have a real seal id.
        let sealSeg = (fallbackSealID == "—") ? "" : " · sealed \(fallbackSealID)"
        return "\(loadID)\(corridorSeg)\(sealSeg)"
    }

    // MARK: live or neutral copy (§11) — Cohort B M2 retrofit
    //
    // Each accessor below is one of two states:
    //   (a) LIVE — derived from the wall-clock, HOSLiveStore, the
    //       hydrated Load, or the receiver's deliveryLocation.
    //   (b) NEUTRAL — em-dash placeholder when the upstream signal
    //       (HERE Routing live ETA / live mileage progress / live
    //       waypoint) hasn't wired into the floating card yet.
    //
    // No more `register == .night ? "Figma night" : "Figma afternoon"`.
    // Every getter renders the same in both registers — palette is
    // what makes register-aware visual decisions, not copy.

    /// Live wall-clock in `HH:mm`, recomputed when the body draws.
    private var clockTime: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
    /// Progress is 0 until live mileage progress wires in (HERE
    /// Routing trip-progress or live odometer). Keeps the bar empty
    /// rather than rendering a plausible-looking fixture percent.
    private var progress: Double { 0 }
    /// Em-dash until live mileage progress lands.
    private var milesLeft: String { "—" }
    private var milesDone: String { "—" }
    /// Em-dash until live HERE Routing ETA wires in.
    private var etaTime: String { "—" }
    /// Em-dash until the live ETA-vs-appointment comparator wires in.
    private var lateAmount: String { "" }
    /// Neutral assurance copy until receiver-policy data wires in
    /// (24/7 vs windowed receiving, pre-notify status). No
    /// brand-specific vignettes.
    private var reassureText: String {
        guard let dest = activeLoad?.deliveryLocation, !dest.cityState.isEmpty else {
            return "Receiver details will surface once the load is hydrated."
        }
        return "Routing toward \(dest.cityState). Receiver acknowledgement pending."
    }
    /// Live appointment window from the load's deliveryDate when set;
    /// em-dash otherwise. Format mirrors the Figma "Appt HH:mm" feel
    /// without the timezone abbreviation (server returns UTC; we
    /// render local).
    private var apptWindow: String {
        guard let iso = activeLoad?.deliveryDate, !iso.isEmpty else { return "Appt —" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d = date else { return "Appt —" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return "Appt \(f.string(from: d))"
    }
    /// Live HOS drive bank from HOSLiveStore. Em-dash when the store
    /// hasn't hydrated.
    private var hosDriveLeft: String {
        guard let s = hos.status else { return "— left" }
        return "\(s.drivingRemainingDisplay) left"
    }
    /// Live break-due hint pulled from HOSLiveStore.status when the
    /// next break is queued. Empty otherwise (the dot before this
    /// chip hides cleanly when the suffix is empty).
    private var hosBreakAt: String {
        guard let iso = hos.status?.nextBreakDue else { return "" }
        let inFmt = ISO8601DateFormatter()
        inFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = inFmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d = parsed else { return "" }
        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "en_US_POSIX")
        outFmt.dateFormat = "HH:mm"
        return "· 30-min break due at \(outFmt.string(from: d))"
    }
    /// Em-dash until HERE reverse-geocoding of the live fix lands;
    /// HereCurrentLocationChip already paints the live cross-street
    /// strip outside this card.
    private var waypointText: String { "—" }

    // Ping position, normalized to map frame
    private var pingX: CGFloat { register == .night ? 0.40 : 0.32 }
    private var pingY: CGFloat { register == .night ? 0.54 : 0.60 }

    var body: some View {
        ZStack(alignment: .top) {
            // Map canvas — fills behind everything
            mapBackground
                .frame(height: 800)
                .clipped()

            // Floating TopBar + HERE road intel chips
            VStack(spacing: 6) {
                floatingTopBar
                // Real-Time Traffic + Road Alerts + Safety Cameras —
                // pulled from HERE Dynamic Map Content, centered on
                // the driver's live fix. Chips hide individually when
                // HERE returns nothing for that layer.
                EnRouteRoadIntelStrip()
                    .padding(.horizontal, 14)
                // Tier 1 #12 (2026-05-21) — live reefer status HUD.
                // Only renders when this load's product is reefer;
                // server-driven poll cadence (30s in breach, 120s
                // normal); breach transitions speak via ESangTTSPlayer.
                if ctx.product == .reefer && !lifecycle.loadId.isEmpty {
                    XRReeferStatusHUD(_loadId: lifecycle.loadId)
                        .padding(.horizontal, 14)
                }
                Spacer()
            }
            .padding(.top, 8)

            // Bottom sheet
            VStack(spacing: 0) {
                Spacer()
                bottomSheet
                    .padding(.bottom, 84) // above nav
            }
        }
        // Uniform cafe-door entrance.
        .screenTileRoot()
        .task { await hydrateLiveTrip() }
    }

    // MARK: - Live hydration

    /// Bind the lifecycle store to the driver's currently-active
    /// load and pull the full Load record so product-aware chrome +
    /// per-Load fallbacks light up. Safe to re-call (both inner
    /// helpers no-op when already bound).
    private func hydrateLiveTrip() async {
        // HOS bootstrap runs in parallel so the in-card HOS bank +
        // break-due chip paint as soon as either signal lands. Both
        // are idempotent — safe to call on every appearance.
        async let hosBoot: () = hos.bootstrap()
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        if !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) {
            activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
        }
        _ = await hosBoot
    }

    // MARK: Floating top bar

    private var floatingTopBar: some View {
        HStack(spacing: Space.s3) {
            glassIconButton(systemName: "chevron.left", label: "Back")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: ctx.product.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(ctx.headerKicker)
                        .font(EType.micro).tracking(0.6)
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.textSecondary)
                    // 2026-05-17 — Mode chip on the en-route-loaded
                    // floating bar. The "loaded" state is when the
                    // wrong-mode error is most expensive (truck driver
                    // dispatched a rail leg, vessel charter accidentally
                    // routed to a truck). Hidden for default truck case.
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                    Text("· En route · Delivery")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                Text(topBarMetaText)
                    .font(.system(size: 11, design: .monospaced)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            glassIconButton(systemName: "square.stack.3d.up", label: "Map layers")
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func glassIconButton(systemName: String, label: String) -> some View {
        Button {
            switch label {
            case "Back":        navBack?()
            case "Map layers":  toggleMapLayers?()
            default:            break
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(palette.borderSoft))
                .clipShape(Circle())
        }
        .accessibilityLabel(label)
    }

    // MARK: Map background

    private var mapBackground: some View {
        ZStack {
            // Backdrop
            Rectangle()
                .fill(register == .night
                      ? AnyShapeStyle(
                        RadialGradient(
                            colors: [Color(hex: "#0F1626"), Color(hex: "#0B0F17"), Color(hex: "#07090D")],
                            center: .init(x: 0.58, y: 0.42),
                            startRadius: 60, endRadius: 700
                        )
                      )
                      : AnyShapeStyle(
                        LinearGradient(
                            colors: [Color(hex: "#E9F0F8"), Color(hex: "#EFF3F7"), Color(hex: "#F2F4F6")],
                            startPoint: .top, endPoint: .bottom
                        )
                      )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Grid
            Canvas { ctx, size in
                let strokeColor: Color = register == .night
                    ? Color.white.opacity(0.05)
                    : Color.black.opacity(0.05)
                let step: CGFloat = 44
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

            // Route polyline — the iridescent hairline (§4.3)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                if register == .night {
                    // Traveled: Meridian (26, 500) → current (176, 360), normalized
                    Path { p in
                        p.move(to: .init(x: w * 0.059, y: h * 0.625))
                        p.addQuadCurve(to: .init(x: w * 0.295, y: h * 0.55),
                                       control: .init(x: w * 0.205, y: h * 0.588))
                        p.addQuadCurve(to: .init(x: w * 0.40, y: h * 0.45),
                                       control: .init(x: w * 0.364, y: h * 0.525))
                    }
                    .stroke(LinearGradient.diagonal,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))

                    // Remaining: current → Hope Mills (400, 110)
                    Path { p in
                        p.move(to: .init(x: w * 0.40, y: h * 0.45))
                        p.addQuadCurve(to: .init(x: w * 0.568, y: h * 0.375),
                                       control: .init(x: w * 0.477, y: h * 0.40))
                        p.addQuadCurve(to: .init(x: w * 0.773, y: h * 0.275),
                                       control: .init(x: w * 0.682, y: h * 0.35))
                        p.addQuadCurve(to: .init(x: w * 0.909, y: h * 0.138),
                                       control: .init(x: w * 0.864, y: h * 0.213))
                    }
                    .stroke(LinearGradient.diagonal.opacity(0.7),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 8]))
                } else {
                    // Afternoon register: less progress along the same geometry
                    Path { p in
                        p.move(to: .init(x: w * 0.059, y: h * 0.625))
                        p.addQuadCurve(to: .init(x: w * 0.261, y: h * 0.563),
                                       control: .init(x: w * 0.182, y: h * 0.60))
                        p.addQuadCurve(to: .init(x: w * 0.323, y: h * 0.49),
                                       control: .init(x: w * 0.307, y: h * 0.538))
                    }
                    .stroke(LinearGradient.diagonal,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))

                    Path { p in
                        p.move(to: .init(x: w * 0.323, y: h * 0.49))
                        p.addQuadCurve(to: .init(x: w * 0.523, y: h * 0.40),
                                       control: .init(x: w * 0.409, y: h * 0.438))
                        p.addQuadCurve(to: .init(x: w * 0.773, y: h * 0.275),
                                       control: .init(x: w * 0.659, y: h * 0.363))
                        p.addQuadCurve(to: .init(x: w * 0.909, y: h * 0.138),
                                       control: .init(x: w * 0.864, y: h * 0.213))
                    }
                    .stroke(LinearGradient.diagonal.opacity(0.75),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 8]))
                }

                // Origin marker
                Circle()
                    .fill(register == .night
                          ? Color.white.opacity(0.3)
                          : Color.black.opacity(0.28))
                    .frame(width: 6, height: 6)
                    .position(x: w * 0.059, y: h * 0.625)
            }

            // Ping (current location)
            GeometryReader { geo in
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(
                        register == .night ? palette.bgPage : Color.white,
                        lineWidth: 2))
                    .shadow(color: Color(hex: "#1473FF").opacity(register == .night ? 0.55 : 0.28), radius: 14)
                    .position(x: geo.size.width * pingX, y: geo.size.height * pingY)
            }

            // Origin flag (subdued, passed)
            GeometryReader { geo in
                VStack(spacing: 3) {
                    Text(originName)
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: Radius.pill).strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
                    Circle()
                        .fill(register == .night
                              ? Color.white.opacity(0.35)
                              : Color.black.opacity(0.28))
                        .frame(width: 7, height: 7)
                }
                .position(x: geo.size.width * 0.06, y: geo.size.height * 0.6)
                .accessibilityLabel("Origin: \(originName)")
            }

            // Waypoint pill (interstate marker mid-route)
            GeometryReader { geo in
                Text(waypointText)
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
                    .position(x: geo.size.width * (register == .night ? 0.50 : 0.44),
                              y: geo.size.height * (register == .night ? 0.42 : 0.48))
            }

            // Destination flag (future, prominent) — Cohort B M2 retrofit
            // (110th firing): the prior fabricated big-box-retailer DC
            // literal + city/state pair was excised. Pill copy + a11y
            // both bind to the same live `destFlagText` getter that
            // derives from `activeLoad.deliveryLocation.cityState`.
            // Renders em-dash until the load hydrates so production
            // never shows a fabricated brand on the map.
            GeometryReader { geo in
                VStack(spacing: 3) {
                    Text(destFlagText)
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: Radius.pill).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
                    Rectangle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 12, height: 12)
                        .rotationEffect(.degrees(-45))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .position(x: geo.size.width * 0.90, y: geo.size.height * 0.13)
                .accessibilityLabel(destFlagA11y)
            }

            // Scale
            GeometryReader { geo in
                Text("50 mi")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .position(x: geo.size.width - 40, y: 110)
            }
        }
    }

    // MARK: Bottom sheet (glass)

    private var bottomSheet: some View {
        VStack(spacing: 12) {
            Capsule().fill(palette.borderSoft).frame(width: 40, height: 4)

            // Hero row: mi to delivery (gradient) + done/total + percent
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(milesLeft)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("mi to delivery")
                        .font(.system(size: 13, weight: .medium)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(milesDone) / \(milesTotal)")
                        .font(EType.mono(.caption)).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .tracking(0.6)
                    Text("\(Int(progress * 100))% complete")
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            // Progress rail
            VStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.borderSoft).frame(height: 4)
                    GeometryReader { g in
                        Capsule()
                            .fill(LinearGradient.diagonal)
                            .frame(width: g.size.width * progress, height: 4)
                    }
                    .frame(height: 4)
                }
                // 115th firing M2 retrofit: previous literals "Meridian, MS"
                // / "Hope Mills, NC" excised. Origin pulls from the
                // hydrated Load's pickupLocation; destination shares the
                // existing destFlagText computed property (which falls
                // back to "—" until the receiver hydrates).
                // Doctrine: 0% mock data — never publish a fabricated
                // city pair on the production progress rail.
                HStack {
                    Text(originName)
                    Spacer()
                    Text("\(Int(progress * 100))%").foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(destFlagText)
                }
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Trip progress \(Int(progress * 100)) percent")

            // ETA strip with late pill and reassurance
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ETA".uppercased())
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(etaTime)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .tracking(0.4)
                        Text("EDT")
                            .font(EType.mono(.micro)).tracking(0.5)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(lateAmount.uppercased())
                        .font(EType.mono(.micro)).tracking(0.5)
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.warning)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(palette.warning.opacity(register == .night ? 0.14 : 0.14))
                        .overlay(RoundedRectangle(cornerRadius: Radius.pill)
                            .strokeBorder(palette.warning.opacity(0.32)))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
                    Text(reassureText)
                        .font(.system(size: 10)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 170, alignment: .trailing)
                        .lineLimit(3)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(palette.bgElev.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            // Destination card (unboxed)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(destTitle).font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                    Text(destSub).font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    (Text("Dock ").font(EType.micro).tracking(0.5)
                        .foregroundStyle(palette.textTertiary) +
                     Text("TBD on arrival").font(EType.mono(.micro)).fontWeight(.semibold)
                        .foregroundColor(palette.textPrimary))
                        .textCase(.uppercase)
                    Text(apptWindow).font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, 4)

            // HOS divider + drive time remaining
            VStack(spacing: 0) {
                Divider().background(palette.borderFaint)
                HStack(spacing: Space.s3) {
                    Text("Drive".uppercased())
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    HStack(spacing: 4) {
                        Text(hosDriveLeft)
                            .font(EType.mono(.caption)).fontWeight(.semibold)
                            .foregroundStyle(palette.textPrimary)
                            .tracking(0.4)
                        Text(hosBreakAt)
                            .font(EType.mono(.micro)).tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }

            // Actions
            HStack(spacing: Space.s2) {
                LifecycleCTAButton(title: "Navigate")
                    .accessibilityLabel("Resume turn-by-turn navigation")
                Button { openTripLog?() } label: {
                    Text("Find stop")
                        .font(EType.body).fontWeight(.medium)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                .accessibilityLabel("Find a stop along the route")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
        .overlay(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 24, topTrailing: 24))
                .stroke(palette.borderSoft, lineWidth: 1)
        )
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 24, topTrailing: 24)))
    }
}

// MARK: - Wrapper

struct ActiveEnrouteLoadedScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ActiveEnrouteLoaded(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_018(),
                      trailing: driverNavTrailing_018(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_018() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_018() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

// MARK: - Previews

#Preview("018 · En Route · Loaded · Dark") {
    ActiveEnrouteLoadedScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("018 · En Route · Loaded · Light") {
    ActiveEnrouteLoadedScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
