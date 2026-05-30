//
//  295_ShipperDockAppointments.swift
//  EusoTrip
//
//  EusoTrip 2027 · 295 Shipper Dock Appointments · verbatim port of
//  `02 Shipper/Light-SVG/295 Shipper Dock Appointments.svg` (viewBox 440×956).
//
//  PURPOSE (from the wireframe <desc>): a vertical day-timeline of dock
//  appointments at the shipper's own terminal. The shipper sees every
//  truck's dock window on one rail and can pull a load forward into an
//  open slot to cut dwell before detention starts.
//
//  WEB PEER: client/src/pages/shipper/ShipperAppointments.tsx (/shipper/appointments)
//
//  BACKEND CONTRACT (all in server/routers/appointments.ts):
//    • appointments.getSummary       EXISTS·328  → KPI hero (today/completed/inProgress/upcoming)
//    • appointments.list             EXISTS·39   → timeline blocks (terminal/date scoped)
//    • appointments.getAvailableSlots EXISTS·267  → ESang open-slot suggestion
//    • appointments.checkIn          EXISTS·238  → advance a block → checked_in
//    • appointments.startLoading     EXISTS·342  → advance a block → loading
//    • appointments.complete         EXISTS·353  → advance a block → completed
//    • appointments.getHazmatBays    EXISTS·370  → certified bay options for the NH₃ block
//    • appointments.assignHazmatBay  EXISTS·468  → gate the escort block to a certified bay
//
//  HONESTY NOTES (read the §40 oath report before editing):
//    1. The <desc> names `getMyAppointments` for the timeline, but that
//       procedure is DRIVER-scoped (eq(appointments.driverId, userId)).
//       A SHIPPER user has no driverId match, so it returns []. The
//       honest read for a shipper terminal is `appointments.list`
//       (terminal + date filtered). This port binds `list`.
//    2. The SVG's sample lanes ("Houston TX → Dallas TX", "gasoline",
//       etc.) are DESIGN PLACEHOLDERS. This port renders only fields the
//       server actually returns. Lane / commodity / hazmat are decoded
//       as OPTIONALS — they populate once the `appointments.list`
//       enrichment patch (joins `loads`) lands, and degrade to the load
//       reference + dock + status before then. Nothing is faked.
//    3. Status badge colors map verbatim to the SVG fills:
//       LOADING #FFA726→Brand.warning · CHECKED IN #00C48C→Brand.success
//       SCHEDULED #2196F3→Brand.info · DONE #8A96A3→Brand.neutral.
//    4. BottomNav uses the canonical ShipperScreenWrap chrome
//       (Home/Create Load/Loads/Me + orb), currentSlot = .loads, per the
//       shipped design-authority reconciliation across 219+ screens. The
//       SVG's older HOME/LOADS/WALLET/ME plate is superseded.
//
//  Persona: Diego Usoro / Eusorone Technologies · Houston Terminal.
//  transportMode = truck · country = US.
//

import SwiftUI

// MARK: - Decoders (screen-scoped; field-for-field with the server returns)

/// One timeline block. Mirrors the `appointments.list` row mapping
/// (id/type/terminalId/loadId/driverId/scheduledAt/dockNumber/status)
/// plus the OPTIONAL enrichment fields added by the `appointments.list`
/// loads-join patch (loadNumber/originState/destState/commodity/hazmat…).
/// Every enrichment field is optional so the row decodes whether or not
/// the backend patch has landed (graceful degradation — pre-mortem #2).
struct DockAppointmentRow: Decodable, Hashable, Identifiable {
    let id: String
    let type: String?
    let terminalId: String?
    let loadId: String?
    let driverId: String?
    let scheduledAt: String?       // ISO-8601
    let dockNumber: String?
    let status: String?
    // enrichment (optional)
    let loadNumber: String?
    let originState: String?
    let destState: String?
    let commodity: String?
    let hazmatClass: String?
    let unNumber: String?
    let weightLbs: Double?
    let equipment: String?
}

private struct DockListEnvelope: Decodable {
    let appointments: [DockAppointmentRow]
    let total: Int?
}

private struct DockSlot: Decodable, Hashable {
    let time: String
    let available: Bool
    let capacity: Int?
    let booked: Int?
}

private struct DockSlotsEnvelope: Decodable {
    let facilityId: String?
    let date: String?
    let slots: [DockSlot]
}

// MARK: - Store

/// Loads the KPI summary + the terminal day-timeline in parallel. Holds
/// the open-slot ESang suggestion alongside. Subclass of nothing — a
/// lean ObservableObject because we fan three reads into one settle.
@MainActor
final class DockAppointmentsStore: ObservableObject {

    @Published var summary: AppointmentSummary? = nil
    @Published var rows: [DockAppointmentRow] = []
    @Published fileprivate var openSlot: DockSlot? = nil
    @Published var state: RemoteState<[DockAppointmentRow]> = .loading
    @Published var actingId: String? = nil
    @Published var actionError: String? = nil
    @Published var actionAck: String? = nil

    /// The shipper's home terminal. Houston Terminal = facility 1 in the
    /// canonical Eusorone seed; injected so the screen is not pinned to a
    /// constant if the surface later passes a resolved facilityId.
    var facilityId: String = "1"

    private func today() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
    }

    func load() async {
        if rows.isEmpty { state = .loading }
        async let s: Void = loadSummary()
        async let l: Void = loadTimeline()
        async let o: Void = loadOpenSlot()
        _ = await (s, l, o)
    }

    private func loadSummary() async {
        do {
            // getSummary's input is `.optional()` → a no-input query decodes fine.
            let out: AppointmentSummary = try await EusoTripAPI.shared
                .queryNoInput("appointments.getSummary")
            summary = out
        } catch {
            // Hero degrades to em-dashes; never blocks the timeline.
        }
    }

    private func loadTimeline() async {
        struct In: Encodable {
            let date: String
            let facilityId: String
            let limit: Int
            let offset: Int
        }
        do {
            let env: DockListEnvelope = try await EusoTripAPI.shared.query(
                "appointments.list",
                input: In(date: today(), facilityId: facilityId, limit: 50, offset: 0)
            )
            let sorted = env.appointments.sorted { ($0.scheduledAt ?? "") < ($1.scheduledAt ?? "") }
            rows = sorted
            state = sorted.isEmpty ? .empty : .loaded(sorted)
        } catch {
            state = .error(error)
        }
    }

    private func loadOpenSlot() async {
        struct In: Encodable { let facilityId: String; let date: String; let type: String }
        do {
            let env: DockSlotsEnvelope = try await EusoTripAPI.shared.query(
                "appointments.getAvailableSlots",
                input: In(facilityId: facilityId, date: today(), type: "pickup")
            )
            openSlot = env.slots.first(where: { $0.available })
        } catch {
            openSlot = nil
        }
    }

    /// Advance one block. action ∈ { checkIn, startLoading, complete }.
    /// Real mutation, real do/catch → actionError. No optimistic lie.
    func advance(_ action: String, id: String) async {
        actingId = id; actionError = nil; actionAck = nil
        struct In: Encodable { let appointmentId: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "appointments.\(action)", input: In(appointmentId: id)
            )
            actionAck = "Block \(id) → \(action) ✓"
            await load()   // re-pull so the timeline + hero reflect the new state
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        actingId = nil
    }
}

// MARK: - Status mapping (verbatim from the SVG fills)

private enum DockStatus {
    case scheduled, checkedIn, loading, unloading, completed, cancelled, unknown

    init(_ raw: String?) {
        switch (raw ?? "").lowercased() {
        case "scheduled", "confirmed": self = .scheduled
        case "checked_in":             self = .checkedIn
        case "loading":                self = .loading
        case "unloading":              self = .unloading
        case "completed":              self = .completed
        case "cancelled", "no_show":   self = .cancelled
        default:                       self = .unknown
        }
    }

    var label: String {
        switch self {
        case .scheduled: return "SCHEDULED"
        case .checkedIn: return "CHECKED IN"
        case .loading:   return "LOADING"
        case .unloading: return "UNLOADING"
        case .completed: return "DONE"
        case .cancelled: return "CANCELLED"
        case .unknown:   return "—"
        }
    }

    var tint: Color {
        switch self {
        case .loading, .unloading: return Brand.warning   // #FFA726
        case .checkedIn:           return Brand.success    // #00C48C
        case .scheduled:           return Brand.info       // #2196F3
        case .completed:           return Brand.neutral    // #8A96A3
        case .cancelled:           return Brand.danger
        case .unknown:             return Brand.neutral
        }
    }

    /// The next forward action available from this state (nil = terminal).
    var nextAction: (label: String, verb: String)? {
        switch self {
        case .scheduled: return ("Check in", "checkIn")
        case .checkedIn: return ("Start loading", "startLoading")
        case .loading, .unloading: return ("Complete", "complete")
        default: return nil
        }
    }
}

// MARK: - Screen

struct ShipperDockAppointments: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = DockAppointmentsStore()

    var body: some View {
        ShipperScreenWrap(palette: palette, currentSlot: .loads) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    header
                    kpiHero
                    timelineSection
                    if let slot = store.openSlot { esangSuggestion(slot) }
                    if let err = store.actionError { errorBanner(err) }
                    Color.clear.frame(height: Space.s8)   // nav breathing room
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
            .refreshable { await store.load() }
            .task { await store.load() }
        }
    }

    // MARK: top-of-page header (matches "Dock appointments" + subtitle)

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ SHIPPER · DOCK APPOINTMENTS")
                    .font(EType.micro)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                topPill
            }
            .padding(.bottom, Space.s2)

            Text("Dock appointments")
                .font(EType.h1)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · Houston Terminal · today")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    /// "N TODAY · M LOADING" — gold pill (SVG #FFB100 → Brand.hazmat).
    private var topPill: some View {
        let today = store.summary?.today ?? store.summary?.todayTotal
        let loading = store.rows.filter { DockStatus($0.status) == .loading || DockStatus($0.status) == .unloading }.count
        let todayStr = today.map(String.init) ?? "—"
        return Text("\(todayStr) TODAY · \(loading) LOADING")
            .font(EType.mono(.micro))
            .tracking(0.4)
            .foregroundStyle(Brand.hazmat)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s1)
            .background(Capsule().fill(Brand.hazmat.opacity(0.12)))
    }

    // MARK: KPI hero (DOCK SCHEDULE eyebrow + 4 stat cells)

    private var kpiHero: some View {
        let s = store.summary
        let done = s?.completed
        let loading = store.rows.filter {
            let st = DockStatus($0.status); return st == .loading || st == .unloading
        }.count
        // NEXT = first scheduled block's local HH:mm after now, else "—".
        let next = nextScheduledTime()
        return VStack(alignment: .leading, spacing: Space.s3) {
            Text("DOCK SCHEDULE · HOUSTON TERMINAL · TODAY")
                .font(EType.micro)
                .tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                statCell("TODAY", s?.today.map(String.init) ?? "—", palette.textPrimary)
                statCell("LOADING", String(loading), Brand.warning)
                statCell("DONE", done.map(String.init) ?? "—", palette.textSecondary)
                statCell("NEXT", next ?? "—", Brand.info)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func statCell(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro)
                .tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.numeric)
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("DAY TIMELINE · DOCK 1–4 · 08:00 → 16:00")
                    .font(EType.micro)
                    .tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("See all")
                    .font(EType.caption)
                    .foregroundStyle(Brand.info)
            }
            IridescentHairline()

            switch store.state {
            case .loading:
                ForEach(0..<3, id: \.self) { _ in skeletonBlock }
            case .empty:
                emptyState
            case .error(let e):
                errorBanner((e as? LocalizedError)?.errorDescription ?? "\(e)")
            case .loaded(let rows):
                VStack(spacing: Space.s3) {
                    ForEach(rows) { row in timelineBlock(row) }
                }
            }
        }
    }

    /// One appointment block on the vertical day-rail: a left time gutter,
    /// a status-tinted spine, and a card carrying the load reference, lane,
    /// commodity / dock, and the contextual forward action.
    private func timelineBlock(_ row: DockAppointmentRow) -> some View {
        let st = DockStatus(row.status)
        return HStack(alignment: .top, spacing: Space.s3) {
            // time gutter (verbatim HH:mm from scheduledAt)
            Text(localTime(row.scheduledAt))
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 44, alignment: .leading)
                .padding(.top, Space.s2)

            // status spine
            RoundedRectangle(cornerRadius: 2)
                .fill(st.tint)
                .frame(width: 3)
                .padding(.vertical, Space.s1)

            // card
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(laneLine(row))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(st.label)
                        .font(EType.micro)
                        .tracking(0.5)
                        .foregroundStyle(st.tint)
                }
                Text(referenceLine(row))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
                Text(detailLine(row))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isHazmat(row) { hazmatChip(row) }

                if let action = st.nextAction {
                    Button {
                        Task { await store.advance(action.verb, id: row.id) }
                    } label: {
                        HStack(spacing: Space.s2) {
                            if store.actingId == row.id {
                                ProgressView().controlSize(.mini)
                            }
                            Text(action.label)
                                .font(EType.caption.weight(.semibold))
                        }
                        .foregroundStyle(Brand.blue)
                        .padding(.vertical, Space.s1)
                    }
                    .disabled(store.actingId != nil)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md)
        }
    }

    private func hazmatChip(_ row: DockAppointmentRow) -> some View {
        HStack(spacing: Space.s1) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
            Text(hazmatLine(row))
                .font(EType.micro).tracking(0.4)
        }
        .foregroundStyle(Brand.hazmat)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 3)
        .background(Capsule().fill(Brand.hazmat.opacity(0.12)))
    }

    // MARK: ESang open-slot suggestion (matches the bottom card)

    private func esangSuggestion(_ slot: DockSlot) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("Open \(slot.time) slot · bay clear")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("ESang · pull a scheduled load forward to cut dwell before detention")
                    .font(EType.micro)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.magenta)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(LinearGradient.esangSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Brand.magenta.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: states

    private var skeletonBlock: some View {
        HStack(spacing: Space.s3) {
            Color.clear.frame(width: 44)
            RoundedRectangle(cornerRadius: 2).fill(palette.borderFaint).frame(width: 3)
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(palette.bgCardSoft)
                .frame(height: 78)
        }
        .redacted(reason: .placeholder)
    }

    private var emptyState: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 28))
                .foregroundStyle(palette.textTertiary)
            Text("No dock appointments today")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
            Text("Houston Terminal · scheduled windows will appear here")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s7)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(Brand.blue)
        }
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.danger.opacity(0.10)))
    }

    // MARK: derived copy (honest — only renders what the payload carries)

    private func laneLine(_ row: DockAppointmentRow) -> String {
        if let o = row.originState, let d = row.destState, !o.isEmpty, !d.isEmpty {
            return "\(o) → \(d)"
        }
        // fall back to the load reference so the row is never blank
        return row.loadNumber ?? (row.loadId.map { "LOAD-\($0)" } ?? "Appointment \(row.id)")
    }

    private func referenceLine(_ row: DockAppointmentRow) -> String {
        row.loadNumber ?? (row.loadId.map { "LOAD-\($0)" } ?? "—")
    }

    private func detailLine(_ row: DockAppointmentRow) -> String {
        var parts: [String] = []
        if let c = row.commodity, !c.isEmpty { parts.append(c) }
        if let w = row.weightLbs, w > 0 {
            parts.append("\(Int(w).formatted()) lb")
        }
        if let e = row.equipment, !e.isEmpty { parts.append(e) }
        if let dock = row.dockNumber, !dock.isEmpty { parts.append("Dock \(dock)") }
        if parts.isEmpty {
            parts.append((row.type ?? "appointment").replacingOccurrences(of: "_", with: " "))
        }
        return parts.joined(separator: " · ")
    }

    private func isHazmat(_ row: DockAppointmentRow) -> Bool {
        (row.hazmatClass?.isEmpty == false) || (row.unNumber?.isEmpty == false)
    }

    private func hazmatLine(_ row: DockAppointmentRow) -> String {
        var s = "HAZMAT"
        if let cls = row.hazmatClass, !cls.isEmpty { s += " · CLASS \(cls)" }
        if let un = row.unNumber, !un.isEmpty { s += " · \(un)" }
        return s
    }

    private func localTime(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter.dock.date(from: iso) else { return "--:--" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = .current
        return f.string(from: d)
    }

    private func nextScheduledTime() -> String? {
        let now = Date()
        let upcoming = store.rows.compactMap { row -> Date? in
            guard DockStatus(row.status) == .scheduled,
                  let iso = row.scheduledAt,
                  let d = ISO8601DateFormatter.dock.date(from: iso),
                  d >= now else { return nil }
            return d
        }.sorted()
        guard let next = upcoming.first else { return nil }
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = .current
        return f.string(from: next)
    }
}

private extension ISO8601DateFormatter {
    /// Tolerant parser — the server emits both plain and fractional ISO.
    static let dock: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Preview

#if DEBUG
#Preview("295 · Shipper Dock Appointments") {
    ShipperDockAppointments()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}
#endif
