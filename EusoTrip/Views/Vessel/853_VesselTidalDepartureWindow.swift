//
//  853_VesselTidalDepartureWindow.swift
//  EusoTrip — Vessel Operator · Tidal Departure Window & Under-Keel Clearance (853).
//
//  Composition port of "853 Vessel Tidal Departure Window.svg" (Light + Dark).
//  The catalog sketch for this screen arrived already written (447 lines,
//  five call-sites) rather than as the usual static composition, so its unit of
//  work this fire was VERIFICATION, not reconstruction. The SVG's composition
//  is kept intact — tide-curve hero, tri-country datum strip, vertical
//  clearance-math ledger, departure-windows list, ESang advisory, CTA pair.
//  What was verified and what failed is recorded under FINDINGS below.
//
//  ARCHETYPE — TIME/DEPTH INSTRUMENT · a go/no-go gate on a moving datum.
//  A departure window is not a schedule and not a board. It is a single
//  question asked against two curves at once: the water is rising and falling
//  on a tide, the ship's keel is fixed, and there is an interval in which the
//  gap between them is large enough to sail. The organ is therefore a HEIGHT
//  SERIES ON A 24-HOUR AXIS with a horizontal rule on it, plus a subtraction
//  that ends in one signed number.
//
//  SIBLING SEPARATION:
//    852 Port Disbursement (the other half of this fire) is a money variance
//        ledger — two columns and a delta, no time axis at all.
//    698 Berth Window / 703 Port Lineup are ALLOCATION boards: who has the
//        berth, when. They never ask whether the ship can physically leave.
//    671 Marine Weather Routing plots weather along a passage; 660 Live
//        Position plots a ship on a chart. Neither carries a datum.
//    834 Stability & Stress is the nearest relative — it also reduces a ship
//        to numbers — but it is a static condition at one instant, with no
//        time axis and no external environmental series.
//    853 is the only surface in the band where the answer changes hour by hour
//        because the sea moves.
//
//  ─────────────────────────────────────────────────────────────────────────
//  FINDINGS FROM THE VERIFICATION PASS (all fixed in this file, and all of
//  them were real — this screen was NOT sound as delivered):
//
//  F1 · STALE CITATIONS (the lane's #1 recurring failure, and the sketch had
//       three of them). Read off the live files this fire:
//         getVesselCompliance   cited :1654 → LIVE routers/vesselShipments.ts:2457  (−803)
//         getOceanTrackingBoard cited :2020 → LIVE routers/vesselShipments.ts:2821  (−801)
//         ports.maxDraft        cited db.ts:2512 → LIVE db.ts:2531
//       (worldPorts.ts:96 and spectraDestinationIntelligence.ts:536 both
//       verified CORRECT and are retained.)
//
//  F2 · WRONG INPUT SHAPES — the calls could not have worked.
//         getVesselCompliance takes `{ vesselId?: number }` (ts:2458). The
//           sketch sent `{ imo: "MV EUSO PIONEER" }` — a vessel NAME under an
//           `imo` key. tRPC's z.object strips unknown keys, so this does not
//           throw: it silently degrades to the un-filtered whole-fleet
//           compliance read. Worse than an error, because it looks fine.
//         getOceanTrackingBoard takes `{ bookingNumber: z.string().min(1) }`
//           (ts:2822). The sketch sent `{ voyageNumber: … }`, which fails
//           input validation and THROWS — so the screen would have shown a
//           permanent error banner in the field.
//       Both are replaced with the reads this screen actually needs, called
//       with their verified shapes.
//
//  F3 · FAKE WIRING — both results were discarded into `let _: … = try await`.
//       Five call-sites were counted; not one of them reached a pixel. The
//       reads here decode into @State and name the header, the ledger and the
//       port strip, or the screen says plainly that they did not resolve.
//
//  F4 · NO-OP CONTROLS (Axis B). `confirmDraft()` and `requestPilot()` were
//       `{ await load() }` — two live, tappable, haptic-firing buttons that
//       re-read and did nothing. Confirming a sailing draft is a safety
//       attestation; a button that appears to record one and does not is worse
//       than no button. Both are now `.disabled(true)` with the missing
//       procedures named on screen.
//
//  F5 · A TAP-GESTURE CONTROL. The tri-country datum strip switched on
//       `.onTapGesture` attached to a plain HStack — no Button, no disabled
//       semantics, invisible to VoiceOver as a control. That is the class that
//       sank 007. It is a real Button now.
//
//  F6 · THE DATUM SWITCH WAS ALSO A LIE. Its own copy says switching country
//       "re-references the whole UKC ledger to that country's vertical datum",
//       but selecting CA or MX only re-ran the same load and every number on
//       the ledger stayed put. Now the selection actually re-references the
//       ledger: the basis line, the authority and the station change with it,
//       and because no station is bound for any of the three, all three read
//       as unreferenced rather than one pretending to be live.
//
//  F7 · THE GRAVEST ONE — FABRICATED SAFETY DATA. The tide series was
//       `seedSeries()`, a two-term cosine evaluated on the device. From it the
//       screen derived and PAINTED AS OBSERVED: a solid tide curve, green
//       sailing-window bands, a NOW marker reading a live clearance, a
//       "NET UNDER-KEEL CLEARANCE +0.74 m", and a green "GO" chip. The file
//       header above all of it read "0 stubs · 0 mock data · 0 placeholders".
//       A GO verdict on an under-keel clearance screen that no tide station
//       produced is how a laden hull touches bottom in a channel. This is the
//       same class 842 was built to avoid (a MARPOL PASS no laboratory
//       returned) and it is handled the same way here:
//         · the verdict chip is WITHHELD — no GO, no HOLD, no colour;
//         · the net UKC figure is an em-dash in NEUTRAL ink;
//         · the green sailing-window bands are GONE, because a drawn window is
//           the verdict restated as a shape;
//         · the harmonic curve is retained ONLY as an explicitly-labelled
//           device model, drawn DASHED in tertiary ink with a caption on the
//           plot, per the fire's own rule that an extrapolated tide is drawn
//           as extrapolated and never as observed.
//       The one rule that IS real — the charted depth at the berth — is drawn
//       solid, because it comes off the ports table.
//  ─────────────────────────────────────────────────────────────────────────
//
//  WIRING (every line number below read off the live file this fire):
//    REAL — vesselShipments.getVesselShipmentDetail EXISTS
//        routers/vesselShipments.ts:561 (vesselProcedure, input { id: Int }).
//        Returns a FLAT spread including `originPort` / `destinationPort`
//        (vesselShipments.ts:587) — no `shipment` wrapper. Supplies the vessel,
//        the voyage and the booking on the header.
//    REAL — vesselShipments.getPortDetails EXISTS
//        routers/vesselShipments.ts:2313 (vesselProcedure, input
//        { portId: Int }) -> `{ ...port, berths }`. This is the screen's one
//        genuinely load-bearing read: `ports.maxDraft` (DECIMAL(6,2),
//        db.ts:2531; seeded worldPorts.ts:96 — Port of Long Beach USLGB
//        16.80 m; already consumed as draft logic at
//        services/spectraDestinationIntelligence.ts:536) is the CHARTED DEPTH
//        the whole clearance subtraction starts from.
//    REAL — vesselShipments.getPortConditions EXISTS
//        routers/vesselShipments.ts:3276 (vesselProcedure, input
//        { portId: String } — a STRING here, an Int on getPortDetails; they
//        genuinely differ on the same router). Returns `pilotageHold` from the
//        local helper `pilotageHoldFrom` (vesselShipments.ts:242). Departure
//        is gated by pilot availability as much as by water, so this belongs
//        on the window. Enterprise-gated and fail-soft: `available:false` with
//        a named reason on the free tier, rendered verbatim.
//    REAL — vesselShipments.getBerthSchedule EXISTS
//        routers/vesselShipments.ts:2337 (vesselProcedure, input
//        { portId: Int, berthId?: Int }). The berth assignment is the OTHER
//        constraint on the window: a tide the ship cannot use because the
//        berth is not clear is not a departure window.
//
//    STUB · named-gap — THE TIDE / UKC ENGINE DOES NOT EXIST.
//        Grepped the router layer repo-wide this fire: `tide|tidal|underKeel|
//        UKC` returns ZERO in frontend/server/routers. Proposed:
//          vesselShipments.getTideWindow({ unlocode, etdIso, draftM, speedKn,
//                                          country: 'US'|'CA'|'MX' })
//            -> { datum: 'MLLW'|'CD'|'NBM', authority, stationId,
//                 chartedDepthM, controllingDepthM, requiredTideM,
//                 nowHeightM, nowUkcM, verdict: 'GO'|'HOLD'|'UNKNOWN',
//                 observedAtIso, series: [{ tHour, heightM,
//                                           kind: 'observed'|'predicted' }],
//                 windows: [{ openHHMM, closeHHMM, peakUkcM,
//                             state: 'PASSED'|'ACTIVE'|'NEXT' }] }
//        `kind` per point is not decoration: an observed height and a predicted
//        one must never be drawn with the same stroke.
//
//    FOUND, NOT A GAP — there IS already a tide feed on disk, and the sketch
//        did not know about it. `frontend/server/integrations/admiralty/
//        provider.ts` is a full UK Hydrographic Office IntegrationProvider
//        (`admiralty_ukho`) with `listTidalStations()` at :43 and
//        `tidalPredictions(stationId, durationHours)` at :48 against the UKHO
//        Tidal API, already role-scoped to VESSEL_OPERATOR and already
//        advertising an `admiralty_tides` dashboard widget. Its `status` is
//        `sandbox_only` and NO router consumes it (grepped: zero hits in
//        routers/ and services/). So getTideWindow is a gap at the ROUTER
//        layer, not a green field — it has a provider waiting to be bound, and
//        NOAA CO-OPS / DFO CHS / CICESE would join it per landing country.
//        Recorded for the-oath because it changes the size of the job.
//
//    STUB · named-gap WRITES —
//          vesselShipments.confirmSailingDraft({ bookingId, draftM, windowId,
//                                                netUkcM, confirm: true })
//          vesselShipments.requestPilotTug({ bookingId, castOffEtaIso, tugs })
//        confirmSailingDraft should write the sailing-readiness row + a
//        BlockchainService.logEvent(loadId, "vessel.sailing_draft_confirmed",
//        { draftM, netUkcM, windowId }) + emitVesselAlert on
//        WS_CHANNELS.VESSEL_ALERTS / WS_EVENTS.VESSEL_STATUS_UPDATE (hook
//        lines to be verified at wire-time — they are NOT cited as verified
//        here, because they were not read this fire). Neither exists, so both
//        controls are `.disabled(true)` with the gap named on screen.
//
//  OFFLINE POLICY (doctrine §W) — derived, not stamped:
//    TIDE / UKC STATE · ONLINE_ONLY(a stale tide is a grounding). This is the
//        one surface in the band that refuses a read cache outright. A tide
//        height is wrong within minutes and a clearance derived from a stale
//        height is wrong in the direction that puts a hull on the bottom. The
//        screen therefore declines a TTL rather than declaring one, and says
//        so in the UI. If a future build does cache it, the fire's rule stands:
//        the staleness must be unmissable and an extrapolated height must be
//        drawn dashed. The plot in this file already honours the second half of
//        that rule for the device model it draws.
//    PORT / BERTH CONTEXT · READ_CACHED(10m) is acceptable in principle — a
//        berth assignment and a charted depth do not move in ten minutes.
//        HONEST SCOPE: no such cache exists. Services/EusoTripAPI.swift:1425
//        sets `.reloadIgnoringLocalAndRemoteCacheData` on every query, so
//        nothing survives a cold launch and the TTL is a policy statement, not
//        an enforced one. OPEN item (owning lane: the-oath).
//    WRITE · ONLINE_ONLY(a sailing-draft attestation is never queued). Queued,
//        it would replay against a tide that has since fallen.
//
//  COUNTRY (single-country content, never a file fork): the VERTICAL DATUM is
//    the thing that varies, and it is not cosmetic — a +0.74 m clearance
//    referenced to MLLW is a different number referenced to Chart Datum or to
//    Nivel de Bajamar Media, because the zero the height is measured from
//    moves. US NOAA CO-OPS · MLLW (active) · CA DFO CHS · Chart Datum ·
//    MX CICESE-SEMAR · NBM.
//
//  PERSONA: Vessel Operator Lena Bjornstad · Aurora Ocean Division.
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Vertical datum (the thing the country selector actually changes)

private enum TideDatum853: String, CaseIterable, Identifiable {
    case us, ca, mx
    var id: String { rawValue }
    var country: String { rawValue.uppercased() }

    /// The hydrographic authority whose predictions the window would be solved
    /// against, and the vertical datum its heights are referenced to.
    var authority: String {
        switch self {
        case .us: return "NOAA CO-OPS"
        case .ca: return "DFO CHS"
        case .mx: return "CICESE-SEMAR"
        }
    }
    var datum: String {
        switch self {
        case .us: return "MLLW"
        case .ca: return "Chart Datum"
        case .mx: return "NBM"
        }
    }
    var datumLong: String {
        switch self {
        case .us: return "Mean Lower Low Water"
        case .ca: return "Chart Datum (LAT)"
        case .mx: return "Nivel de Bajamar Media"
        }
    }
    var ring: Color {
        switch self {
        case .us: return Color(hex: 0x2952CC)
        case .ca: return Color(hex: 0xD52B1E)
        case .mx: return Color(hex: 0x006847)
        }
    }
}

// MARK: - Tolerant numeric decode (DECIMAL columns arrive as strings)

/// `ports.maxDraft` is DECIMAL(6,2) (db.ts:2531). Postgres drivers hand
/// DECIMAL back as a string to preserve precision, but a JSON serializer in
/// front of it may or may not have coerced it. Decode both, so the one real
/// number on this screen cannot vanish on a driver detail.
private struct FlexDouble853: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil
    }
}

// MARK: - Wire shapes

private struct TideShipment853: Decodable {
    let id: Int?
    let vesselName: String?
    let bookingNumber: String?
    let voyageNumber: String?
}

/// FLAT spread, no wrapper (vesselShipments.ts:587) — same repair 842 carries.
private struct TideDetail853: Decodable {
    let shipment: TideShipment853?
    private enum CodingKeys: String, CodingKey { case shipment }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(TideShipment853.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? TideShipment853(from: decoder)
        }
    }
}

private struct TideBerth853: Decodable {
    let id: Int?
    let name: String?
}

/// getPortDetails -> `{ ...port, berths }` (vesselShipments.ts:2313).
private struct TidePort853: Decodable {
    let name: String?
    let unlocode: String?
    let city: String?
    let maxDraft: FlexDouble853?
    let totalBerths: Int?
    let berths: [TideBerth853]?
}

private struct TidePilotageHold853: Decodable {
    let visibilityHold: Bool?
    let pilotageMinimumNm: Double?
    let windGustKt: Double?
}
private struct TideConditions853: Decodable {
    let available: Bool?
    let reason: String?
    let pilotageHold: TidePilotageHold853?
}

/// getBerthSchedule -> assignment rows (vesselShipments.ts:2337).
private struct TideBerthAssignment853: Decodable {
    let id: Int?
    let berthId: Int?
    let vesselName: String?
    let startTime: String?
    let endTime: String?
}

// MARK: - Departure-window anatomy

/// The three states a tidal window is ever in. These are the ANATOMY of the
/// list — every 24-hour window set has a window behind you, one you are in or
/// waiting on, and one ahead — so the rows are drawn whether or not the engine
/// has solved any. `span` and `detail` stay nil until getTideWindow ships.
private enum TideWindowState853: String {
    case passed = "PASSED"
    case active = "ACTIVE"
    case next   = "NEXT"
}

private struct TideWindow853: Identifiable {
    let id: String
    let state: TideWindowState853
    let anatomy: String
    var span: String? = nil
    var peakUkc: String? = nil

    static let unsolved: [TideWindow853] = [
        .init(id: "passed", state: .passed, anatomy: "the window behind you · already shut"),
        .init(id: "active", state: .active, anatomy: "the window you are in or waiting on"),
        .init(id: "next",   state: .next,   anatomy: "the next deep-water slot")
    ]
}

// MARK: - Tide plot (rules solid · model dashed · nothing observed)

/// The hero instrument. What it draws, and why each thing is drawn that way:
///
///  · the 24-hour axis — REAL (a day is a day), solid.
///  · the datum baseline at height zero — REAL, solid hairline, because the
///    vertical datum is a published reference, not a measurement.
///  · the charted-depth annotation — REAL when getPortDetails returns
///    `ports.maxDraft`, and labelled with the metres it returned.
///  · the harmonic curve — A DEVICE MODEL. Drawn DASHED, in tertiary ink, at
///    reduced weight, with a caption on the plot naming it. It is NOT a
///    prediction for this port: no station is bound, so it carries no station's
///    constituents. It is kept only so the screen still reads as a tide
///    instrument, and it is drawn so that it can never be mistaken for a feed.
///  · the current-time marker — REAL (the clock is real), but it carries NO
///    height readout, because the height under it is not known.
///  · sailing-window bands — NOT DRAWN. A green band on a tide plot is a GO
///    verdict expressed as a shape, and no verdict is available.
private struct TidePlot853: View {
    @Environment(\.palette) private var palette
    /// Modelled height series. Never presented as observed.
    let model: [(tHour: Double, heightM: Double)]
    /// Fraction of the day elapsed, 0…1.
    let nowFraction: Double
    let nowClock: String
    let datumLabel: String

    /// Height domain the plot box is mapped to, in metres above the datum.
    /// Static so the mapping closures below capture plain values rather than
    /// `self` (an escaping capture of a View's storage).
    private static let hTop = 2.10
    private static let hBot = -0.40

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let h = max(geo.size.height, 1)
                let top = TidePlot853.hTop
                let bot = TidePlot853.hBot
                let px: (Double) -> CGFloat = { t in CGFloat(min(max(t / 24.0, 0), 1)) * w }
                let py: (Double) -> CGFloat = { m in CGFloat((top - m) / (top - bot)) * h }

                ZStack(alignment: .topLeading) {
                    // Datum baseline — a published reference, so it is solid.
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: py(0)))
                        p.addLine(to: CGPoint(x: w, y: py(0)))
                    }
                    .stroke(palette.textTertiary.opacity(0.55), lineWidth: 1)

                    // The device model. Dashed, tertiary, thin — an unmistakably
                    // different stroke from anything this app draws as data.
                    Path { p in
                        for (i, pt) in model.enumerated() {
                            let cp = CGPoint(x: px(pt.tHour), y: py(pt.heightM))
                            if i == 0 { p.move(to: cp) } else { p.addLine(to: cp) }
                        }
                    }
                    .stroke(palette.textTertiary.opacity(0.75),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round,
                                               lineJoin: .round, dash: [4, 4]))

                    // Current time. The clock is real; the height under it is not,
                    // so the marker is a bare rule with no dot and no readout.
                    Path { p in
                        p.move(to: CGPoint(x: px(nowFraction * 24.0), y: 0))
                        p.addLine(to: CGPoint(x: px(nowFraction * 24.0), y: h))
                    }
                    .stroke(palette.textSecondary.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

                    Text(nowClock)
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(palette.bgCardSoft))
                        .offset(x: min(max(px(nowFraction * 24.0) - 16, 0), max(w - 40, 0)), y: 2)

                    Text("\(datumLabel) 0.0 m")
                        .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                        .offset(x: 2, y: max(py(0) - 11, 0))
                }
                .frame(width: w, height: h)
            }
            .frame(height: 104)

            HStack {
                ForEach(["00", "06", "12", "18", "24h"], id: \.self) { lbl in
                    Text(lbl)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    if lbl != "24h" { Spacer(minLength: 0) }
                }
            }

            HStack(spacing: 6) {
                // The legend for the dashed stroke, so the caption and the ink
                // are read together rather than one being missed.
                Rectangle()
                    .fill(palette.textTertiary.opacity(0.75))
                    .frame(width: 16, height: 1.4)
                    .overlay(
                        Rectangle().fill(palette.bgCard).frame(width: 4, height: 2)
                    )
                Text("Dashed line is a device-side harmonic model, not a tide prediction. No station is bound to this port, so no height on this plot is observed and no sailing window is drawn.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Screen

struct VesselTidalDepartureWindowScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var portId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselTidalDepartureWindowBody(shipmentId: shipmentId, portId: portId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselTidalDepartureWindowBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let portId: Int

    @State private var shipment: TideShipment853? = nil
    @State private var port: TidePort853? = nil
    @State private var conditions: TideConditions853? = nil
    @State private var assignments: [TideBerthAssignment853] = []
    @State private var datum: TideDatum853 = .us
    @State private var loading = true
    @State private var loadError: String? = nil

    /// The harmonic model the plot draws dashed. It is a SHAPE, not a
    /// prediction: two terms, no station constituents, no port. It exists so
    /// the instrument reads as a tide instrument while the engine is missing.
    private let model: [(tHour: Double, heightM: Double)] = stride(from: 0.0, through: 24.0, by: 0.25).map { t in
        (tHour: t,
         heightM: 0.85
                + 0.80 * cos(2 * .pi * (t - 3.4) / 12.42)
                + 0.32 * cos(2 * .pi * (t - 9.0) / 24.0))
    }

    private var nowClock: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date())
    }
    private var nowFraction: Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0) / 24.0
    }

    /// The one real number in the clearance subtraction.
    private var chartedDepthM: Double? { port?.maxDraft?.value }

    private var portLabel: String {
        if let p = port {
            let code = p.unlocode ?? ""
            let name = p.name ?? p.city ?? "port"
            return code.isEmpty ? name : "\(name) \(code)"
        }
        return "no port resolved"
    }

    private var subtitleLine: String {
        if let s = shipment {
            let vessel = s.vesselName ?? "vessel"
            let voy = s.voyageNumber ?? s.bookingNumber ?? ""
            return voy.isEmpty ? "\(vessel) · \(portLabel) approach"
                               : "\(voy) · \(vessel) · \(portLabel) approach"
        }
        return "No booking selected · departure window · no vessel draft on file"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · TIDE WINDOW",
                // Was "NOAA CO-OPS · LIVE". Nothing is bound to NOAA or to any
                // other station, so the caption said the opposite of the truth.
                caption: "TIDE FEED · NOT BOUND",
                title: "Tidal departure window",
                subtitle: subtitleLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError, shipment == nil, port == nil {
                    VesselErrorCard(text: err)
                } else {
                    if let err = loadError {
                        VesselErrorCard(text: "Refresh failed — \(err) The context below is the last serve this session returned and is not being updated. A departure window is a safety calculation: do not sail on a view that is not refreshing.")
                    }
                    onlineOnlyRow
                    tideHero
                    datumStrip
                    clearanceSection
                    windowsSection
                    pilotAndBerthSection
                    esangAdvisory
                    ctaPair
                    VesselGapNote(text: "Vessel, voyage, port, charted depth, berth assignment, and pilotage-hold context are available. No hydrographic station or tide series is connected, so tide height, sailing window, and under-keel clearance remain unknown. Confirm draft and request pilot/tug controls stay disabled until current tide observations are available.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Offline posture

    private var onlineOnlyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Brand.vessel)
            Text("ONLINE ONLY · a tide window is never served from cache — a stale height is a grounding, and a sailing-draft confirmation is never queued")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Brand.vessel.opacity(0.10)))
    }

    // MARK: - Hero

    private var tideHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("DEPARTURE TIDE WINDOW · \(port?.unlocode ?? "—") APPROACH")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    // The verdict chip. WITHHELD — not GO, not HOLD, and not
                    // coloured. A green chip here is the whole failure.
                    HStack(spacing: 5) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 9, weight: .heavy))
                        Text("VERDICT WITHHELD")
                            .font(.system(size: 8.5, weight: .heavy)).tracking(0.3)
                    }
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(palette.tintNeutral))
                }

                Text(heroBasisLine)
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.65)

                TidePlot853(model: model,
                            nowFraction: nowFraction,
                            nowClock: nowClock,
                            datumLabel: datum.datum)
            }
        }
    }

    private var heroBasisLine: String {
        let depth = chartedDepthM.map { String(format: "berth %.2f m", $0) } ?? "berth — m"
        return "\(depth) \(datum.datum) · ctrl depth — · draft — · \(datum.authority) stn —"
    }

    // MARK: - Datum strip (a real Button · and it really re-references)

    private var datumStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "TIDE AUTHORITY · VERTICAL DATUM",
                                right: "NO STATION BOUND")
            HStack(spacing: Space.s2) {
                ForEach(TideDatum853.allCases) { d in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { datum = d }
                    } label: {
                        datumTab(d)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(d.country) · \(d.authority) · \(d.datumLong)")
                    .accessibilityAddTraits(d == datum ? [.isSelected] : [])
                }
            }
            Text("Selecting a country re-references every height on this screen to that country's vertical datum — \(datum.datumLong). The same clearance is a different number against a different zero. No station is bound for any of the three, so the reference changes and the figures stay unreported rather than one country pretending to be live.")
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func datumTab(_ d: TideDatum853) -> some View {
        let active = d == datum
        return HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(palette.bgCard)
                    .overlay(Circle().strokeBorder(d.ring, lineWidth: 2.2))
                    .frame(width: 22, height: 22)
                Text(d.country)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(d.ring)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(d.datum)
                    .font(.system(size: 10.5, weight: .heavy))
                    .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(d.authority)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(active ? palette.bgCard : palette.bgCardSoft))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(active ? AnyShapeStyle(LinearGradient.primary)
                                     : AnyShapeStyle(palette.borderFaint),
                              lineWidth: active ? 1.4 : 1)
        )
    }

    // MARK: - Clearance math

    private var clearanceSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "CLEARANCE MATH · CHARTED-DEPTH BASIS",
                                right: chartedDepthM == nil ? "NO CHARTED DEPTH" : "1 OF 5 INPUTS LIVE")
            VesselGroupCard {
                VStack(spacing: 0) {
                    // The ONLY real input on this ledger.
                    clearanceRow(
                        label: "Charted depth at berth · \(datum.datum)",
                        note: "Port record",
                        value: chartedDepthM.map { String(format: "%.2f m", $0) },
                        real: chartedDepthM != nil
                    )
                    Divider().overlay(palette.borderFaint)
                    clearanceRow(
                        label: "Approach controlling depth · survey",
                        note: "channel survey input — deliberately NOT the berth column",
                        value: nil, real: false
                    )
                    Divider().overlay(palette.borderFaint)
                    clearanceRow(
                        label: "＋ Height of tide at cast-off",
                        note: "\(datum.authority) prediction · no station bound",
                        value: nil, real: false
                    )
                    Rectangle().fill(palette.borderSoft).frame(height: 1).padding(.vertical, Space.s2)
                    clearanceRow(
                        label: "＝ Available water depth",
                        note: "controlling depth plus tide",
                        value: nil, real: false, subtotal: true
                    )
                    Divider().overlay(palette.borderFaint)
                    clearanceRow(
                        label: "－ Laden sailing draft · even keel",
                        note: "declared on the departure condition",
                        value: nil, real: false
                    )
                    Divider().overlay(palette.borderFaint)
                    clearanceRow(
                        label: "－ Dynamic squat + port safety margin",
                        note: "Barrass / ICORELS squat term · port-published margin",
                        value: nil, real: false
                    )
                    Rectangle().fill(palette.borderSoft).frame(height: 1).padding(.vertical, Space.s3)

                    // The outcome. Neutral, em-dash, no verdict, no colour.
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("NET UNDER-KEEL CLEARANCE")
                                .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                                .foregroundStyle(palette.textPrimary)
                            Text("not computed — four of five inputs are unreported")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 8)
                        Text("—")
                            .font(.system(size: 22, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                        Text("m")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
    }

    private func clearanceRow(label: String, note: String, value: String?,
                              real: Bool, subtotal: Bool = false) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: subtotal ? 11 : 10.5, weight: subtotal ? .heavy : .semibold))
                    .foregroundStyle(subtotal || real ? palette.textPrimary : palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
            Spacer(minLength: 8)
            Text(value ?? "—")
                .font(.system(size: subtotal ? 12.5 : 11, weight: subtotal ? .heavy : .bold,
                              design: .monospaced))
                .foregroundStyle(real ? Brand.blue : palette.textTertiary)
        }
        .padding(.vertical, Space.s2)
    }

    // MARK: - Departure windows

    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "DEPARTURE WINDOWS · NEXT 24H",
                                right: "0 SOLVED")
            VesselGroupCard {
                VStack(spacing: 0) {
                    ForEach(Array(TideWindow853.unsolved.enumerated()), id: \.element.id) { idx, w in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        HStack(spacing: Space.s3) {
                            // Hollow, dashed marker — a solved window would carry
                            // a filled one. Nothing here is solved.
                            Circle()
                                .strokeBorder(palette.textTertiary,
                                              style: StrokeStyle(lineWidth: 1.6, dash: [2.5, 2.5]))
                                .frame(width: 16, height: 16)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(w.span ?? "—:— – —:—")
                                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(palette.textTertiary)
                                Text(w.anatomy)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(palette.textTertiary)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 6)
                            Text(w.state.rawValue)
                                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(palette.textTertiary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(palette.tintNeutral))
                        }
                        .padding(.vertical, Space.s3)
                    }
                }
            }
        }
    }

    // MARK: - Pilot + berth (the two non-tidal gates on a departure)

    private var pilotAndBerthSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(
                label: "OTHER GATES ON CAST-OFF",
                right: assignments.isEmpty ? "NO BERTH WINDOW" : "\(assignments.count) BERTH WINDOW\(assignments.count == 1 ? "" : "S")"
            )
            VesselGroupCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    // Pilotage — real marine reading or an honest refusal.
                    HStack(spacing: Space.s3) {
                        Image(systemName: pilotIcon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(pilotTint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pilotHeadline)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(pilotDetail)
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                    }
                    Divider().overlay(palette.borderFaint)
                    // Berth — a tide the ship cannot use is not a window.
                    HStack(spacing: Space.s3) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(assignments.isEmpty ? palette.textTertiary : Brand.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assignments.isEmpty
                                 ? "No berth assignment returned for this port"
                                 : "Berth assignment on record · \(assignments.count) window\(assignments.count == 1 ? "" : "s")")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(assignments.isEmpty ? palette.textTertiary : palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(berthDetail)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var pilotIcon: String {
        guard conditions?.available == true, let h = conditions?.pilotageHold else { return "eye.slash" }
        return h.visibilityHold == true ? "eye.trianglebadge.exclamationmark" : "eye"
    }
    private var pilotTint: Color {
        guard conditions?.available == true, let h = conditions?.pilotageHold else { return palette.textTertiary }
        return h.visibilityHold == true ? Brand.warning : palette.textSecondary
    }
    private var pilotHeadline: String {
        guard conditions?.available == true, let h = conditions?.pilotageHold else {
            return "No marine reading for this port"
        }
        if h.visibilityHold == nil { return "Visibility layer not observed — pilotage gate unknown" }
        return h.visibilityHold == true
            ? "Pilotage hold — channel visibility at or under the minimum"
            : "No pilotage hold on visibility"
    }
    private var pilotDetail: String {
        guard conditions?.available == true, let h = conditions?.pilotageHold else {
            return conditions?.reason ?? "port conditions not requested"
        }
        var parts: [String] = []
        if let m = h.pilotageMinimumNm { parts.append(String(format: "minimum %.1f nm", m)) }
        if let g = h.windGustKt { parts.append(String(format: "gust %.0f kt", g)) } else { parts.append("gust not observed") }
        return parts.joined(separator: " · ")
    }
    private var berthDetail: String {
        guard let first = assignments.first else {
            return port == nil ? "no port selected" : "getBerthSchedule returned no windows for this port"
        }
        let start = first.startTime ?? "—"
        let end = first.endTime ?? "—"
        return "\(start) → \(end)"
    }

    // MARK: - ESang advisory (carries a figure, and the figure is honest)

    private var esangAdvisory: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Circle().fill(LinearGradient.diagonal).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(esangHeadline)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("ESANG counsel is advisory and does not authorize departure.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.esangSoft))
    }

    /// The figure ESang carries is the count of unreported inputs — a real
    /// number about a real deficiency, not a manufactured clearance.
    private var esangHeadline: String {
        let live = chartedDepthM == nil ? 0 : 1
        return "\(5 - live) of the 5 clearance inputs are unreported — this window cannot be solved, and no sailing decision should be taken from this screen"
    }

    // MARK: - CTA pair (both genuinely disabled)

    /// AXIS B, and the specific repair for F4. These were live buttons that
    /// re-read and returned. They are real Buttons in a disabled state now.
    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                CTAButton(title: "Confirm sailing draft", trailingIcon: "lock.fill")
                    .disabled(true)
                    .opacity(0.5)
                    .accessibilityHint("Unavailable until current tide observations are connected")
                VesselGhostButton(title: "Pilot + tug", width: 130)
                    .disabled(true)
                    .opacity(0.5)
                    .accessibilityHint("Unavailable until current tide observations and sailing draft are confirmed")
            }
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.lock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                Text("Tide-window confirmation and pilot/tug request are unavailable until current tide observations and a confirmed sailing draft are available.")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 60)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 240)
        }
    }

    // MARK: - Load
    //
    // REAL: getVesselShipmentDetail:561 · getPortDetails:2313 ·
    //       getPortConditions:3276 · getBerthSchedule:2337.
    // Each result is decoded into @State and read by the view. The two calls
    // the sketch made (getVesselCompliance with an `imo` key it does not
    // accept, getOceanTrackingBoard with a `voyageNumber` it rejects) are gone.

    private func load() async {
        loading = true; loadError = nil

        if shipmentId > 0 {
            struct In: Encodable { let id: Int }
            do {
                let detail: TideDetail853? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
                self.shipment = detail?.shipment
            } catch {
                loadError = error.eusoUserCopy
            }
        } else {
            shipment = nil
        }

        if portId > 0 {
            struct PortIn: Encodable { let portId: Int }
            struct CondIn: Encodable { let portId: String }
            struct BerthIn: Encodable { let portId: Int }
            do {
                self.port = try await EusoTripAPI.shared.query(
                    "vesselShipments.getPortDetails", input: PortIn(portId: portId))
            } catch {
                if loadError == nil {
                    loadError = error.eusoUserCopy
                }
            }
            do {
                self.conditions = try await EusoTripAPI.shared.query(
                    "vesselShipments.getPortConditions", input: CondIn(portId: String(portId)))
            } catch {
                self.conditions = nil    // server is fail-soft here by design
            }
            do {
                self.assignments = try await EusoTripAPI.shared.query(
                    "vesselShipments.getBerthSchedule", input: BerthIn(portId: portId))
            } catch {
                self.assignments = []
            }
        } else {
            port = nil
            conditions = nil
            assignments = []
        }

        loading = false
    }
}

#Preview("853 · Vessel Tidal Departure Window · Night") {
    VesselTidalDepartureWindowScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("853 · Vessel Tidal Departure Window · Light") {
    VesselTidalDepartureWindowScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
