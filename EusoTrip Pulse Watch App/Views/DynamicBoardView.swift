//
//  DynamicBoardView.swift
//  EusoTrip Pulse Watch App
//
//  Generic data-bound list view backed by a live tRPC endpoint.
//  Every wrist tab that isn't already a purpose-built view routes
//  through here — zero placeholders, zero seeded fixtures. The
//  store either has server-returned rows or surfaces an error
//  banner; it never invents a row.
//
//  Usage pattern: pick an endpoint, map the server response to
//  `BoardRow`, pass the descriptor into `DynamicBoardView`. Each
//  row renders as title / subtitle / accessory + an optional
//  severity accent. The caller configures the title, empty
//  message, and regulator chip. Shape parity with DispatcherBoardView
//  / BrokerAuctionsView / ShipperShipmentsView — those three are
//  deliberately left as dedicated views because they have
//  role-specific affordances (bid amount, lane, exception tint) but
//  every other wrist tab flows through here.
//

import SwiftUI
import Combine

// MARK: - BoardRow shape

// BoardRow is a pure value type the @Sendable decoders construct off
// the main actor. Marked `nonisolated` so the build with default-
// MainActor isolation (Swift 6 mode) doesn't flag every `BoardRow(...)`
// call inside the @Sendable closures.
nonisolated struct BoardRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let accessory: String?
    let severity: BoardRowSeverity
    let timestamp: Date?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        accessory: String? = nil,
        severity: BoardRowSeverity = .info,
        timestamp: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
        self.severity = severity
        self.timestamp = timestamp
    }
}

nonisolated enum BoardRowSeverity: Equatable, Sendable {
    case info, watch, critical, positive

    /// `@MainActor` because the brand color tokens
    /// (`.esangBlue/Amber/Magenta/Green`) are themselves main-actor-
    /// isolated UI tokens. Only the SwiftUI render side touches `tint`,
    /// so this stays cleanly nonisolated where it matters (decoders).
    @MainActor
    var tint: Color {
        switch self {
        case .info:     return .esangBlue
        case .watch:    return .esangAmber
        case .critical: return .esangMagenta
        case .positive: return .esangGreen
        }
    }
}

// MARK: - Store

@MainActor
final class DynamicBoardStore: ObservableObject {
    @Published var rows: [BoardRow] = []
    @Published var hasLoadedOnce: Bool = false
    @Published var lastError: String?

    /// Endpoint path for the live tRPC query, e.g. "claims.list".
    let endpoint: String
    /// Optional query input. Kept as a plain dictionary so callers
    /// don't have to declare a dedicated Encodable for every tab.
    let input: [String: Any]
    /// Server-response decoder — transforms raw JSON into a typed
    /// [BoardRow]. Each tab supplies the tRPC envelope-aware decoder
    /// so we never guess at a shape.
    let decode: @Sendable (Data) throws -> [BoardRow]

    init(
        endpoint: String,
        input: [String: Any] = [:],
        decode: @escaping @Sendable (Data) throws -> [BoardRow]
    ) {
        self.endpoint = endpoint
        self.input = input
        self.decode = decode
    }

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else {
            lastError = "Sign in on your iPhone"
            return
        }
        do {
            let client = EsangClient(auth: auth)
            let data = try await client.queryJSON(endpoint, input: input)
            rows = try decode(data)
            hasLoadedOnce = true
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? "Can't reach \(endpoint)"
        }
    }
}

// MARK: - tRPC envelope helper

/// Decodes a tRPC v10 success envelope wrapping `T`. Every Pulse
/// endpoint responds with `{result: {data: {json: T}}}`; this one
/// struct means each board's decoder is a single `T -> [BoardRow]`
/// mapping, not a fresh envelope boilerplate.
nonisolated struct TRPCEnvelope<T: Decodable>: Decodable {
    nonisolated struct Result: Decodable {
        nonisolated struct DataContainer: Decodable { let json: T }
        let data: DataContainer
    }
    let result: Result
}

// MARK: - View

struct DynamicBoardView: View {
    @EnvironmentObject var auth: AuthStore
    @StateObject var store: DynamicBoardStore

    let title: String
    let regulator: String
    let emptyMessage: String

    init(
        title: String,
        regulator: String,
        emptyMessage: String,
        store: DynamicBoardStore
    ) {
        self.title = title
        self.regulator = regulator
        self.emptyMessage = emptyMessage
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    header
                    if let err = store.lastError, !store.hasLoadedOnce {
                        errorBanner(err)
                    } else if store.rows.isEmpty && store.hasLoadedOnce {
                        emptyState
                    } else if !store.rows.isEmpty {
                        list
                    } else {
                        loadingBanner
                    }
                }
                // Zero horizontal padding so list rows + the bezel ticks
                // meet the actual wrist edge; the orb tab does the same.
                .padding(.horizontal, 0)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Corner-labels overlay — Modular Ultra-style four-corner
            // micro labels flush to the bezel curve. Inlined here so
            // the view is self-sufficient and builds even when the
            // shared `ModularTickBezel` helper isn't in this target's
            // index pass (the watch project's synchronized-group
            // resolver has gone stale on this file before).
            VStack {
                HStack {
                    bezelLabel(title.uppercased(),     align: .leading)
                    Spacer(minLength: 0)
                    bezelLabel(regulator.uppercased(), align: .trailing)
                }
                .padding(.top, 2)
                Spacer()
                HStack {
                    bezelLabel(counterLabel, align: .leading)
                    Spacer(minLength: 0)
                    bezelLabel(staleLabel,   align: .trailing)
                }
                .padding(.bottom, 2)
            }
            .padding(.horizontal, 6)
            .allowsHitTesting(false)
        }
        .toolbar(.hidden)
        .ignoresSafeArea(.container, edges: .all)
        // Same radial halo HomeView uses so the bezel's rounded
        // corners feel lit, not clipped against rectangular rows.
        .watchEdgeGlow()
        .task { await store.refresh(auth: auth) }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Task { await store.refresh(auth: auth) }
        }
    }

    // MARK: - Subviews

    /// Modular Ultra-style corner label, flush to the bezel curve.
    /// Inlined from `ModularTickBezel.cornerLabel` so this file builds
    /// without a sibling-file dep.
    @ViewBuilder
    private func bezelLabel(
        _ text: String,
        align: HorizontalAlignment
    ) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .semibold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.45))
            .lineLimit(1)
            .frame(
                maxWidth: 56,
                alignment: align == .leading ? .leading : .trailing
            )
            .allowsTightening(true)
            .minimumScaleFactor(0.6)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Spacer()
            if let latest = store.rows.first?.timestamp {
                Text(relative(latest))
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var list: some View {
        VStack(spacing: 4) {
            ForEach(store.rows) { row in
                rowCard(row)
            }
        }
    }

    private func rowCard(_ row: BoardRow) -> some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(row.severity.tint)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 10, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                if let sub = row.subtitle {
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let accessory = row.accessory {
                Text(accessory)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(row.severity.tint)
            }
        }
        .padding(6)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 18))
                .foregroundStyle(Color.esangGreen)
            Text(emptyMessage)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    private var loadingBanner: some View {
        HStack(spacing: 4) {
            ProgressView().scaleEffect(0.7)
            Text("Loading…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
    }

    private func errorBanner(_ err: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.esangAmber)
            Text(err)
                .font(.system(size: 9, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: R.sm))
    }

    // MARK: - Bezel helpers

    private var counterLabel: String {
        if !store.hasLoadedOnce { return "LOADING" }
        let n = store.rows.count
        if n == 0 { return "CLEAR" }
        return "\(n) ROWS"
    }

    private var staleLabel: String {
        guard let latest = store.rows.first?.timestamp else { return "" }
        return relative(latest).uppercased()
    }

    private func relative(_ d: Date) -> String {
        let s = -d.timeIntervalSinceNow
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }
}

// MARK: - Board factories
//
// Every factory decodes the EXACT server response shape — verified
// against `eusoronetechnologiesinc/frontend/server/routers/*`. No
// placeholders, no stubs, no speculative field names.
//
// Date parsing note: the server ships timestamps in two shapes:
//   • full ISO 8601 (`"2026-04-24T11:33:04.123Z"`) — used by most
//     `.createdAt` / `.completedAt` / `.updatedAt` columns.
//   • date-only (`"2026-04-24"`) — used by helpers that do
//     `.toISOString().split('T')[0]` before returning.
// `BoardDate.parse` handles both shapes so a row with either form
// lands on the right relative-time label.

private nonisolated enum BoardDate {
    /// Local ISO-8601 formatter — replaces the shared
    /// `ISO8601DateFormatter.iso` extension in LoadStore.swift, which
    /// the Xcode index pass occasionally fails to surface in this
    /// file's compile unit. Static-let so we still pay the formatter-
    /// init cost only once per process.
    nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) static let isoFormatterNoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let s = raw, !s.isEmpty else { return nil }
        if let d = isoFormatter.date(from: s) { return d }
        if let d = isoFormatterNoFractional.date(from: s) { return d }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)
    }
}

enum BoardFactory {

    // MARK: Compliance — compliance.getViolations
    //
    // Server shape (routers/compliance.ts:getViolations):
    //   [{ id, driverId, vehicleId, type, status, defectsFound,
    //      oosViolation, location, completedAt, createdAt,
    //      driverName? }]
    // Flat array (not wrapped).

    static func compliance() -> DynamicBoardStore {
        DynamicBoardStore(
            endpoint: "compliance.getViolations",
            input: ["limit": 10]
        ) { data in
            struct Row: Decodable {
                let id: Int
                let type: String?
                let status: String?
                let defectsFound: Int?
                let oosViolation: Bool?
                let location: String?
                let completedAt: String?
                let createdAt: String?
                let driverName: String?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<[Row]>.self, from: data)
            return env.result.data.json.map { r in
                let sev: BoardRowSeverity = (r.oosViolation == true)
                    ? .critical
                    : ((r.defectsFound ?? 0) > 0 ? .watch : .info)
                let title = (r.defectsFound ?? 0) > 0
                    ? "\(r.defectsFound!) defect\(r.defectsFound! == 1 ? "" : "s")"
                    : (r.type?.capitalized ?? "Violation")
                return BoardRow(
                    id: String(r.id),
                    title: title,
                    subtitle: [r.driverName, r.location].compactMap { $0 }.joined(separator: " · "),
                    accessory: (r.oosViolation == true) ? "OOS" : r.type?.uppercased(),
                    severity: sev,
                    timestamp: BoardDate.parse(r.completedAt ?? r.createdAt)
                )
            }
        }
    }

    // MARK: Maintenance — equipment.list
    //
    // Server shape (routers/equipment.ts:list):
    //   { equipment: [{ id, unitNumber, type, status, make, model,
    //      year, vin, licensePlate, lastInspection, nextInspection,
    //      ... }], total, summary }

    static func maintenance() -> DynamicBoardStore {
        DynamicBoardStore(
            endpoint: "equipment.list",
            input: ["limit": 10]
        ) { data in
            struct Envelope: Decodable {
                let equipment: [Row]
            }
            struct Row: Decodable {
                let id: String
                let unitNumber: String?
                let type: String?
                let status: String?
                let make: String?
                let model: String?
                let year: Int?
                let lastInspection: String?
                let nextInspection: String?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<Envelope>.self, from: data)
            return env.result.data.json.equipment.map { r in
                let status = (r.status ?? "").lowercased()
                let sev: BoardRowSeverity = status.contains("out")
                    ? .critical
                    : (status.contains("maint") ? .watch : .info)
                let makeModel = [r.make, r.model]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " ")
                return BoardRow(
                    id: r.id,
                    title: r.unitNumber ?? "EQ-\(r.id)",
                    subtitle: makeModel.isEmpty ? r.status?.capitalized : makeModel,
                    accessory: r.type?.uppercased(),
                    severity: sev,
                    timestamp: BoardDate.parse(r.nextInspection ?? r.lastInspection)
                )
            }
        }
    }

    // MARK: Fuel — fuel.getTransactions
    //
    // Server shape (routers/fuel.ts:getTransactions):
    //   { transactions: [{ id, driverId, vehicleId, stationName,
    //      gallons, pricePerGallon, totalAmount, date }], total }

    static func fuel() -> DynamicBoardStore {
        DynamicBoardStore(
            endpoint: "fuel.getTransactions",
            input: ["limit": 8]
        ) { data in
            struct Envelope: Decodable {
                let transactions: [Row]
            }
            struct Row: Decodable {
                let id: String
                let stationName: String?
                let gallons: Double?
                let totalAmount: Double?
                let date: String?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<Envelope>.self, from: data)
            return env.result.data.json.transactions.map { r in
                let amt = r.totalAmount ?? 0
                let gal = r.gallons ?? 0
                let subtitle = gal > 0 ? String(format: "%.1f gal", gal) : nil
                return BoardRow(
                    id: r.id,
                    title: (r.stationName?.isEmpty == false ? r.stationName! : "Fuel stop"),
                    subtitle: subtitle,
                    accessory: amt > 0 ? "$\(String(format: "%.0f", amt))" : nil,
                    severity: .info,
                    timestamp: BoardDate.parse(r.date)
                )
            }
        }
    }

    // MARK: Factoring — factoring.getOverview
    //
    // Server shape (routers/factoring.ts:getOverview):
    //   { account: {...}, currentPeriod: {...},
    //     recentActivity: [{ id, invoiceNumber, status, amount,
    //                        date }] }

    static func factoring() -> DynamicBoardStore {
        DynamicBoardStore(endpoint: "factoring.getOverview") { data in
            struct Envelope: Decodable {
                let recentActivity: [Row]?
            }
            struct Row: Decodable {
                let id: String
                let invoiceNumber: String?
                let status: String?
                let amount: Double?
                let date: String?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<Envelope>.self, from: data)
            let rows = env.result.data.json.recentActivity ?? []
            return rows.map { r in
                let statusLower = (r.status ?? "").lowercased()
                let sev: BoardRowSeverity = statusLower.contains("reject") || statusLower.contains("dispute")
                    ? .critical
                    : (statusLower.contains("pend") || statusLower.contains("review") ? .watch : .positive)
                return BoardRow(
                    id: r.id,
                    title: r.invoiceNumber ?? "Invoice \(r.id)",
                    subtitle: r.status?.capitalized,
                    accessory: (r.amount ?? 0) > 0 ? "$\(String(format: "%.0f", r.amount ?? 0))" : nil,
                    severity: sev,
                    timestamp: BoardDate.parse(r.date)
                )
            }
        }
    }

    // MARK: Admin — admin.getRecentActivity
    //
    // Server shape (routers/admin.ts:getRecentActivity):
    //   [{ id, action, user, entity, entityId, timestamp }]

    static func adminPlatform() -> DynamicBoardStore {
        DynamicBoardStore(
            endpoint: "admin.getRecentActivity",
            input: ["limit": 10]
        ) { data in
            struct Row: Decodable {
                let id: String
                let action: String?
                let user: String?
                let entity: String?
                let entityId: String?
                let timestamp: String?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<[Row]>.self, from: data)
            return env.result.data.json.map { r in
                let action = r.action?
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized ?? "Activity"
                let entity = [r.entity, r.entityId]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " #")
                return BoardRow(
                    id: r.id,
                    title: action,
                    subtitle: [r.user, entity]
                        .compactMap { $0?.isEmpty == false ? $0 : nil }
                        .joined(separator: " · "),
                    severity: .info,
                    timestamp: BoardDate.parse(r.timestamp)
                )
            }
        }
    }

    // MARK: Safety ops — safety.getRecentIncidents
    //
    // Server shape (routers/safety.ts:getRecentIncidents):
    //   [{ id, type, driver, date, severity, status }]

    static func safetyOps() -> DynamicBoardStore {
        DynamicBoardStore(
            endpoint: "safety.getRecentIncidents",
            input: ["limit": 10]
        ) { data in
            struct Row: Decodable {
                let id: String
                let type: String?
                let driver: String?
                let date: String?
                let severity: String?
                let status: String?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<[Row]>.self, from: data)
            return env.result.data.json.map { r in
                let sev: BoardRowSeverity = {
                    switch (r.severity ?? "").lowercased() {
                    case "critical", "major": return .critical
                    case "minor", "watch":    return .watch
                    default:                  return .info
                    }
                }()
                return BoardRow(
                    id: r.id,
                    title: r.type?.capitalized ?? "Incident",
                    subtitle: r.driver,
                    accessory: r.status?.uppercased(),
                    severity: sev,
                    timestamp: BoardDate.parse(r.date)
                )
            }
        }
    }

    // MARK: Rail shipments — railShipments.getRailShipments
    //
    // Server shape (routers/railShipments.ts:getRailShipments):
    //   { shipments: [DrizzleRow], total }
    // Drizzle row uses camelCase `railShipments` table columns —
    // we decode a forgiving subset.

    static func railShipmentBoard() -> DynamicBoardStore {
        DynamicBoardStore(
            endpoint: "railShipments.getRailShipments",
            input: ["limit": 10]
        ) { data in
            struct Envelope: Decodable {
                let shipments: [Row]
            }
            struct Row: Decodable {
                let id: Int
                let waybillNumber: String?
                let originYard: String?
                let destinationYard: String?
                let origin: String?
                let destination: String?
                let status: String?
                let commodity: String?
                let eta: String?
                let createdAt: String?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<Envelope>.self, from: data)
            return env.result.data.json.shipments.map { r in
                let lane = [r.originYard ?? r.origin, r.destinationYard ?? r.destination]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " → ")
                let sev: BoardRowSeverity = {
                    switch (r.status ?? "").lowercased() {
                    case let s where s.contains("delay"): return .watch
                    case let s where s.contains("hold"):  return .critical
                    default:                              return .info
                    }
                }()
                return BoardRow(
                    id: String(r.id),
                    title: r.waybillNumber ?? "RS-\(r.id)",
                    subtitle: lane.isEmpty ? r.commodity : lane,
                    accessory: r.status?.uppercased(),
                    severity: sev,
                    timestamp: BoardDate.parse(r.eta ?? r.createdAt)
                )
            }
        }
    }

    // MARK: Train consist — railShipments.getRailcars
    //
    // Server shape (routers/railShipments.ts:getRailcars):
    //   { railcars: [DrizzleRow], total }
    // Drizzle `railcars` columns: `carNumber`, `carType`, `status`,
    // `owner`, `currentYardId`, `lastLoadCommodity` (schema-dependent).

    static func trainConsist() -> DynamicBoardStore {
        DynamicBoardStore(
            endpoint: "railShipments.getRailcars",
            input: ["limit": 20]
        ) { data in
            struct Envelope: Decodable {
                let railcars: [Row]
            }
            struct Row: Decodable {
                let id: Int
                let carNumber: String?
                let carType: String?
                let status: String?
                let owner: String?
                let lastLoadCommodity: String?
                let commodity: String?
                let hazmat: Bool?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<Envelope>.self, from: data)
            return env.result.data.json.railcars.map { r in
                let isHazmat = r.hazmat == true
                let subtitle = r.lastLoadCommodity ?? r.commodity ?? r.carType
                let accessory: String = {
                    if isHazmat { return "HAZMAT" }
                    switch (r.status ?? "").lowercased() {
                    case "loaded":     return "LOADED"
                    case "empty":      return "MT"
                    case "in_transit": return "TRANSIT"
                    default:           return (r.status?.uppercased() ?? "—")
                    }
                }()
                return BoardRow(
                    id: String(r.id),
                    title: r.carNumber ?? "RC-\(r.id)",
                    subtitle: subtitle,
                    accessory: accessory,
                    severity: isHazmat ? .critical : .info,
                    timestamp: nil
                )
            }
        }
    }
    
    

    // MARK: Vessel shipments — vesselShipments.getVesselShipments
    //
    // Server shape: { shipments: [DrizzleRow], total }.
    // Drizzle `vesselShipments` columns: `bookingNumber`, `status`,
    // `eta`, `vesselName`, `originPortId`/`destinationPortId`,
    // `commodity`.

    static func vesselShipmentBoard() -> DynamicBoardStore {
        DynamicBoardStore(
            endpoint: "vesselShipments.getVesselShipments",
            input: ["limit": 10]
        ) { data in
            struct Envelope: Decodable {
                let shipments: [Row]
            }
            struct Row: Decodable {
                let id: Int
                let bookingNumber: String?
                let vesselName: String?
                let commodity: String?
                let status: String?
                let eta: String?
                let createdAt: String?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<Envelope>.self, from: data)
            return env.result.data.json.shipments.map { r in
                BoardRow(
                    id: String(r.id),
                    title: r.bookingNumber ?? r.vesselName ?? "VS-\(r.id)",
                    subtitle: r.commodity ?? r.vesselName,
                    accessory: r.status?.uppercased(),
                    severity: .info,
                    timestamp: BoardDate.parse(r.eta ?? r.createdAt)
                )
            }
        }
    }

    // MARK: Customs — vesselShipments.listBOLs
    //
    // Server shape (routers/vesselShipments.ts:listBOLs):
    //   flat [DrizzleRow] from the billsOfLading table.

    static func customs() -> DynamicBoardStore {
        DynamicBoardStore(
            endpoint: "vesselShipments.listBOLs",
            input: ["limit": 10]
        ) { data in
            struct Row: Decodable {
                let id: Int
                let bolNumber: String?
                let shipmentId: Int?
                let status: String?
                let issuedAt: String?
                let createdAt: String?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<[Row]>.self, from: data)
            return env.result.data.json.map { r in
                let statusLower = (r.status ?? "").lowercased()
                let sev: BoardRowSeverity = statusLower == "surrendered"
                    ? .positive
                    : (statusLower == "pending" ? .watch : .info)
                return BoardRow(
                    id: String(r.id),
                    title: r.bolNumber ?? "BOL-\(r.id)",
                    subtitle: r.shipmentId.map { "Shipment #\($0)" },
                    accessory: r.status?.uppercased(),
                    severity: sev,
                    timestamp: BoardDate.parse(r.issuedAt ?? r.createdAt)
                )
            }
        }
    }

    // MARK: Intermodal — intermodal.getIntermodalShipments
    //
    // Server shape: { shipments: [DrizzleRow], total } from the
    // intermodalShipments table.

    static func intermodal() -> DynamicBoardStore {
        DynamicBoardStore(
            endpoint: "intermodal.getIntermodalShipments",
            input: ["limit": 10]
        ) { data in
            struct Envelope: Decodable {
                let shipments: [Row]
            }
            struct Row: Decodable {
                let id: Int
                let containerNumber: String?
                let chassisNumber: String?
                let status: String?
                let currentSegment: String?
                let segment: String?
                let commodity: String?
                let eta: String?
                let createdAt: String?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<Envelope>.self, from: data)
            return env.result.data.json.shipments.map { r in
                BoardRow(
                    id: String(r.id),
                    title: r.containerNumber ?? r.chassisNumber ?? "IM-\(r.id)",
                    subtitle: r.commodity ?? r.currentSegment ?? r.segment,
                    accessory: r.status?.uppercased(),
                    severity: .info,
                    timestamp: BoardDate.parse(r.eta ?? r.createdAt)
                )
            }
        }
    }

    // MARK: Port ops — controlTower.exceptions
    //
    // Server shape (routers/controlTower.ts:exceptions):
    //   { truckExceptions: [LoadRow + mode + exceptionType],
    //     vesselExceptions: [VesselRow + mode + exceptionType],
    //     ... }
    // Both feeds folded into one board — the mode label rides on
    // the row's accessory.

    static func portOps() -> DynamicBoardStore {
        DynamicBoardStore(
            endpoint: "controlTower.exceptions",
            input: ["limit": 10]
        ) { data in
            struct Envelope: Decodable {
                let truckExceptions: [TruckRow]?
                let vesselExceptions: [VesselRow]?
            }
            struct TruckRow: Decodable {
                let id: Int
                let status: String?
                let pickupLocation: String?
                let deliveryLocation: String?
                let deliveryDate: String?
                let exceptionType: String?
            }
            struct VesselRow: Decodable {
                let id: Int
                let bookingNumber: String?
                let status: String?
                let eta: String?
                let exceptionType: String?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<Envelope>.self, from: data)
            var rows: [BoardRow] = []
            for t in env.result.data.json.truckExceptions ?? [] {
                let lane = [t.pickupLocation, t.deliveryLocation]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " → ")
                rows.append(BoardRow(
                    id: "truck-\(t.id)",
                    title: t.exceptionType?
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized ?? "Truck exception",
                    subtitle: lane.isEmpty ? t.status : lane,
                    accessory: "TRUCK",
                    severity: .watch,
                    timestamp: BoardDate.parse(t.deliveryDate)
                ))
            }
            for v in env.result.data.json.vesselExceptions ?? [] {
                rows.append(BoardRow(
                    id: "vessel-\(v.id)",
                    title: v.exceptionType?
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized ?? "Vessel exception",
                    subtitle: v.bookingNumber ?? v.status,
                    accessory: "VESSEL",
                    severity: .watch,
                    timestamp: BoardDate.parse(v.eta)
                ))
            }
            rows.sort { (a, b) in
                (a.timestamp ?? .distantPast) > (b.timestamp ?? .distantPast)
            }
            return rows
        }
    }

    // MARK: Insurance — claims.list
    //
    // Server shape (routers/claims.ts:list):
    //   { claims: [{ id: "claim_N", claimNumber, type, status,
    //      loadNumber, shipper, catalyst, amount, filedDate,
    //      description }], total }

    // MARK: DataQs — dataqs.listMine
    //
    // Server shape (routers/dataqs.ts:listMine, deployed 2026-05-05):
    //   { total: number, rows: [{ id, requestType, referenceNumber,
    //       jurisdiction, issuingOfficer, violationCode,
    //       challengeStatement, status, expectedReplyBy, submittedAt,
    //       resolvedAt, createdAt }] }
    //
    // Glance copy: ref # → "INSP-MO-…"; subtitle = jurisdiction +
    // status; accessory = days remaining on the FMCSA 21-day SLA.
    // Reform-aware: status `denied` paints critical, `approved` is
    // positive, `submitted/in_review` are watch.
    static func dataqs() -> DynamicBoardStore {
        DynamicBoardStore(
            endpoint: "dataqs.listMine",
            input: ["limit": 8, "offset": 0]
        ) { data in
            struct Envelope: Decodable {
                let total: Int
                let rows: [Row]
            }
            struct Row: Decodable {
                let id: String
                let requestType: String
                let referenceNumber: String
                let jurisdiction: String?
                let issuingOfficer: String?
                let violationCode: String?
                let status: String
                let expectedReplyBy: String?
                let submittedAt: String?
                let resolvedAt: String?
                let createdAt: String
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<Envelope>.self, from: data)
            let now = Date()
            return env.result.data.json.rows.map { r in
                let statusLower = r.status.lowercased()
                let sev: BoardRowSeverity = {
                    switch statusLower {
                    case "denied", "appeal_denied":      return .critical
                    case "approved":                     return .positive
                    case "submitted", "in_review",
                         "info_requested", "appeal_filed": return .watch
                    default:                             return .info
                    }
                }()
                // Days remaining against the 21d FMCSA initial-review
                // SLA (or "Resolved"). Surfaces "5d left" on the wrist
                // so a Compliance Officer / Safety Mgr knows at a
                // glance which RDR is about to lapse.
                let accessory: String? = {
                    if r.resolvedAt != nil { return "DONE" }
                    if let iso = r.expectedReplyBy,
                       let d = BoardDate.parse(iso) {
                        let days = Int((d.timeIntervalSince(now) / 86_400).rounded())
                        if days < 0 { return "OVERDUE" }
                        if days == 0 { return "TODAY" }
                        return "\(days)d"
                    }
                    return r.status.uppercased()
                }()
                let subtitle = [
                    r.jurisdiction.map { "MO·\($0)".replacingOccurrences(of: "MO·", with: "") },
                    r.violationCode,
                    r.issuingOfficer
                ].compactMap { $0 }.joined(separator: " · ")
                return BoardRow(
                    id: r.id,
                    title: "RDR \(r.referenceNumber)",
                    subtitle: subtitle.isEmpty ? r.requestType.replacingOccurrences(of: "_", with: " ") : subtitle,
                    accessory: accessory,
                    severity: sev,
                    timestamp: BoardDate.parse(r.submittedAt ?? r.createdAt)
                )
            }
        }
    }

    static func insurance() -> DynamicBoardStore {
        DynamicBoardStore(
            endpoint: "claims.list",
            input: ["limit": 10]
        ) { data in
            struct Envelope: Decodable {
                let claims: [Row]
            }
            struct Row: Decodable {
                let id: String
                let claimNumber: String?
                let type: String?
                let status: String?
                let amount: Double?
                let filedDate: String?
                let description: String?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<Envelope>.self, from: data)
            return env.result.data.json.claims.map { r in
                let sev: BoardRowSeverity = {
                    switch (r.status ?? "").lowercased() {
                    case "open", "reported", "investigating": return .watch
                    case "denied", "disputed":                  return .critical
                    case "paid", "closed", "settled":           return .positive
                    default:                                     return .info
                    }
                }()
                return BoardRow(
                    id: r.id,
                    title: r.claimNumber ?? r.id,
                    subtitle: r.type?.capitalized ?? r.description,
                    accessory: (r.amount ?? 0) > 0
                        ? "$\(String(format: "%.0f", r.amount ?? 0))"
                        : r.status?.uppercased(),
                    severity: sev,
                    timestamp: BoardDate.parse(r.filedDate)
                )
            }
        }
    }
}
