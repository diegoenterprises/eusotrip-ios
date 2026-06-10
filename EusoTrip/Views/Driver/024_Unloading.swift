//
//  024_Unloading.swift
//  EusoTrip — Lifecycle screen 024 · Unloading.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `024 Unloading.png` (Dark + Light). Fires while the trailer is
//  being unloaded at the dock. Surfaces a live pallet map (trailer
//  grid with unloaded squares), a progress counter + rate, a
//  detention ticker (free-time passed → paid), a receiver info
//  row, and an ESANG advisory.
//
//  Adapts to the product — hazmat tanker shows gallons offloaded,
//  reefer shows pallet count (same as dry van), flatbed shows
//  tie-downs released, container shows moves.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct Unloading: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    // Server-shaped projection (id String, nested {city,state}) — the legacy
    // `Load` (id Int, full LoadLocation) does NOT decode the loads.getById
    // response and silently leaves this nil.
    @State private var activeLoad: LoadsAPI.LoadDetail?
    @State private var showBol: Bool = false

    /// Real-time anchor for the detention accrual ticker — set to the
    /// load's actual `at_delivery` (arrival) lifecycle transition
    /// timestamp once hydrated. Free time runs from arrival; detention
    /// accrues once the free window passes. Nil until the live history
    /// resolves, in which case the screen falls back to the Figma
    /// reference clock so the layout still holds.
    @State private var arrivalAnchor: Date?

    /// The real instant the unload began — the `unloading` lifecycle
    /// transition `createdAt` (else the `at_delivery` arrival), parsed
    /// from the server audit trail. Drives the "STARTED" stamp on the
    /// progress card. Nil until a real transition row resolves → "-".
    @State private var unloadStartedAt: Date?

    /// Whether the load has reached a terminal unload state (every unit
    /// is provably off). The load envelope ships NO granular unloaded-unit
    /// / total-unit column (`LiveLoadFacets.palletCount` is a backend gap),
    /// so the only count we can assert is the binary "all off" at a
    /// terminal state. Drives the grid/rail to a full fill at completion
    /// while the numeric "N of N" header still em-dashes (no real
    /// denominator to print). Never produces a seeded partial number.
    @State private var unloadComplete: Bool = false

    /// Drives the autoreversing opacity breath on the PAID chip while
    /// detention is accruing. Toggled true on appear; the repeatForever
    /// animation carries it. Off under reduce-motion.
    @State private var billingPulse: Bool = false

    /// Real dock door, resolved from `appointments.getByLoad.dockNumber`
    /// for this load. Nil until the appointment hydrates (or when the
    /// appointment carries no assigned door) → the door slots render an
    /// honest em-dash sentinel, never the prior fabricated "12".
    @State private var dockDoor: String?

    /// Live detention math from `detentionAccessorials.calculateDetention`,
    /// fed the real `arrivalAnchor` ISO + the load's cargo type. Drives the
    /// running charge ($) and the active $/hr tier rate. Nil until the proc
    /// returns (no arrival anchor / empty result) → the charge + rate lines
    /// render em-dash sentinels rather than invented "$60/hr" / "$..." copy.
    @State private var detentionCalc: DetentionAPI.DetentionCalc?

    /// The driver's assigned trailer unit, resolved from the REAL fleet
    /// roster (`fleet.listAssets`, kind == "trailer"). Replaces the prior
    /// permanent em-dash: when the driver's fleet carries a trailer asset
    /// its unit number renders; with no trailer on file the honest em-dash
    /// stays. Never a fabricated "TR-2118".
    @State private var trailerUnit: String?

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        // LoadDetail (not Load) — resolve the product context from the live
        // cargo/hazmat strings via forCargo (same helper 050 uses).
        LifecycleProductContext.forCargo(
            cargoType: activeLoad?.cargoType,
            hazmatClass: activeLoad?.hazmatClass,
            role: session.user?.role
        )
    }

    /// Transport mode of the active load (truck fallback) — drives the
    /// mode-aware detained-equipment charge label (Detention vs Barge Det.).
    private var resolvedMode: TransportMode {
        TransportMode(rawValue: activeLoad?.transportMode ?? "truck") ?? .truck
    }

    // MARK: - Figma fallback
    //
    // 2026-06-06 de-fabrication: door "12" / detention "2:47" / the
    // "door 12" receiver-sub leak excised. Door reads from the live
    // appointment (`appointments.getByLoad.dockNumber`), detention from
    // the live calc proc, receiver from `activeLoad.deliveryLocation`.
    //
    // 2026-06-07 de-fabrication (this pass): the seeded unload metrics
    // were Figma literals leaking onto the live path —
    //   • off "4" / total "26"        → no granular unloaded-unit / total
    //                                    column on the load envelope
    //                                    (LiveLoadFacets.palletCount is a
    //                                    backend gap). The numeric "N of N"
    //                                    header + hero now em-dash; the
    //                                    grid/rail sit empty until a real
    //                                    terminal-state completion fills
    //                                    them (binary, provable).
    //   • started "00:32"             → now the real `unloading` (else
    //                                    `at_delivery`) lifecycle-transition
    //                                    `createdAt`, formatted local; "-"
    //                                    when no transition row exists.
    //   • eta "3:15"                  → no remaining-time projection feeds
    //                                    a dock unload (no live rate); "-".
    //   • rate "2"                    → no per-unit unload-rate telemetry
    //                                    reaches this screen; "-".
    // None of these emit a fabricated figure now. The trailer line reads
    // the REAL fleet trailer asset when one resolves, em-dash otherwise.
    private let fallbackTrailer   = "-"

    /// Trailer line — the real fleet trailer's unit number, else em-dash.
    private var trailerDisplay: String {
        guard let unit = trailerUnit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !unit.isEmpty else { return fallbackTrailer }
        return unit
    }

    // MARK: - Honest live displays

    /// Dock door for the header / pallet-map / receiver slots. The real
    /// `appointments.getByLoad.dockNumber` when present; an em-dash
    /// sentinel otherwise. Never the prior hardcoded "12".
    private var doorDisplay: String {
        guard let d = dockDoor?.trimmingCharacters(in: .whitespacesAndNewlines),
              !d.isEmpty else { return "—" }
        return d
    }

    /// Receiver name line — the delivery city/state from the load's
    /// `deliveryLocation`. Em-dash when no delivery location is on the
    /// load. No fabricated facility brand.
    private var receiverName: String {
        guard let loc = activeLoad?.deliveryLocation,
              !loc.cityState.isEmpty else { return "—" }
        return loc.cityState
    }

    /// Receiver sub line — the delivery street address, then the live
    /// dock door when assigned. Em-dash when neither is known. Replaces
    /// the prior "dispatch bell · door 12" fabrication.
    private var receiverSub: String {
        let addr = (activeLoad?.deliveryLocation?.address ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !addr.isEmpty { parts.append(addr) }
        if let d = dockDoor?.trimmingCharacters(in: .whitespacesAndNewlines),
           !d.isEmpty {
            parts.append("door \(d)")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// "2:00" free-window label, derived from the live calc's
    /// `freeTimeMinutes` (server default 120) — not a hardcoded string.
    private var freeWindowLabel: String {
        let mins = detentionCalc?.freeTimeMinutes ?? Int(freeTimeWindow / 60)
        return String(format: "%d:%02d", mins / 60, mins % 60)
    }

    /// Live $/hr — the active escalation tier's rate from the calc proc
    /// (`tierBreakdown.first?.rate`). Em-dash until the proc returns or
    /// when no billable tier has opened yet.
    private var detentionRateLabel: String {
        guard let rate = detentionCalc?.tierBreakdown.first?.rate, rate > 0 else {
            return "—"
        }
        return "\(currency(rate))/hr"
    }

    /// Live running detention charge — the calc proc's `totalCharge`.
    /// Em-dash until the proc returns; "$0" honestly once it returns
    /// inside the free window.
    private var detentionChargeLabel: String {
        guard let calc = detentionCalc else { return "—" }
        return currency(calc.totalCharge)
    }

    /// USD currency formatter for the detention $ + $/hr labels.
    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    // MARK: - Real-logic bindings
    //
    // The grid fill + progress rail bind to ONE derived fraction
    // (`unloadProgress`); the numeric "N of N" header/hero bind to the
    // count getters below. None falls back to a seeded literal — the
    // load envelope ships no granular unloaded-unit / total column, so
    // the count axis is honest em-dash until a real terminal completion
    // (binary "all off") lands.

    /// Real per-load unit total — the `palletCount` column on the load
    /// envelope (decode seam in LoadsAPI.LoadDetail; nil until the server
    /// ships it). Drives the "of N" denominator + the pallet-map cell
    /// count. Never a seeded "26".
    private var totalUnits: Int? { activeLoad?.palletCount }

    /// Live count of units off the trailer when a real source exists,
    /// else nil. There is still no granular partial-count column on the
    /// wire, so mid-unload this is nil (header/hero em-dash). The one
    /// count we CAN prove: at a terminal unload state every unit is off,
    /// so with a real total the count completes to it — "26 of 26" is a
    /// provable statement, "4 of 26" without a feed is not.
    private var unloadedNow: Int? {
        guard unloadComplete, let total = totalUnits else { return nil }
        return total
    }

    /// Numeric "off" label for the header / hero — the live count, else
    /// the honest em-dash sentinel. No seeded number.
    private var unloadedNowLabel: String {
        unloadedNow.map(String.init) ?? "—"
    }

    /// Numeric "of N" total label — the REAL `palletCount` denominator
    /// when the column ships; the honest em-dash otherwise.
    private var unloadTotalLabel: String {
        totalUnits.map(String.init) ?? "—"
    }

    /// THE real unload fraction (0…1) the grid + rail bind to. Empty
    /// (0) until a terminal completion is proven, then full (1). No
    /// fabricated partial percentage — the wire ships no partial count.
    private var unloadProgress: Double {
        unloadComplete ? 1 : 0
    }

    /// "STARTED HH:MM" value — the real `unloading` (else arrival)
    /// lifecycle-transition local time, em-dash until it resolves.
    private var startedLabel: String {
        guard let d = unloadStartedAt else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// "Est. … remaining" value — no remaining-time projection feeds a
    /// dock unload (no live unload-rate telemetry on the wire), so this
    /// is the honest em-dash sentinel rather than a seeded "3:15".
    private var etaRemainingLabel: String { "—" }

    /// "RATE …" value — no per-unit unload-rate telemetry reaches this
    /// screen, so the honest em-dash rather than a seeded "2".
    private var unloadRateValueLabel: String { "—" }

    // MARK: Detention accrual

    /// Free-time window before detention starts billing. Standard
    /// 2-hour free window (matches the "Free time ended at 2:00"
    /// reference copy). A regulatory/contract constant, not fabricated
    /// per-load data.
    private let freeTimeWindow: TimeInterval = 2 * 3600

    /// The instant detention began accruing (= arrival + free window).
    /// Nil until the live arrival timestamp resolves.
    private var detentionStart: Date? {
        arrivalAnchor.map { $0.addingTimeInterval(freeTimeWindow) }
    }

    /// Real detention elapsed at `now`. Zero before the free window
    /// passes. Returns nil when no live anchor is wired (→ the Figma
    /// reference string renders instead).
    private func detentionElapsed(at now: Date) -> TimeInterval? {
        guard let start = detentionStart else { return nil }
        return max(0, now.timeIntervalSince(start))
    }

    /// "H:MM" accrual display for a real elapsed interval.
    private func formatDetention(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600
        let m = (total % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                palletMap
                progressCard
                detentionCard
                receiverRow
                advisoryCard
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    // MARK: Header

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
                    Text(TransportLexicon.short(.detention, mode: resolvedMode).uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.warning)
                        .lineLimit(1)
                    Text("· PAID TIME")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                    // 2026-05-17 — Mode chip on unloading header. The
                    // unloading procedure differs by mode (vessel
                    // hatch discharge, rail tank-car offloading, truck
                    // dock unload). Hidden on default truck-single-
                    // vehicle.
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text("Door \(doorDisplay) · \(unloadedNowLabel) of \(unloadTotalLabel) \(ctx.unloadUnitLabel) off")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.numericText(value: Double(unloadedNow ?? 0)))
                Text(trailerDisplay)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 38, height: 38)
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Pallet map

    private var palletMap: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                // Refresh stamp = the live device clock (the map mirrors
                // the on-screen state, which refreshes with the view),
                // not a seeded "03:19". TimelineView re-renders it every
                // minute so it always reads "now".
                TimelineView(.everyMinute) { tl in
                    Text("PALLET MAP · REFRESHED \(Self.clockHHmm.string(from: tl.date))")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(palette.textSecondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text("on trailer").font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    Circle().fill(LinearGradient.diagonal).frame(width: 6, height: 6)
                    Text("unloaded").font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
            }

            // Stylized trailer grid. Trailer id reads the REAL fleet
            // trailer asset (`fleet.listAssets`, kind == "trailer") when
            // one resolves; em-dash otherwise — never a fake "TR-2118".
            // Cell count binds to the REAL `palletCount` denominator when
            // the column ships (capped at the 26-slot trailer footprint);
            // 26 stylized slots otherwise.
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(trailerDisplay)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .accessibilityLabel(trailerDisplay == "-" ? "Trailer pending" : "Trailer \(trailerDisplay)")
                    Spacer()
                    Text("DOOR \(doorDisplay)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                GeometryReader { geo in
                    let rows = 2
                    let cols = 13
                    let cellW = (geo.size.width - CGFloat(cols - 1) * 3) / CGFloat(cols)
                    let cellH: CGFloat = 18
                    // Real pallet slots when the count column ships; the
                    // full stylized footprint otherwise. Cells past the
                    // real count render as faint voids so a 12-pallet
                    // load doesn't read as a 26-pallet trailer.
                    let realSlots = totalUnits.map { max(1, min($0, rows * cols)) } ?? (rows * cols)
                    VStack(spacing: 3) {
                        ForEach(0..<rows, id: \.self) { row in
                            HStack(spacing: 3) {
                                ForEach(0..<cols, id: \.self) { col in
                                    // Bound to the REAL unload fraction.
                                    // No granular partial count exists on
                                    // the wire, so every cell sits empty
                                    // until a terminal completion is
                                    // proven (`unloadProgress` == 1), then
                                    // the cells STAGGER-fill nose→tail
                                    // (~25ms/cell spring) — never a seeded
                                    // partial grid. The stagger machinery
                                    // is the same one a real per-pallet
                                    // count feed will drive cell-by-cell
                                    // when `palletCount` granularity lands.
                                    let index = row * cols + col
                                    let isRealSlot = index < realSlots
                                    let isOff = isRealSlot && unloadProgress >= 1
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(isOff
                                              ? AnyShapeStyle(LinearGradient.diagonal)
                                              : AnyShapeStyle(isRealSlot ? palette.bgCardSoft : Color.clear))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 2)
                                                .stroke(
                                                    isOff
                                                        ? Color.clear
                                                        : palette.borderFaint.opacity(isRealSlot ? 1.0 : 0.35),
                                                    lineWidth: 1
                                                )
                                        )
                                        .frame(width: cellW, height: cellH)
                                        // Per-cell stagger on the REAL data
                                        // flip; snaps under reduce-motion.
                                        .animation(
                                            reduceMotion
                                                ? nil
                                                : .spring(response: 0.34, dampingFraction: 0.72)
                                                    .delay(Double(index) * 0.025),
                                            value: unloadProgress
                                        )
                                }
                            }
                        }
                    }
                }
                .frame(height: 44)

                HStack(spacing: 4) {
                    Text("unload")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.top, 2)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Progress card

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(unloadedNowLabel)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(unloadedNow ?? 0)))
                Text("/ \(unloadTotalLabel) \(ctx.unloadUnitLabel)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Text("Est. \(etaRemainingLabel) remaining")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            // Progress rail — width is bound to the REAL `unloadProgress`
            // fraction (unloaded / total), never a decorative value.
            // Eases with a cubic-bezier(0.4,0,0.2,1) decelerate curve on
            // a 280ms data-update beat as the count advances; snaps to
            // the final fill under reduce-motion.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 5)
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(
                            width: geo.size.width * CGFloat(unloadProgress),
                            height: 5
                        )
                        .animation(
                            reduceMotion
                                ? nil
                                : .timingCurve(0.4, 0, 0.2, 1, duration: 0.28),
                            value: unloadProgress
                        )
                }
            }
            .frame(height: 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Unload progress")
            .accessibilityValue("\(Int((unloadProgress * 100).rounded())) percent, \(unloadedNowLabel) of \(unloadTotalLabel) \(ctx.unloadUnitLabel)")

            HStack {
                Text("STARTED \(startedLabel)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                // No live unload-rate telemetry → the value em-dashes and
                // the unit suffix is dropped (no "— PALLETS/HR" sentinel
                // mash-up); the rate unit reappears with a real number.
                Text(unloadRateValueLabel == "—"
                     ? "RATE —"
                     : "RATE \(unloadRateValueLabel) \(ctx.unloadRateLabel)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Detention card

    private var detentionCard: some View {
        // Real-time accrual ticker. The clock advances off a real
        // `Date`, computing elapsed against the live `detentionStart`
        // anchor (arrival + free window). The display is H:MM, so under
        // reduce-motion we step the schedule down to a 60s minute
        // cadence and freeze the PAID-chip breath + digit-roll — no
        // per-second churn or pulsing. When no live anchor is wired the
        // card falls through to the Figma reference clock.
        let tick: TimeInterval = reduceMotion ? 60.0 : 1.0
        return TimelineView(.periodic(from: .now, by: tick)) { timeline in
            let now = timeline.date
            let elapsed = detentionElapsed(at: now)
            let display = elapsed.map(formatDetention) ?? "—"
            let isAccruing = (elapsed ?? 0) > 0

            return VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("\(TransportLexicon.short(.detention, mode: resolvedMode).uppercased()) · PAID")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1)
                    Spacer()
                    Text("PAID")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().stroke(Brand.warning.opacity(0.5), lineWidth: 1))
                        // Live "billing" pulse — a slow 1.6s autoreversing
                        // opacity breath on the PAID chip while detention
                        // is actually accruing, signalling the meter is
                        // running. Held static at full opacity when not
                        // accruing or under reduce-motion.
                        .opacity((billingPulse && isAccruing && !reduceMotion) ? 0.5 : 1.0)
                        .animation(
                            (isAccruing && !reduceMotion)
                                ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                                : .default,
                            value: billingPulse
                        )
                }
                Text(display)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Detention time accrued")
                    .accessibilityValue(display)
                Text("Free time ended at \(freeWindowLabel). \(detentionRateLabel) since. Running charge: \(detentionChargeLabel)")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        // Kick the PAID-chip breath once detention is actually accruing
        // (anchor resolved + free window past). Keyed on the live anchor
        // so it also fires after async hydration lands, not just on
        // first appear. Stays off under reduce-motion.
        .onChange(of: detentionStart) { _, newStart in
            guard !reduceMotion, let s = newStart, Date() >= s else { return }
            billingPulse = true
        }
        .onAppear {
            guard !reduceMotion, let s = detentionStart, Date() >= s else { return }
            billingPulse = true
        }
    }

    // MARK: Receiver row

    private var receiverRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(palette.bgCardSoft)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(receiverName)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(receiverSub)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("BACK")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(doorDisplay)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Advisory

    /// De-templated advisory. The seeded "two-person crew at 4/hr" and
    /// "$75" figures were Figma fixtures — there is no live lumper-crew /
    /// crew-rate feed and no per-load detention threshold on the wire, so
    /// neither number is invented. The detention guidance keys off the
    /// REAL live calc: it cites the actual $/hr tier rate when the calc
    /// has returned one, otherwise stays a generic prompt with no figure.
    private var advisoryText: String {
        let base = "Wake the house crew if it stalls; no lumper overnight."
        if let rate = detentionCalc?.tierBreakdown.first?.rate, rate > 0 {
            return "\(base) Detention is now billing at \(currency(rate))/hr past free time — ping dispatch from the Chat button and they'll rebill the shipper."
        }
        return "\(base) If detention starts billing, ping dispatch from the Chat button and they'll rebill the shipper."
    }

    private var advisoryCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Brand.success)
            Text(advisoryText)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Footer CTAs

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button {
                // Route to the messages tab via the canonical
                // RealtimeService notification — same path the
                // DISPATCH_MESSAGE WS event uses, so the chat
                // surface always resolves the same way regardless
                // of entry point. Was an empty closure (audit hit).
                NotificationCenter.default.post(
                    name: .esangOpenMeDetail,
                    object: "messages",
                    userInfo: nil
                )
            } label: {
                Text("Chat")
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

            CTAButton(title: "Capture POD") { showBol = true }
            .fullScreenCover(isPresented: $showBol) {
                // Production-grade POD capture (camera + signature
                // pad + receiver + notes) firing pod.submitPOD.
                // Replaces the prior PickupBolSigning sheet — wrong
                // sheet for delivery context. After submit the load
                // server-side flips to pod_pending; lifecycle store
                // advances to 025 Paperwork.
                DeliveryPODCaptureView(
                    loadId: lifecycle.loadId,
                    loadNumber: activeLoad?.loadNumber,
                    receiverHint: ctx.facets.deliveryFacility == LiveLoadFacets.dash
                        ? nil : ctx.facets.deliveryFacility
                )
                .environment(\.palette, palette)
                .environment(\.lifecycleAdvance, advance)
                .environmentObject(session)
            }
        }
    }

    // MARK: Hydration

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, Int(lifecycle.loadId) != nil else { return }
        activeLoad = (try? await EusoTripAPI.shared.loads.getDetail(id: lifecycle.loadId)) ?? nil

        // Detention anchor — the REAL arrival timestamp. Free time runs
        // from the moment the driver hit the receiver, so the detention
        // ticker accrues against the actual `at_delivery` (falling back
        // to `unloading`) lifecycle transition recorded server-side.
        // Stays nil if no arrival row exists → the Figma reference clock
        // renders instead, never a fake live tick.
        resolveArrivalAnchor(from: lifecycle.history)

        // Live detention math — `detentionAccessorials.calculateDetention`
        // fed the REAL arrival anchor ISO + the load's cargo type. No
        // departureTime → server computes against `now`, returning the
        // running charge + the active $/hr tier. Stays nil (→ em-dash
        // charge/rate) until a real arrival anchor resolves.
        if let anchor = arrivalAnchor {
            let arrivalISO = ISO8601DateFormatter().string(from: anchor)
            detentionCalc = try? await EusoTripAPI.shared.detention
                .calculateDetention(
                    arrivalTime: arrivalISO,
                    cargoType: activeLoad?.cargoType ?? "general"
                )
        }

        // Unload-started stamp — the REAL `unloading` (else arrival)
        // lifecycle transition `createdAt`. Drives the "STARTED HH:MM"
        // value; nil → em-dash. No seeded "00:32".
        resolveUnloadStarted(from: lifecycle.history)

        // Completion — derived honestly from lifecycle state. The load
        // envelope doesn't ship a granular unloaded-unit / total column
        // (LiveLoadFacets.palletCount is a backend gap), so we assert no
        // partial count and no numeric total. The only thing we can
        // prove is the binary "all off" once the load reaches a terminal
        // unload state — that flips the grid/rail to a full fill. The
        // numeric "N of N" header still em-dashes (no real denominator).
        // Mid-unload everything stays empty rather than fabricating a
        // partial number or a seeded "4 of 26".
        // Canonical set per TANKER_LOAD_STATUSES (schema.additions.
        // wave4-1.ts) — `unloaded` is the state that proves completion;
        // the Wave-4 disconnect block + POD/terminal states all occur
        // strictly after it. The previous set carried pod_signed /
        // completed / closed, none of which exist in the state machine
        // (the terminal state is `complete`), so completion never lit.
        let terminalUnloaded: Set<String> = [
            "unloaded", "vapor_purging", "disconnecting", "detaching",
            "released", "pod_pending", "pod_rejected", "delivered",
            "invoiced", "paid", "complete",
        ]
        let state = (lifecycle.currentState ?? activeLoad?.status ?? "").lowercased()
        if terminalUnloaded.contains(state) {
            // Spring the grid + ease the rail to full on the real data
            // update. Snap under reduce-motion.
            if reduceMotion {
                unloadComplete = true
            } else {
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.4)) {
                    unloadComplete = true
                }
            }
        }

        // Live dock door + Phase 10 closure from the SAME appointment
        // read. `appointments.getByLoad` carries the real `dockNumber`
        // assigned shipper-side (205 dock-assign) → the door slots read
        // it honestly. Then mark the appointment `unloading` (server
        // marks completed when the lifecycle store transitions to 025 /
        // Paperwork). Both best-effort.
        if let appt = try? await EusoTripAPI.shared.appointments
            .getByLoad(loadId: lifecycle.loadId) {
            if let door = appt.dockNumber?
                .trimmingCharacters(in: .whitespacesAndNewlines), !door.isEmpty {
                dockDoor = door
            }
            _ = try? await EusoTripAPI.shared.appointments
                .updateStatus(id: appt.id, status: "unloading")
        }

        // Trailer id — the driver's REAL fleet trailer asset
        // (`fleet.listAssets` is scoped to the authed user). Prefer an
        // active trailer; fall back to any trailer on file; stay nil
        // (em-dash) when the fleet carries none. Best-effort.
        if let assets = try? await EusoTripAPI.shared.fleet.listAssets().items {
            let trailers = assets.filter { $0.kind.lowercased() == "trailer" }
            let active = trailers.first {
                ($0.status ?? "active").lowercased() == "active"
            }
            if let unit = (active ?? trailers.first)?.unitNumber, !unit.isEmpty {
                trailerUnit = unit
            }
        }
    }

    /// Find the real arrival timestamp from the lifecycle audit trail
    /// and set `arrivalAnchor`. Prefers the transition INTO `at_delivery`
    /// (arrival at the receiver); falls back to the first `unloading`
    /// transition. Parses the ISO-8601 `createdAt` server stamp.
    private func resolveArrivalAnchor(from history: [LoadLifecycleAPI.StateTransition]) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func parse(_ s: String?) -> Date? {
            guard let s = s, !s.isEmpty else { return nil }
            return iso.date(from: s) ?? isoPlain.date(from: s)
        }
        // Arrival = transition whose destination is at_delivery; else the
        // first unloading transition.
        let arrival = history.first(where: { ($0.toState ?? "").lowercased() == "at_delivery" })
            ?? history.first(where: { ($0.toState ?? "").lowercased() == "unloading" })
        if let stamp = parse(arrival?.createdAt) {
            arrivalAnchor = stamp
        }
    }

    /// Find the real instant the unload began from the lifecycle audit
    /// trail and set `unloadStartedAt`. Prefers the transition INTO
    /// `unloading` (offload began); falls back to `at_delivery` (arrival
    /// at the receiver). Parses the ISO-8601 `createdAt` server stamp;
    /// leaves the anchor nil → "STARTED —" when no row exists.
    private func resolveUnloadStarted(from history: [LoadLifecycleAPI.StateTransition]) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func parse(_ s: String?) -> Date? {
            guard let s = s, !s.isEmpty else { return nil }
            return iso.date(from: s) ?? isoPlain.date(from: s)
        }
        let started = history.first(where: { ($0.toState ?? "").lowercased() == "unloading" })
            ?? history.first(where: { ($0.toState ?? "").lowercased() == "at_delivery" })
        if let stamp = parse(started?.createdAt) {
            unloadStartedAt = stamp
        }
    }

    /// Shared "HH:MM" local clock formatter for the pallet-map refresh
    /// stamp (and any other live wall clock on this screen).
    private static let clockHHmm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}

struct UnloadingScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            Unloading(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_024(),
                      trailing: driverNavTrailing_024(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_024() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_024() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

#Preview("024 · Unloading · Dark") {
    UnloadingScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("024 · Unloading · Light") {
    UnloadingScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
