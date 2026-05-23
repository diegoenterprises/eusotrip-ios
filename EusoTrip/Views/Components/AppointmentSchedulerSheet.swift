//
//  AppointmentSchedulerSheet.swift
//  EusoTrip — Universal dock-appointment surface.
//
//  iOS port of web `frontend/client/src/pages/AppointmentScheduler.tsx`.
//  Reads off the real `appointments` router. All actions
//  (checkIn / startLoading / complete) hit real mutations with
//  server-side security checks — no stubs.
//
//  Reshaped 2026-05-23 from a flat list (with per-row sequential
//  action buttons) into a 5-column lifecycle Kanban with THREE
//  sequential drag transitions:
//
//    SCHEDULED  → CHECKED IN  via appointments.checkIn
//    CHECKED IN → LOADING     via appointments.startLoading
//    LOADING    → COMPLETED   via appointments.complete
//    CANCELLED  (terminal — no drag transitions)
//
//  Drag-to-advance only flows forward one stage at a time
//  (matching the existing per-row button logic which only renders
//  the SINGLE current-stage action). The server rejects out-of-
//  order transitions, so the client-side guard mirrors that.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire models

struct AppointmentSummary: Decodable, Hashable {
    let today: Int?
    let todayTotal: Int?
    let completed: Int?
    let inProgress: Int?
    let upcoming: Int?
    let cancelled: Int?
}

struct AppointmentRow: Decodable, Hashable, Identifiable {
    let id: String
    let type: String?
    let terminalId: String?
    let loadId: String?
    let driverId: String?
    let scheduledAt: String?
    let dockNumber: String?
    let status: String?
}

struct AppointmentList: Decodable, Hashable {
    let appointments: [AppointmentRow]
    let total: Int
}

// MARK: - Kanban columns

private struct AppointmentKanbanColumn: Identifiable, Hashable {
    let id: String          // canonical bucket key
    let label: String
    let icon: String
    let statuses: [String]  // server statuses that bucket here
    let nextStatus: String? // nil for terminal lanes
    let action: String?     // mutation name suffix for drop-to-advance
    let color: ColorTint

    enum ColorTint { case scheduled, checkedIn, loading, completed, cancelled }
}

private let appointmentKanbanColumns: [AppointmentKanbanColumn] = [
    .init(id: "scheduled",  label: "SCHEDULED",  icon: "calendar",                statuses: ["scheduled", "arrived"], nextStatus: "checked_in", action: "checkIn",      color: .scheduled),
    .init(id: "checked_in", label: "CHECKED IN", icon: "person.crop.circle.badge.checkmark", statuses: ["checked_in"], nextStatus: "loading",    action: "startLoading", color: .checkedIn),
    .init(id: "loading",    label: "LOADING",    icon: "shippingbox.fill",        statuses: ["loading"],              nextStatus: "completed",  action: "complete",     color: .loading),
    .init(id: "completed",  label: "COMPLETED",  icon: "checkmark.seal.fill",     statuses: ["completed"],            nextStatus: nil,          action: nil,            color: .completed),
    .init(id: "cancelled",  label: "CANCELLED",  icon: "xmark.octagon.fill",      statuses: ["cancelled"],            nextStatus: nil,          action: nil,            color: .cancelled),
]

// MARK: - Sheet

public struct AppointmentSchedulerSheet: View {
    /// Optional facility / terminal scope. Pass to filter the list.
    public let facilityId: String?
    public init(facilityId: String? = nil) { self.facilityId = facilityId }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date = Date()
    @State private var summary: AppointmentSummary?
    @State private var list: [AppointmentRow] = []
    @State private var loading: Bool = true
    @State private var error: String?
    @State private var actingId: String?
    @State private var actionAck: String?
    @State private var actionError: String?
    @State private var lastAdvance: String?
    @State private var selected: String = "scheduled"
    @State private var dragHoverColumn: String? = nil

    private func columnId(for status: String?) -> String {
        let s = (status ?? "scheduled").lowercased()
        return appointmentKanbanColumns.first(where: { $0.statuses.contains(s) })?.id ?? "scheduled"
    }

    private var byColumn: [String: [AppointmentRow]] {
        Dictionary(grouping: list) { columnId(for: $0.status) }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        datePicker
                        if let s = summary { summaryStrip(s) }
                        if let m = lastAdvance {
                            Text(m).font(.caption).foregroundStyle(.green)
                                .padding(.horizontal, 6)
                        }
                        if let e = actionError {
                            Text(e).font(.caption).foregroundStyle(.red)
                                .padding(.horizontal, 6)
                        }
                        if loading {
                            HStack { ProgressView().controlSize(.small); Text("Loading appointments…").font(.callout).foregroundStyle(.secondary) }
                        } else if let err = error {
                            Text(err).font(.callout).foregroundStyle(.red)
                        } else if list.isEmpty {
                            Text("No appointments on \(humanDate(selectedDate)).")
                                .font(.callout).foregroundStyle(.secondary)
                                .padding(20)
                                .frame(maxWidth: .infinity)
                        } else {
                            scrubber
                            columnPager
                                .frame(minHeight: 440)
                        }
                        if let ack = actionAck {
                            Text(ack).font(.caption).foregroundStyle(.green)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Appointments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadAll() }
            .onChange(of: selectedDate) { _, _ in Task { await loadAll() } }
            .refreshable { await loadAll() }
        }
    }

    // MARK: subviews

    private var datePicker: some View {
        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
            .datePickerStyle(.compact)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func summaryStrip(_ s: AppointmentSummary) -> some View {
        HStack(spacing: 8) {
            stat(label: "TODAY",     value: "\(s.todayTotal ?? s.today ?? 0)", color: .primary)
            stat(label: "COMPLETE",  value: "\(s.completed ?? 0)",             color: .green)
            stat(label: "PROGRESS",  value: "\(s.inProgress ?? 0)",            color: .orange)
            stat(label: "UPCOMING",  value: "\(s.upcoming ?? 0)",              color: .blue)
            stat(label: "CANCELLED", value: "\(s.cancelled ?? 0)",             color: .red)
        }
    }

    private func stat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
            Text(value).font(.body.weight(.heavy).monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private var scrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(appointmentKanbanColumns) { col in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { selected = col.id }
                    } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: col.icon).font(.system(size: 9, weight: .heavy))
                                Text(col.label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            }
                            Text("\(byColumn[col.id]?.count ?? 0)")
                                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        }
                        .foregroundStyle(selected == col.id ? Color.white : Color.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selected == col.id ? AnyShapeStyle(tintFor(col)) : AnyShapeStyle(Color(.secondarySystemBackground)))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var columnPager: some View {
        TabView(selection: $selected) {
            ForEach(appointmentKanbanColumns) { col in
                column(col).tag(col.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func column(_ col: AppointmentKanbanColumn) -> some View {
        let cards = byColumn[col.id] ?? []
        let isHover = dragHoverColumn == col.id && col.action != nil
        let acceptsDrops = col.action != nil  // only forward-advance lanes accept
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(col.label)
                        .font(.system(size: 13, weight: .heavy)).tracking(0.8)
                    Text("\(cards.count)")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(tintFor(col)).clipShape(Capsule())
                    Spacer(minLength: 0)
                    if let next = col.nextStatus {
                        Text("→ \(next.replacingOccurrences(of: "_", with: " ").uppercased())")
                            .font(.system(size: 9, weight: .heavy)).foregroundStyle(.tertiary)
                    } else {
                        Text("TERMINAL")
                            .font(.system(size: 9, weight: .heavy)).foregroundStyle(.tertiary)
                    }
                }
                if cards.isEmpty {
                    Text(emptySubtitle(col))
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 18)
                } else {
                    ForEach(cards) { a in
                        let canDrag = (col.action != nil)
                        if canDrag {
                            appointmentRow(a)
                                .draggable(a.id) {
                                    appointmentRow(a)
                                        .frame(maxWidth: 320)
                                        .opacity(0.92)
                                        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                                }
                        } else {
                            appointmentRow(a)
                        }
                    }
                }
                Color.clear.frame(height: 24)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isHover ? AnyShapeStyle(tintFor(col)) : AnyShapeStyle(Color.clear),
                    lineWidth: isHover ? 2 : 0
                )
                .padding(.horizontal, 4)
                .animation(.easeOut(duration: 0.12), value: isHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard acceptsDrops else { return false }
            guard let aid = droppedIds.first else { return false }
            guard let row = list.first(where: { $0.id == aid }) else { return false }
            // The destination column owns the advance action. Drag from
            // the immediately-prior lane only — out-of-order drops are
            // no-ops because the server rejects them anyway.
            let srcColId = columnId(for: row.status)
            let validSource: String? = {
                switch col.id {
                case "checked_in": return "scheduled"
                case "loading":    return "checked_in"
                case "completed":  return "loading"
                default:           return nil
                }
            }()
            guard srcColId == validSource else { return false }
            guard let action = col.action else { return false }
            Task { await fire(action: action, id: aid, columnLabel: col.label) }
            return true
        } isTargeted: { hovering in
            guard acceptsDrops else { return }
            dragHoverColumn = hovering ? col.id : (dragHoverColumn == col.id ? nil : dragHoverColumn)
        }
    }

    private func appointmentRow(_ a: AppointmentRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: typeIcon(a.type))
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.type?.capitalized ?? "Appointment").font(.callout.weight(.semibold))
                    Text("Dock \(a.dockNumber ?? "—") · \(timeOf(a.scheduledAt))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge(a.status ?? "scheduled")
            }
            actionButtons(a)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func actionButtons(_ a: AppointmentRow) -> some View {
        HStack(spacing: 8) {
            let status = (a.status ?? "").lowercased()
            if status == "scheduled" || status == "arrived" {
                Button { Task { await fire(action: "checkIn", id: a.id, columnLabel: "CHECKED IN") } } label: {
                    Label("Check In", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(actingId != nil)
            }
            if status == "checked_in" {
                Button { Task { await fire(action: "startLoading", id: a.id, columnLabel: "LOADING") } } label: {
                    Label("Start Loading", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(actingId != nil)
            }
            if status == "loading" {
                Button { Task { await fire(action: "complete", id: a.id, columnLabel: "COMPLETED") } } label: {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(actingId != nil)
            }
            if actingId == a.id {
                ProgressView().controlSize(.mini)
            }
        }
    }

    private func statusBadge(_ raw: String) -> some View {
        let color: Color = {
            switch raw.lowercased() {
            case "scheduled":   return .blue
            case "checked_in":  return .cyan
            case "loading":     return .orange
            case "completed":   return .green
            case "cancelled":   return .red
            default:            return .secondary
            }
        }()
        return Text(raw.uppercased())
            .font(.caption2.weight(.bold)).tracking(0.6)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private func tintFor(_ col: AppointmentKanbanColumn) -> Color {
        switch col.color {
        case .scheduled: return .blue
        case .checkedIn: return .cyan
        case .loading:   return .orange
        case .completed: return .green
        case .cancelled: return .red
        }
    }

    private func emptySubtitle(_ col: AppointmentKanbanColumn) -> String {
        switch col.id {
        case "scheduled":  return "No appointments scheduled for this date."
        case "checked_in": return "Nothing checked in yet. Drag a SCHEDULED card here."
        case "loading":    return "Nothing loading. Drag a CHECKED IN card here to start."
        case "completed":  return "No completed appointments yet."
        case "cancelled":  return "No cancellations."
        default:           return "Empty."
        }
    }

    // MARK: helpers

    private func typeIcon(_ raw: String?) -> String {
        switch (raw ?? "").lowercased() {
        case "pickup":   return "arrow.up.right.circle.fill"
        case "delivery": return "arrow.down.left.circle.fill"
        case "loading":  return "shippingbox.fill"
        case "unloading": return "shippingbox.and.arrow.backward.fill"
        default:          return "calendar"
        }
    }

    private func humanDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: d)
    }

    private func timeOf(_ iso: String?) -> String {
        guard let iso else { return "—" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter(); out.dateStyle = .none; out.timeStyle = .short
        return out.string(from: d)
    }

    private func isoDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    // MARK: pipeline

    private func loadAll() async {
        loading = true; error = nil
        async let s: Void = loadSummary()
        async let l: Void = loadList()
        _ = await (s, l)
        loading = false
    }

    private func loadSummary() async {
        struct In: Encodable { let date: String }
        do {
            let s: AppointmentSummary = try await EusoTripAPI.shared.query(
                "appointments.getSummary", input: In(date: isoDate(selectedDate))
            )
            summary = s
        } catch { /* optional */ }
    }

    private func loadList() async {
        struct In: Encodable {
            let date: String
            let facilityId: String?
            let limit: Int
            let offset: Int
        }
        do {
            let r: AppointmentList = try await EusoTripAPI.shared.query(
                "appointments.list",
                input: In(date: isoDate(selectedDate),
                          facilityId: facilityId, limit: 50, offset: 0)
            )
            list = r.appointments
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func fire(action: String, id: String, columnLabel: String) async {
        await MainActor.run { actingId = id; actionAck = nil; actionError = nil }
        struct In: Encodable { let appointmentId: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "appointments.\(action)",
                input: In(appointmentId: id)
            )
            await MainActor.run {
                actionAck = "Appointment \(id): \(action) ✓"
                lastAdvance = "Appointment → \(columnLabel)"
            }
            await loadAll()
            await MainActor.run {
                let nextCol = appointmentKanbanColumns.first(where: { $0.label == columnLabel })?.id
                if let nc = nextCol {
                    withAnimation(.easeOut(duration: 0.18)) { selected = nc }
                }
            }
        } catch let err {
            await MainActor.run {
                error = (err as? LocalizedError)?.errorDescription ?? "\(err)"
            }
        }
        await MainActor.run { actingId = nil }
    }
}

#Preview("Appointments · Dark") {
    AppointmentSchedulerSheet()
        .preferredColorScheme(.dark)
}

#Preview("Appointments · Light") {
    AppointmentSchedulerSheet()
        .preferredColorScheme(.light)
}
