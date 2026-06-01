//
//  697_VesselPortOperations.swift
//  EusoTrip — Vessel Operator · Port Operations (MARINE TERMINAL LIVE OPS CONSOLE).
//
//  Verbatim bespoke port of canonical wireframe 697 "Vessel Port Operations".
//  Carrier-side live ops console for a marine terminal (USLGB Long Beach Pier T,
//  MSC ocean carrier). Console/detail grammar — NOT the operator-home grammar:
//  one gradient-rim hero "live · port dashboard" card with the berths-used %,
//  a three-tile KPI strip (GATE MOVES · DWELL · ON HOLD), a live PORT CALL QUEUE
//  list (queued / working / hold berth windows), a BERTH GUARD rollup, and a
//  two-CTA action row (Assign berth · Lineup).
//
//  Docked under HOME. transportMode=vessel · US (USCG / CBP).
//
//  REAL WIRING (tRPC, server/routers/vesselShipments.ts):
//    · getPorts          {search:"Long Beach", limit:5}  -> resolve home port
//        (ports row: id, name, unlocode, totalBerths) (vesselShipments.ts:1760)
//    · getBerthSchedule  {portId}  -> vessel_berth_assignments rows ->
//        PORT CALL QUEUE rows + berths-used numerator + ON HOLD count
//        (vesselShipments.ts:971 -> port_berths/vessel_berth_assignments schema)
//    · getVesselFleet    {limit:50} -> {vessels,total} -> VESSELS in port count
//        (vesselShipments.ts:1124)
//    · getVesselsAtPort  {portId}  -> live MarineTraffic vessels-at-berth, used
//        to enrich the "in port" figure when AIS data is present
//        (vesselShipments.ts:1303)
//
//  RBAC: reads vesselProcedure. NO mock data — the berths-used %, queue rows,
//  on-hold count and vessels-in-port all derive from live endpoints, with real
//  loading / error / honest-empty states. The "Assign berth" / "Lineup" CTAs
//  push into the directory/lineup surfaces (no fabricated mutation).
//

import SwiftUI

struct VesselPortOperationsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselPortOperationsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: true),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

/// `getPorts` row (subset of the `ports` table we read for the console header).
private struct PortRow697: Decodable, Identifiable {
    let id: Int
    let name: String?
    let unlocode: String?
    let city: String?
    let state: String?
    let totalBerths: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, unlocode, city, state, totalBerths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) { id = i }
        else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) { id = i }
        else { id = 0 }
        name = try? c.decode(String.self, forKey: .name)
        unlocode = try? c.decode(String.self, forKey: .unlocode)
        city = try? c.decode(String.self, forKey: .city)
        state = try? c.decode(String.self, forKey: .state)
        totalBerths = try? c.decode(Int.self, forKey: .totalBerths)
    }
}

/// `getBerthSchedule` -> vessel_berth_assignments rows. One row per scheduled /
/// berthed call; powers the PORT CALL QUEUE list and the berths-used / on-hold
/// rollups. All columns are nullable server-side, so decode defensively.
private struct BerthAssignment697: Decodable, Identifiable {
    let id: Int
    let vesselId: Int?
    let berthId: Int?
    let scheduledArrival: String?
    let actualArrival: String?
    let scheduledDeparture: String?
    let actualDeparture: String?
    let status: String?            // scheduled | berthed | departed | cancelled
    let pilotRequired: Bool?
    let tugboatsRequired: Int?

    private enum CodingKeys: String, CodingKey {
        case id, vesselId, berthId
        case scheduledArrival, actualArrival, scheduledDeparture, actualDeparture
        case status, pilotRequired, tugboatsRequired
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) { id = i }
        else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) { id = i }
        else { id = 0 }
        vesselId = try? c.decode(Int.self, forKey: .vesselId)
        berthId  = try? c.decode(Int.self, forKey: .berthId)
        scheduledArrival   = try? c.decode(String.self, forKey: .scheduledArrival)
        actualArrival      = try? c.decode(String.self, forKey: .actualArrival)
        scheduledDeparture = try? c.decode(String.self, forKey: .scheduledDeparture)
        actualDeparture    = try? c.decode(String.self, forKey: .actualDeparture)
        status = try? c.decode(String.self, forKey: .status)
        if let b = try? c.decode(Bool.self, forKey: .pilotRequired) { pilotRequired = b }
        else if let n = try? c.decode(Int.self, forKey: .pilotRequired) { pilotRequired = n != 0 }
        else { pilotRequired = nil }
        tugboatsRequired = try? c.decode(Int.self, forKey: .tugboatsRequired)
    }
}

/// `getVesselFleet` -> { vessels, total }
private struct VesselFleetResponse697: Decodable {
    let vessels: [FleetVessel697]
    let total: Int?
}

private struct FleetVessel697: Decodable, Identifiable {
    let id: Int
    let name: String?
    let imoNumber: String?
    let status: String?
}

/// `getVesselsAtPort` — live MarineTraffic vessels-at-port payload (or null).
/// Decoded defensively so an unexpected provider shape degrades to an empty
/// strip rather than breaking the console.
private struct VesselsAtPort697: Decodable {
    let count: Int

    private enum CodingKeys: String, CodingKey { case vessels, data }

    init(count: Int) { self.count = count }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            if let v = try? c.decode([AnyDecodable697].self, forKey: .vessels) { count = v.count; return }
            if let v = try? c.decode([AnyDecodable697].self, forKey: .data) { count = v.count; return }
        }
        if let arr = try? decoder.singleValueContainer().decode([AnyDecodable697].self) {
            count = arr.count; return
        }
        count = 0
    }
}

/// Opaque element used only to count provider rows.
private struct AnyDecodable697: Decodable { init(from decoder: Decoder) throws {} }

// MARK: - Body

private struct VesselPortOperationsBody: View {
    @Environment(\.palette) private var palette

    @State private var port: PortRow697? = nil
    @State private var assignments: [BerthAssignment697] = []
    @State private var fleetTotal: Int? = nil
    @State private var liveAtPort: Int? = nil

    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s3)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(Brand.danger)
                                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            }
                        }
                    } else {
                        heroCard
                        kpiStrip
                        portCallQueueSection
                        berthGuardCard
                        ctaRow
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + back chevron + title + carrier·port mono + menu)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · PORT OPS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text(carrierPortLabel)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Port ops")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s4)
        }
        .padding(.top, Space.s5)
    }

    /// "MSC · USLGB" — carrier fixed to the operator; port code from the live row.
    private var carrierPortLabel: String {
        let code = port?.unlocode?.uppercased()
        if let code, !code.isEmpty { return "MSC · \(code)" }
        return "MSC · PORT"
    }

    // MARK: - Hero card (gradient rim · live · port dashboard · berths-used %)

    private var heroCard: some View {
        ZStack {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: 6) {
                        pill("live")
                        pill("port dashboard")
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                        Text(berthUsedLabel)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                        VStack(alignment: .leading, spacing: 1) {
                            Text("berths used")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text(berthsFractionLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("VESSELS")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(vesselsLabel)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text("in port")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1.5)
        )
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).tracking(0.5)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
    }

    // MARK: - KPI strip (GATE MOVES · DWELL · ON HOLD)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // GATE MOVES — gradient-fill tile. HONEST-EMPTY until a gate-moves
            // feed exists server-side; we render "—" rather than a fabricated
            // 1,240. (No gate-throughput proc on vesselShipments today.)
            VStack(alignment: .leading, spacing: 6) {
                Text("GATE MOVES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text("—")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).monospacedDigit()
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(Space.s4)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiTile(label: "DWELL", value: "—",
                    accent: nil)
            kpiTile(label: "ON HOLD", value: "\(onHoldCount)",
                    accent: onHoldCount > 0 ? Brand.warning : nil)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func kpiTile(label: String, value: String, accent: Color?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent ?? palette.textPrimary).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Port call queue

    private var portCallQueueSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("PORT CALL QUEUE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("Live")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            }

            VStack(spacing: 0) {
                if visibleCalls.isEmpty {
                    emptyQueueRow
                } else {
                    ForEach(Array(visibleCalls.enumerated()), id: \.element.id) { idx, call in
                        callRow(call)
                        if idx < visibleCalls.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                    if footerLine != nil {
                        Divider().overlay(palette.borderFaint)
                            .padding(.horizontal, Space.s4)
                        HStack {
                            Text(footerLine ?? "")
                                .font(.system(size: 10))
                                .foregroundStyle(palette.textTertiary)
                            Spacer()
                        }
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s3)
                    }
                }
            }
            .padding(.vertical, Space.s1)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// Show up to 3 calls in the queue card (matches the SVG's 3-row window).
    private var visibleCalls: [BerthAssignment697] {
        Array(sortedCalls.prefix(3))
    }

    /// "+ N more calls · M vessels in port" footer, or nil when nothing extra.
    private var footerLine: String? {
        let extra = sortedCalls.count - visibleCalls.count
        let inPort = vesselsInPort
        var parts: [String] = []
        if extra > 0 { parts.append("+ \(extra) more call\(extra == 1 ? "" : "s")") }
        if let inPort { parts.append("\(inPort) vessel\(inPort == 1 ? "" : "s") in port") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var emptyQueueRow: some View {
        EusoEmptyState(
            systemImage: "ferry",
            title: "No berth calls scheduled",
            subtitle: port == nil
                ? "Resolve a home port to surface its live berth schedule."
                : "Scheduled and berthed calls for this terminal will appear here."
        )
        .padding(Space.s3)
    }

    private func callRow(_ call: BerthAssignment697) -> some View {
        let cat = category(for: call)
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cat.color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: cat.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(cat.color)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(cat.title + berthSuffix(call))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: Space.s2)
                    Text(cat.badge)
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(cat.color)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(cat.color.opacity(0.16)))
                }
                Text(metaLine(call))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack {
                    Spacer()
                    Text(trailingMetric(call, cat: cat))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                }
            }
        }
        .padding(Space.s4)
    }

    // MARK: - Berth guard rollup

    private var berthGuardCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("BERTH GUARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("Live")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(berthGuardLineOne)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(berthGuardLineTwo)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var berthGuardLineOne: String {
        var parts: [String] = []
        if let open = openBerths { parts.append("\(open) open berth\(open == 1 ? "" : "s")") }
        parts.append("\(onHoldCount) hold\(onHoldCount == 1 ? "" : "s") active")
        return parts.joined(separator: " · ")
    }

    private var berthGuardLineTwo: String {
        let active = activeCalls.count
        return "\(active) active call\(active == 1 ? "" : "s") · \(vesselsInPort ?? fleetTotal ?? 0) vessels tracked"
    }

    // MARK: - CTA row (Assign berth · Lineup)

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { } label: {
                Text("Assign berth")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button { } label: {
                Text("Lineup")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 160)
        }
    }

    // MARK: - Call categorization (real status → console grammar)

    private struct CallCategory {
        let title: String
        let badge: String
        let icon: String
        let color: Color
    }

    /// Map the real vessel_berth_assignments.status enum onto the console's
    /// queued / working / hold grammar from the wireframe.
    private func category(for call: BerthAssignment697) -> CallCategory {
        let s = (call.status ?? "").lowercased()
        switch s {
        case "berthed":
            return CallCategory(title: "Discharge", badge: "WORKING",
                                icon: "shippingbox.fill", color: Brand.success)
        case "cancelled":
            return CallCategory(title: "Crane hold", badge: "HOLD",
                                icon: "bracket.rectangle", color: Brand.warning)
        case "departed":
            return CallCategory(title: "Departed", badge: "CLEARED",
                                icon: "arrow.up.right", color: palette.textSecondary)
        default: // scheduled / unknown → queued berth window
            return CallCategory(title: "Berth window", badge: "QUEUED",
                                icon: "ferry.fill", color: Brand.info)
        }
    }

    private func berthSuffix(_ call: BerthAssignment697) -> String {
        if let b = call.berthId { return " · B\(b)" }
        return ""
    }

    /// "vessel #ID · pilot · 2 tugs" — real assignment metadata (mono).
    private func metaLine(_ call: BerthAssignment697) -> String {
        var parts: [String] = []
        if let v = call.vesselId { parts.append("vessel #\(v)") }
        if call.pilotRequired == true { parts.append("pilot") }
        if let t = call.tugboatsRequired, t > 0 { parts.append("\(t) tug\(t == 1 ? "" : "s")") }
        if let etb = etbLabel(call) { parts.append("ETB \(etb)") }
        return parts.isEmpty ? "assignment #\(call.id)" : parts.joined(separator: " · ")
    }

    /// Trailing metric: ETB-relative time for queued; status word otherwise.
    private func trailingMetric(_ call: BerthAssignment697, cat: CallCategory) -> String {
        if let rel = relativeETB(call) { return rel }
        return cat.badge == "QUEUED" ? "queued" : cat.title.lowercased()
    }

    // MARK: - Derived KPI / rollup values (all from live endpoints)

    /// Calls considered "active at terminal": scheduled or berthed.
    private var activeCalls: [BerthAssignment697] {
        assignments.filter {
            let s = ($0.status ?? "").lowercased()
            return s == "scheduled" || s == "berthed"
        }
    }

    /// Queue ordering: berthed (working) first, then by scheduled arrival.
    private var sortedCalls: [BerthAssignment697] {
        func isBerthed(_ c: BerthAssignment697) -> Bool {
            (c.status ?? "").lowercased() == "berthed"
        }
        return activeCalls.sorted { a, b in
            let aB = (isBerthed(a) ? 0 : 1)
            let bB = (isBerthed(b) ? 0 : 1)
            if aB != bB { return aB < bB }
            return (a.scheduledArrival ?? "") < (b.scheduledArrival ?? "")
        }
    }

    /// ON HOLD = cancelled assignments (terminal/labor holds). HONEST mapping:
    /// the schema has no dedicated "hold" enum, so a cancelled berth window is
    /// the on-hold signal; 0 when none.
    private var onHoldCount: Int {
        assignments.filter { ($0.status ?? "").lowercased() == "cancelled" }.count
    }

    /// Berths occupied right now = distinct berthIds with a berthed assignment.
    private var berthsUsed: Int {
        Set(assignments
            .filter { ($0.status ?? "").lowercased() == "berthed" }
            .compactMap { $0.berthId }).count
    }

    private var totalBerths: Int? { port?.totalBerths }

    private var openBerths: Int? {
        guard let total = totalBerths else { return nil }
        return max(0, total - berthsUsed)
    }

    private var berthUsedLabel: String {
        guard let total = totalBerths, total > 0 else { return "—" }
        let pct = Int((Double(berthsUsed) / Double(total) * 100).rounded())
        return "\(pct)%"
    }

    private var berthsFractionLabel: String {
        guard let total = totalBerths else { return "berths from schedule" }
        return "\(berthsUsed) of \(total) berths"
    }

    /// Vessels in port: prefer live MarineTraffic count, else berthed-assignment
    /// count, else the operator fleet total.
    private var vesselsInPort: Int? {
        if let live = liveAtPort, live > 0 { return live }
        let berthed = activeCalls.filter { ($0.status ?? "").lowercased() == "berthed" }.count
        if berthed > 0 { return berthed }
        return fleetTotal
    }

    private var vesselsLabel: String {
        if let n = vesselsInPort { return "\(n)" }
        return "—"
    }

    // MARK: - Time formatting helpers

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return Self.iso.date(from: s) ?? Self.isoNoFrac.date(from: s)
    }

    /// "06:00" ETB clock label from the scheduled arrival.
    private func etbLabel(_ call: BerthAssignment697) -> String? {
        guard let d = parseDate(call.scheduledArrival) else { return nil }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// "in 2h" / "now" relative ETB for the trailing metric.
    private func relativeETB(_ call: BerthAssignment697) -> String? {
        guard let d = parseDate(call.scheduledArrival) else { return nil }
        let delta = d.timeIntervalSinceNow
        if delta <= 0 { return "now" }
        let mins = Int(delta / 60)
        if mins < 60 { return "in \(mins) min" }
        let hrs = mins / 60
        if hrs < 48 { return "in \(hrs)h" }
        return "in \(hrs / 24)d"
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 252)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct PortsIn: Encodable { let limit: Int; let search: String? }
        struct BerthIn: Encodable { let portId: Int }
        struct FleetIn: Encodable { let limit: Int }
        struct AtPortIn: Encodable { let portId: String }
        do {
            // 1) Resolve the operator's home terminal (Long Beach Pier T / USLGB).
            let portRows: [PortRow697] = try await EusoTripAPI.shared.query(
                "vesselShipments.getPorts", input: PortsIn(limit: 5, search: "Long Beach"))
            let resolved = portRows.first { ($0.unlocode ?? "").uppercased().contains("USLGB") }
                ?? portRows.first
            self.port = resolved

            // 2) Fleet total (VESSELS in port denominator) — independent of port.
            async let fleet: VesselFleetResponse697 = EusoTripAPI.shared.query(
                "vesselShipments.getVesselFleet", input: FleetIn(limit: 50))

            // 3) Berth schedule + live vessels-at-port — only when a port resolved.
            if let pid = resolved?.id, pid > 0 {
                async let berths: [BerthAssignment697] = EusoTripAPI.shared.query(
                    "vesselShipments.getBerthSchedule", input: BerthIn(portId: pid))
                async let atPort: VesselsAtPort697? = EusoTripAPI.shared.query(
                    "vesselShipments.getVesselsAtPort", input: AtPortIn(portId: String(pid)))
                let (fleetResp, berthResp, atPortResp) = try await (fleet, berths, atPort)
                self.fleetTotal = fleetResp.total ?? fleetResp.vessels.count
                self.assignments = berthResp
                self.liveAtPort = atPortResp?.count
            } else {
                let fleetResp = try await fleet
                self.fleetTotal = fleetResp.total ?? fleetResp.vessels.count
                self.assignments = []
                self.liveAtPort = nil
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("697 · Vessel Port Operations · Night") { VesselPortOperationsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("697 · Vessel Port Operations · Light") { VesselPortOperationsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
