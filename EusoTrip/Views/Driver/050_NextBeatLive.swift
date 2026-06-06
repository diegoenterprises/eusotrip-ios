//
//  050_NextBeatLive.swift
//  EusoTrip — Lifecycle screen 050 · Next Beat Live (off-duty reset).
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `050 Next Beat Live.png`. Resting hero ring + off-duty card +
//  3 amenity tiles + product-aware ESANG-holds list + ESANG voice
//  strip + Amenities / Set do-not-disturb CTAs.
//
//  LIVE BINDING (zero fabrication):
//  -------------------------------
//  • The resting hero ring + duty state + break/reset lines read off the
//    typed HOS API the app already owns — `HOSLiveStore` (which wraps
//    `hos.getStatus` / `hos.getDailyLog` / `hos.getLogHistory` [the HOS
//    audit log] / `hos.getViolations`) and `HOSClockService.shared` (the
//    5-min dashboard poll mirror). The "hours remaining" ring is the
//    §395.3(b) 70-hr/8-day CYCLE counter — the real reset clock — not a
//    fabricated 34:00. Anything the backend hasn't shipped renders an
//    honest em-dash; the bay assignment has no live source → "—".
//  • The active load (parties / lane / rate / distance / weight) decodes
//    with the CORRECTED `loads.getById` shape proven in DL133/DL126:
//    top-level `id: String?` (the server returns `String(load.id)`, so
//    decoding as Int throws typeMismatch and BLANKS the whole screen),
//    nested `pickupLocation`/`deliveryLocation {city,state}` (NOT flat),
//    and real driver/catalyst/shipper PARTY objects {id:Int?, name,
//    initials, companyName, mcNumber, dotNumber} for carrier/driver
//    NAMES. `rate` is a DECIMAL String; `distance` is a Double.
//  • Every prior `?? <invented number/string>` and every hardcoded
//    persona/load number is gone. No value is shown unless it has a live
//    source; otherwise it renders "-" / "—" / an empty-state.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

// MARK: - Corrected `loads.getById` decode (DL133/DL126 proven shape)
//
// Top-level `id` is a String on the wire (`String(load.id)`); decoding
// as Int throws and fails the WHOLE decode → blank screen. pickup/
// delivery are nested {city,state} objects (NOT flat city fields).
// Party (user/company) ids are numeric on the wire.
private struct NBLoadCtx: Decodable, Hashable {
    let id: String?
    let loadNumber: String?
    let pickupLocation: NBLoc?
    let deliveryLocation: NBLoc?
    let rate: String?            // DECIMAL string
    let distance: Double?        // resolved number
    let equipmentType: String?
    let cargoType: String?
    let hazmatClass: String?
    let weight: String?          // DECIMAL string
    let weightUnit: String?
    let transportMode: String?
    let multiVehicleCount: Int?
    let driver: NBParty?
    let catalyst: NBParty?
    let shipper: NBParty?
    struct NBLoc: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct NBParty: Decodable, Hashable {
        let id: Int?
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }

    /// Weight as Double (proxy target for the fill gauge) — 0 when missing.
    var weightValue: Double { Double(weight ?? "") ?? 0 }
}

struct NextBeatLive: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    /// Typed HOS surface the app already owns — wraps `hos.getStatus` /
    /// `hos.getDailyLog` / `hos.getLogHistory` (HOS audit log) /
    /// `hos.getViolations`, mirroring `HOSClockService.shared`'s poll.
    @StateObject private var hos = HOSLiveStore()
    @State private var loadCtx: NBLoadCtx?
    @State private var isMutingDND: Bool = false
    /// Live device wall clock for the LIVE-RESET strip (honest — the
    /// device's own time, not a baked snapshot).
    @State private var now: Date = Date()
    /// Toggle for the "Amenities" sheet — surfaces nearby parking +
    /// fuel via the HERE clients. Replaces the prior dead `navBack()`
    /// secondary CTA per the no-dead-buttons sweep.
    @State private var showAmenities: Bool = false

    // MARK: - Bottom-load fill gauge animation state
    //
    // The fill ring + tank liquid both read off `fillFraction` (the
    // single source of truth, computed from loaded/target gallons in
    // `fillModel`). On appear we drive `fillProgress` 0 → fraction with
    // an eased sweep so the arc, the count-up percent, and the rising
    // liquid level all move in lockstep. Reduce-motion short-circuits to
    // the final static fill (no sweep, no ripple, no flow pulse).
    @State private var fillProgress: CGFloat = 0
    /// Phase clock for the surface ripple + active-arm flow pulse. The
    /// ripple rides this; the pulse opacity is derived from it at the
    /// gpm cadence. Held at 1 (settled) when reduce-motion is on.
    @State private var rippleClock: CGFloat = 0

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    /// Product/vertical context — resolves the bay/spur/berth word + the
    /// ESANG-holds list. Built from the live cargo/hazmat strings the
    /// corrected decode ships (no `Load` object needed for the values
    /// this screen reads).
    private var ctx: LifecycleProductContext {
        LifecycleProductContext.forCargo(
            cargoType: loadCtx?.cargoType,
            hazmatClass: loadCtx?.hazmatClass,
            role: session.user?.role
        )
    }

    // MARK: - Honest display helpers (live-bound; "-"/"—" fallback)

    private let dash = "-"

    /// Live device clock "HH:mm" for the LIVE-RESET strip.
    private var clockDisplay: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: now)
    }

    /// §395.3(b) 70-hr/8-day CYCLE remaining — the real reset clock the
    /// ring renders. Em-dash until the HOS snapshot lands.
    private var cycleRemainingDisplay: String {
        hos.status?.cycleRemainingDisplay ?? dash
    }

    /// Whether the driver is in a reset/off-duty state per the live
    /// duty code. Drives the "Resting. Clock running." headline vs. the
    /// real status when the driver isn't actually resting.
    private var isResting: Bool {
        switch hos.currentDuty {
        case .offDuty, .sleeperBerth: return true
        case .driving, .onDuty:       return false
        }
    }

    /// Live duty-state headline. "Resting. Clock running." only when the
    /// live duty code says off-duty/sleeper; otherwise the real label.
    private var dutyHeadline: String {
        guard hos.status != nil else { return "Off-duty status loading…" }
        switch hos.currentDuty {
        case .offDuty:      return "Resting. Clock running."
        case .sleeperBerth: return "Sleeper berth. Clock running."
        case .driving:      return "Driving."
        case .onDuty:       return "On duty."
        }
    }

    /// Next break / reset milestone line, sourced from the live snapshot.
    /// We surface the §395.3(a)(3)(ii) 30-min break due time when present
    /// (the only forward-looking milestone the snapshot ships). Bay has
    /// no live source → "—".
    private var milestoneLine: String {
        let bay = "—"   // no live bay-assignment source on the HOS/load envelope
        guard let s = hos.status else { return "Next milestone — · Bay \(bay)" }
        if s.breakRequired {
            return "Break required now · Bay \(bay)"
        }
        if let iso = s.nextBreakDue,
           let d = ISO8601DateFormatter().date(from: iso) {
            let f = DateFormatter(); f.dateFormat = "EEE HH:mm"
            return "Break due \(f.string(from: d)) · Bay \(bay)"
        }
        return "No break due · Bay \(bay)"
    }

    /// ESANG pre-trip line — derived from the live break/cycle snapshot,
    /// never a baked "09:30". Em-dash when no snapshot.
    private var prePingLine: String {
        guard let s = hos.status else { return "ESANG pre-trip prompt — awaiting HOS sync" }
        if let iso = s.nextBreakDue,
           let d = ISO8601DateFormatter().date(from: iso) {
            let f = DateFormatter(); f.dateFormat = "EEE HH:mm"
            return "ESANG pre-trip prompt at \(f.string(from: d))"
        }
        return s.canDrive
            ? "ESANG pre-trip prompt queued · drive bank open"
            : "ESANG holds dispatch until reset clears"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                fillGaugeCard
                restingCard
                offDutyCard
                amenityTiles
                holdsCard
                esangFooter
                actions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .onAppear { startFillAnimation(); now = Date() }
        .screenTileRoot()
        .sheet(isPresented: $showAmenities) {
            AmenitiesNearbySheet(palette: palette)
                .presentationDetents([.large])
        }
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
            Spacer()
            LoadModeBadge(modeRaw: loadCtx?.transportMode,
                          multiVehicleCount: loadCtx?.multiVehicleCount,
                          compact: true)
            HStack(spacing: 4) {
                Circle().fill(Brand.success).frame(width: 6, height: 6)
                Text("LIVE RESET")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
            }
            Text(clockDisplay)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    private var restingCard: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                Circle().stroke(palette.bgCardSoft, lineWidth: 6).frame(width: 84, height: 84)
                Circle()
                    .trim(from: 0, to: 0.99)
                    .stroke(LinearGradient.diagonal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 84, height: 84)
                VStack(spacing: -2) {
                    Text(cycleRemainingDisplay)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("HOURS REMAINING")
                        .font(.system(size: 7, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("OFF-DUTY · 70-HR/8-DAY CYCLE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
                Text(dutyHeadline)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(milestoneLine)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                Text(prePingLine)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Bottom-load FILL gauge
    //
    // Operationally: the rack arm mates a dry-break (API RP-1004) coupler
    // to the trailer's bottom-load adapter — the coupler's piston valves
    // only open once the lever seats against a fully-latched connection,
    // so product never flows into open air. Product then enters from the
    // BOTTOM of the compartment and the level climbs as gallons land. We
    // draw that literally: a tank silhouette whose liquid rises from the
    // bottom up to the fill fraction, the dry-break coupler clamped to
    // the bottom adapter with a soft flow pulse at the gpm cadence, and a
    // large progress ring whose arc + count-up percent track the same
    // bound fraction.

    /// Single source of truth for the gauge. The backend has NOT shipped
    /// a metered loaded-gallons column on the load envelope (fill net is
    /// captured by viga AI photo at the rack, per
    /// `LiveLoadFacets.loadedGallons`, which is a known em-dash gap), so
    /// `loaded` has no live source and the gauge renders honest "—" for
    /// the loaded value, percent, and ETA. The TARGET is derived from the
    /// live load weight when present (DECIMAL string → gallons proxy);
    /// when absent the whole readout is em-dash. Nothing here is faked.
    private struct FillModel {
        let loaded: Double?     // gallons in the compartment now (no live source → nil)
        let target: Double?     // ticketed batch size proxy (from live weight)

        /// Loaded ÷ target, clamped to 0…1. nil when either side has no
        /// live source — the ring then renders empty (0) rather than a
        /// fabricated fraction.
        var fraction: CGFloat? {
            guard let loaded, let target, target > 0 else { return nil }
            return CGFloat(min(max(loaded / target, 0), 1))
        }
        private static let grouped: NumberFormatter = {
            let f = NumberFormatter(); f.numberStyle = .decimal
            f.maximumFractionDigits = 0; return f
        }()
        func gal(_ v: Double?) -> String {
            guard let v else { return "—" }
            return Self.grouped.string(from: NSNumber(value: v)) ?? "\(Int(v))"
        }
    }

    /// Resolve the gauge from live state. Target is derived from the
    /// live load weight when present; loaded gallons have NO live source
    /// on the load envelope yet (viga fill telemetry isn't surfaced), so
    /// it stays nil and the readout renders honest em-dash. Fraction is
    /// always COMPUTED — never a literal — and nil when not derivable.
    private var fillModel: FillModel {
        let w = loadCtx?.weightValue ?? 0
        let target: Double? = w > 1_000 ? (w / 1_000).rounded() * 1_000 : nil
        return FillModel(loaded: nil, target: target)
    }

    private var fillGaugeCard: some View {
        let m = fillModel
        // No live fraction (loaded gallons unsourced) → ring renders
        // empty (0) and the percent reads "—". When the backend ships
        // loaded-net-at-fill this lights up automatically.
        let frac = m.fraction ?? 0
        let shown = reduceMotion ? frac : fillProgress
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("BOTTOM-LOAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Circle().fill(palette.textTertiary)
                        .frame(width: 6, height: 6)
                        .opacity(flowPulseOpacity)
                    Text("AWAITING FILL DATA")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            HStack(alignment: .center, spacing: Space.s4) {
                fillRing(fraction: shown, hasLive: m.fraction != nil)
                    .frame(width: 116, height: 116)

                BottomLoadTankGraphic(fraction: shown,
                                      rippleClock: reduceMotion ? 1 : rippleClock,
                                      reduceMotion: reduceMotion,
                                      palette: palette)
                    .frame(width: 60, height: 96)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Loading.")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("\(m.gal(m.loaded)) / \(m.gal(m.target)) gal")
                        .font(EType.mono(.body)).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text("Fill telemetry — viga capture")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
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

    /// Large progress ring: faint full-circle track + a white/light arc
    /// trimmed to the live fraction, sweeping clockwise from 12 o'clock.
    /// Center carries the count-up percent. When there's no live fill
    /// source the percent reads "—" (no fabricated number).
    private func fillRing(fraction: CGFloat, hasLive: Bool) -> some View {
        // Count-up percent stays in lockstep with the arc by reading the
        // SAME animated fraction — but only when there's a live source.
        let livePct = Int((fraction * 100).rounded())
        return ZStack {
            Circle()
                .stroke(palette.bgCardSoft, lineWidth: 9)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    LinearGradient(colors: [palette.textPrimary,
                                            palette.textPrimary.opacity(0.78)],
                                   startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))   // start sweep at 12 o'clock
            VStack(spacing: 0) {
                Text(hasLive ? "\(livePct)%" : "—")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text("FILL")
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    /// Active-arm flow pulse opacity. Rides `rippleClock` so the dot
    /// breathes at the gpm cadence; pinned solid under reduce-motion.
    private var flowPulseOpacity: Double {
        guard !reduceMotion else { return 1 }
        // 0.45…1.0 sinusoidal breath off the shared phase clock.
        return 0.45 + 0.55 * Double((sin(rippleClock * 2 * .pi) + 1) / 2)
    }

    /// Kick the eased sweep + ripple on appear. The arc, count-up, and
    /// liquid level share `fillProgress`; the gpm flow pulse + surface
    /// ripple ride `rippleClock`. Reduce-motion settles both instantly.
    private func startFillAnimation() {
        let target = fillModel.fraction ?? 0
        guard !reduceMotion else {
            fillProgress = target
            rippleClock = 1
            return
        }
        fillProgress = 0
        rippleClock = 0
        // (1) eased sweep ~0.9s on the cubic-bezier(0.4,0,0.2,1) curve —
        //     drives the arc, the count-up percent, and the rising liquid.
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.9)) {
            fillProgress = target
        }
        // (3) soft flow pulse / surface ripple at the gpm cadence —
        //     a repeating phase the dot + tank surface read from.
        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
            rippleClock = 1
        }
    }

    private var offDutyCard: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 1) {
                Text("Off-duty · 49 CFR 395.3(c) reset")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Sleeper \(ctx.vertical.bayWord) — · no smart-lock assignment on file")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(isResting ? "RESTING" : hos.currentDuty.shortLabel)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(isResting ? Brand.success : palette.textSecondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(Capsule().stroke((isResting ? Brand.success : palette.textSecondary).opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var amenityTiles: some View {
        HStack(spacing: Space.s2) {
            // No live amenity telemetry source (no bay temp / DND-hours /
            // breakfast-slot feed on the HOS or load envelope) → honest
            // em-dash values. Labels preserved verbatim.
            tile(label: "BAY TEMP",  value: "—", sub: "NO SENSOR FEED")
            tile(label: "DND",       value: isMutingDND ? "ON" : "—", sub: "ALERTS")
            tile(label: "BREAKFAST", value: "—", sub: "NO SLOT FEED")
        }
    }

    private func tile(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
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

    private var holdsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHAT ESANG HOLDS THROUGH THE RESET")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            ForEach(ctx.nextBeatHolds) { hold in
                HStack(spacing: Space.s3) {
                    Image(systemName: holdIcon(hold))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(holdColor(hold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hold.title)
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text(hold.subtitle)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(hold.tail)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(holdColor(hold))
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

    private func holdIcon(_ hold: LifecycleProductContext.ResetHold) -> String {
        if hold.tail == "ACCEPTED" { return "checkmark.circle.fill" }
        if hold.tail == "QUEUED"   { return "clock.fill" }
        return "doc.fill"
    }
    private func holdColor(_ hold: LifecycleProductContext.ResetHold) -> Color {
        if hold.tail == "ACCEPTED" { return Brand.success }
        if hold.tail == "QUEUED"   { return Brand.warning }
        return palette.textSecondary
    }

    private var esangFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text(esangFooterCopy)
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

    /// ESANG footer copy — composed from the live duty snapshot, never a
    /// baked "09:30 SUNDAY". Em-dash-safe when no snapshot.
    private var esangFooterCopy: String {
        guard let s = hos.status else {
            return "ESANG · REST WELL · I'LL HOLD YOUR BOARD UNTIL HOS SYNCS"
        }
        if s.canDrive {
            return "ESANG · REST WELL · DRIVE BANK \(s.drivingRemainingDisplay.uppercased()) · CYCLE \(s.cycleRemainingDisplay.uppercased())"
        }
        return "ESANG · REST WELL · RESET IN PROGRESS · CYCLE \(s.cycleRemainingDisplay.uppercased()) · I'LL WAKE YOU WHEN THE CLOCK CLEARS"
    }

    private var actions: some View {
        HStack(spacing: Space.s3) {
            Button {
                MeAction.fire("050.amenities-requested",
                              userInfo: ["loadId": lifecycle.loadId])
                showAmenities = true
            } label: {
                Text("Amenities")
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
                title: "Set do-not-disturb",
                action: { Task { await setDND() } },
                trailingIcon: "arrow.right",
                isLoading: isMutingDND
            )
        }
    }

    private func hydrateLiveTrip() async {
        // Live HOS snapshot + audit log (HOSLiveStore wraps the typed
        // hos.* API and mirrors HOSClockService.shared's poll). Kicked
        // first so the resting ring + footer bind immediately.
        HOSClockService.shared.start()
        await hos.bootstrap()

        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty else { return }
        // CORRECTED loads.getById decode (DL133/DL126 proven shape):
        // top-level id is a String on the wire — decode it as such or the
        // WHOLE record throws typeMismatch and the screen blanks.
        struct In: Encodable { let id: String }
        loadCtx = try? await EusoTripAPI.shared.query(
            "loads.getById", input: In(id: lifecycle.loadId))
    }

    private func setDND() async {
        isMutingDND = true
        defer { isMutingDND = false }
        let keys = ["dnd", "rest", "completed"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

// MARK: - Bottom-load tank vector
//
// Bespoke vector illustration of a tanker compartment being filled from
// the BOTTOM through a dry-break (API RP-1004) coupler. Product enters at
// the bottom adapter and the liquid level rises from the floor up to the
// bound fraction. A subtle sine ripple rides the liquid surface; the
// coupler body + lever sit at the bottom inlet with a soft inflow glow.
// Everything is transform/opacity-based off `fraction` + `rippleClock`.
private struct BottomLoadTankGraphic: View {
    /// Bound fill fraction (0…1) — the liquid surface sits at this height.
    let fraction: CGFloat
    /// Shared 0…1 phase clock for the surface ripple (1 = settled).
    let rippleClock: CGFloat
    let reduceMotion: Bool
    let palette: Theme.Palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Reserve the bottom strip for the coupler/adapter assembly.
            let couplerH: CGFloat = 22
            let tankH = h - couplerH
            let r: CGFloat = 10
            // Liquid height, measured from the tank floor, bound to the
            // fill fraction (leave a 4pt lip so a full tank still reads).
            let liquidH = max(0, min(tankH - 4, (tankH - 4) * fraction))

            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    // Tank shell (faint fill).
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .fill(palette.bgCardSoft)

                    // Rising liquid — fills the bottom `liquidH` points,
                    // clipped to the shell so the ripple crest stays inside
                    // the silhouette.
                    LiquidShape(level: liquidH,
                                rippleClock: rippleClock,
                                reduceMotion: reduceMotion)
                        .fill(LinearGradient(
                            colors: [Brand.blue.opacity(0.60),
                                     Brand.magenta.opacity(0.48)],
                            startPoint: .bottom, endPoint: .top))
                        .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))

                    // Compartment baffle hints (two faint dividers).
                    HStack {
                        Rectangle().fill(palette.borderFaint).frame(width: 1)
                        Spacer()
                        Rectangle().fill(palette.borderFaint).frame(width: 1)
                    }
                    .padding(.horizontal, w / 3 - 0.5)
                    .padding(.vertical, 6)

                    // Gradient hairline on top so it rides above the liquid.
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal.opacity(0.5),
                                      lineWidth: 1)
                }
                .frame(width: w, height: tankH)

                couplerAssembly(width: w, height: couplerH)
            }
            .frame(width: w, height: h, alignment: .top)
            .accessibilityHidden(true)
        }
    }

    /// Dry-break coupler clamped to the bottom-load adapter. The piston
    /// valves only open once the lever seats against a latched coupling —
    /// we draw the lever down (seated/flowing) with an inflow glow that
    /// breathes at the flow cadence.
    private func couplerAssembly(width w: CGFloat, height couplerH: CGFloat) -> some View {
        let glow = reduceMotion ? 0.6
            : 0.35 + 0.55 * Double((sin(rippleClock * 2 * .pi) + 1) / 2)
        return ZStack {
            // Bottom adapter neck (short stub centered under the tank).
            VStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(palette.textTertiary.opacity(0.6))
                    .frame(width: 14, height: 5)
                // Coupler body (the hose-side unit) with lever stub.
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(palette.textSecondary.opacity(0.85))
                        .frame(width: 20, height: 11)
                    // Lever — seated (rotated down) = valve open / flowing.
                    // Per API RP-1004 the piston valves can't open until the
                    // coupler is latched + the lever seated, so a seated
                    // lever IS the "flowing" state we're depicting.
                    Capsule()
                        .fill(palette.textPrimary)
                        .frame(width: 9, height: 2.5)
                        .rotationEffect(.degrees(26))
                        .offset(x: 7, y: 2)
                }
                .overlay(
                    // Inflow glow at the seat — soft flow pulse.
                    Circle()
                        .fill(Brand.success)
                        .frame(width: 6, height: 6)
                        .blur(radius: 2)
                        .opacity(glow)
                        .offset(y: -1)
                )
            }
        }
        .frame(width: w, height: couplerH)
    }
}

/// A liquid level filling a tank from the bottom up. `level` is the
/// height of product (in points) measured from the tank FLOOR; the shape
/// fills the bottom `level` points. The surface carries a subtle sine
/// ripple driven by `rippleClock` (flattened under reduce-motion).
private struct LiquidShape: Shape {
    var level: CGFloat
    var rippleClock: CGFloat
    var reduceMotion: Bool

    // Animate the surface height + ripple phase together.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(level, rippleClock) }
        set { level = newValue.first; rippleClock = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let surfaceY = rect.maxY - level          // top of the liquid
        guard level > 0 else { return p }

        if reduceMotion || level <= 1 {
            p.addRect(CGRect(x: rect.minX, y: surfaceY,
                             width: rect.width, height: level))
            return p
        }

        // Ripple: a low-amplitude double-hump sine across the surface.
        let amp: CGFloat = 2.0
        let phase = rippleClock * 2 * .pi
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: surfaceY))
        let steps = 24
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = rect.minX + rect.width * t
            let y = surfaceY + sin(t * 2 * .pi * 2 + phase) * amp
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct NextBeatLiveScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            NextBeatLive(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_050(),
                      trailing: driverNavTrailing_050(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_050() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_050() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

// MARK: - Amenities sheet
//
// Surfaces nearby parking + fuel for the driver's current fix. Lives
// inside 050 because it's a Next-Beat companion, but the implementation
// is generic enough that other lifecycle screens (045 DepartingReceiver,
// 053 Dispatch chat) can present the same sheet by calling the same
// view directly.

private struct AmenitiesNearbySheet: View {
    let palette: Theme.Palette
    @Environment(\.dismiss) private var dismiss

    @State private var coord: CLLocationCoordinate2D?
    @State private var parking: [HereBrowseParkingItem] = []
    @State private var fuel: [HereFuelStation] = []
    @State private var isLoading: Bool = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AMENITIES NEAR YOU")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text("Parking · diesel · truck stops")
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                SheetCloseButton { dismiss() }
            }
            .padding(Space.s4)

            if isLoading {
                VStack(spacing: Space.s3) {
                    ProgressView()
                    Text("Pulling fresh data…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = error {
                VStack(spacing: Space.s3) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textSecondary)
                    Text(msg)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.s4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        if !parking.isEmpty {
                            sectionHeader("PARKING + TRUCK STOPS")
                            VStack(spacing: 6) {
                                ForEach(parking.prefix(8)) { p in
                                    parkingRow(p)
                                }
                            }
                        }
                        if !fuel.isEmpty {
                            sectionHeader("DIESEL · NEAREST 8")
                            VStack(spacing: 6) {
                                ForEach(fuel.prefix(8), id: \.id) { f in
                                    fuelRow(f)
                                }
                            }
                        }
                        if parking.isEmpty && fuel.isEmpty {
                            Text("No amenities found within 25 miles. Try widening the radius from Settings.")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    .padding(Space.s4)
                }
            }
        }
        .background(palette.bgPage.ignoresSafeArea())
        .task { await load() }
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            .foregroundStyle(palette.textTertiary)
    }

    private func parkingRow(_ p: HereBrowseParkingItem) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "p.square.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 32, height: 32)
                .background(Circle().fill(palette.bgCardSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(p.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(p.address?.label ?? "-")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let m = p.distance {
                Text("\(Int(round(Double(m) / 1609.344))) mi")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private func fuelRow(_ f: HereFuelStation) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 32, height: 32)
                .background(Circle().fill(palette.bgCardSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(f.name ?? "Diesel")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(f.address?.oneLine ?? "-")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let p = f.cheapestDieselPrice {
                Text(String(format: "$%.2f", p.price))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let c = await DriverLocationResolver.shared.currentCoordinate()
        guard let c else {
            error = "Couldn't get a location fix. Enable Location Services and try again."
            return
        }
        coord = c
        async let parkingTask: [HereBrowseParkingItem] = (try? await HereParkingClient().parkingNearby(center: c)) ?? []
        async let fuelTask: [HereFuelStation] = (try? await HereFuelPricesClient().nearby(center: c)) ?? []
        let (p, f) = await (parkingTask, fuelTask)
        parking = p
        fuel = f
        if p.isEmpty && f.isEmpty {
            error = nil
        }
    }
}

#Preview("050 · Next Beat Live · Dark") {
    NextBeatLiveScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("050 · Next Beat Live · Light") {
    NextBeatLiveScreen(theme: Theme.light).preferredColorScheme(.light)
}
