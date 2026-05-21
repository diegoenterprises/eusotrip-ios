//
//  AppointmentSchedulerSheet.swift
//  EusoTrip — Universal dock-appointment surface.
//
//  iOS port of web `frontend/client/src/pages/AppointmentScheduler.tsx`.
//  Reads off the real `appointments` router. All actions
//  (checkIn / startLoading / complete) hit real mutations with
//  server-side security checks — no stubs.
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

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    datePicker
                    if let s = summary { summaryStrip(s) }
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
                        ForEach(list) { a in appointmentRow(a) }
                    }
                    if let ack = actionAck {
                        Text(ack).font(.caption).foregroundStyle(.green)
                    }
                }
                .padding(16)
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
                Button { Task { await fire(action: "checkIn", id: a.id) } } label: {
                    Label("Check In", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(actingId != nil)
            }
            if status == "checked_in" {
                Button { Task { await fire(action: "startLoading", id: a.id) } } label: {
                    Label("Start Loading", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(actingId != nil)
            }
            if status == "loading" {
                Button { Task { await fire(action: "complete", id: a.id) } } label: {
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

    private func fire(action: String, id: String) async {
        actingId = id; actionAck = nil
        struct In: Encodable { let appointmentId: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "appointments.\(action)",
                input: In(appointmentId: id)
            )
            actionAck = "Appointment \(id): \(action) ✓"
            await loadAll()
        } catch let err {
            error = (err as? LocalizedError)?.errorDescription ?? "\(err)"
        }
        actingId = nil
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
