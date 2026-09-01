//
//  554_RailCrewHOSRoster.swift
//  EusoTrip — Rail Engineer · Crew HOS Roster (carrier vantage).
//
//  Visual identity: 49 CFR §228 hours-of-service compliance dashboard.
//  Team HOS ring shows collective duty-quota consumption at a glance.
//  Per-member inline arcs encode individual remaining-hours at a glance;
//  role-specific avatar colors (engineer=gradient, conductor=blue, helper=info).
//

import SwiftUI

struct RailCrewHOSRosterScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailCrewHOSRosterBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shape (mirror railCrewAssignments row)

private struct RailCrewMember: Decodable, Identifiable {
    let id: Int
    let role: String?
    let crewId: String?
    let onDutyHours: Double?
    let remainingHours: Double?
    let dutyStatus: String?     // on_duty | off_duty | near_limit
    let endorsement: String?
    let tracked: Bool?
    let trackingState: HOSTrackingState?
    let source: String?
    let freshness: String?
    let observationState: String?

    enum CodingKeys: String, CodingKey {
        case id, role, crewId, onDutyHours, remainingHours, dutyStatus, endorsement
        case hoursOnDuty
        case tracked, trackingState, source, freshness, observationState
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.role = try c.decodeIfPresent(String.self, forKey: .role)
        self.crewId = try c.decodeIfPresent(String.self, forKey: .crewId)
        
        // Server sends hoursOnDuty as decimal string, iOS expects Double
        if let hoursStr = try? c.decodeIfPresent(String.self, forKey: .hoursOnDuty),
           let hours = Double(hoursStr) {
            self.onDutyHours = hours
        } else if let hours = try? c.decodeIfPresent(Double.self, forKey: .hoursOnDuty) {
            self.onDutyHours = hours
        } else {
            self.onDutyHours = nil
        }
        
        if let hours = try? c.decodeIfPresent(Double.self, forKey: .remainingHours) {
            self.remainingHours = hours
        } else if let hoursString = try? c.decodeIfPresent(String.self, forKey: .remainingHours) {
            self.remainingHours = Double(hoursString)
        } else {
            self.remainingHours = nil
        }
        self.dutyStatus = try c.decodeIfPresent(String.self, forKey: .dutyStatus)
        self.endorsement = try c.decodeIfPresent(String.self, forKey: .endorsement)
        self.tracked = try c.decodeIfPresent(Bool.self, forKey: .tracked)
        self.trackingState = try c.decodeIfPresent(HOSTrackingState.self, forKey: .trackingState)
        self.source = try c.decodeIfPresent(String.self, forKey: .source)
        self.freshness = try c.decodeIfPresent(String.self, forKey: .freshness)
        self.observationState = try c.decodeIfPresent(String.self, forKey: .observationState)
    }
}

// MARK: - Corridor weather shapes (weather.getRouteConditions / getImpactedLoads)
//
// The crew roster is the CARRIER vantage — it carries no railId and no
// canonical corridor, so the §228 HOS burn note is anchored exactly like
// 578: the first REAL `weather.getImpactedLoads` row gives a "City, ST" →
// "City, ST" corridor, and `weather.getRouteConditions({origin,destination})`
// is asked whether that corridor is adverse. Every weather field is
// enterprise-gated (available:false / nil today), so the note stays HONESTLY
// HIDDEN until the feed lights up — never a fabricated gust/restriction.

private struct HOSImpactedLoad: Decodable {
    let loadId: Int
    let origin: String?
    let destination: String?
    let alertSeverity: String?
}

private struct HOSRouteConditions: Decodable {
    let available: Bool?
    let overallRisk: String?            // "low"|"moderate"|"high"|"extreme"|"unknown"
    let segments: [HOSRouteSegment]?
    let advisories: [HOSRouteAdvisory]?
}

private struct HOSRouteSegment: Decodable {
    let risk: String?
    let condition: String?
    let weatherCode: Int?
    let windGust: Double?               // mph
    let visibility: Double?             // mi
    let precipitationIntensity: Double? // in/hr
    let floods: [HOSRouteFlood]?
    let overallRisk: String?
}

private struct HOSRouteFlood: Decodable {
    let severity: String?
    let headline: String?
}

private struct HOSRouteAdvisory: Decodable {
    let eventType: String?
    let severity: String?
    let headline: String?
}

// MARK: - Body

private struct RailCrewHOSRosterBody: View {
    @Environment(\.palette) private var palette
    @State private var crew: [RailCrewMember] = []
    @State private var route: HOSRouteConditions? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private let hosQuota: Double = 12.0   // 49 CFR §228 shift limit (hours)

    private var onDuty: Int    { crew.filter { ($0.dutyStatus ?? "") == "on_duty" }.count }
    private var offDuty: Int   { crew.filter { ($0.dutyStatus ?? "") == "off_duty" }.count }
    private var nearLimit: Int { crew.filter { ($0.dutyStatus ?? "") == "near_limit" }.count }
    private var unverified: Int { crew.filter { !hasCompleteReportedHOS($0) }.count }

    // A team percentage is meaningful only when every assigned crew row carries
    // complete, finite reported counters. This endpoint does not expose an
    // observation timestamp, so the UI labels the result as reported rather
    // than live/current.
    private var teamQuotaFraction: Double? {
        guard !crew.isEmpty else { return nil }
        let hours = crew.compactMap(\.onDutyHours)
        guard hours.count == crew.count,
              hours.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return hours.map { min($0 / hosQuota, 1.0) }.reduce(0, +) / Double(hours.count)
    }
    private var teamRingColor: Color {
        guard let fraction = teamQuotaFraction else { return palette.textTertiary }
        return fraction > 0.85 ? Brand.danger : (fraction > 0.70 ? Brand.warning : Brand.blue)
    }

    private func hasCompleteReportedHOS(_ member: RailCrewMember) -> Bool {
        let validStatus = ["on_duty", "off_duty", "near_limit"].contains(member.dutyStatus ?? "")
        return validStatus
            && member.onDutyHours?.isFinite == true
            && member.remainingHours?.isFinite == true
            && hasCurrentObservation(member)
    }

    private func hasCurrentObservation(_ member: RailCrewMember) -> Bool {
        member.tracked == true
            && member.trackingState == .tracked
            && member.observationState == "current"
            && member.source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && HOSObservationClock.freshness(member.freshness).isCurrent
    }

    // MARK: Weather-driven §228 HOS burn note
    //
    // §228 hours-of-service runs FASTER when the corridor is adverse: gusts
    // that force a speed restriction, floods/washouts that hold the train,
    // low visibility that slows the crew — all burn duty hours against the
    // same 12h ceiling without covering the miles. We surface that as an
    // HONEST advisory bound to the REAL corridor envelope: a gust reading, a
    // flood headline, or an elevated risk/advisory. We never assert an hour
    // figure the feed doesn't carry — the note describes the burn DRIVER
    // (verbatim from the server), not an invented "−2.0h remaining".

    /// The single worst corridor signal driving HOS burn, or nil when the
    /// corridor is clear / the enterprise feed is dark (honest hidden state).
    /// Severity ranks: flood > severe/extreme/high gust-risk > advisory.
    private var hosBurnNote: (glyph: WeatherIcons.Utility, weatherCode: Int?, color: Color, headline: String, detail: String)? {
        guard let r = route, r.available != false else { return nil }
        let segs = r.segments ?? []
        let advs = r.advisories ?? []

        // 1) Floods/washouts on a segment — the hardest HOS hold.
        for seg in segs {
            if let flood = (seg.floods ?? []).first {
                return (.alert, seg.weatherCode, Brand.danger,
                        "Weather hold burning duty",
                        flood.headline ?? "Flooding on the corridor is holding the train — §228 duty accrues without miles.")
            }
        }
        // 2) High gust → speed restriction. Only when the server gives a real
        //    gust reading; the value is quoted verbatim, never rounded into a
        //    fabricated restriction.
        if let seg = segs.compactMap({ s in s.windGust.map { ($0, s) } }).max(by: { $0.0 < $1.0 }),
           seg.0 >= 40 {
            return (.wind, seg.1.weatherCode, seg.0 >= 58 ? Brand.danger : Brand.warning,
                    "Crosswind slowing the crew",
                    "\(Int(seg.0.rounded())) mph gusts on the corridor — a speed restriction stretches the run against the §228 ceiling.")
        }
        // 3) Low visibility slows the crew.
        if let seg = segs.compactMap({ s in s.visibility.map { ($0, s) } }).min(by: { $0.0 < $1.0 }),
           seg.0 <= 1.0 {
            return (.eye, seg.1.weatherCode, Brand.warning,
                    "Low visibility slowing the run",
                    "\(seg.0.formatted(.number.precision(.fractionLength(0...1)))) mi visibility — restricted-speed operation burns duty without covering miles.")
        }
        // 4) Elevated corridor risk or an active advisory (no metric yet).
        let risk = (r.overallRisk ?? "").lowercased()
        if ["high", "severe", "extreme", "elevated"].contains(risk) {
            return (.alert, nil, Brand.danger,
                    "Adverse corridor weather",
                    "Corridor risk is \(risk.uppercased()) — expect the run to stretch against the §228 duty ceiling.")
        }
        if let adv = advs.first(where: { ["severe", "extreme", "high"].contains(($0.severity ?? "").lowercased()) }) {
            return (.alert, nil, Brand.warning,
                    "Weather advisory on the corridor",
                    adv.headline ?? adv.eventType ?? "An active advisory may slow the crew against the §228 ceiling.")
        }
        return nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading crew…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    teamHeroCard
                    if let note = hosBurnNote { hosBurnChip(note) }
                    summaryTiles
                    crewHeader
                    crewList
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("RAIL ENGINEER · CREW HOS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Crew roster")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Team HOS hero card

    private var teamHeroCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            HStack(spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 8) {
                    // Regulatory badge
                    Text("49 CFR §228")
                        .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(palette.textTertiary.opacity(0.12)))
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(crew.count)")
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("crew assigned")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text(teamSummary)
                                .font(EType.caption)
                                .foregroundStyle(nearLimit > 0 ? Brand.warning : palette.textSecondary)
                        }
                    }
                }
                Spacer()
                teamHOSRing
            }
            .padding(Space.s4)
        }
        .frame(height: 120)
    }

    private var teamHOSRing: some View {
        ZStack {
            Circle()
                .stroke(teamRingColor.opacity(0.18), lineWidth: 7)
                .frame(width: 68, height: 68)
            if let fraction = teamQuotaFraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(teamRingColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 68, height: 68)
            }
            VStack(spacing: 1) {
                Text(teamQuotaFraction.map { "\(Int($0 * 100))%" } ?? "—")
                    .font(.system(size: 14, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(teamRingColor)
                Text(teamQuotaFraction == nil ? "UNAVAILABLE" : "REPORTED")
                    .font(.system(size: 7, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Weather HOS-burn chip (bespoke — WeatherIcons, never an SF Symbol)
    //
    // Sits directly under the team §228 ring: when the corridor is adverse,
    // the team's remaining-hours headroom is being eaten by weather, so the
    // note belongs next to the quota. Honest hidden when clear / feed dark.

    private func hosBurnChip(_ note: (glyph: WeatherIcons.Utility, weatherCode: Int?, color: Color, headline: String, detail: String)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(note.color.opacity(0.14))
                    .frame(width: 40, height: 40)
                // Prefer the real Apple WeatherKit condition glyph when the segment
                // carries a weatherCode; else the driver utility glyph (wind /
                // eye / alert). Both are bespoke WeatherIcons, no SF Symbols.
                if let code = note.weatherCode, code != 0 {
                    WeatherIcons.symbolView(for: code, size: 24)
                } else {
                    WeatherIcons.utility(note.glyph, size: 20, tint: note.color)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(note.headline)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("§228")
                        .font(.system(size: 8.5, weight: .heavy)).kerning(0.4)
                        .foregroundStyle(note.color)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(note.color.opacity(0.14)))
                }
                Text(note.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(note.color.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Summary tiles

    private var summaryTiles: some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "ON DUTY",    value: "\(onDuty)",    icon: "checkmark.circle")
            LifecycleStatTile(label: "OFF DUTY",   value: "\(offDuty)",   icon: "moon.fill")
            LifecycleStatTile(
                label: unverified > 0 ? "UNVERIFIED" : "NEAR LIMIT",
                value: "\(unverified > 0 ? unverified : nearLimit)",
                icon: unverified > 0 ? "questionmark.circle" : "exclamationmark.circle",
                danger: nearLimit > 0
            )
        }
    }

    // MARK: Crew list

    private var crewHeader: some View {
        Text("ASSIGNED CREW · REPORTED HOS · FRESHNESS UNAVAILABLE")
            .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }

    private var crewList: some View {
        VStack(spacing: Space.s2) {
            ForEach(crew) { crewRow($0) }
        }
    }

    private func crewRow(_ m: RailCrewMember) -> some View {
        let (statusLabel, statusColor): (String, Color) = {
            switch (m.dutyStatus ?? "") {
            case "on_duty":    return ("ON DUTY · REPORTED", Brand.blue)
            case "near_limit": return ("NEAR LIMIT", Brand.warning)
            case "off_duty":   return ("OFF DUTY · REPORTED", palette.textTertiary)
            default:           return ("STATUS UNAVAILABLE", palette.textTertiary)
            }
        }()
        let remaining = m.remainingHours.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let fraction = remaining.map { min(max(hosQuota - $0, 0) / hosQuota, 1.0) }
        let arcColor: Color = fraction.map {
            $0 > 0.85 ? Brand.danger : ($0 > 0.70 ? Brand.warning : Brand.blue)
        } ?? palette.textTertiary

        return HStack(spacing: Space.s3) {
            roleAvatar(m)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(m.role?.capitalized ?? "Crew") · \(m.crewId ?? "-")")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("\(m.onDutyHours.map { String(format: "%.1fh on duty", $0) } ?? "on-duty hours unavailable")\(m.endorsement.map { " · \($0)" } ?? "")")
                    .font(.system(size: 11)).monospaced().foregroundStyle(palette.textSecondary)
            }
            Spacer()
            // Inline HOS arc
            hosArc(fraction: fraction, color: arcColor, remaining: remaining)
            Text(statusLabel)
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(statusColor.opacity(0.14)).clipShape(Capsule())
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func roleAvatar(_ m: RailCrewMember) -> some View {
        ZStack {
            Circle()
                .fill(roleGradient(m.role))
                .frame(width: 36, height: 36)
            Image(systemName: "person.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func roleGradient(_ role: String?) -> AnyShapeStyle {
        switch (role ?? "").lowercased() {
        case "engineer":  return AnyShapeStyle(LinearGradient.diagonal)
        case "conductor": return AnyShapeStyle(Brand.blue)
        case "helper":    return AnyShapeStyle(Brand.info)
        default:          return AnyShapeStyle(palette.textTertiary.opacity(0.8))
        }
    }

    private func hosArc(fraction: Double?, color: Color, remaining: Double?) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 4)
                .frame(width: 30, height: 30)
            if let fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 30, height: 30)
            }
            Text(remaining.map { $0 <= 0 ? "0h" : "\(Int($0))h" } ?? "—")
                .font(.system(size: 7.5, weight: .heavy)).monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private var teamSummary: String {
        if unverified > 0 { return "\(unverified) HOS row\(unverified == 1 ? "" : "s") unverified" }
        if nearLimit > 0 { return "\(nearLimit) reported near HOS limit" }
        return "reported values · freshness unavailable"
    }

    // MARK: Data

    /// Input for `weather.getRouteConditions` — origin/destination as
    /// {city,state}. Never invented: parsed from a REAL impacted load's
    /// "City, ST" endpoints. No load → no call → no HOS burn note.
    private struct RouteConditionsInput: Encodable {
        struct Place: Encodable { let city: String; let state: String }
        let origin: Place
        let destination: Place
    }

    /// Parse a server "City, ST" endpoint into {city,state}; nil when
    /// "Unknown"/empty/malformed so we never query garbage.
    private func parsePlace(_ s: String?) -> RouteConditionsInput.Place? {
        guard let raw = s?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
              raw.lowercased() != "unknown" else { return nil }
        let parts = raw.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return .init(city: parts[0], state: parts[1])
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let result: [RailCrewMember] = try await EusoTripAPI.shared.queryNoInput("railShipments.getRailCrewHOS")
            self.crew = result
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false

        // Corridor weather for the §228 HOS burn note — carrier vantage, so
        // anchored to the first REAL impacted load's origin→destination (same
        // honest path as 578). Soft-fail: a weather error must never break the
        // roster, and an unparseable / absent corridor simply hides the note.
        await loadCorridor()
    }

    private func loadCorridor() async {
        guard let impacted: [HOSImpactedLoad] = try? await EusoTripAPI.shared
                .queryNoInput("weather.getImpactedLoads"),
              let first = impacted.first,
              let o = parsePlace(first.origin),
              let d = parsePlace(first.destination) else {
            self.route = nil
            return
        }
        self.route = try? await EusoTripAPI.shared.query(
            "weather.getRouteConditions",
            input: RouteConditionsInput(origin: o, destination: d))
    }
}

#Preview("554 · Rail Crew HOS · Night") { RailCrewHOSRosterScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("554 · Rail Crew HOS · Light") { RailCrewHOSRosterScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
