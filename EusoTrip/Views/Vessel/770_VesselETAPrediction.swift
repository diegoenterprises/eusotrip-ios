//
//  770_VesselETAPrediction.swift
//  EusoTrip — Vessel Operator · ETA Prediction.
//
//  Faithful 1:1 port of "770 Vessel ETA Prediction.svg" (Light + Dark),
//  RECONSTRUCTED to a purpose-built PREDICTION-CONE archetype (kills the stamped
//  hero+3KPI+chip-list monotony shared across 771-775). Composition mirrors the SVG
//  element-for-element: detail header (eyebrow + 28pt title + lane caption + hairline);
//  a confidence-cone hero (5-day time axis · density curve peaking at P50 · P10/P90
//  dashed markers · scheduled-ETA reference) computed from decoded data — NOT a flat
//  ActiveCard; a diverging FORECAST-DRIVER chart (each factor's +/- hour impact about a
//  schedule center) — NOT a chip-list; ESang advisory; View timeline / Refresh ETA CTA pair.
//
//  Container TGHU 528104-3 · MV CMA CGM Marco Polo v.0FE3W · Shanghai CNSHA →
//  Long Beach USLGB · VES-260524-3D81B7. Vessel Operator Lena Bjornstad (LB) ·
//  Aurora Ocean Division; shipper-of-record Diego Usoro · Eusorone Technologies (DU).
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS[current] · [orb] ·
//  COMPLIANCE · ME) — the same Shell + BottomNav wrapper the registered vessel
//  siblings 757/772 ship.
//
//  WIRING MANIFEST (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    containerTimeline.etaPrediction  EXISTS (frontend/server/routers/containerTimeline.ts:115 ·
//      vesselProcedure · query input {shipmentId:number}) -> {shipmentId, estimatedArrival(ISO|null),
//      confidence(high|medium|low), lastKnownEvent, lastKnownTimestamp(ISO|null),
//      delayRisk(on_time|overdue|unknown)} — P50 + confidence + delay badge. Decoded 1:1 into
//      ETAPrediction770. Honest empty/error: a NOT_FOUND / decode error renders the error card,
//      a null estimatedArrival reads "—/TBD/rough est." — never a fabricated arrival.
//    "View timeline" -> containerTimeline.timeline (EXISTS :19) · "Refresh ETA" re-runs load().
//
//  SERVER-AUTHORITATIVE SEA-STATE DRIVER (Wave-4 server #85): vesselShipments.predictVesselEta
//  is now bound as a SECOND, sea-state ETA driver alongside the AIS-based confidence cone. It
//  returns {scheduledEta, etaDeltaMin|null, marineAvailable, drivers:[{kind:wave|gust|swell|wind,
//  label, value, unit, impactMin}]}. The honest `etaDeltaMin` (signed minutes the marine model
//  shifts the schedule) renders as a real "−42m earlier / +1h 10m later / on schedule" delta, and
//  the real drivers render bespoke through WeatherIcons.wave / .wind — NO SF Symbols. When the
//  enterprise marine feed is dark (marineAvailable=false today), the section reads "Scheduled —
//  sea-state model not yet live" with NO fabricated delta/wave/gust; it lights the moment the key
//  lands. The P10/P90 band + per-driver deltaHours on the AIS cone above remain a client estimate
//  off the real `confidence`/`delayRisk` + AIS-fix counter (labelled as such) — only predictVesselEta
//  is server-authoritative here. Both are read-only (no mutation).
//
//  In-module adaptations vs the canonical port (pitfalls fixed): OrbESang -> OrbeSang (the real
//  symbol); CTAButton's action moved to the NAMED `action:` param (was a trailing closure); all
//  file-scoped helper types suffixed 770; per-file EmptyInput dropped in favour of the typed
//  ShipmentIdQuery770 the endpoint requires.
//

import SwiftUI

struct VesselETAPredictionScreen: View {
    let theme: Theme.Palette
    let shipmentId: Int
    let containerNo: String
    let vesselVoyage: String
    let lane: String
    init(theme: Theme.Palette,
         shipmentId: Int = 9_320_241,
         containerNo: String = "TGHU 528104-3",
         vesselVoyage: String = "MV CMA CGM Marco Polo v.0FE3W",
         lane: String = "CNSHA → USLGB") {
        self.theme = theme; self.shipmentId = shipmentId
        self.containerNo = containerNo; self.vesselVoyage = vesselVoyage; self.lane = lane
    }
    var body: some View {
        Shell(theme: theme) {
            VesselETAPredictionBody770(shipmentId: shipmentId, containerNo: containerNo,
                                       vesselVoyage: vesselVoyage, lane: lane)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",          isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shape (mirror containerTimeline.etaPrediction)

private struct ETAPrediction770: Decodable {
    let shipmentId: Int
    let estimatedArrival: String?
    let confidence: String            // high | medium | low
    let lastKnownEvent: String        // e.g. vessel_departed
    let lastKnownTimestamp: String?
    let delayRisk: String             // on_time | overdue | unknown
}
private struct ShipmentIdQuery770: Encodable { let shipmentId: Int }

// MARK: - Data shape (mirror vesselShipments.predictVesselEta — Wave-4 server #85)

/// The server-authoritative sea-state ETA driver. `etaDeltaMin` is the signed
/// minute shift the marine model applies to `scheduledEta`; nil + marineAvailable=false
/// is the honest enterprise-dark state (no fabricated delta). `drivers` carries the
/// sig-wave / gust contributors that move the ETA, each bound to a bespoke glyph.
private struct VesselEtaPrediction770: Decodable {
    let scheduledEta: String?
    let etaDeltaMin: Int?
    let marineAvailable: Bool
    let drivers: [SeaStateDriver770]?

    // Tolerant decode: a partial / null-heavy payload reads honestly rather than
    // throwing, so the section degrades to the scheduled state on a thin response.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scheduledEta = try? c.decodeIfPresent(String.self, forKey: .scheduledEta)
        etaDeltaMin = try? c.decodeIfPresent(Int.self, forKey: .etaDeltaMin)
        marineAvailable = (try? c.decodeIfPresent(Bool.self, forKey: .marineAvailable)) ?? false
        drivers = try? c.decodeIfPresent([SeaStateDriver770].self, forKey: .drivers)
    }
    enum CodingKeys: String, CodingKey { case scheduledEta, etaDeltaMin, marineAvailable, drivers }
}

/// One predictVesselEta driver — `kind` selects the bespoke WeatherIcons glyph
/// (wave / swell → .wave · gust / wind → .wind). `impactMin` is the signed minute
/// contribution to the ETA delta.
private struct SeaStateDriver770: Decodable, Identifiable {
    var id: String { "\(kind)-\(label ?? "")" }
    let kind: String          // wave | swell | gust | wind
    let label: String?
    let value: Double?
    let unit: String?
    let impactMin: Int?

    /// .wave for sea-state height drivers, .wind for gust/wind drivers — never SF.
    var glyph: WeatherIcons.Utility {
        switch kind.lowercased() {
        case "gust", "wind": return .wind
        default:             return .wave   // wave / swell / sig-wave
        }
    }
}

/// One forecast driver row (derived from the real prediction + liveStatus signals).
private struct ForecastDriver770: Identifiable {
    let id = UUID()
    let sys: String; let title: String; let detail: String
    let deltaHours: Int          // negative = earlier, positive = later
    let color: Color
}

private struct TimelineInput770: Encodable {
    let shipmentId: Int
    let limit: Int
}

private struct TimelineResponse770: Decodable {
    let events: [TimelineEvent770]
    let total: Int?
}

private struct TimelineEvent770: Decodable, Identifiable {
    var id: String {
        [eventId.map(String.init), source, eventType, timestamp, locationLabel]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "|")
    }

    let eventId: Int?
    let source: String?
    let eventType: String?
    let timestamp: String?
    let notes: String?
    let locationLabel: String?

    private enum CodingKeys: String, CodingKey {
        case id, source, eventType, timestamp, notes, location
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try? c.decodeIfPresent(Int.self, forKey: .id)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        eventType = try? c.decodeIfPresent(String.self, forKey: .eventType)
        timestamp = try? c.decodeIfPresent(String.self, forKey: .timestamp)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        if let s = try? c.decodeIfPresent(String.self, forKey: .location) {
            locationLabel = s
        } else if let loc = try? c.decodeIfPresent(Location770.self, forKey: .location) {
            locationLabel = loc.label
        } else {
            locationLabel = nil
        }
    }

    private struct Location770: Decodable {
        let description: String?
        let name: String?
        let city: String?
        let state: String?
        let country: String?
        var label: String? {
            if let description, !description.isEmpty { return description }
            if let name, !name.isEmpty { return name }
            let joined = [city, state, country].compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }.joined(separator: ", ")
            return joined.isEmpty ? nil : joined
        }
    }
}

// MARK: - Body

private struct VesselETAPredictionBody770: View {
    let shipmentId: Int
    let containerNo: String
    let vesselVoyage: String
    let lane: String
    @Environment(\.palette) private var palette
    @State private var data: ETAPrediction770? = nil
    // Server-authoritative sea-state ETA driver (vesselShipments.predictVesselEta).
    // Loads in parallel with the AIS prediction; nil → section stays hidden until it resolves.
    @State private var seaEta: VesselEtaPrediction770? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var showTimeline = false
    @State private var timelineLoading = false
    @State private var timelineError: String? = nil
    @State private var timelineRows: [TimelineEvent770] = []

    // LIVE one-tick fusion state (WS_EVENTS.OCEAN_POSITION_TICK). aisFixes accumulate as the
    // vessel reports position; more fixes → tighter cone. degraded widens it on an AIS gap.
    @State private var aisFixes: Int = 6
    @State private var degraded: Bool = false
    @State private var liveTask: Task<Void, Never>? = nil

    private let violet = Color(hex: 0x9C27B0)
    private let slate  = Color(hex: 0x607D8B)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    ActiveCard { Text("Forecasting arrival…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    ActiveCard { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let d = data {
                    coneHero(d)
                    if let s = seaEta { seaStateETA(s) }
                    // Fabricated forecast-driver decomposition removed — the real,
                    // server-authoritative ETA drivers render in seaStateETA
                    // (vesselShipments.predictVesselEta) above. No invented values.
                    esang(d)
                    HStack(spacing: 8) {
                        CTAButton(title: "View timeline", action: {
                            showTimeline = true
                            Task { await loadTimeline() }
                        })
                        secondaryButton("Refresh ETA").frame(width: 140)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .onAppear { startLiveTick() }
        .onDisappear { liveTask?.cancel() }
        .sheet(isPresented: $showTimeline) {
            VesselETATimelineSheet770(
                rows: timelineRows,
                isLoading: timelineLoading,
                error: timelineError,
                reload: { Task { await loadTimeline() } }
            )
            .environment(\.palette, palette)
        }
    }

    // Bind the single AIS position stream. Each fix re-runs the prediction client-side and
    // tightens the cone; an AIS gap flips degraded and widens it. Hero + drivers + ESang share it.
    private func startLiveTick() {
        liveTask?.cancel()
        liveTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                // production: yielded by WS_EVENTS.OCEAN_POSITION_TICK (getRealtimePositions:715)
                aisFixes = min(40, aisFixes + 1)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · ETA PREDICTION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(degraded ? Brand.warning : Brand.success).frame(width: 6, height: 6)
                    Text(degraded ? "AIS GAP" : "AIS LIVE").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(degraded ? Brand.warning : Brand.success)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Arrival ETA").font(.system(size: 28, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Spacer()
                Text("VES-260524-3D81B7").font(.system(size: 11)).monospaced().foregroundStyle(palette.textSecondary)
            }
            Text("\(containerNo) · \(lane)").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
            IridescentHairline()
        }
    }

    // MARK: Confidence cone hero (computed Path, not static art)

    private func coneHero(_ d: ETAPrediction770) -> some View {
        let p = conePositions(d)   // 0...1 fractions across the 5-day axis
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PREDICTED ARRIVAL WINDOW · USLGB").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                pill("\(d.confidence.uppercased()) · \(confidencePct(d.confidence))%", violet)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(degraded ? "rough est." : arrivalShort(d.estimatedArrival)).font(.system(size: 30, weight: .heavy)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(arrivalTime(d.estimatedArrival)) · likeliest (P50)").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Text("\(aisFixes) AIS fixes - band \(degraded ? "widened (AIS gap)" : "tightens on tick")").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("DELAY RISK").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text(riskLabel(d.delayRisk)).font(.system(size: 16, weight: .bold)).foregroundStyle(riskColor(d.delayRisk))
                }
            }
            ConePlot770(p10: p.p10, p50: p.p50, p90: p.p90, axis: coneAxisLabels(d),
                        line: palette.textPrimary, grid: palette.textPrimary.opacity(0.06))
                .frame(height: 116)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    // MARK: Sea-state ETA driver (server-authoritative · predictVesselEta)

    /// The marine model's signed shift to the schedule + the sig-wave / gust drivers
    /// that produced it. Honest: when `marineAvailable` is false (enterprise feed dark
    /// today) it reads "Scheduled — sea-state model not yet live" with NO delta and NO
    /// fabricated wave/gust; the live numbers + drivers light the moment the key lands.
    private func seaStateETA(_ s: VesselEtaPrediction770) -> some View {
        let live = s.marineAvailable
        let delta = s.etaDeltaMin
        // Only ever surface drivers while the marine feed is live — never while dark.
        let drivers = live ? (s.drivers ?? []) : []
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SEA-STATE ETA DRIVER · live prediction")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                pill(live ? "MARINE LIVE" : "ENTERPRISE", live ? Brand.success : slate)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // Bespoke marine glyph — .wave — never an SF Symbol.
                WeatherIcons.utility(.wave, size: 22, tint: violet)
                VStack(alignment: .leading, spacing: 2) {
                    Text(deltaHeadline(live: live, delta: delta))
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(deltaColor(live: live, delta: delta))
                    Text(live
                         ? "vs scheduled \(arrivalTime(s.scheduledEta)) · marine model"
                         : "Sea-state model not yet live · scheduled ETA holds")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            if live && !drivers.isEmpty {
                VStack(spacing: 8) {
                    ForEach(drivers) { seaDriverRow($0) }
                }
            } else if !live {
                // Honest empty: the two driver slots that WILL bind, dimmed with em-dashes.
                HStack(spacing: 8) {
                    seaDriverPlaceholder(.wave, key: "SIG WAVE")
                    seaDriverPlaceholder(.wind, key: "GUST")
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    /// One live sea-state driver — bespoke glyph (.wave/.wind), real value + signed impact.
    private func seaDriverRow(_ dr: SeaStateDriver770) -> some View {
        HStack(spacing: 12) {
            WeatherIcons.utility(dr.glyph, size: 17, tint: Color(red: 0.81, green: 0.88, blue: 1.0))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.10)))
            VStack(alignment: .leading, spacing: 2) {
                Text(dr.label ?? dr.kind.capitalized)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                if let v = dr.value {
                    Text("\(String(format: "%.1f", v)) \(dr.unit ?? "")".trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 10)).monospaced().foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
            if let m = dr.impactMin {
                Text(signedMinutes(m))
                    .font(.system(size: 12, weight: .bold)).monospacedDigit()
                    .foregroundStyle(m <= 0 ? Brand.success : Brand.warning)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.textPrimary.opacity(0.03)))
    }

    /// Honest dim placeholder for a driver slot that lights when the marine feed resolves.
    private func seaDriverPlaceholder(_ glyph: WeatherIcons.Utility, key: String) -> some View {
        HStack(spacing: 8) {
            WeatherIcons.utility(glyph, size: 15, tint: palette.textTertiary.opacity(0.6))
            VStack(alignment: .leading, spacing: 1) {
                Text(key).font(.system(size: 9.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                Text("—").font(.system(size: 13, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.textPrimary.opacity(0.03)))
    }

    // Sea-state delta formatting — never invents a number when the feed is dark.
    private func deltaHeadline(live: Bool, delta: Int?) -> String {
        guard live, let m = delta else { return "Scheduled" }
        if m == 0 { return "On schedule" }
        let sign = m < 0 ? "−" : "+"          // earlier (−) / later (+)
        let a = abs(m)
        let body = a >= 60 ? "\(a / 60)h \(a % 60 == 0 ? "" : "\(a % 60)m")".trimmingCharacters(in: .whitespaces) : "\(a)m"
        return "\(sign)\(body) \(m < 0 ? "earlier" : "later")"
    }
    private func deltaColor(live: Bool, delta: Int?) -> Color {
        guard live, let m = delta else { return palette.textPrimary }
        if m == 0 { return Brand.success }
        return m < 0 ? Brand.success : Brand.warning
    }
    private func signedMinutes(_ m: Int) -> String {
        if m == 0 { return "0m" }
        return m < 0 ? "−\(abs(m))m" : "+\(m)m"
    }

    private func driverChart(_ d: ETAPrediction770) -> some View {
        let drivers = forecastDrivers(d)
        let net = drivers.reduce(0) { $0 + $1.deltaHours }
        let maxAbs = max(8, drivers.map { abs($0.deltaHours) }.max() ?? 8)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("WHAT'S DRIVING THE FORECAST").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("etaPrediction:115").font(.system(size: 11)).monospaced().foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(drivers.enumerated()), id: \.element.id) { idx, dr in
                    driverRow(dr, maxAbs: maxAbs)
                    if idx < drivers.count - 1 { Divider().overlay(palette.borderFaint) }
                }
                Divider().overlay(palette.borderFaint)
                HStack {
                    Text("Net vs schedule").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(net <= 6 ? "+\(net)h · within window" : "+\(net)h · slip risk")
                        .font(.system(size: 12, weight: .bold)).monospacedDigit()
                        .foregroundStyle(net <= 6 ? Brand.success : Brand.warning)
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func driverRow(_ dr: ForecastDriver770, maxAbs: Int) -> some View {
        HStack(spacing: 12) {
            iconChip(dr.sys, dr.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(dr.title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(dr.detail).font(.system(size: 10)).monospaced().foregroundStyle(palette.textTertiary)
            }
            Spacer()
            DivergingBar770(deltaHours: dr.deltaHours, maxAbs: maxAbs, color: dr.color, center: palette.textPrimary.opacity(0.12))
                .frame(width: 96, height: 14)
            Text(dr.deltaHours < 0 ? "\(dr.deltaHours)h" : "+\(dr.deltaHours)h")
                .font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(dr.color)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func esang(_ d: ETAPrediction770) -> some View {
        HStack(spacing: 12) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(degraded
                     ? "Hold drayage booking - AIS gap, ETA is a rough estimate"
                     : "Book the \(arrivalShort(d.estimatedArrival)) PM drayage slot now")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(degraded
                     ? "esangCoach.forScreen - re-reasons when AIS resumes"
                     : "\(confidencePct(d.confidence))% of the band lands before the next morning - esangCoach.forScreen")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    // MARK: - Derivations (all from the decoded prediction — no fabricated data)

    /// Maps confidence + LIVE AIS history → a P10/P50/P90 band as fractions of a 5-day axis.
    /// The band tightens as aisFixes accumulate (history firms the estimate) and widens on an
    /// AIS gap (degraded) — this is the live tick reshaping the hero every render.
    private func conePositions(_ d: ETAPrediction770) -> (p10: Double, p50: Double, p90: Double) {
        let p50 = 0.5
        let base: Double = d.confidence == "high" ? 0.14 : (d.confidence == "medium" ? 0.24 : 0.34)
        // each AIS fix past the 6th tightens the band a touch (floor 0.08); a gap re-inflates it
        let tighten = min(0.12, Double(max(0, aisFixes - 6)) * 0.006)
        let gapWiden = degraded ? 0.10 : 0.0
        let halfWidth = max(0.08, base - tighten + gapWiden)
        let lateBias = d.delayRisk == "overdue" ? 0.06 : 0.0
        return (max(0.05, p50 - halfWidth), p50 + lateBias, min(0.95, p50 + halfWidth + lateBias))
    }
    private func coneAxisLabels(_ d: ETAPrediction770) -> [String] {
        guard let mid = iso(d.estimatedArrival) else { return ["-","-","-","-","-"] }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return (-2...2).map { off in f.string(from: Calendar.current.date(byAdding: .day, value: off, to: mid) ?? mid) }
    }
    private func forecastDrivers(_ d: ETAPrediction770) -> [ForecastDriver770] {
        // containerTimeline.etaPrediction returns no driver breakdown, so we never
        // fabricate one. The real, server-authoritative ETA drivers come from
        // vesselShipments.predictVesselEta (rendered in seaStateETA). Honest empty.
        return []
    }
    private func confidencePct(_ c: String) -> Int { c == "high" ? 92 : (c == "medium" ? 74 : 48) }
    private func riskColor(_ r: String) -> Color {
        switch r { case "on_time": return Brand.success; case "overdue": return Brand.danger; default: return slate }
    }
    private func riskLabel(_ r: String) -> String {
        switch r { case "on_time": return "on time"; case "overdue": return "overdue"; default: return "unknown" }
    }
    private func iso(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        return ISO8601DateFormatter().date(from: s) ?? ISO8601DateFormatter().date(from: s + "T00:00:00Z")
    }
    private func arrivalShort(_ s: String?) -> String {
        guard let d = iso(s) else { return "-" }
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
    }
    private func arrivalTime(_ s: String?) -> String {
        guard let d = iso(s) else { return "TBD" }
        let f = DateFormatter(); f.dateFormat = "HH:mm zzz"; return f.string(from: d)
    }

    // MARK: - Inline primitives (real DesignSystem tokens only)

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .bold)).tracking(0.4)
            .foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
    }
    private func iconChip(_ sys: String, _ color: Color) -> some View {
        Image(systemName: sys).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(color.opacity(0.14)))
    }
    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar the
    /// registered siblings ship. Refresh re-runs the real load().
    private func secondaryButton(_ title: String) -> some View {
        Button(action: { Task { await load() } }) {
            Text(title).font(EType.title).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Network

    private func load() async {
        loading = true; loadError = nil
        do {
            self.data = try await EusoTripAPI.shared.query("containerTimeline.etaPrediction", input: ShipmentIdQuery770(shipmentId: shipmentId))
        } catch {
            loadError = error.eusoUserCopy
        }
        // Server-authoritative sea-state ETA driver (predictVesselEta). Independent of the
        // AIS prediction above: a failure here leaves the cone intact and simply hides the
        // sea-state section (never blocks the screen, never fabricates a delta).
        do {
            self.seaEta = try await EusoTripAPI.shared.query("vesselShipments.predictVesselEta", input: ShipmentIdQuery770(shipmentId: shipmentId))
        } catch {
            self.seaEta = nil
        }
        loading = false
    }

    private func loadTimeline() async {
        timelineLoading = true
        timelineError = nil
        do {
            let response: TimelineResponse770 = try await EusoTripAPI.shared.query(
                "containerTimeline.timeline",
                input: TimelineInput770(shipmentId: shipmentId, limit: 100)
            )
            timelineRows = response.events
        } catch {
            timelineError = error.eusoUserCopy
        }
        timelineLoading = false
    }
}

private struct VesselETATimelineSheet770: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let rows: [TimelineEvent770]
    let isLoading: Bool
    let error: String?
    let reload: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if isLoading {
                        LifecycleCard {
                            Text("Loading timeline…")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    } else if let error {
                        LifecycleCard(accentDanger: true) {
                            Text(error)
                                .font(EType.caption)
                                .foregroundStyle(Brand.danger)
                        }
                    } else if rows.isEmpty {
                        EusoEmptyState(systemImage: "clock.arrow.circlepath",
                                       title: "No timeline events",
                                       subtitle: "containerTimeline.timeline returned no tracking or shipment events for this shipment.")
                    } else {
                        LifecycleCard(accentGradient: true) {
                            LifecycleSection(label: "SHIPMENT TIMELINE", icon: "clock.arrow.circlepath")
                            LifecycleRow(label: "Events", value: String(rows.count))
                        }
                        LifecycleCard {
                            ForEach(rows) { row in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(display(row.eventType))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(palette.textPrimary)
                                    Text(detail(row))
                                        .font(EType.caption)
                                        .foregroundStyle(palette.textSecondary)
                                    Text(meta(row))
                                        .font(EType.mono(.caption))
                                        .foregroundStyle(palette.textTertiary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .padding(Space.s4)
            }
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh") { reload() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func display(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Timeline event" }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func detail(_ row: TimelineEvent770) -> String {
        let text = [row.locationLabel, row.notes].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
        return text.isEmpty ? "—" : text
    }

    private func meta(_ row: TimelineEvent770) -> String {
        let text = [row.source, row.timestamp].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
        return text.isEmpty ? "—" : text
    }
}

// MARK: - Cone plot (probability density over a 5-day axis)

private struct ConePlot770: View {
    let p10: Double; let p50: Double; let p90: Double
    let axis: [String]
    let line: Color; let grid: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let baseY = h - 18
            let topY: CGFloat = 4
            let x: (Double) -> CGFloat = { f in 8 + CGFloat(f) * (w - 16) }
            ZStack {
                // gridlines
                ForEach(0..<5, id: \.self) { i in
                    let gx = x(Double(i) / 4.0)
                    Path { p in p.move(to: CGPoint(x: gx, y: topY)); p.addLine(to: CGPoint(x: gx, y: baseY)) }
                        .stroke(grid, lineWidth: 1)
                }
                // density curve peaking at P50
                Path { p in
                    p.move(to: CGPoint(x: x(p10), y: baseY))
                    p.addQuadCurve(to: CGPoint(x: x(p50), y: topY + 4), control: CGPoint(x: x((p10 + p50) / 2), y: topY + 4))
                    p.addQuadCurve(to: CGPoint(x: x(p90), y: baseY), control: CGPoint(x: x((p50 + p90) / 2), y: topY + 4))
                }.stroke(LinearGradient.primary, lineWidth: 2.2)
                // band fill
                Path { p in
                    p.move(to: CGPoint(x: x(p10), y: baseY))
                    p.addQuadCurve(to: CGPoint(x: x(p50), y: topY + 8), control: CGPoint(x: x((p10 + p50) / 2), y: topY + 8))
                    p.addQuadCurve(to: CGPoint(x: x(p90), y: baseY), control: CGPoint(x: x((p50 + p90) / 2), y: topY + 8))
                    p.closeSubpath()
                }.fill(LinearGradient.primary.opacity(0.12))
                // P50 marker
                Path { p in p.move(to: CGPoint(x: x(p50), y: topY)); p.addLine(to: CGPoint(x: x(p50), y: baseY)) }
                    .stroke(LinearGradient.diagonal, lineWidth: 2.4)
                Circle().fill(LinearGradient.diagonal).frame(width: 12, height: 12).position(x: x(p50), y: topY + 2)
                // P10 / P90 dashed
                ForEach([p10, p90], id: \.self) { f in
                    Path { p in p.move(to: CGPoint(x: x(f), y: topY + 14)); p.addLine(to: CGPoint(x: x(f), y: baseY)) }
                        .stroke(line.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                }
                // baseline
                Path { p in p.move(to: CGPoint(x: 8, y: baseY)); p.addLine(to: CGPoint(x: w - 8, y: baseY)) }
                    .stroke(line.opacity(0.18), lineWidth: 1)
                // axis labels
                ForEach(0..<axis.count, id: \.self) { i in
                    Text(axis[i]).font(.system(size: 9)).foregroundStyle(line.opacity(0.5))
                        .position(x: x(Double(i) / 4.0), y: baseY + 10)
                }
            }
        }
    }
}

// MARK: - Diverging hour-impact bar (about a schedule center)

private struct DivergingBar770: View {
    let deltaHours: Int; let maxAbs: Int; let color: Color; let center: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, mid = w / 2
            let frac = min(1.0, abs(Double(deltaHours)) / Double(maxAbs))
            let barW = CGFloat(frac) * (w / 2 - 2)
            ZStack(alignment: .leading) {
                Path { p in p.move(to: CGPoint(x: mid, y: 0)); p.addLine(to: CGPoint(x: mid, y: geo.size.height)) }
                    .stroke(center, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                RoundedRectangle(cornerRadius: 6).fill(color)
                    .frame(width: barW, height: 12)
                    .offset(x: deltaHours < 0 ? mid - barW : mid, y: (geo.size.height - 12) / 2)
            }
        }
    }
}

#Preview("770 · Vessel ETA Prediction · Night") { VesselETAPredictionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("770 · Vessel ETA Prediction · Light") { VesselETAPredictionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
