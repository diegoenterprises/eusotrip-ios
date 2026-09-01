//
//  703_DispatchExceptionTriage.swift
//  EusoTrip — Dispatch · Operations Alerts (unified exception center).
//
//  Web peer: `frontend/client/src/pages/DispatchExceptions.tsx`.
//  2026-05-21 extension lands the eusotrip-killers team's unified
//  operations-alert center on iOS. Previously this screen only
//  rendered `dispatch.getExceptions` rows; now it merges four
//  real-time sources into a single list:
//
//    • dispatch.getExceptions       — stale-load + HOS + check-call
//    • zeunMechanics.getFleetBreakdowns — driver-reported mechanical
//    • eld.getDriverStatus          — live HOS violations + warnings
//    • weather.getImpactedLoads     — in-transit loads inside an active
//                                     NWS severe-weather alert (Wave 1-3b
//                                     server feeds). Each severe/elevated
//                                     cell becomes a triage row; honestly
//                                     empty when no lane is impacted.
//
//  Each row carries a source badge (LOAD / ZEUN / ELD / WX) and an
//  appropriate severity color. The "Mark resolved" button only
//  fires for `load` source rows (the others resolve at their own
//  closeout flows — mechanic closes the Zeun ticket, driver resets
//  HOS, etc.) and writes a real audit-chain row server-side via
//  `dispatch.resolveException` (no-stubs doctrine fix shipped
//  2026-05-21 commit eb90fee0).
//

import SwiftUI

struct DispatchExceptionTriageScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { OperationsAlertsBody() } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire models

/// `dispatch.getExceptions` row.
private struct DispatchExceptionRow: Decodable, Hashable {
    let id: String
    let type: String?
    let severity: String?
    let driverName: String?
    let loadNumber: String?
    let location: String?
    let description: String?
    let createdAt: String?
    let status: String?
    let transportMode: String?
    let multiVehicleCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, severity, driverName, loadNumber, location, createdAt, status, transportMode, multiVehicleCount
        case description = "message"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.type = try c.decodeIfPresent(String.self, forKey: .type)
        self.severity = try c.decodeIfPresent(String.self, forKey: .severity)
        self.driverName = try c.decodeIfPresent(String.self, forKey: .driverName)
        self.loadNumber = try c.decodeIfPresent(String.self, forKey: .loadNumber)
        self.location = try c.decodeIfPresent(String.self, forKey: .location)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        self.transportMode = try c.decodeIfPresent(String.self, forKey: .transportMode)
        self.multiVehicleCount = try c.decodeIfPresent(Int.self, forKey: .multiVehicleCount)
    }
}

/// `zeunMechanics.getFleetBreakdowns` row (subset of fields we render).
private struct DispatchTriageBreakdownRow: Decodable, Hashable {
    let id: Int
    let severity: String?
    let issueCategory: String?
    let canDrive: Bool?
    let driverName: String?
    let driverId: Int?
    let vehicleVin: String?
    let latitude: Double?
    let longitude: Double?
    let createdAt: String?
    let status: String?
    
    enum CodingKeys: String, CodingKey {
        case id, severity, issueCategory, canDrive, driverName, driverId
        case vehicleVin, latitude, longitude, createdAt, status
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.severity = try c.decodeIfPresent(String.self, forKey: .severity)
        self.issueCategory = try c.decodeIfPresent(String.self, forKey: .issueCategory)
        self.canDrive = try c.decodeIfPresent(Bool.self, forKey: .canDrive)
        self.driverName = try c.decodeIfPresent(String.self, forKey: .driverName)
        self.driverId = try c.decodeIfPresent(Int.self, forKey: .driverId)
        self.vehicleVin = try c.decodeIfPresent(String.self, forKey: .vehicleVin)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        
        // latitude ships as STRING (decimal database field from tRPC MySQL driver).
        // Tolerate both Double and String representations.
        if let d = try? c.decodeIfPresent(Double.self, forKey: .latitude) {
            self.latitude = d
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .latitude),
                  let d = Double(s) {
            self.latitude = d
        } else {
            self.latitude = nil
        }
        
        // longitude ships as STRING for the same reason.
        if let d = try? c.decodeIfPresent(Double.self, forKey: .longitude) {
            self.longitude = d
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .longitude),
                  let d = Double(s) {
            self.longitude = d
        } else {
            self.longitude = nil
        }
    }
}

/// `eld.getDriverStatus` row (subset).
private struct EldDriverStatusRow: Decodable, Hashable {
    struct Tracking: Decodable, Hashable {
        let driveTime: Bool?
        let violation: Bool?
    }

    let driverId: String?
    let id: Int?
    let name: String?
    let hasViolation: Bool?
    let driveTimeRemaining: Double?       // minutes
    let lastUpdate: String?
    let provider: String?
    let tracked: Tracking?

    enum CodingKeys: String, CodingKey {
        case driverId, id, name, hasViolation, driveTimeRemaining, lastUpdate, provider, tracked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Identity is opaque on the wire. Preserve string/UUID values instead
        // of converting an unreadable identity into driver 0.
        if let value = try c.decodeIfPresent(String.self, forKey: .driverId) {
            self.driverId = value
        } else if let dIdInt = try c.decodeIfPresent(Int.self, forKey: .driverId) {
            self.driverId = String(dIdInt)
        } else {
            self.driverId = nil
        }
        self.id = try c.decodeIfPresent(Int.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.hasViolation = try c.decodeIfPresent(Bool.self, forKey: .hasViolation)
        self.driveTimeRemaining = try c.decodeIfPresent(Double.self, forKey: .driveTimeRemaining)
        self.lastUpdate = try c.decodeIfPresent(String.self, forKey: .lastUpdate)
        self.provider = try c.decodeIfPresent(String.self, forKey: .provider)
        self.tracked = try c.decodeIfPresent(Tracking.self, forKey: .tracked)
    }

    var stableIdentity: String? {
        let opaque = driverId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let opaque, !opaque.isEmpty { return opaque }
        return id.map(String.init)
    }

    var sourceIdentity: String? {
        let value = provider?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    var observedAt: Date? {
        guard let lastUpdate else { return nil }
        return Self.fractional.date(from: lastUpdate) ?? Self.internet.date(from: lastUpdate)
    }

    func hasCurrentDriveEvidence(at now: Date = Date()) -> Bool {
        guard stableIdentity != nil,
              sourceIdentity != nil,
              tracked?.driveTime == true,
              let driveTimeRemaining,
              driveTimeRemaining.isFinite,
              driveTimeRemaining >= 0,
              let observedAt else { return false }
        let age = now.timeIntervalSince(observedAt)
        return age >= -(5 * 60) && age <= 15 * 60
    }

    var hasRecordedViolationEvidence: Bool {
        stableIdentity != nil
            && sourceIdentity != nil
            && tracked?.violation == true
            && hasViolation == true
            && observedAt != nil
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// `weather.getImpactedLoads` row — an in-transit load whose pickup or
/// delivery state is inside an active NWS weather alert (weather.ts:481).
/// Shape: `{ loadId, loadNumber, status, origin, destination,
/// alertSeverity, alertHeadline }`. The proc returns `[]` when no alerts
/// are active or no in-transit load is affected, so the WEATHER source
/// stays honestly empty until real weather impacts a real load.
private struct WeatherImpactedLoadRow: Decodable, Hashable {
    let loadId: Int
    let loadNumber: String?
    let status: String?
    let origin: String?
    let destination: String?
    let alertSeverity: String?     // NWS: "Extreme" | "Severe" | "Moderate" | "Minor" | null
    let alertHeadline: String?     // e.g. "Winter Storm Warning until 6 PM"
}

/// Unified UI alert row. `source` drives the badge + the resolve
/// button visibility.
private struct UnifiedAlert: Identifiable, Hashable {
    let id: String
    let source: AlertSource
    let severity: AlertSeverity
    let title: String
    let description: String
    let driverName: String?
    let vehicle: String?
    let loadNumber: String?
    let location: String?
    let createdAt: String?
    let transportMode: String?
    let multiVehicleCount: Int?
    let resolvableExceptionId: String?    // non-nil only for `dispatch.*` rows
}

private enum AlertSource: String, Hashable {
    case load, zeun, eld, weather
    var label: String {
        switch self {
        case .load:    return "LOAD"
        case .zeun:    return "ZEUN"
        case .eld:     return "ELD"
        case .weather: return "WX"
        }
    }
    /// SF symbol for the source badge. `weather` is bespoke (renders via
    /// WeatherIcons in `alertCard`), so it has no SF symbol — see
    /// `usesWeatherGlyph`.
    var symbol: String {
        switch self {
        case .load:    return "shippingbox.fill"
        case .zeun:    return "wrench.and.screwdriver.fill"
        case .eld:     return "clock.badge.exclamationmark"
        case .weather: return ""
        }
    }
    /// The weather source draws its badge glyph through WeatherIcons (the
    /// bespoke condition/alert corpus) rather than an SF symbol — ZERO
    /// SF Symbols on the weather path per the bespoke doctrine.
    var usesWeatherGlyph: Bool { self == .weather }
    var color: Color {
        switch self {
        case .load:    return .purple
        case .zeun:    return .orange
        case .eld:     return .cyan
        case .weather: return WeatherIcons.drop   // the v2 widget's --drop token
        }
    }
}

private enum AlertSeverity: String, Hashable, Comparable {
    case critical, high, warning, info
    var rank: Int {
        switch self {
        case .critical: return 0
        case .high:     return 1
        case .warning:  return 2
        case .info:     return 3
        }
    }
    static func < (l: AlertSeverity, r: AlertSeverity) -> Bool { l.rank < r.rank }
    var color: Color {
        switch self {
        case .critical: return .red
        case .high:     return .orange
        case .warning:  return .yellow
        case .info:     return .blue
        }
    }
    var label: String { rawValue.uppercased() }

    static func fromString(_ raw: String?) -> AlertSeverity {
        switch (raw ?? "").lowercased() {
        case "critical": return .critical
        case "high":     return .high
        case "warning", "medium": return .warning
        default:         return .info
        }
    }
}

// MARK: - Body

private struct OperationsAlertsBody: View {
    private enum ELDFeedState: Equatable {
        case loading
        case current(observedAt: Date)
        case failed(message: String)
    }

    @Environment(\.palette) private var palette
    @State private var loadExceptions: [DispatchExceptionRow] = []
    @State private var breakdowns: [DispatchTriageBreakdownRow] = []
    @State private var drivers: [EldDriverStatusRow] = []
    @State private var eldFeedState: ELDFeedState = .loading
    @State private var weatherImpacted: [WeatherImpactedLoadRow] = []
    @State private var loading: Bool = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var lastResolved: String?
    @State private var resolvingId: String?
    @State private var sourceFilter: SourceFilter = .all
    @State private var severityFilter: SeverityFilter = .all
    @State private var search: String = ""

    private enum SourceFilter: String, CaseIterable {
        case all, load, zeun, eld, weather
        var label: String {
            switch self {
            case .all:     return "ALL"
            case .weather: return "WX"
            default:       return rawValue.uppercased()
            }
        }
    }
    private enum SeverityFilter: String, CaseIterable {
        case all, critical, high, warning, info
        var label: String { self == .all ? "ALL" : rawValue.uppercased() }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                statsRow
                searchField
                filterStrip
                if let m = lastResolved {
                    LifecycleCard(accentGradient: true) {
                        Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                if let e = actionError {
                    LifecycleCard(accentDanger: true) {
                        Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
                if case .failed(let message) = eldFeedState {
                    LifecycleCard(accentDanger: true) {
                        Text("ELD/HOS feed unavailable · \(message)")
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                    }
                }
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .eusoRefreshable { await loadAll() }
        // RealtimeService → `dispatch:board_update`. Live exception +
        // breakdown queue; same reasoning as 410.
        .onReceive(NotificationCenter.default.publisher(for: .eusoDispatchBoardUpdated)) { _ in
            Task { await loadAll() }
        }
    }

    // MARK: subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · OPERATIONS ALERTS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Operations alerts")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Load exceptions, Zeun breakdowns, ELD violations and severe-weather lanes, one queue.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statsRow: some View {
        let alerts = builtAlerts()
        let critical = alerts.filter { $0.severity == .critical }.count
        let high     = alerts.filter { $0.severity == .high }.count
        let zeun     = alerts.filter { $0.source   == .zeun }.count
        let eld      = alerts.filter { $0.source   == .eld  }.count
        let eldValue: String = {
            if case .current = eldFeedState { return "\(eld)" }
            return "—"
        }()
        let wx       = alerts.filter { $0.source   == .weather }.count
        return HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "CRITICAL",  value: "\(critical)", icon: "exclamationmark.octagon.fill", danger: critical > 0)
            LifecycleStatTile(label: "HIGH",      value: "\(high)",     icon: "exclamationmark.triangle.fill")
            LifecycleStatTile(label: "ZEUN",      value: "\(zeun)",     icon: "wrench.and.screwdriver.fill")
            LifecycleStatTile(label: "ELD/HOS",   value: eldValue,      icon: "clock.badge.exclamationmark")
            // WEATHER tile is bespoke (WeatherIcons glyph, ZERO SF Symbol) —
            // it mirrors the LifecycleStatTile idiom but renders the v2 alert
            // glyph rather than an SF symbol, per the bespoke doctrine.
            weatherStatTile(count: wx)
        }
    }

    /// Bespoke WEATHER stat tile — the LifecycleStatTile layout reproduced
    /// inline so the weather metric can use a WeatherIcons glyph instead of
    /// an SF symbol. Honest: shows the live count, em-dash treatment is the
    /// shared "0" the other tiles use.
    @ViewBuilder
    private func weatherStatTile(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                WeatherIcons.utility(.alert, size: 11, tint: count > 0 ? Brand.danger : WeatherIcons.drop)
                Text("WEATHER").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("\(count)").font(.system(size: 15, weight: .heavy))
                .foregroundStyle(count > 0 ? Brand.danger : palette.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(count > 0 ? Brand.danger.opacity(0.4) : palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.textTertiary)
            TextField("Search by driver / load / type", text: $search)
                .textInputAutocapitalization(.never)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderSoft)
        )
    }

    private var filterStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(SourceFilter.allCases, id: \.self) { f in
                    Button { sourceFilter = f } label: {
                        Text(f.label)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(sourceFilter == f ? .white : palette.textSecondary)
                            .background(sourceFilter == f
                                ? AnyShapeStyle(LinearGradient.diagonal)
                                : AnyShapeStyle(palette.bgCard))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                ForEach(SeverityFilter.allCases, id: \.self) { f in
                    Button { severityFilter = f } label: {
                        Text(f.label)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(severityFilter == f ? .white : palette.textSecondary)
                            .background(severityFilter == f
                                ? AnyShapeStyle(LinearGradient.diagonal)
                                : AnyShapeStyle(palette.bgCard))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard {
                Text("Loading operations alerts…")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        } else {
            let filtered = filteredAlerts()
            if filtered.isEmpty {
                EusoEmptyState(
                    systemImage: "checkmark.seal.fill",
                    title: "Queue is clear",
                    subtitle: "No alerts match the current filters."
                )
            } else {
                ForEach(filtered) { a in alertCard(a) }
            }
        }
    }

    /// Bespoke source badge. The LOAD/ZEUN/ELD sources keep their SF-symbol
    /// labels (untouched); the WEATHER source renders the bespoke WeatherIcons
    /// `.alert` glyph (the v2 weather corpus) so there is ZERO SF Symbol on
    /// the weather path, per the bespoke doctrine.
    @ViewBuilder
    private func sourceBadge(_ source: AlertSource) -> some View {
        HStack(spacing: 5) {
            if source.usesWeatherGlyph {
                WeatherIcons.utility(.alert, size: 11, tint: source.color)
            } else {
                Image(systemName: source.symbol)
                    .font(.system(size: 9, weight: .heavy))
            }
            Text(source.label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(source.color.opacity(0.18)))
        .foregroundStyle(source.color)
    }

    @ViewBuilder
    private func alertCard(_ a: UnifiedAlert) -> some View {
        LifecycleCard(accentDanger: a.severity == .critical || a.severity == .high) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    sourceBadge(a.source)
                    Spacer()
                    Text(a.severity.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(a.severity.color.opacity(0.18)))
                        .foregroundStyle(a.severity.color)
                    LoadModeBadge(modeRaw: a.transportMode,
                                  multiVehicleCount: a.multiVehicleCount,
                                  compact: true)
                }
                Text(a.title)
                    .font(EType.body.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                Text(a.description)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 3) {
                    if let d = a.driverName  { LifecycleRow(label: "Driver",   value: d) }
                    if let v = a.vehicle     { LifecycleRow(label: "Vehicle",  value: v) }
                    if let l = a.loadNumber  { LifecycleRow(label: "Load",     value: l) }
                    if let loc = a.location  { LifecycleRow(label: "Location", value: loc) }
                    if let when = a.createdAt { LifecycleRow(label: "When",    value: timeAgo(when)) }
                }

                if let exceptionId = a.resolvableExceptionId {
                    Button {
                        Task { await resolve(exceptionId: exceptionId, label: a.title) }
                    } label: {
                        HStack(spacing: 6) {
                            if resolvingId == exceptionId { ProgressView().tint(.white).controlSize(.mini) }
                            Text(resolvingId == exceptionId ? "Resolving…" : "Mark resolved")
                                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(resolvingId != nil)
                    .padding(.top, 6)
                }
            }
        }
    }

    // MARK: pipeline

    private func loadAll() async {
        loading = true; loadError = nil
        async let exc: Void = loadExceptionsSrc()
        async let zeun: Void = loadBreakdowns()
        async let eld: Void = loadDrivers()
        async let wx: Void = loadWeather()
        _ = await (exc, zeun, eld, wx)
        loading = false
    }

    private func loadExceptionsSrc() async {
        struct In: Encodable { let status: String? }
        do {
            let r: [DispatchExceptionRow] = try await EusoTripAPI.shared.query(
                "dispatch.getExceptions", input: In(status: nil)
            )
            loadExceptions = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadBreakdowns() async {
        struct In: Encodable {
            let status: String
            let limit: Int
        }
        do {
            let r: [DispatchTriageBreakdownRow] = try await EusoTripAPI.shared.query(
                "zeunMechanics.getFleetBreakdowns",
                input: In(status: "OPEN", limit: 50)
            )
            breakdowns = r
        } catch {
            // Best-effort: breakdowns are an additive source. A failure
            // here shouldn't blow away the dispatch alerts queue.
        }
    }

    private func loadDrivers() async {
        struct In: Encodable { let filter: String? }
        do {
            let r: [EldDriverStatusRow] = try await EusoTripAPI.shared.query(
                "eld.getDriverStatus", input: In(filter: nil)
            )
            drivers = r
            eldFeedState = .current(observedAt: Date())
        } catch {
            drivers = []
            let message = (error as? EusoTripAPIError)?.errorDescription
                ?? error.localizedDescription
            eldFeedState = .failed(message: message)
        }
    }

    private func loadWeather() async {
        do {
            // weather.getImpactedLoads — in-transit loads inside an active
            // NWS weather alert. No input; returns [] when nothing is
            // impacted (or weather is enterprise-gated / unavailable), so
            // the WEATHER source is honestly empty until a real alert lands.
            let r: [WeatherImpactedLoadRow] = try await EusoTripAPI.shared
                .queryNoInput("weather.getImpactedLoads")
            weatherImpacted = r
        } catch {
            // Best-effort: weather is an additive 4th source. A failure here
            // (proc absent, feed not licensed) must NOT blow away the queue.
        }
    }

    private func resolve(exceptionId: String, label: String) async {
        resolvingId = exceptionId; actionError = nil
        struct In: Encodable { let exceptionId: String; let resolution: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.resolveException",
                input: In(exceptionId: exceptionId,
                          resolution: "Acknowledged from mobile dispatch")
            )
            lastResolved = "Resolved: \(label)"
            await loadExceptionsSrc()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        resolvingId = nil
    }

    // MARK: merging + filtering

    private func builtAlerts() -> [UnifiedAlert] {
        var out: [UnifiedAlert] = []

        // 1. Load exceptions.
        for e in loadExceptions {
            out.append(UnifiedAlert(
                id: "load-\(e.id)",
                source: .load,
                severity: AlertSeverity.fromString(e.severity),
                title: e.loadNumber ?? (e.type ?? "Load exception").capitalized,
                description: e.description ?? "Operational exception detected.",
                driverName: e.driverName,
                vehicle: nil,
                loadNumber: e.loadNumber,
                location: e.location,
                createdAt: e.createdAt,
                transportMode: e.transportMode,
                multiVehicleCount: e.multiVehicleCount,
                resolvableExceptionId: e.id
            ))
        }

        // 2. Zeun mechanical breakdowns.
        for b in breakdowns {
            let sev: AlertSeverity = {
                switch (b.severity ?? "").uppercased() {
                case "CRITICAL": return .critical
                case "HIGH":     return .high
                case "MEDIUM":   return .warning
                default:         return .info
                }
            }()
            let coords: String? = {
                guard let coordinate = LatLongParser.validatedCoordinate(
                    latitude: b.latitude,
                    longitude: b.longitude
                ) else { return nil }
                return LatLongParser.displayString(coordinate)
            }()
            out.append(UnifiedAlert(
                id: "zeun-\(b.id)",
                source: .zeun,
                severity: sev,
                title: "Breakdown: \((b.issueCategory ?? "unknown").replacingOccurrences(of: "_", with: " ").capitalized)",
                description: b.canDrive == false
                    ? "Vehicle disabled. Driver cannot continue. Immediate dispatch action needed."
                    : "Driver reported mechanical issue. Vehicle still operable.",
                driverName: b.driverName,
                vehicle: b.vehicleVin,
                loadNumber: nil,
                location: coords,
                createdAt: b.createdAt,
                transportMode: nil,
                multiVehicleCount: nil,
                resolvableExceptionId: nil
            ))
        }

        // 3. ELD HOS violations + warnings.
        for d in drivers {
            guard let identity = d.stableIdentity,
                  let source = d.sourceIdentity else { continue }
            let driverLabel = d.name ?? "Driver"
            if d.hasRecordedViolationEvidence {
                out.append(UnifiedAlert(
                    id: "eld-\(identity)",
                    source: .eld,
                    severity: .critical,
                    title: "Recorded HOS Violation",
                    description: "\(driverLabel) has a sourced HOS violation record from \(source). Revalidate current legal status before assignment.",
                    driverName: d.name,
                    vehicle: nil,
                    loadNumber: nil,
                    location: nil,
                    createdAt: d.lastUpdate,
                    transportMode: nil,
                    multiVehicleCount: nil,
                    resolvableExceptionId: nil
                ))
            } else if d.hasCurrentDriveEvidence(),
                      let m = d.driveTimeRemaining, m > 0, m < 60 {
                out.append(UnifiedAlert(
                    id: "eld-warn-\(identity)",
                    source: .eld,
                    severity: .high,
                    title: "HOS Warning · Low Drive Time",
                    description: "\(driverLabel) has < 1h drive time left (\(Int(m)) min). Plan accordingly.",
                    driverName: d.name,
                    vehicle: nil,
                    loadNumber: nil,
                    location: nil,
                    createdAt: d.lastUpdate,
                    transportMode: nil,
                    multiVehicleCount: nil,
                    resolvableExceptionId: nil
                ))
            }
        }

        // 4. WEATHER — in-transit loads inside an active NWS alert
        //    (weather.getImpactedLoads). Each impacted load in a severe /
        //    elevated cell becomes a triage row. The §3 riskTier ladder
        //    (none/watch/elevated/severe) and the NWS severity strings both
        //    collapse here: severe→critical, elevated/severe-NWS→high.
        //    Moderate/minor/absent stay honestly OUT of the triage queue
        //    (those belong on the per-load weather card, not the exception
        //    triage) — so a clear/watch lane never fabricates an alert row.
        for w in weatherImpacted {
            let sev = weatherSeverity(w.alertSeverity)
            // Honesty gate: only severe/elevated cells are triage-worthy.
            guard sev == .critical || sev == .high else { continue }
            let headline = w.alertHeadline?.trimmingCharacters(in: .whitespaces)
            let lane: String? = {
                let o = (w.origin ?? "").trimmingCharacters(in: .whitespaces)
                let d = (w.destination ?? "").trimmingCharacters(in: .whitespaces)
                let oo = o.isEmpty || o == "Unknown" ? nil : o
                let dd = d.isEmpty || d == "Unknown" ? nil : d
                switch (oo, dd) {
                case let (.some(a), .some(b)): return "\(a) → \(b)"
                case let (.some(a), nil):      return a
                case let (nil, .some(b)):      return b
                default:                       return nil
                }
            }()
            out.append(UnifiedAlert(
                id: "wx-\(w.loadId)",
                source: .weather,
                severity: sev,
                title: (headline?.isEmpty == false ? headline! : "Active weather on lane"),
                description: lane.map { "In-transit load is routed through active severe weather along \($0)." }
                    ?? "In-transit load is routed through an active severe-weather alert.",
                driverName: nil,
                vehicle: nil,
                loadNumber: w.loadNumber,
                location: lane,
                createdAt: nil,                 // proc carries no per-row timestamp
                transportMode: nil,
                multiVehicleCount: nil,
                resolvableExceptionId: nil      // resolves when the alert expires / load clears the cell
            ))
        }

        // Sort: severity → recency.
        out.sort { l, r in
            if l.severity != r.severity { return l.severity < r.severity }
            let lt = (l.createdAt ?? "")
            let rt = (r.createdAt ?? "")
            return lt > rt
        }
        return out
    }

    private func filteredAlerts() -> [UnifiedAlert] {
        let all = builtAlerts()
        return all.filter { a in
            if sourceFilter != .all,
               sourceFilter.rawValue != a.source.rawValue { return false }
            if severityFilter != .all,
               severityFilter.rawValue.lowercased() != a.severity.rawValue { return false }
            if !search.isEmpty {
                let q = search.lowercased()
                let bag = [a.title, a.description, a.driverName ?? "", a.loadNumber ?? "", a.vehicle ?? ""]
                    .joined(separator: " ").lowercased()
                if !bag.contains(q) { return false }
            }
            return true
        }
    }

    // MARK: helpers

    /// Map the weather cell's risk → the screen AlertSeverity. Accepts both
    /// the NWS `alertSeverity` strings (Extreme/Severe/Moderate/Minor) from
    /// getImpactedLoads AND the §3 riskTier ladder (none/watch/elevated/
    /// severe) so the same merge holds if the source swaps to laneImpact.
    private func weatherSeverity(_ raw: String?) -> AlertSeverity {
        switch (raw ?? "").lowercased() {
        case "extreme", "severe":            return .critical
        case "elevated":                     return .high
        case "moderate":                     return .warning
        case "watch", "minor":               return .info
        default:                             return .info
        }
    }

    private func timeAgo(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) else { return iso }
        let mins = max(1, Int(Date().timeIntervalSince(d) / 60))
        if mins < 60 { return "\(mins)m ago" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h ago" }
        return "\(hrs / 24)d ago"
    }
}

#Preview("703 · Operations Alerts · Night") {
    DispatchExceptionTriageScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("703 · Operations Alerts · Afternoon") {
    DispatchExceptionTriageScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
