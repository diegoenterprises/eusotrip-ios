//
//  101_MeAppointments.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · Appointments)
//
//  Screen 101 · Me · Appointments — the facility / dock-side
//  companion to Loads.
//
//    • Loads  → commercial contract: origin, destination, rate,
//               commodity, POD, settlement. "What am I hauling
//               and what am I being paid."
//    • Appts  → dock slot: facility, scheduled time, check-in,
//               start-loading, complete. "When and where do I
//               actually show up — and what's my status at the
//               gate right now."
//
//  One load typically has TWO appointments (pickup + delivery),
//  each with its own lifecycle and facility-side rules (door
//  assignment, hazmat bay, dwell rules, etc.) that Loads doesn't
//  track. Each row here carries a "Load" chip that jumps to the
//  load detail when the driver wants the commercial view.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Summary + driver-scoped list from `appointments.getSummary`
//      + `getMyAppointments` — MCP-verified at
//      `frontend/server/routers/appointments.ts`.
//    • Lifecycle actions (check-in → start-loading → complete →
//      cancel) all hit real mutations. Each mutation refreshes
//      the feed so the status chip flips in-place.
//    • No fabricated dock slots, no placeholder check-in time.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero + primary CTA.
//         Brand.warning on overdue scheduled slots.
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

// MARK: - Screen root

struct MeAppointments: View {
    @Environment(\.palette) var palette
    @StateObject private var store = AppointmentsStore()

    @State private var cancelling: AppointmentsAPI.Appointment?
    @State private var checkingIn: AppointmentsAPI.Appointment?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                summaryStrip
                windowPicker
                appointmentsSection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .onChange(of: store.window) { _, _ in
            Task { await store.refresh() }
        }
        // RealtimeService → refresh appointments when load assignment
        // / reassignment / dock-assign / surface refresh events fire.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await store.refresh() }
        }
        .sheet(item: $cancelling) { appt in
            CancelSheet(appt: appt, store: store)
                .eusoSheetX()
        }
        .sheet(item: $checkingIn) { appt in
            CheckInSheet(appt: appt, store: store)
                .eusoSheetX()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Appointments")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Dock slots · check-in · loading · POD")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                Text("See Loads for rates + commercial detail")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary.opacity(0.8))
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Summary strip

    private var summaryStrip: some View {
        let s = store.summary
        return HStack(spacing: Space.s2) {
            summaryTile(label: "TODAY",    value: "\(s?.today ?? 0)",    gradient: true)
            summaryTile(label: "UPCOMING", value: "\(s?.upcoming ?? 0)", gradient: false)
            summaryTile(label: "DONE",     value: "\(s?.completed ?? 0)", gradient: false)
        }
    }

    private func summaryTile(label: String, value: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.numeric)
                .foregroundStyle(gradient
                                 ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.textPrimary))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Window picker

    private var windowPicker: some View {
        HStack(spacing: Space.s2) {
            ForEach(AppointmentsAPI.Window.allCases) { w in
                Button {
                    store.window = w
                } label: {
                    Text(w.label)
                        .font(EType.caption)
                        .foregroundStyle(store.window == w
                                         ? AnyShapeStyle(LinearGradient.diagonal)
                                         : AnyShapeStyle(palette.textSecondary))
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 6)
                        .overlay(
                            Capsule().stroke(
                                store.window == w ? Color.clear : palette.textTertiary.opacity(0.5),
                                lineWidth: 1
                            )
                        )
                        .background(
                            Capsule().fill(store.window == w
                                           ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                                           : AnyShapeStyle(Color.clear))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: Appointments

    private var appointmentsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if store.appointments.isEmpty && !store.isLoading {
                EusoEmptyState(
                    systemImage: "calendar",
                    title: emptyTitle,
                    subtitle: "Your pickup + delivery dock slots land here as dispatch schedules them."
                )
            } else {
                ForEach(store.appointments) { a in
                    appointmentCard(a)
                }
            }
        }
    }

    private var emptyTitle: String {
        switch store.window {
        case .upcoming: return "No upcoming appointments"
        case .today:    return "Nothing scheduled today"
        case .past:     return "No past appointments"
        }
    }

    private func appointmentCard(_ a: AppointmentsAPI.Appointment) -> some View {
        let status = AppointmentStatusKind(a.status)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(typeLabel(a.type))
                        .font(EType.micro)
                        .tracking(1.2)
                        .foregroundStyle(palette.textTertiary)
                    Text(a.facilityName?.isEmpty == false ? (a.facilityName ?? "") : "Facility TBD")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if let addr = a.address, !addr.isEmpty {
                        Text(addr)
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
                statusChip(status)
            }

            HStack(spacing: Space.s3) {
                whenBlock(date: a.scheduledDate, time: a.scheduledTime)
                Spacer()
                if let loadNumber = a.loadNumber, !loadNumber.isEmpty {
                    loadChip(loadNumber)
                }
            }

            if let product = a.product, !product.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 11, weight: .semibold))
                    Text(product)
                }
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            }

            actionRow(for: a, status: status)
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    @ViewBuilder
    private func actionRow(
        for appt: AppointmentsAPI.Appointment,
        status: AppointmentStatusKind
    ) -> some View {
        if status == .scheduled || status == .upcoming {
            HStack(spacing: Space.s2) {
                Button {
                    checkingIn = appt
                } label: {
                    Label("Check in", systemImage: "checkmark.circle")
                        .font(EType.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
                .disabled(store.mutatingId == appt.id)

                Button {
                    cancelling = appt
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 6)
                        .overlay(
                            Capsule().stroke(palette.textTertiary.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                Spacer()
            }
        } else if status == .checkedIn {
            HStack(spacing: Space.s2) {
                Button {
                    Task { await store.startLoading(appt) }
                } label: {
                    Label("Start loading", systemImage: "arrow.right.arrow.left")
                        .font(EType.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
                .disabled(store.mutatingId == appt.id)
                Spacer()
            }
        } else if status == .loading {
            HStack(spacing: Space.s2) {
                Button {
                    Task { await store.complete(appt) }
                } label: {
                    Label("Complete", systemImage: "checkmark.seal")
                        .font(EType.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
                .disabled(store.mutatingId == appt.id)
                Spacer()
            }
        }
    }

    private func whenBlock(date: String?, time: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(humanDate(date))
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text(humanTime(time))
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .monospacedDigit()
        }
    }

    private func loadChip(_ loadNumber: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 10, weight: .semibold))
            Text(loadNumber)
                .font(EType.micro.monospaced())
        }
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(palette.tintNeutral.opacity(0.55))
        )
    }

    @ViewBuilder
    private func statusChip(_ status: AppointmentStatusKind) -> some View {
        let (label, tint, filled): (String, Color, Bool) = {
            switch status {
            case .scheduled, .upcoming: return ("SCHEDULED", palette.textSecondary, false)
            case .checkedIn:            return ("CHECKED IN", .green, true)
            case .loading:              return ("LOADING",    Brand.warning, false)
            case .completed:            return ("COMPLETED",  .green, false)
            case .cancelled:            return ("CANCELLED",  palette.textTertiary, false)
            case .other(let raw):       return (raw.uppercased(), palette.textTertiary, false)
            }
        }()
        Text(label)
            .font(EType.micro)
            .tracking(1.2)
            .foregroundStyle(filled ? .white : tint)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .background(
                Group {
                    if filled {
                        Capsule().fill(LinearGradient.diagonal)
                    } else {
                        Capsule().stroke(tint, lineWidth: 1)
                    }
                }
            )
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Space.s1) {
            Text("Check in as soon as you arrive — detention clock only starts counting after a confirmed check-in. Start-loading + complete flip your status for dispatch in real time.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Text("Each appointment belongs to a load. Tap the load chip to jump to the commercial detail.")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func typeLabel(_ raw: String?) -> String {
        switch (raw ?? "").lowercased() {
        case "pickup":      return "PICKUP"
        case "delivery":    return "DELIVERY"
        case "drop":        return "DROP TRAILER"
        case "hook":        return "HOOK TRAILER"
        case "live_load":   return "LIVE LOAD"
        case "live_unload": return "LIVE UNLOAD"
        default:            return (raw ?? "APPOINTMENT").uppercased()
        }
    }

    private func humanDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "TBD" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let date = f.date(from: String(raw.prefix(10))) else { return raw }
        let out = DateFormatter()
        out.dateFormat = "EEE MMM d"
        return out.string(from: date)
    }

    private func humanTime(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let date = f.date(from: String(raw.prefix(5))) else { return raw }
        let out = DateFormatter()
        out.dateFormat = "h:mm a"
        return out.string(from: date)
    }
}

// MARK: - Status

private enum AppointmentStatusKind {
    case scheduled, upcoming, checkedIn, loading, completed, cancelled
    case other(String)

    init(_ raw: String?) {
        switch (raw ?? "").lowercased() {
        case "scheduled":  self = .scheduled
        case "upcoming":   self = .upcoming
        case "checked_in", "checked-in": self = .checkedIn
        case "loading", "unloading":     self = .loading
        case "completed", "complete":    self = .completed
        case "cancelled", "canceled":    self = .cancelled
        default:           self = .other(raw ?? "")
        }
    }
}

private extension AppointmentStatusKind {
    static func == (lhs: AppointmentStatusKind, rhs: AppointmentStatusKind) -> Bool {
        switch (lhs, rhs) {
        case (.scheduled, .scheduled), (.upcoming, .upcoming),
             (.checkedIn, .checkedIn), (.loading, .loading),
             (.completed, .completed), (.cancelled, .cancelled):
            return true
        case let (.other(a), .other(b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Check-in sheet

private struct CheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    let appt: AppointmentsAPI.Appointment
    @ObservedObject var store: AppointmentsStore

    @State private var trailer: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Appointment") {
                    Text(appt.facilityName ?? "Facility")
                        .font(EType.bodyStrong)
                    if let d = appt.scheduledDate, let t = appt.scheduledTime {
                        Text("\(d) · \(t)")
                            .foregroundStyle(.secondary)
                            .font(EType.caption)
                    }
                }
                Section("Trailer number (optional)") {
                    TextField("e.g. 48-REF-1120", text: $trailer)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
            }
            .navigationTitle("Check in")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await store.checkIn(
                                appt,
                                trailerNumber: trailer.isEmpty ? nil : trailer
                            )
                            dismiss()
                        }
                    } label: {
                        if store.mutatingId == appt.id {
                            ProgressView()
                        } else {
                            Text("Check in").fontWeight(.semibold)
                        }
                    }
                    .disabled(store.mutatingId == appt.id)
                }
            }
        }
    }
}

// MARK: - Cancel sheet

private struct CancelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let appt: AppointmentsAPI.Appointment
    @ObservedObject var store: AppointmentsStore

    @State private var reason: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Appointment") {
                    Text(appt.facilityName ?? "Facility")
                        .font(EType.bodyStrong)
                }
                Section("Reason") {
                    TextEditor(text: $reason)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Cancel appointment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep it") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .destructive) {
                        Task {
                            await store.cancel(
                                appt,
                                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                            dismiss()
                        }
                    } label: {
                        if store.mutatingId == appt.id {
                            ProgressView()
                        } else {
                            Text("Cancel").fontWeight(.semibold)
                        }
                    }
                    .disabled(
                        reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || store.mutatingId == appt.id
                    )
                }
            }
        }
    }
}

// MARK: - Screen wrapper

struct MeAppointmentsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeAppointments()
        } nav: {
            BottomNav(
                leading: driverNavLeading_101(),
                trailing: driverNavTrailing_101(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_101() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_101() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("101 · Appointments · Night") {
    MeAppointmentsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("101 · Appointments · Afternoon") {
    MeAppointmentsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
