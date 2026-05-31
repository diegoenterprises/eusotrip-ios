//
//  703_DispatchExceptionTriage.swift
//  EusoTrip — Dispatch · Operations Alerts (unified exception center).
//
//  Web peer: `frontend/client/src/pages/DispatchExceptions.tsx`.
//  2026-05-21 extension lands the eusotrip-killers team's unified
//  operations-alert center on iOS. Previously this screen only
//  rendered `dispatch.getExceptions` rows; now it merges three
//  real-time sources into a single list:
//
//    • dispatch.getExceptions       — stale-load + HOS + check-call
//    • zeunMechanics.getFleetBreakdowns — driver-reported mechanical
//    • eld.getDriverStatus          — live HOS violations + warnings
//
//  Each row carries a source badge (LOAD / ZEUN / ELD) and an
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
                leading: [NavSlot(label: "Home",    systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",    isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: true)],
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
    let driverId: Int?
    let id: Int?
    let name: String?
    let hasViolation: Bool?
    let driveTimeRemaining: Double?       // minutes
    let lastUpdate: String?

    enum CodingKeys: String, CodingKey {
        case driverId, id, name, hasViolation, driveTimeRemaining, lastUpdate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Server returns driverId as string (e.g., "d123" or UUID).
        // Parse it; if non-numeric, store nil.
        if let dIdStr = try c.decodeIfPresent(String.self, forKey: .driverId),
           let dIdInt = Int(dIdStr) {
            self.driverId = dIdInt
        } else if let dIdInt = try c.decodeIfPresent(Int.self, forKey: .driverId) {
            self.driverId = dIdInt
        } else {
            self.driverId = nil
        }
        self.id = try c.decodeIfPresent(Int.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.hasViolation = try c.decodeIfPresent(Bool.self, forKey: .hasViolation)
        self.driveTimeRemaining = try c.decodeIfPresent(Double.self, forKey: .driveTimeRemaining)
        self.lastUpdate = try c.decodeIfPresent(String.self, forKey: .lastUpdate)
    }
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
    case load, zeun, eld
    var label: String {
        switch self {
        case .load: return "LOAD"
        case .zeun: return "ZEUN"
        case .eld:  return "ELD"
        }
    }
    var symbol: String {
        switch self {
        case .load: return "shippingbox.fill"
        case .zeun: return "wrench.and.screwdriver.fill"
        case .eld:  return "clock.badge.exclamationmark"
        }
    }
    var color: Color {
        switch self {
        case .load: return .purple
        case .zeun: return .orange
        case .eld:  return .cyan
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
    @Environment(\.palette) private var palette
    @State private var loadExceptions: [DispatchExceptionRow] = []
    @State private var breakdowns: [DispatchTriageBreakdownRow] = []
    @State private var drivers: [EldDriverStatusRow] = []
    @State private var loading: Bool = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var lastResolved: String?
    @State private var resolvingId: String?
    @State private var sourceFilter: SourceFilter = .all
    @State private var severityFilter: SeverityFilter = .all
    @State private var search: String = ""

    private enum SourceFilter: String, CaseIterable {
        case all, load, zeun, eld
        var label: String { self == .all ? "ALL" : rawValue.uppercased() }
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
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
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
            Text("Load exceptions, Zeun breakdowns, and ELD violations — one queue.")
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
        return HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "CRITICAL",  value: "\(critical)", icon: "exclamationmark.octagon.fill", danger: critical > 0)
            LifecycleStatTile(label: "HIGH",      value: "\(high)",     icon: "exclamationmark.triangle.fill")
            LifecycleStatTile(label: "ZEUN",      value: "\(zeun)",     icon: "wrench.and.screwdriver.fill")
            LifecycleStatTile(label: "ELD/HOS",   value: "\(eld)",      icon: "clock.badge.exclamationmark")
        }
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

    @ViewBuilder
    private func alertCard(_ a: UnifiedAlert) -> some View {
        LifecycleCard(accentDanger: a.severity == .critical || a.severity == .high) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(a.source.label, systemImage: a.source.symbol)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(a.source.color.opacity(0.18)))
                        .foregroundStyle(a.source.color)
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
        _ = await (exc, zeun, eld)
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
        } catch {
            // Best-effort: same reasoning as breakdowns.
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
                if let lat = b.latitude, let lng = b.longitude {
                    return String(format: "%.4f, %.4f", lat, lng)
                }
                return nil
            }()
            out.append(UnifiedAlert(
                id: "zeun-\(b.id)",
                source: .zeun,
                severity: sev,
                title: "Breakdown: \((b.issueCategory ?? "unknown").replacingOccurrences(of: "_", with: " ").capitalized)",
                description: b.canDrive == false
                    ? "Vehicle disabled — driver cannot continue. Immediate dispatch action needed."
                    : "Driver reported mechanical issue — vehicle still operable.",
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
            let driverLabel = d.name ?? "Driver"
            if d.hasViolation == true {
                out.append(UnifiedAlert(
                    id: "eld-\(d.driverId ?? d.id ?? 0)",
                    source: .eld,
                    severity: .critical,
                    title: "HOS Violation",
                    description: "\(driverLabel) has exceeded Hours of Service limits. Contact immediately to ensure FMCSA compliance.",
                    driverName: d.name,
                    vehicle: nil,
                    loadNumber: nil,
                    location: nil,
                    createdAt: d.lastUpdate,
                    transportMode: nil,
                    multiVehicleCount: nil,
                    resolvableExceptionId: nil
                ))
            } else if let m = d.driveTimeRemaining, m > 0, m < 60 {
                out.append(UnifiedAlert(
                    id: "eld-warn-\(d.driverId ?? d.id ?? 0)",
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
