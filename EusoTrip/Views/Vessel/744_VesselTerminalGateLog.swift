//
//  744_VesselTerminalGateLog.swift
//  EusoTrip — Vessel Operator · Terminal Gate Log.
//
//  Faithful port of "744 Vessel Terminal Gate Log.svg" (Light + Dark), adapted onto the canonical
//  DesignSystem (Shell · BottomNav · Theme.Palette · StatusPill · CTAButton · IridescentHairline). Role
//  VESSEL_OPERATOR (carrier-side). Nav anchored to VesselOperatorNavController
//  (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME) — SHIPMENTS is inked because the gate log is an
//  operations board, not a statutory surface.
//
//  ARCHETYPE: LOG/COMPLIANCE — a gate log exists to defend ONE number, turn time, against a carrier who
//  disputes it. So the screen decomposes that number into the spans it can actually prove, tests every
//  arrival against the appointment it was promised for, and closes each crossing as an ENTER/EXIT pair.
//  The retired composition (an alternating IN/OUT spine + a 3-tile KPI trio) stated turn time once, with
//  no decomposition and no comparison, and duplicated the spine organ used by four sibling screens.
//
//  LIVE FUSION: the turn-decomposition rail, the appointment-vs-actual scatter, the crossing rows and the
//  ESang line are four faces of ONE state. `docks` (scheduled slot + actual arrival), `gateEntries` (the
//  exit half of each crossing) and `queue` (dwell awaiting a dock) re-reason together off load(): the
//  scatter dots, the rail's two metered spans, the breach count and the row deltas are all derived from
//  those same three arrays and can never disagree. Degraded provider state surfaces an explicit error
//  card, never a frozen number.
//
//  OFFLINE POLICY: READ_CACHED(120s). A gate log that lies about freshness is worse than a blank one, so
//  the header carries a two-part stamp — an AS OF clock plus a state line that reads LIVE · CACHE 120s
//  while fresh and flips to CACHED · STALE in warning, over a dashed breadcrumb rule, the moment a refresh
//  fails while prior rows are still on screen. The dock-assign write is never queued: it races other
//  operators for the same door, so offline it is refused with a stated reason instead of staged blind.
//
//  Data / wiring (line numbers read first-hand 2026-08-11 · md5 of each router recorded in the fire report):
//    yardManagement.getGateLog (EXISTS yardManagement.ts:1812 · protectedProcedure · input
//      {locationId?, date?, type:"entry"|"exit"|"all"="all", limit=50, offset=0} — whole object optional ·
//      returns {entries:[{id:"GL-n", type, timestamp, trailerNumber, tractorNumber, driverName,
//      carrierName, sealNumber, loadId:"LD-n", gate, purpose, notes}], summary:{totalEntries, totalExits,
//      uniqueCarriers, peakHour}} · NOT TENANT-SCOPED — see the P0 below).
//    yardManagement.getDockSchedule (EXISTS yardManagement.ts:615 · protectedProcedure · input
//      {locationId REQUIRED, date?, dockId?} · returns {docks:[{dockId, dockName, type, status,
//      appointments:[{id, loadId:"LD-n" :723, scheduledStart :725, actualArrival :727, status,
//      trailerNumber, carrierName}]}]} · TENANT-SCOPED via the terminal-ownership guard
//      eq(terminals.companyId, callerCompany) at :643 · admins bypass).
//    yardManagement.getYardLocations (EXISTS yardManagement.ts:281 · protectedProcedure · returns
//      {locations:[{id:"TRM-n"|"FAC-n", name, ...}]} · the terminal branch is company-scoped) — used ONLY
//      to resolve a real locationId when the screen is opened with no terminal threaded. Never invented.
//    terminals.getGateQueue (EXISTS terminals.ts:3458 · protectedProcedure · input {limit?} optional ·
//      returns [{id:"mv_n", loadNumber, origin, destination, stage, arrivedAt :3484, dockAssignment,
//      dwellHours :3486, priority, hazmatClass:null, appointmentWindow:null :3491}] · TENANCY CORRECT —
//      eq(yardMoves.companyId, companyId) at terminals.ts:3468. This is the house standard).
//    yardManagement.getAppointmentCompliance (EXISTS yardManagement.ts:2416 · protectedProcedure · input
//      {locationId?, period:"today"|"week"|"month"="week"} · returns {overallCompliancePct, totalScheduled,
//      totalOnTime, totalEarly, totalLate, totalNoShow, carrierBreakdown, peakHours} :2523-2528 · the ±15
//      minute tolerance this screen shades is that procedure's REAL threshold, :2477-2478 · NOT SCOPED).
//    terminals.assignDock (EXISTS terminals.ts:3510 · protectedProcedure · mutation · input
//      {id:String, dock:String min1 max20} · returns the updated queue item · writes yard_moves
//      status='assigned', reason='dock_assignment', toSpot=dock, assignedAt :3526-3531 · company-scoped
//      :3520).
//
//    STUB · named-gap: terminal-internal-span-telemetry — no procedure emits a yard-entry, load-start or
//      gate-out timestamp, so spans 3/4/5 of the rail (YARD · LOAD-OUT · GATE-OUT) are drawn hatched and
//      print an em-dash. Rendering five metered spans here would be fabrication. Proposed shape:
//      terminals.getTurnSpans({terminalId, date}) -> [{loadId, gateInAt, yardAt, loadStartAt, loadEndAt,
//      gateOutAt}], company-scoped.
//    STUB · named-gap: appointment-to-gate-crossing-join — getDockSchedule and getGateLog both mint the
//      SAME loadId key ("LD-n", yardManagement.ts:723 and :1901) but NO server procedure joins them, so
//      this screen performs the join CLIENT-SIDE and a crossing whose partner half is absent renders
//      EXIT NOT PAIRED with an em-dash delta. Proposed shape:
//      yardManagement.getGateCrossings({locationId, date}) -> [{loadId, unit, driverName, enterAt, exitAt,
//      turnMinutes}], company-scoped.
//    STUB · named-gap: marine-gate-log — nothing projects containerTracking gate_in/gate_out into a
//      terminal gate log. The vessel status enum carries both (vesselShipments.ts:168-169) and
//      recordContainerMovement can write them (vesselShipments.ts:1468 · vesselProcedure), but no read
//      surfaces them as gate transactions. Proposed shape:
//      terminals.getMarineGateLog({terminalId, date}) -> [{containerNumber, eventType, occurredAt,
//      portId}] over containerTracking filtered to gate event types, company-scoped.
//
//    CHAIN-OPEN: assign dock — terminals.assignDock:3510 writes the yard_moves row but does NOT broadcast
//      and does NOT insert a blockchainAuditTrail row; the waiting drayage counter-party never learns.
//      WS_EVENTS.TERMINAL_DOCK_ASSIGNED (shared/websocket-events.ts:223) and TERMINAL_QUEUE_UPDATE (:225)
//      have zero emitters; WS_CHANNELS.TERMINAL_QUEUE (:598) has zero emitters AND zero subscribers.
//    CHAIN-OPEN: read gate log — yardManagement.ts contains NO audit write and NO broadcast anywhere in
//      the file (grep blockchainAuditTrail|BlockchainService = 0; grep wsService|getIO|broadcast|io.to = 0,
//      verified 2026-08-11). Its single recordAuditEvent sits on moveTrailer (:528), never on a gate read.
//      WS_EVENTS.TERMINAL_GATE_ALERT (shared/websocket-events.ts:226) exists and is emitted by NO server
//      file. The one live-broadcast family here is TERMINAL_APPOINTMENT_STATUS_CHANGED (:233) from
//      appointments.ts:112 / :828 and terminals.ts:957 — appointment status moves, gate crossings do not.
//      The CTA therefore claims only that the dock was written, never that anyone was notified.
//
//  RBAC: every procedure on this screen is protectedProcedure — AUTH ONLY, no mode gate and no role gate,
//    so a TRUCK-only DRIVER can call all six. The only role-gated write in the router is
//    yardManagement.moveTrailer (yardManagement.ts:440, yardOpsProcedure defined at :19).
//  P0-READ-TENANCY: yardManagement.getGateLog computes `const companyId = ctx.user!.companyId || 0` at
//    yardManagement.ts:1825 and then NEVER USES IT — a dead variable creating a false sense of scoping.
//    The query filters only on gte(loads.updatedAt, dayStart) :1848, lte(loads.updatedAt, dayEnd) :1849
//    and a status IN list :1850, so every tenant's gate traffic for that date is returned, including
//    driver names :1898 and carrier company names :1899. yardManagement.getAppointmentCompliance:2416 is
//    likewise unscoped (its only filter is gte(appointments.scheduledAt, periodStart)). Both are rendered
//    behind a standing on-screen notice, never silently.
//  FABRICATED FIELDS NOT RENDERED AS DATA: `gate` is i % 2 === 0 ? "Gate A" : "Gate B"
//    (yardManagement.ts:1902) — derived from the ARRAY INDEX, not from data — so the gate name is decoded
//    but withheld behind an explicit notice. `purpose` is derived purely from status (:1903) and is not
//    rendered. `sealNumber` (:1900) and `tractorNumber` (:1897) are honest nulls, so the unit column shows
//    the trailer number and never claims a tractor plate.
//
//  transportMode=vessel · country US primary (USLGB Long Beach, Pier J, CBP release at the gate) with
//  CA CBSA and MX SAT carried in the country footer; currency USD / CAD / MXN.
//
//  ZERO-FALLBACK: state starts EMPTY, the loader overwrites UNCONDITIONALLY, an honest empty response
//  renders the bespoke empty state and never fabricated rows. File-scoped types are suffixed 744 to
//  avoid cross-file private collisions.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen wrapper (Shell + vessel nav · SHIPMENTS inked)

struct VesselTerminalGateLogScreen: View {
    let theme: Theme.Palette
    /// Terminal this log is scoped to. 0 (registry / zero-arg use) means "no terminal threaded":
    /// the loader resolves a REAL locationId from yardManagement.getYardLocations rather than
    /// guessing one, and renders the honest gap state if the operator owns no terminal.
    var terminalId: Int = 0

    init(theme: Theme.Palette, terminalId: Int = 0) {
        self.theme = theme; self.terminalId = terminalId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselTerminalGateLogBody744(terminalId: terminalId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",         systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shapes (mirror each procedure's return row EXACTLY)

/// SQL decimals and JS numbers both reach the client here; decode either without throwing.
private struct Flex744: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let i = try? c.decode(Int.self) { value = Double(i); return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil
    }
}

/// `yardManagement.getGateLog` -> entries[] (yardManagement.ts:1893-1904).
private struct GateEntry744: Decodable, Identifiable {
    let id: String
    let type: String?
    let timestamp: String?
    let trailerNumber: String?
    let tractorNumber: String?     // honest null on the wire (:1897)
    let driverName: String?
    let carrierName: String?
    let sealNumber: String?        // honest null on the wire (:1900)
    let loadId: String?            // "LD-n" — the client-side join key (:1901)
    let gate: String?              // ARRAY-INDEX DERIVED (:1902) — decoded, never rendered as fact
    let purpose: String?           // status-derived (:1903) — not rendered
    let notes: String?
}

private struct GateLogSummary744: Decodable {
    let totalEntries: Int?
    let totalExits: Int?
    let uniqueCarriers: Int?
    let peakHour: String?
}

private struct GateLogOut744: Decodable {
    let entries: [GateEntry744]
    let summary: GateLogSummary744?
}

/// `yardManagement.getDockSchedule` -> docks[].appointments[] (yardManagement.ts:715-731).
private struct DockAppt744: Decodable, Identifiable {
    let id: String
    let dockId: String?
    let carrierId: String?
    let carrierName: String?
    let loadId: String?            // "LD-n" — the same key getGateLog mints (:723)
    let type: String?
    let scheduledStart: String?    // appointments.scheduledAt (:725)
    let scheduledEnd: String?
    let actualArrival: String?     // appointments.checkedInAt (:727) — null until check-in
    let status: String?
    let trailerNumber: String?
}

private struct Dock744: Decodable, Identifiable {
    let dockId: String
    let dockName: String?
    let type: String?
    let status: String?            // available | occupied | out_of_service
    let appointments: [DockAppt744]
    var id: String { dockId }
}

private struct DockSchedule744: Decodable {
    let locationId: String?
    let date: String?
    let docks: [Dock744]
}

/// `yardManagement.getYardLocations` -> locations[] (yardManagement.ts:341-365).
private struct YardLocation744: Decodable, Identifiable {
    let id: String                 // "TRM-n" | "FAC-n"
    let name: String?
    let status: String?
}
private struct YardLocationsOut744: Decodable {
    let locations: [YardLocation744]
    let total: Int?
}

/// `terminals.getGateQueue` -> [] (terminals.ts:3479-3491).
private struct GateQueueItem744: Decodable, Identifiable {
    let id: String                 // "mv_n"
    let loadNumber: String?
    let origin: String?
    let destination: String?
    let stage: String?
    let arrivedAt: String?
    let dockAssignment: String?
    let dwellHours: Flex744?
    let priority: String?
    let hazmatClass: String?       // honest null on the wire
    let appointmentWindow: String? // honest null on the wire (:3491)
}

/// `yardManagement.getAppointmentCompliance` -> the 7-day baseline (yardManagement.ts:2523-2528).
private struct ApptCompliance744: Decodable {
    let overallCompliancePct: Double?
    let totalScheduled: Int?
    let totalOnTime: Int?
    let totalEarly: Int?
    let totalLate: Int?
    let totalNoShow: Int?
}

/// One closed (or half-open) gate crossing, assembled client-side on the shared loadId key.
private struct Crossing744: Identifiable {
    let id: String
    let unit: String
    let driver: String
    let enterAt: Date?
    let exitAt: Date?
    var turnMinutes: Int? {
        guard let e = enterAt, let x = exitAt, x > e else { return nil }
        return Int((x.timeIntervalSince(e) / 60).rounded())
    }
    var isPaired: Bool { turnMinutes != nil }
}

/// One appointment plotted on the scatter: x = scheduled slot, y = minutes early(-)/late(+).
private struct ArrivalDelta744: Identifiable {
    let id: String
    let slotHour: Double           // 0…24, from scheduledStart
    let minutesLate: Double        // actualArrival - scheduledStart
    var breached: Bool { abs(minutesLate) > 15 }   // the REAL threshold, yardManagement.ts:2477-2478
}

// MARK: - Body

private struct VesselTerminalGateLogBody744: View {
    @Environment(\.palette) private var palette
    let terminalId: Int

    // Live state only — no seeds anywhere.
    @State private var gateEntries: [GateEntry744] = []
    @State private var docks: [Dock744] = []
    @State private var queue: [GateQueueItem744] = []
    @State private var baseline: ApptCompliance744? = nil
    @State private var resolvedLocationId: String? = nil

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var loadedAt: Date? = nil
    @State private var servedFromCache = false     // a refresh failed while prior rows stood
    @State private var breachOnly = false          // ESang chip — filters the crossing list

    @State private var assigning = false
    @State private var assignResult: String? = nil
    @State private var assignError: String? = nil

    /// The ±15 minute tolerance is NOT a screen invention — it is the live threshold inside
    /// yardManagement.getAppointmentCompliance (yardManagement.ts:2477-2478).
    private let toleranceMinutes: Double = 15
    private let cacheTTLSeconds: TimeInterval = 120

    // MARK: Derived state — every organ reads THIS, never a parallel literal

    private var appointments: [DockAppt744] { docks.flatMap { $0.appointments } }

    /// Scatter dots + hero span 1 + the ESang count all come from here.
    private var arrivalDeltas: [ArrivalDelta744] {
        appointments.compactMap { a in
            guard let sIso = a.scheduledStart, let s = Self.parseISO(sIso),
                  let aIso = a.actualArrival, let act = Self.parseISO(aIso) else { return nil }
            let cal = Calendar.current
            let h = Double(cal.component(.hour, from: s)) + Double(cal.component(.minute, from: s)) / 60
            return ArrivalDelta744(id: a.id,
                                   slotHour: h,
                                   minutesLate: act.timeIntervalSince(s) / 60)
        }
    }

    private var breachCount: Int { arrivalDeltas.filter { $0.breached }.count }

    /// Span 1 · APPT-GATE. Median minutes past the appointment at gate-in. Early arrivals clamp to 0 —
    /// they consume no turn. Real: getDockSchedule scheduledStart(:725) -> actualArrival(:727).
    private var span1Minutes: Int? {
        let vals = arrivalDeltas.map { max(0, $0.minutesLate) }
        guard let m = Self.median(vals) else { return nil }
        return Int(m.rounded())
    }

    /// Span 2 · GATE-DOCK. Median queue dwell awaiting a dock assignment.
    /// Real: terminals.getGateQueue dwellHours(:3486).
    private var span2Minutes: Int? {
        let vals = queue.compactMap { $0.dwellHours?.value }.map { $0 * 60 }
        guard let m = Self.median(vals) else { return nil }
        return Int(m.rounded())
    }

    /// The hero figure. Only the metered spans are summed — spans 3/4/5 are un-instrumented and
    /// contribute nothing rather than an invented number.
    private var meteredTurnMinutes: Int? {
        let parts = [span1Minutes, span2Minutes].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }

    /// Crossings: the ENTER half is the appointment check-in, the EXIT half is the getGateLog row whose
    /// type is "exit", joined on the loadId key both procedures mint identically. No server proc does this.
    private var crossings: [Crossing744] {
        let exitByLoad: [String: GateEntry744] = Dictionary(
            gateEntries.filter { ($0.type ?? "") == "exit" }.compactMap { e in
                (e.loadId).map { ($0, e) }
            },
            uniquingKeysWith: { a, _ in a }
        )
        // Every appointment that has actually checked in is a real gate ENTER.
        let fromAppts: [Crossing744] = appointments.compactMap { a in
            guard let aIso = a.actualArrival, let enter = Self.parseISO(aIso) else { return nil }
            let key = a.loadId ?? ""
            let exitRow = exitByLoad[key]
            let unit = a.trailerNumber
                ?? exitRow?.trailerNumber
                ?? (a.loadId ?? a.id)
            return Crossing744(
                id: a.id,
                unit: unit,
                driver: exitRow?.driverName ?? a.carrierName ?? "—",
                enterAt: enter,
                exitAt: exitRow?.timestamp.flatMap(Self.parseISO)
            )
        }
        // Gate-log ENTRY rows whose load never reached an appointment check-in are still real crossings.
        let apptLoadIds = Set(appointments.compactMap { $0.loadId })
        let fromLog: [Crossing744] = gateEntries
            .filter { ($0.type ?? "") == "entry" && !apptLoadIds.contains($0.loadId ?? "") }
            .map { e in
                let exitRow = e.loadId.flatMap { exitByLoad[$0] }
                return Crossing744(
                    id: e.id,
                    unit: e.trailerNumber ?? e.loadId ?? e.id,
                    driver: e.driverName ?? "—",
                    enterAt: e.timestamp.flatMap(Self.parseISO),
                    exitAt: exitRow?.timestamp.flatMap(Self.parseISO)
                )
            }
        let all = (fromAppts + fromLog).sorted {
            ($0.enterAt ?? .distantPast) > ($1.enterAt ?? .distantPast)
        }
        guard breachOnly else { return all }
        // "SHOW BREACH" means exactly what the ESang line counts: an arrival outside the ±15 tolerance,
        // plus any crossing the platform cannot close a pair on. Crossing ids for appointment-derived
        // rows ARE the appointment ids, so the two organs share one identity.
        let breachedIds = Set(arrivalDeltas.filter { $0.breached }.map { $0.id })
        return all.filter { breachedIds.contains($0.id) || !$0.isPaired }
    }

    private var queueHead: GateQueueItem744? { queue.first { ($0.dockAssignment ?? "").isEmpty } ?? queue.first }
    private var firstAvailableDock: Dock744? { docks.first { ($0.status ?? "") == "available" } }
    private var canAssign: Bool { queueHead != nil && firstAvailableDock != nil }

    private var isStale: Bool {
        guard let t = loadedAt else { return false }
        return servedFromCache || Date().timeIntervalSince(t) > cacheTTLSeconds
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleRow
                IridescentHairline()

                if loading {
                    loadingState
                } else if let err = loadError, gateEntries.isEmpty && docks.isEmpty && queue.isEmpty {
                    errorState(err)
                } else {
                    heroTurnRail
                    scatterSection
                    crossingsSection
                    esangRow
                    countryFooter
                    actionRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ VESSEL · GATE LOG · TURN TIME")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text("USLGB LONG BEACH · PIER J")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .top) {
            Text("Gate log")
                .font(EType.h1).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: Space.s2)
            // OFFLINE POLICY affordance · READ_CACHED(120s)
            VStack(alignment: .trailing, spacing: 2) {
                Text(loadedAt.map { "AS OF \(Self.clock($0))" } ?? "AS OF —")
                    .font(EType.mono(.caption)).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                Text(isStale ? "CACHED · STALE" : "LIVE · CACHE 120s")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(isStale ? Brand.warning : Brand.success)
                // The dashed breadcrumb only inks when the read is not fresh.
                Rectangle()
                    .fill(isStale ? Brand.warning.opacity(0.55) : Color.clear)
                    .frame(width: 88, height: 1)
            }
        }
    }

    // MARK: HERO ORGAN · turn-time decomposition rail

    /// Layout proportions. The two METERED spans share 160/368 of the rail and are sized in proportion to
    /// their REAL minutes inside that share, so the metered part is to scale. The three un-instrumented
    /// spans hold the remaining 208/368 at a fixed width because their duration is unknown — the hatch
    /// and the em-dash say so rather than implying a measurement.
    private var heroTurnRail: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("TURN TIME · APPT TO GATE-OUT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                Text("\(meteredSpanCount) OF 5 METERED")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.primary)
                    .padding(.horizontal, Space.s2).padding(.vertical, 3)
                    .background(Capsule().fill(Brand.blue.opacity(0.10)))
            }

            HStack(alignment: .lastTextBaseline, spacing: Space.s3) {
                Text(meteredTurnMinutes.map { "\($0)m" } ?? "—")
                    .font(.system(size: 34, weight: .bold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(5 - meteredSpanCount) SPANS NOT METERED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(arrivalDeltas.isEmpty
                         ? "metered turn · no checked-in appointment yet"
                         : "metered turn · median of \(arrivalDeltas.count)")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }

            GeometryReader { geo in
                let total = max(geo.size.width, 1)
                let meteredShare = total * (160.0 / 368.0)
                let m1 = Double(span1Minutes ?? 0)
                let m2 = Double(span2Minutes ?? 0)
                let sum = max(m1 + m2, 0.001)
                let w1 = span1Minutes == nil ? meteredShare / 2 : meteredShare * (m1 / sum)
                let w2 = meteredShare - w1
                let darkShare = total - meteredShare
                let dw = darkShare / 3

                VStack(alignment: .leading, spacing: 0) {
                    // minutes printed above each span
                    HStack(spacing: 0) {
                        spanMinutes(span1Minutes, width: w1)
                        spanMinutes(span2Minutes, width: w2)
                        spanMinutes(nil, width: dw)
                        spanMinutes(nil, width: dw)
                        spanMinutes(nil, width: dw)
                    }
                    .frame(height: 14)

                    // the rail
                    HStack(spacing: 0) {
                        railSpan("APPT-GATE", width: w1, metered: true,
                                 fill: AnyShapeStyle(LinearGradient.primary))
                        railSpan("GATE-DOCK", width: w2, metered: true,
                                 fill: AnyShapeStyle(Brand.info.opacity(0.85)))
                        railSpan("YARD", width: dw, metered: false, fill: AnyShapeStyle(Color.clear))
                        railSpan("LOAD-OUT", width: dw, metered: false, fill: AnyShapeStyle(Color.clear))
                        railSpan("GATE-OUT", width: dw, metered: false, fill: AnyShapeStyle(Color.clear))
                    }
                    .frame(height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .leading) {
                        // dashed SLA marker at the REAL +15 tolerance edge (yardManagement.ts:2477)
                        Rectangle()
                            .fill(Brand.blue)
                            .frame(width: 2, height: 34)
                            .opacity(0.9)
                            .offset(x: slaOffset(meteredShare: meteredShare, w1: w1))
                    }

                    // drop-lines from every seam down to the minute axis
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(seamOffsets(w1: w1, w2: w2, dw: dw).enumerated()), id: \.offset) { _, x in
                            Rectangle()
                                .fill(palette.textPrimary.opacity(0.22))
                                .frame(width: 1.5, height: 16)
                                .offset(x: min(x, total - 1.5))
                        }
                    }
                    .frame(height: 16, alignment: .topLeading)

                    Rectangle().fill(palette.borderFaint).frame(height: 1)

                    // the minute axis: only metered seams carry a number
                    HStack(spacing: 0) {
                        axisTick("0 MIN", width: w1, strong: false)
                        axisTick(span1Minutes.map(String.init) ?? "—", width: w2, strong: true)
                        axisTick(meteredTurnMinutes.map(String.init) ?? "—", width: dw, strong: true)
                        axisTick("—", width: dw, strong: false)
                        axisTick("—", width: dw, strong: false)
                    }
                    .frame(height: 14)
                }
            }
            .frame(height: 88)

            // 7-day baseline ghost — real counts from getAppointmentCompliance(period: week)
            baselineGhost
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.xl)
    }

    private var meteredSpanCount: Int {
        [span1Minutes, span2Minutes].compactMap { $0 }.count
    }

    private func slaOffset(meteredShare: CGFloat, w1: CGFloat) -> CGFloat {
        // +15 minutes expressed inside span 1's own scale.
        guard let s1 = span1Minutes, s1 > 0 else { return w1 / 2 }
        let frac = min(max(toleranceMinutes / Double(s1), 0), 1)
        return w1 * CGFloat(frac)
    }

    private func seamOffsets(w1: CGFloat, w2: CGFloat, dw: CGFloat) -> [CGFloat] {
        var xs: [CGFloat] = [0]
        var run: CGFloat = 0
        for w in [w1, w2, dw, dw, dw] { run += w; xs.append(run) }
        return xs
    }

    private func spanMinutes(_ minutes: Int?, width: CGFloat) -> some View {
        Text(minutes.map { "\($0)m" } ?? "—")
            .font(.system(size: 9, weight: .heavy)).tracking(0.4).monospacedDigit()
            .foregroundStyle(minutes == nil ? palette.textTertiary : palette.textPrimary)
            .frame(width: width)
    }

    @ViewBuilder
    private func railSpan(_ label: String, width: CGFloat, metered: Bool, fill: AnyShapeStyle) -> some View {
        ZStack {
            if metered {
                Rectangle().fill(fill)
            } else {
                Rectangle().fill(palette.textPrimary.opacity(0.05))
                UnInstrumentedHatch744(spacing: 8)
                    .stroke(palette.textPrimary.opacity(0.16), lineWidth: 1)
            }
            Text(label)
                .font(.system(size: 8, weight: .bold)).tracking(0.4)
                .foregroundStyle(metered ? Color.white : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 2)
        }
        .frame(width: width)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(metered ? Color.white.opacity(0.55) : palette.textPrimary.opacity(0.12))
                .frame(width: 1)
        }
    }

    private func axisTick(_ text: String, width: CGFloat, strong: Bool) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold)).tracking(0.4).monospacedDigit()
            .foregroundStyle(strong ? palette.textSecondary : palette.textTertiary)
            .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private var baselineGhost: some View {
        let early  = Double(baseline?.totalEarly ?? 0)
        let onTime = Double(baseline?.totalOnTime ?? 0)
        let late   = Double(baseline?.totalLate ?? 0)
        let noShow = Double(baseline?.totalNoShow ?? 0)
        let total  = early + onTime + late + noShow

        VStack(alignment: .leading, spacing: Space.s2) {
            if total <= 0 {
                Text("7-DAY BASELINE UNAVAILABLE · no scheduled appointments in the window")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            } else {
                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    HStack(spacing: 2) {
                        ghostSeg(Brand.info.opacity(0.35),    w * CGFloat(early  / total))
                        ghostSeg(Brand.blue.opacity(0.35),    w * CGFloat(onTime / total))
                        ghostSeg(Brand.warning.opacity(0.60), w * CGFloat(late   / total))
                        ghostSeg(Brand.danger.opacity(0.50),  w * CGFloat(noShow / total))
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("7-DAY BASELINE · APPOINTMENT PUNCTUALITY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: Space.s2)
                    Text(String(format: "%.0f%% ON TIME", (baseline?.overallCompliancePct ?? 0)))
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func ghostSeg(_ color: Color, _ width: CGFloat) -> some View {
        Capsule().fill(color).frame(width: max(width - 2, 0), height: 8)
    }

    // MARK: MID-BAND ORGAN · appointment-vs-actual scatter

    private var scatterSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("APPOINTMENT vs ACTUAL · SCHEDULED SLOT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                Text("DOCK SCHEDULE")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }

            VStack(alignment: .leading, spacing: Space.s2) {
                if arrivalDeltas.isEmpty {
                    Text("No appointment has checked in yet, so there is nothing to plot. The scatter needs both a scheduled slot and a real arrival — it never invents one.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .frame(height: 96, alignment: .center)
                } else {
                    GeometryReader { geo in
                        let w = max(geo.size.width, 1)
                        let h: CGFloat = 96
                        ZStack(alignment: .topLeading) {
                            // ±15 tolerance band — the REAL threshold (yardManagement.ts:2477-2478)
                            Rectangle().fill(Brand.success.opacity(0.10))
                                .frame(width: w, height: Self.plotY(15, h) - Self.plotY(-15, h))
                                .offset(y: Self.plotY(-15, h))
                            // zero rule
                            Rectangle().fill(LinearGradient.primary).opacity(0.30)
                                .frame(width: w, height: 1)
                                .offset(y: Self.plotY(0, h))
                            ForEach(arrivalDeltas) { d in
                                Circle()
                                    .fill(d.breached ? Brand.danger : Brand.info.opacity(0.85))
                                    .frame(width: d.breached ? 10 : 7, height: d.breached ? 10 : 7)
                                    .offset(x: Self.plotX(d.slotHour, w) - (d.breached ? 5 : 3.5),
                                            y: Self.plotY(d.minutesLate, h) - (d.breached ? 5 : 3.5))
                            }
                            VStack(alignment: .leading) {
                                Text("-30 EARLY").font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(palette.textTertiary)
                                Spacer()
                                Text("+60 LATE").font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .frame(height: h, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("ON TIME").font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(palette.textSecondary)
                                Text("±15 TOLERANCE").font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Brand.success)
                                Spacer()
                                Text("\(breachCount) OUTSIDE").font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Brand.danger)
                            }
                            .frame(width: w, height: h, alignment: .topTrailing)
                        }
                    }
                    .frame(height: 96)

                    HStack(spacing: 0) {
                        ForEach(["06", "09", "12", "15", "18"], id: \.self) { t in
                            Text(t).font(.system(size: 8, weight: .bold)).tracking(0.4).monospacedDigit()
                                .foregroundStyle(palette.textTertiary)
                                .frame(maxWidth: .infinity, alignment: t == "06" ? .leading : (t == "18" ? .trailing : .center))
                        }
                    }
                }
            }
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg)
        }
    }

    // MARK: ROW GRAMMAR · gate crossings

    private var crossingsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("GATE CROSSINGS · ENTER / EXIT PAIR")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                Text("GATE LOG")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }

            VStack(alignment: .leading, spacing: Space.s3) {
                tenancyNotice
                if crossings.isEmpty {
                    Text(breachOnly
                         ? "Every arrival in the live window is inside ±15 and every crossing closed its pair."
                         : "No gate crossing has landed for this date. The log renders what the wire returns and never fills the gap with rows.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .padding(.vertical, Space.s3)
                } else {
                    ForEach(Array(crossings.prefix(8).enumerated()), id: \.element.id) { idx, c in
                        crossingRow(c)
                        if idx < min(crossings.count, 8) - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                        }
                    }
                }
            }
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg)

            // The wire's gate name is derived from the array index, so it is withheld rather than shown.
            Text("GATE LABEL WITHHELD · POSITION IN THE LIST, NOT A RECORDED GATE")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
        }
    }

    /// P0-READ-TENANCY, rendered as a standing band — not a footnote.
    private var tenancyNotice: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Text("!")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Brand.danger)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Brand.danger.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text("SCOPE NOT ENFORCED · THIS READ IS NOT COMPANY-FILTERED")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.danger)
                Text("Rows are not narrowed to your company — read this as terminal-wide")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Brand.danger.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(Brand.danger.opacity(0.30), lineWidth: 1))
        )
    }

    private func crossingRow(_ c: Crossing744) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.unit)
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text(c.driver)
                    .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            // the geofence event pair — two mono timestamps stacked in ONE right-aligned column
            VStack(alignment: .trailing, spacing: 2) {
                Text("ENTER \(c.enterAt.map(Self.clockSeconds) ?? "—")")
                    .font(EType.mono(.caption)).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                Text(c.exitAt.map { "EXIT  \(Self.clockSeconds($0))" } ?? "EXIT  NOT PAIRED")
                    .font(EType.mono(.caption)).monospacedDigit()
                    .foregroundStyle(c.exitAt == nil ? palette.textTertiary : palette.textSecondary)
            }
            // the delta, in its own column
            Text(c.turnMinutes.map { "\($0)m" } ?? "—")
                .font(.system(size: 14, weight: .bold)).monospacedDigit()
                .foregroundStyle(turnColor(c.turnMinutes))
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.vertical, Space.s1)
    }

    private func turnColor(_ minutes: Int?) -> Color {
        guard let m = minutes else { return palette.textTertiary }
        return m > 60 ? Brand.danger : Brand.success
    }

    // MARK: ESang

    private var esangRow: some View {
        HStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(LinearGradient.diagonal)
                .frame(width: 4, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("ESANG · GATE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(arrivalDeltas.isEmpty
                     ? "No checked-in arrival to test against tolerance yet."
                     : "\(breachCount) of \(arrivalDeltas.count) arrivals outside ±15.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: Space.s2)
            Button {
                breachOnly.toggle()
            } label: {
                Text(breachOnly ? "SHOW ALL" : "SHOW BREACH")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.primary)
                    .padding(.horizontal, Space.s3).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.blue.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s4)
        .eusoRow(radius: Radius.lg)
    }

    // MARK: Country footer (small — never a feature organ)

    private var countryFooter: some View {
        HStack(spacing: Space.s2) {
            Circle().fill(LinearGradient.primary).frame(width: 6, height: 6)
            Text("US CBP · CA CBSA · MX SAT · USD / CAD / MXN")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            Text("MODE VESSEL")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Actions

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                CTAButton(
                    title: assigning ? "Assigning…" : "Assign dock",
                    action: { Task { await assignDock() } },
                    subtitle: assignSubtitle,
                    isLoading: assigning
                )
                Button { Task { await load() } } label: {
                    Text("Refresh")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 116, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(palette.bgCard)
                                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(palette.borderSoft, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
            if let r = assignResult {
                Text(r).font(EType.caption).foregroundStyle(Brand.success)
            }
            if let e = assignError {
                Text(e).font(EType.caption).foregroundStyle(Brand.danger)
            }
            // The chain is open: the write lands, nobody is told.
            Text("Assigning a dock records the yard move. The carrier is NOT notified automatically — tell them yourself.")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
        }
    }

    private var assignSubtitle: String? {
        if let head = queueHead, let dock = firstAvailableDock {
            return "\(head.loadNumber ?? head.id) → \(dock.dockName ?? dock.dockId)"
        }
        if queueHead == nil { return "no truck in the live gate queue" }
        return "no dock reporting available"
    }

    // MARK: States

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ProgressView().tint(Brand.blue)
            Text("Reading the gate…").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s5)
        .eusoCard(radius: Radius.lg)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("GATE FEED UNAVAILABLE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(Brand.danger)
            Text(message).font(EType.caption).foregroundStyle(palette.textSecondary)
            Button("Retry") { Task { await load() } }
                .font(EType.bodyStrong).foregroundStyle(Brand.blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s5)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Load (one tick · all four organs re-reason together)

    private func load() async {
        loading = true
        loadError = nil
        assignResult = nil
        assignError = nil
        let hadRows = !(gateEntries.isEmpty && docks.isEmpty && queue.isEmpty)
        var anyFailed = false

        struct GateLogIn744: Encodable { let type: String; let limit: Int }
        struct DockScheduleIn744: Encodable { let locationId: String }
        struct QueueIn744: Encodable { let limit: Int }
        struct ComplianceIn744: Encodable { let period: String }

        // 1 · gate log (cross-tenant by construction — the banner says so on screen)
        do {
            let out: GateLogOut744 = try await EusoTripAPI.shared.query(
                "yardManagement.getGateLog", input: GateLogIn744(type: "all", limit: 50))
            gateEntries = out.entries          // UNCONDITIONAL overwrite
        } catch {
            anyFailed = true
            if !hadRows { loadError = error.eusoUserCopy }
        }

        // 2 · resolve a REAL locationId (never invented) so getDockSchedule can be called at all
        var locationId: String? = terminalId > 0 ? "TRM-\(terminalId)" : resolvedLocationId
        if locationId == nil {
            let locs: YardLocationsOut744? = try? await EusoTripAPI.shared.queryNoInput(
                "yardManagement.getYardLocations")
            locationId = locs?.locations.first(where: { $0.id.hasPrefix("TRM-") })?.id
                ?? locs?.locations.first?.id
            resolvedLocationId = locationId
        }

        // 3 · dock schedule — the scatter's x/y and the crossings' ENTER half
        if let loc = locationId {
            do {
                let sched: DockSchedule744 = try await EusoTripAPI.shared.query(
                    "yardManagement.getDockSchedule", input: DockScheduleIn744(locationId: loc))
                docks = sched.docks             // UNCONDITIONAL overwrite
            } catch {
                anyFailed = true
                if !hadRows && loadError == nil {
                    loadError = error.eusoUserCopy
                }
            }
        } else {
            docks = []                          // honest empty: no terminal resolved, no invented slots
        }

        // 4 · gate queue — the metered GATE-DOCK span + the assignDock target
        do {
            let q: [GateQueueItem744] = try await EusoTripAPI.shared.query(
                "terminals.getGateQueue", input: QueueIn744(limit: 25))
            queue = q                           // UNCONDITIONAL overwrite
        } catch {
            anyFailed = true
        }

        // 5 · 7-day baseline ghost (best-effort overlay; its absence hides the ghost, never fakes it)
        baseline = try? await EusoTripAPI.shared.query(
            "yardManagement.getAppointmentCompliance", input: ComplianceIn744(period: "week"))

        servedFromCache = anyFailed && hadRows
        if !anyFailed { loadedAt = Date() }
        loading = false
    }

    /// Real mutation. Only fires with a live queue row AND a dock the wire reports as available —
    /// the dock label is never invented.
    private func assignDock() async {
        guard let head = queueHead, let dock = firstAvailableDock else {
            assignError = queueHead == nil
                ? "No truck in the live gate queue to assign."
                : "No dock is reporting available in the live schedule."
            return
        }
        assigning = true; assignError = nil; assignResult = nil
        struct AssignIn744: Encodable { let id: String; let dock: String }
        struct AssignOut744: Decodable { let id: String?; let dockAssignment: String? }
        do {
            let out: AssignOut744 = try await EusoTripAPI.shared.mutation(
                "terminals.assignDock",
                input: AssignIn744(id: head.id, dock: String((dock.dockId).prefix(20))))
            assignResult = "Dock \(out.dockAssignment ?? dock.dockId) written to the yard move. No broadcast — the carrier is not notified."
            await load()
        } catch {
            assignError = error.eusoUserCopy
        }
        assigning = false
    }

    // MARK: Helpers

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    static func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
    static func clockSeconds(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }

    /// Scatter mapping. x maps the scheduled slot 06:00…18:00 across the plot width;
    /// y maps -30 (early, top) … +60 (late, bottom) down the plot height.
    static func plotX(_ hour: Double, _ width: CGFloat) -> CGFloat {
        CGFloat(min(max((hour - 6) / 12, 0), 1)) * width
    }
    static func plotY(_ minutes: Double, _ height: CGFloat) -> CGFloat {
        CGFloat(min(max((minutes + 30) / 90, 0), 1)) * height
    }

    static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}

// MARK: - The un-instrumented hatch (a span the platform cannot measure)

private struct UnInstrumentedHatch744: Shape {
    var spacing: CGFloat = 8
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return p
    }
}

#Preview("744 · Vessel Terminal Gate Log · Light") {
    VesselTerminalGateLogScreen(theme: Theme.light)
        .environment(\.palette, Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
#Preview("744 · Vessel Terminal Gate Log · Dark") {
    VesselTerminalGateLogScreen(theme: Theme.dark)
        .environment(\.palette, Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
