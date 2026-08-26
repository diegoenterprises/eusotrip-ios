//
//  690_VesselTerminalStatus.swift
//  EusoTrip — Vessel Operator · Terminal Status.
//
//  Faithful port of "690 Vessel Terminal Status.svg" (Light + Dark), adapted onto the canonical
//  DesignSystem (Shell · BottomNav · Theme.Palette · StatusPill · CTAButton · IridescentHairline).
//  Role VESSEL_OPERATOR (carrier-side). Nav anchored to VesselOperatorNavController
//  (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME) — terminal congestion is an operations board,
//  so the SHIPMENTS slot is inked.
//
//  ARCHETYPE: BOARD — the screen's whole job is COMPARING four facilities against each other, so the
//  composition is comparative end to end: a proportional tape where WIDTH is exposure and COLOUR is pain,
//  then a centre-zero rail that says which way each facility deviates from the group median. A single
//  scalar gauge (the retired hero) spent the whole screen on one number and answered none of that.
//
//  LIVE FUSION: the congestion tape, the deviation rail, the facility rows, the ESang read and the
//  country footer are FIVE faces of ONE `ports` array and re-reason together off load(). Segment widths,
//  median, deviation, severity, caret direction, the divert advisory and the customs regimes are all
//  DERIVED from that one state — never a parallel literal. Degraded provider state surfaces an explicit
//  error card, never a frozen number.
//
//  OFFLINE POLICY: READ_CACHED(600s) — nothing here moves money or commits an award. The staleness is
//  DRAWN, not claimed: the header subline stamps the read clock beside the cache ceiling, the tape's
//  right caption repeats the same stamp, and a facility whose weather face came back from the 600s
//  server cache carries an explicit CACHED marker so a cached board cannot be read as a live one.
//
//  Data / wiring (line numbers read first-hand 2026-08-11 — the legacy citations for terminals.ts had
//  ALL drifted and were re-read against the file rather than copied):
//    multiModal.getPortOperations (EXISTS server/routers/multiModal.ts:576 · protectedProcedure ·
//      input {portCode?:string} · returns {ports:[{code,name,city,state,country,portType,coordinates,
//      totalBerths,containerCapacityTEU,hasRailAccess,status,vesselCount,vesselsAtBerth,
//      vesselsApproaching,vesselsDeparted}], total, alerts:[]} · mounted routers.ts:3328). The congestion
//      flag is `vesselCount > 15` at multiModal.ts:619 — THE ONLY REAL CONGESTION SIGNAL IN THE CODEBASE
//      and this hero's sole data source. vesselCount = vesselsAtBerth + vesselsApproaching
//      (multiModal.ts:606), so the two right-hand row tokens are one number decomposed, not a second
//      measurement. P0-READ-TENANCY multiModal.ts:578 — `.query(async ({ input })` takes no ctx, so the
//      aggregate spans ALL tenants; the board says so on screen rather than implying these are only ours.
//    vesselShipments.getPortConditions (EXISTS server/routers/vesselShipments.ts:2944 · vesselProcedure ·
//      input {portId:string} · returns {available,reason,craneWindLimitKt,craneLimitBasis,forecastGustKt,
//      windGust,gustExceedsCraneLimit,pilotageHold,berthingSafety,source,computedAt}). Server-cached 600s
//      via lsCacheThrough (vesselShipments.ts:2965). The portId argument accepts a UN/LOCODE — resolvePort
//      branches on it at MarineWeatherService.ts:593 — so `ports[].code` threads straight in with no
//      invented id map. Enterprise-gated, so available:false is the honest normal and the weather face
//      simply stays hidden.
//    terminals.getOperatingHours (EXISTS server/routers/terminals.ts:2944 · protectedProcedure ·
//      input {terminalId:string} · returns {terminalId,terminalName,regularHours[{day,open,close,isOpen}],
//      holidays[],specialSchedules[],timezone,notes}). P0-READ-TENANCY terminals.ts:2946 — caller-supplied
//      terminalId, no companyId check, although terminals.companyId exists at drizzle/schema.ts:1480.
//    DELIBERATELY NOT CALLED — terminals.isTerminalOpen (terminals.ts:3057) is NOT a real open/closed
//      signal: it discards every stored hour and computes from defaultOperatingHours(input.terminalId) at
//      terminals.ts:3066. This screen therefore renders no open/closed verdict anywhere.
//    DELIBERATELY NOT CALLED — terminals.getTerminals (terminals.ts:433) returns racks:4 HARDCODED at
//      terminals.ts:444 over an unscoped `.from(terminals).limit(50)` at terminals.ts:439.
//    STUB · named-gap: there is no marine-terminal status / gate-hours / congestion procedure, and no
//      procedure at all maps a UN/LOCODE to a terminals row — terminals.terminalType carries "marine"
//      (drizzle/schema.ts:1489-1491) but only the private helper vesselDrayage.resolveMarineTerminal
//      (vesselDrayage.ts:104) filters on it, and it is not exposed. Proposed shape:
//      portOps.getMarineTerminalStatus: vesselProcedure.input(z.object({unlocode:z.string()})).query
//      returns {unlocode, terminalId, gateOpen, gateHours:{open,close}, trucksWaiting, avgTurnMin,
//      queueDepth, dualTransaction, source, computedAt}. Because no gate-turn metric exists anywhere in
//      the codebase, the deviation rail plots QUEUE DEPTH deviation from the same vesselCount field and
//      is labelled queue depth on screen — never as a turn time.
//    CHAIN-OPEN: publish gate hours — terminals.setOperatingHours (terminals.ts:2987) upserts
//      terminal_metadata.operating_hours and returns {success} but broadcasts nothing, so an hours change
//      is silent to every subscriber. WS_EVENTS.TERMINAL_GATE_ALERT (shared/websocket-events.ts:226) and
//      TERMINAL_BAY_STATUS (:222) exist with ZERO emitters; WS_CHANNELS.TERMINAL_QUEUE (:598) has zero
//      emitters and zero subscribers. WS_CHANNELS.TERMINAL(terminalId) (:597) IS live — emitted at
//      terminals.ts:643, :858 and :2215 — but only for appointment and check-out events, never for
//      congestion. This board therefore offers NO publish CTA and claims no counter-party notification.
//    WRITES / AUDIT / BROADCAST: this screen writes NO database row, inserts NO blockchainAuditTrail row,
//      and broadcasts on NO channel. Every procedure it touches is a query.
//
//  ZERO-FALLBACK: state starts EMPTY, the loader overwrites UNCONDITIONALLY, an honest empty response
//  renders the bespoke empty state and never fabricated rows. Segment widths, median, deviation, severity
//  bands, the divert advisory and the customs regimes are computed from the live rows only. File-scoped
//  types are suffixed 690 to avoid cross-file private collisions.
//
//  transportMode=vessel. Countries are CONTENT: the footer renders the customs regime of every country
//  actually present in the returned rows (US → CBP, CA → CBSA, MX → SAT/ANAM) rather than a fixed strip.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen wrapper (Shell + vessel nav · SHIPMENTS inked)

struct VesselTerminalStatusScreen: View {
    let theme: Theme.Palette
    /// Real `terminals.id` for the facility whose gate hours the operator can pull.
    /// 0 (registry / zero-arg use) means no terminal row is threaded — and because NO procedure maps a
    /// UN/LOCODE to a terminals row, the gate-hours CTA then renders the named-gap notice instead of
    /// inventing an id. That refusal is the honest behaviour, not a missing feature.
    var terminalId: Int = 0

    init(theme: Theme.Palette, terminalId: Int = 0) {
        self.theme = theme; self.terminalId = terminalId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselTerminalStatusBody690(terminalId: terminalId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shapes (mirror the procedure returns EXACTLY)

/// SQL decimals reach the client as a JSON number OR a string. One tolerant decoder for both.
private struct FlexInt690: Decodable {
    let value: Int?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            value = i
        } else if let d = try? c.decode(Double.self) {
            value = Int(d)
        } else if let s = try? c.decode(String.self), let d = Double(s) {
            value = Int(d)
        } else {
            value = nil
        }
    }
}

/// One row of `multiModal.getPortOperations().ports` (multiModal.ts:576). Only the fields this board
/// draws are declared; `coordinates`, `portType`, `hasRailAccess`, `containerCapacityTEU` and
/// `vesselsDeparted` are on the wire and deliberately ignored rather than rendered without a purpose.
private struct PortOps690: Decodable, Identifiable {
    let code: String?
    let name: String?
    let city: String?
    let state: String?
    let country: String?
    /// "congested" when vesselCount > 15 (multiModal.ts:619), otherwise "operational".
    let status: String?
    let vesselCount: Int?
    let vesselsAtBerth: Int?
    let vesselsApproaching: Int?
    let totalBerths: FlexInt690?

    var id: String { (code ?? "") + "|" + (name ?? "") }
    var boxes: Int { vesselCount ?? 0 }
    var berthed: Int { vesselsAtBerth ?? 0 }
    var inbound: Int { vesselsApproaching ?? 0 }
    var locode: String {
        if let c = code, !c.isEmpty { return c }
        return name ?? "—"
    }
    var facility: String { name ?? code ?? "Unnamed port" }
    var place: String {
        [city, state].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
    }
}

/// A facility whose live marine reading says work is stopped or restricted. A named struct rather than a
/// tuple so `ForEach` has a real `Identifiable` element to key on.
private struct WeatherStop690: Identifiable {
    let port: PortOps690
    let conditions: PortConditions690
    var id: String { port.id }
}

/// A customs regime present in the returned rows. Named struct for the same reason.
private struct Regime690: Identifiable {
    let code: String
    let label: String
    var id: String { code }
}

private struct PortOpsResponse690: Decodable {
    let ports: [PortOps690]
    let total: Int?
}

/// `vesselShipments.getPortConditions` (vesselShipments.ts:2944). Every field optional so an
/// enterprise-gated `available:false` payload decodes cleanly and the weather face stays hidden.
private struct PortConditions690: Decodable {
    let available: Bool?
    let reason: String?
    let craneWindLimitKt: Double?
    let forecastGustKt: Double?
    let windGust: Double?
    let gustExceedsCraneLimit: Bool?
    let pilotageHold: Bool?
    let berthingSafety: String?
    let computedAt: String?

    var gust: Double? { forecastGustKt ?? windGust }
    var isStop: Bool {
        (gustExceedsCraneLimit ?? false) || (pilotageHold ?? false) || berthingSafety == "Closed"
    }
    var isCaution: Bool { berthingSafety == "Restricted" || berthingSafety == "Caution" }
}

/// `terminals.getOperatingHours` (terminals.ts:2944).
private struct TerminalHoursDay690: Decodable, Identifiable {
    let day: String?
    let open: String?
    let close: String?
    let isOpen: Bool?
    var id: String { day ?? "" }
}

private struct TerminalHours690: Decodable {
    let terminalId: String?
    let terminalName: String?
    let regularHours: [TerminalHoursDay690]?
    let timezone: String?
    let notes: String?
}

/// Severity band. `.congested` is the REAL wire flag; `.watch` and `.clear` are presentation bands over
/// the same single `vesselCount` field, never a second measurement.
private enum Sev690 { case congested, watch, clear
    var tone: Color { switch self { case .congested: return Brand.danger
                                    case .watch:     return Brand.warning
                                    case .clear:     return Brand.success } }
    var caption: String? { switch self { case .congested: return "CONGESTED"
                                         case .watch:     return "WATCH"
                                         case .clear:     return nil } }
}

// MARK: - Body

private struct VesselTerminalStatusBody690: View {
    @Environment(\.palette) private var palette
    let terminalId: Int

    // ---- live state only · no seeds, no demo arrays -------------------------
    @State private var ports: [PortOps690] = []
    @State private var conditions: [String: PortConditions690] = [:]
    @State private var hours: TerminalHours690? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var readStamp: String = ""
    @State private var loadingHours = false
    @State private var showHours = false
    @State private var hoursGap: String? = nil

    /// How many facilities the tape compares. getPortOperations returns up to 50 rows platform-wide, so
    /// the board takes the top slice by queue depth and SAYS SO in the caption — it never implies the
    /// slice is the whole estate.
    private let boardSize = 4

    // ---- derived · every organ reads THIS state -----------------------------

    private var ranked: [PortOps690] { ports.sorted { $0.boxes > $1.boxes } }
    private var board: [PortOps690] { Array(ranked.prefix(boardSize)) }
    private var totalBoxes: Int { board.reduce(0) { $0 + $1.boxes } }

    private var median: Double {
        let s = board.map { Double($0.boxes) }.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    private func severity(_ p: PortOps690) -> Sev690 {
        if p.status == "congested" { return .congested }        // the real wire flag
        return p.boxes >= 11 ? .watch : .clear                  // presentation band over the same field
    }

    private func deviation(_ p: PortOps690) -> Double { Double(p.boxes) - median }

    private var clearCount: Int { board.filter { $0.status != "congested" }.count }

    /// Divert advisory — derived, never a written sentence with numbers pasted in.
    private var divertLine: String? {
        guard board.count >= 2, let worst = board.first, let best = board.last,
              worst.boxes > best.boxes else { return nil }
        return "Divert to \(best.locode) · \(best.boxes) boxes vs \(worst.boxes) at \(worst.locode)"
    }

    /// Customs regimes actually present in the returned rows — the country footer, drawn from live data.
    private var regimes: [Regime690] {
        let map = ["US": "CBP", "CA": "CBSA", "MX": "SAT"]
        var seen: [String] = []
        for p in board {
            let c = (p.country ?? "").uppercased()
            guard !c.isEmpty, !seen.contains(c) else { continue }
            seen.append(c)
        }
        return seen.map { Regime690(code: $0, label: map[$0] ?? "customs") }
    }

    private var weatherStops: [WeatherStop690] {
        board.compactMap { p -> WeatherStop690? in
            guard let code = p.code, let c = conditions[code],
                  (c.available ?? false), c.isStop || c.isCaution else { return nil }
            return WeatherStop690(port: p, conditions: c)
        }
    }

    // ---- body ---------------------------------------------------------------

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()

                if loading {
                    loadingCard
                } else if let err = loadError {
                    errorCard(err)
                } else if board.isEmpty {
                    emptyCard
                } else {
                    congestionTape
                    weatherFace
                    deviationRail
                    facilityBoard
                    esangRead
                }

                ctaPair
                if showHours { hoursPanel }
                countryFooter
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: header · title + the drawn staleness stamp

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text("VESSEL · TERMINAL STATUS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
                Text(ports.isEmpty ? "NO PORTS" : "\(board.count) OF \(ports.count)")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Terminal congestion")
                .font(EType.h1).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            // OFFLINE POLICY affordance — READ_CACHED(600s) made visible, never merely asserted.
            Text(stalenessLine)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var stalenessLine: String {
        guard !readStamp.isEmpty else { return "Not read yet · pull to re-read" }
        return "Port read \(readStamp) · queue live · weather cached 10 min"
    }

    // MARK: HERO ORGAN · proportional congestion tape (width = queue depth)

    private var congestionTape: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text("YOUR BOXES BY FACILITY · WIDTH = QUEUE DEPTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text(readStamp.isEmpty ? "NO READ" : "READ \(readStamp)")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }

            GeometryReader { geo in
                let gaps = CGFloat(max(board.count - 1, 0)) * 2
                let usable = max(geo.size.width - gaps, 1)
                let unit = usable / CGFloat(max(totalBoxes, 1))
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 2) {
                        ForEach(board) { p in
                            tapeSegment(p).frame(width: max(unit * CGFloat(p.boxes), 22))
                        }
                    }
                    .frame(height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    metreScale(unit: unit)
                }
            }
            .frame(height: 76 + 24)

            Text("This total covers every operator at the port, not just your estate — read it as port-wide queue depth.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(palette.textTertiary)
        }
    }

    private func tapeSegment(_ p: PortOps690) -> some View {
        let sev = severity(p)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(sev.tone)
            // the 3-stop vertical severity ramp
            LinearGradient(stops: [.init(color: .white.opacity(0.30), location: 0.00),
                                   .init(color: .white.opacity(0.06), location: 0.46),
                                   .init(color: .black.opacity(0.18), location: 1.00)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Text(p.locode).font(.system(size: 10, weight: .heavy)).tracking(0.6)
                Text("\(p.boxes)").font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .padding(.top, 6)
                Text(sev.caption.map { "BOXES · \($0)" } ?? "BOXES")
                    .font(.system(size: 8, weight: .bold)).tracking(0.4).opacity(0.78)
                    .padding(.top, 2)
            }
            .foregroundStyle(Color.white)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.leading, 8).padding(.top, 14)
        }
    }

    private func metreScale(unit: CGFloat) -> some View {
        let steps = Array(stride(from: 0, through: max((totalBoxes / 10) * 10, 0), by: 10))
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(palette.borderFaint).frame(height: 1)
            ForEach(steps, id: \.self) { n in
                Rectangle().fill(palette.borderSoft)
                    .frame(width: 1, height: 5)
                    .offset(x: unit * CGFloat(n), y: 1)
                Text(n == 0 ? "0 BOXES" : "\(n)")
                    .font(.system(size: 8, weight: .bold)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .offset(x: unit * CGFloat(n) + (n == 0 ? 0 : -6), y: 8)
            }
        }
        .frame(height: 24, alignment: .topLeading)
    }

    // MARK: the weather face — a terminal that is crane- or pilotage-stopped

    @ViewBuilder private var weatherFace: some View {
        if !weatherStops.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                ForEach(weatherStops) { stop in
                    HStack(alignment: .top, spacing: Space.s3) {
                        Image(systemName: "wind")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(stop.conditions.isStop ? Brand.danger : Brand.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Space.s2) {
                                Text(stop.port.locode).font(EType.bodyStrong)
                                    .foregroundStyle(palette.textPrimary)
                                StatusPill(text: stop.conditions.isStop ? "crane stop" : "restricted",
                                           kind: stop.conditions.isStop ? .danger : .warning)
                                StatusPill(text: "cached", kind: .neutral)
                            }
                            Text(weatherDetail(stop.conditions))
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Space.s4)
                    .eusoRow(radius: Radius.lg)
                }
            }
        }
    }

    private func weatherDetail(_ c: PortConditions690) -> String {
        var parts: [String] = []
        if let g = c.gust { parts.append(String(format: "gust %.0f kt", g)) }
        if let l = c.craneWindLimitKt { parts.append(String(format: "crane limit %.0f kt", l)) }
        if let b = c.berthingSafety { parts.append("berthing \(b.lowercased())") }
        if c.pilotageHold == true { parts.append("pilotage hold") }
        if parts.isEmpty { parts.append("marine reading available") }
        return parts.joined(separator: " · ")
    }

    // MARK: MID-BAND ORGAN · centre-zero deviation rail

    private var deviationRail: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text("QUEUE VS MEDIAN ACROSS YOUR FACILITIES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text("\u{00B1}90PX = \u{00B1}10 BOXES")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("FEWER BOXES").font(.system(size: 8, weight: .bold)).tracking(0.4)
                        .foregroundStyle(Brand.success)
                    Spacer()
                    Text(String(format: "MEDIAN %.1f BOXES", median))
                        .font(.system(size: 8, weight: .bold)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("MORE BOXES").font(.system(size: 8, weight: .bold)).tracking(0.4)
                        .foregroundStyle(Brand.danger)
                }

                GeometryReader { geo in
                    let half = geo.size.width / 2
                    let scale = max(min(half - 76, 90), 8) / 10        // 90px == 10 boxes, clamped
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(LinearGradient.diagonal)
                            .frame(width: 2, height: CGFloat(board.count) * 24 + 8)
                            .offset(x: half - 1)
                        Rectangle().fill(LinearGradient.primary)
                            .frame(width: 10, height: 2).offset(x: half - 5, y: -2)
                        Rectangle().fill(LinearGradient.primary)
                            .frame(width: 10, height: 2)
                            .offset(x: half - 5, y: CGFloat(board.count) * 24 + 8)
                        ForEach(Array(board.enumerated()), id: \.element.id) { i, p in
                            railBar(p, index: i, half: half, scale: scale)
                        }
                    }
                }
                .frame(height: CGFloat(board.count) * 24 + 16)
                .padding(.top, Space.s3)

                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.top, Space.s2)
                Text("GATE-TURN METRIC UNAVAILABLE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.warning)
                    .padding(.top, Space.s2)
                Text("Rail plots queue depth · a marine terminal equivalent is planned, not built")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 2)
            }
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg)
        }
    }

    private func railBar(_ p: PortOps690, index: Int, half: CGFloat, scale: CGFloat) -> some View {
        let dev = deviation(p)
        let len = max(CGFloat(abs(dev)) * scale, 6)
        let y = CGFloat(index) * 24 + 6
        let worse = dev > 0
        let tone: Color = worse ? severity(p).tone : Brand.success
        let sign = dev > 0 ? "+" : ""
        return ZStack(alignment: .topLeading) {
            Capsule().fill(tone)
                .frame(width: len, height: 10)
                .offset(x: worse ? half : half - len, y: y)
            Text("\(p.locode) \(sign)\(String(format: "%.1f", dev))")
                .font(EType.mono(.caption)).tracking(0.4)
                .foregroundStyle(tone)
                .fixedSize()
                .frame(width: 92, alignment: worse ? .leading : .trailing)
                .offset(x: worse ? half + len + 8 : half - len - 100, y: y - 1)
        }
    }

    // MARK: ROWS · no icon chip, no pill, no dots, no mini-track

    private var facilityBoard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text("FACILITY DETAIL · RANKED BY QUEUE DEPTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text("\(board.count) OF \(ports.count)")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(board.enumerated()), id: \.element.id) { i, p in
                    facilityRow(p)
                    if i < board.count - 1 {
                        Rectangle().fill(palette.borderFaint)
                            .frame(height: 1).padding(.vertical, Space.s2)
                    }
                }
            }
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg)
        }
    }

    private func facilityRow(_ p: PortOps690) -> some View {
        let worse = deviation(p) > 0
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.facility)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(subLine(p))
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            // 14px delta caret · success / danger
            Image(systemName: worse ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 11))
                .foregroundStyle(worse ? Brand.danger : Brand.success)
                .padding(.top, 2)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(p.boxes) boxes")
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("\(p.berthed) berthed · \(p.inbound) inbound")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func subLine(_ p: PortOps690) -> String {
        var parts = [p.locode]
        if !p.place.isEmpty { parts.append(p.place) }
        if let b = p.totalBerths?.value, b > 0 { parts.append("\(b) berths") }
        return parts.joined(separator: " · ")
    }

    // MARK: ESang · congestion read (derived from the same rows)

    @ViewBuilder private var esangRead: some View {
        if let line = divertLine {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                                 center: .init(x: 0.35, y: 0.30),
                                                 startRadius: 1, endRadius: 15))
                        .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("ESANG · CONGESTION READ")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.primary)
                    Text(line)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("\(clearCount) of \(board.count) facilities sit under the 15-vessel congestion flag")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg)
        }
    }

    // MARK: CTA pair · both real Buttons

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: "Check gate hours",
                action: {
                    guard terminalId > 0 else {
                        // Honest refusal — the named gap, rendered rather than faked.
                        hoursGap = "No procedure maps a UN/LOCODE to a terminals row, so this board cannot resolve a terminal id from \(board.first?.locode ?? "a port") on its own. terminals.getOperatingHours (terminals.ts:2944) needs a real terminals.id threaded in. Proposed fix: portOps.getMarineTerminalStatus {unlocode}."
                        hours = nil
                        showHours = true
                        return
                    }
                    Task { showHours = true; await loadHours() }
                },
                leadingIcon: "clock",
                isLoading: loadingHours
            )
            Button {
                Task { await load() }
            } label: {
                Text("Re-read")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(minHeight: 52)
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderSoft, lineWidth: 1)
            )
            .disabled(loading)
            .opacity(loading ? 0.6 : 1)
        }
    }

    // MARK: gate-hours panel · real payload OR the honest gap notice

    private var hoursPanel: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text("GATE HOURS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Button { showHours = false } label: {
                    Text("Hide").font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
            if loadingHours {
                Text("Reading terminal operating hours…")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                    .eusoCard(radius: Radius.lg)
            } else if let gap = hoursGap {
                VStack(alignment: .leading, spacing: Space.s2) {
                        Text("LIVE STATUS UNAVAILABLE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(Brand.warning)
                    Text(gap).font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.tintWarning))
            } else if let h = hours {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(h.terminalName ?? "Terminal \(terminalId)")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    ForEach(h.regularHours ?? []) { d in
                        HStack {
                            Text((d.day ?? "").capitalized)
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                            Spacer()
                            Text((d.isOpen ?? false) ? "\(d.open ?? "—") – \(d.close ?? "—")" : "closed")
                                .font(EType.mono(.caption))
                                .foregroundStyle((d.isOpen ?? false) ? palette.textPrimary : palette.textTertiary)
                        }
                    }
                    if let tz = h.timezone, !tz.isEmpty {
                        Text(tz).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    }
                    Text("Stored hours only. A change to these hours notifies no one, so treat this as a lookup, not an alert — confirm with the terminal before you plan against it.")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.lg)
            }
        }
    }

    // MARK: country footer · regimes present in the LIVE rows

    @ViewBuilder private var countryFooter: some View {
        if !regimes.isEmpty {
            HStack(spacing: Space.s2) {
                Text(regimes.map { $0.code }.joined(separator: " · "))
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text("·").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                Text(regimes.map { $0.label }.joined(separator: " · "))
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: states

    private var loadingCard: some View {
        Text("Reading port operations…")
            .font(EType.caption).foregroundStyle(palette.textSecondary)
            .padding(Space.s5).frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg)
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("PORT READ FAILED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("No congestion figure is shown rather than a stale one.")
                .font(.system(size: 10, weight: .regular)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s5).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.tintDanger))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            Text("No ports returned")
                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("The port operations read came back with no ports. Nothing is drawn — there is no congestion to compare.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s5).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: - load · real calls only, unconditional overwrite

    private func load() async {
        loading = true; loadError = nil
        struct PortsIn690: Encodable { let portCode: String? }
        do {
            let resp: PortOpsResponse690 = try await EusoTripAPI.shared.query(
                "multiModal.getPortOperations", input: PortsIn690(portCode: nil))
            ports = resp.ports                       // UNCONDITIONAL — an empty list clears the board
            readStamp = Self.clock()
        } catch {
            ports = []
            conditions = [:]
            loadError = error.eusoUserCopy
            loading = false
            return
        }
        await loadConditions()
        if terminalId > 0 && showHours { await loadHours() }
        loading = false
    }

    /// Best-effort weather face. Enterprise-gated and server-cached 600s, so a failure or an
    /// `available:false` payload simply leaves the face hidden — it never degrades the board.
    private func loadConditions() async {
        struct CondIn690: Encodable { let portId: String }
        var next: [String: PortConditions690] = [:]
        for p in board {
            guard let code = p.code, !code.isEmpty else { continue }
            if let c: PortConditions690 = try? await EusoTripAPI.shared.query(
                "vesselShipments.getPortConditions", input: CondIn690(portId: code)) {
                next[code] = c
            }
        }
        conditions = next                            // UNCONDITIONAL
    }

    private func loadHours() async {
        guard terminalId > 0 else { return }
        loadingHours = true; hoursGap = nil
        struct HoursIn690: Encodable { let terminalId: String }
        do {
            hours = try await EusoTripAPI.shared.query(
                "terminals.getOperatingHours", input: HoursIn690(terminalId: String(terminalId)))
        } catch {
            hours = nil
            hoursGap = error.eusoUserCopy
        }
        loadingHours = false
    }

    private static func clock() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date())
    }
}

#Preview("690 Terminal Status · Light") {
    VesselTerminalStatusScreen(theme: Theme.light).environment(\.palette, Theme.light)
}
#Preview("690 Terminal Status · Dark") {
    VesselTerminalStatusScreen(theme: Theme.dark).environment(\.palette, Theme.dark)
}
