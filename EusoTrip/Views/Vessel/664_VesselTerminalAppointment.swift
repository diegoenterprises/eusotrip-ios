//
//  664_VesselTerminalAppointment.swift
//  EusoTrip — Vessel Operator · Terminal Appointment
//
//  Verbatim port of "06 Vessel/Dark-SVG/664 Vessel Terminal Appointment.svg".
//  Cross-mode sibling of Rail 562 Gate Appointment at tri-mode parity —
//  docked under SHIPMENTS in the VesselOperatorNavController.
//
//  PURPOSE: lets the operator grab a marine-terminal gate slot for an
//  import box's dray gate-out in two taps, turning a discharged container
//  into a gate pass without a terminal phone queue. Vessel import dray
//  gate-out maps to the "pickup" appointment type (a trucker collects the
//  discharged container).
//
//  Data (frontend/server/routers/appointments.ts):
//    appointments.getAvailableSlots (EXISTS :267 · query)
//      input  {facilityId, date, type}
//      output {facilityId, date, slots:[{time, available, capacity, booked}]}
//             capacity 2 · hours 06/08/10/12/14/16
//    appointments.create            (EXISTS :114 · mutation)
//      input  {type, loadId, facilityId, catalystId, scheduledDate, scheduledTime}
//      output {id, confirmationNumber, status, createdAt}
//    appointments.updateStatus      (EXISTS :194 · mutation)
//      issues GP-XXXXXX gatePass + qrCodeData, validUntil +4h.
//

import SwiftUI

struct VesselTerminalAppointmentScreen: View {
    let theme: Theme.Palette
    /// LBCT Pier T marine terminal facility id (USLGB). Defaults to the
    /// canonical booking VES-260523-9F2C41A0E7 context.
    var facilityId: String = "1"
    /// Discharged import container's load id (gate-out target).
    var loadId: String = "VES-260523-9F2C41A0E7"

    var body: some View {
        Shell(theme: theme) {
            VesselTerminalAppointmentBody(facilityId: facilityId, loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror appointments.ts projections)

private struct VesselAvailableSlot664: Decodable, Identifiable {
    var id: String { time }
    let time: String
    let available: Bool
    let capacity: Int
    let booked: Int
}

private struct VesselSlotResult664: Decodable {
    let facilityId: String?
    let date: String?
    let slots: [VesselAvailableSlot664]
}

private struct VesselCreateResult664: Decodable {
    let id: String
    let confirmationNumber: String?
    let status: String?
    let createdAt: String?
}

// MARK: - Body

private struct VesselTerminalAppointmentBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    let facilityId: String
    let loadId: String

    @State private var slots: [VesselAvailableSlot664] = []
    @State private var selectedTime: String? = "10:00"   // SVG default selection
    @State private var selectedDate: Date = {
        // SVG canonical date: Wed · May 27 · 2026 (LBCT is Pacific Time).
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 27
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal.date(from: c) ?? Date()
    }()
    @State private var loading = true
    @State private var submitting = false
    @State private var confirmation: VesselCreateResult664? = nil
    @State private var errorText: String? = nil

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    // Slot scheduling runs in the terminal's local time (Pacific · LBCT).
    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return f.string(from: selectedDate)
    }
    private var displayDate: String {
        // "Wed · May 27 · 2026"
        let f = DateFormatter(); f.dateFormat = "EEE · MMM d · yyyy"
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return f.string(from: selectedDate)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let conf = confirmation {
                    confirmedCard(conf)
                } else {
                    moveContextCard
                    datePicker
                    slotSection
                    selectionPreview
                    if let e = errorText {
                        Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    reserveCTA
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, 8)
        }
        .task { await loadSlots() }
        .onChange(of: selectedDate) { _, _ in Task { await loadSlots() } }
    }

    // MARK: - Header (back + eyebrow + title + subtitle)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Image(systemName: "ferry.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("✦ VESSEL OPERATOR · TERMINAL APPOINTMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Text("Reserve a slot")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("getAvailableSlots · Maersk · USLGB · LBCT Pier T")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            IridescentHairline()
        }
    }

    // MARK: - Move context card (gradient-rimmed)

    private var moveContextCard: some View {
        HStack(alignment: .center, spacing: 12) {
            // Container glyph — 40' HC dry box silhouette.
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Brand.blue, lineWidth: 1.6)
                    .frame(width: 34, height: 22)
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { _ in
                        Rectangle().fill(Brand.blue.opacity(0.6)).frame(width: 1.1, height: 22)
                    }
                }
                .frame(width: 34, height: 22)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("MSKU 709 234-5 · 40' HC dry")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("VES-260523-9F2C41A0E7 · import gate-out")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            Text("PICKUP")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Brand.blue)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(Brand.blue.opacity(0.12)))
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    // MARK: - Date selector

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("APPOINTMENT DATE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(displayDate)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            // Live, terminal-local date control — slots reload on change.
            DatePicker("", selection: $selectedDate, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(Brand.blue)
        }
    }

    // MARK: - Slots

    private var slotSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("AVAILABLE SLOTS · getAvailableSlots · cap 2/slot")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if loading {
                LifecycleCard {
                    Text("Loading slots…").font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else if slots.isEmpty {
                EusoEmptyState(systemImage: "calendar.badge.exclamationmark",
                               title: "No slots for this date",
                               subtitle: "LBCT Pier T returned no gate windows for \(displayDate). Try another date.")
            } else {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(slots) { slot in slotTile(slot) }
                }
            }
        }
    }

    private func slotTile(_ s: VesselAvailableSlot664) -> some View {
        let isFull     = !s.available
        let isSelected = selectedTime == s.time
        return Button {
            guard s.available else { return }
            selectedTime = s.time
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if isSelected {
                            Text(s.time).foregroundStyle(LinearGradient.diagonal)
                        } else if isFull {
                            Text(s.time).foregroundStyle(palette.textTertiary)
                        } else {
                            Text(s.time).foregroundStyle(palette.textPrimary)
                        }
                    }
                    .font(.system(size: 16, weight: .bold)).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.success)
                    }
                }
                Text(slotLabel(s))
                    .font(.system(size: 10))
                    .foregroundStyle(isFull ? Brand.danger : palette.textSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(isFull ? palette.bgCardSoft.opacity(0.5) : palette.bgCardSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isFull)
    }

    private func slotLabel(_ s: VesselAvailableSlot664) -> String {
        // SVG: "full · 2 of 2" / "open · 1 of 2" / "open · 0 of 2".
        if !s.available { return "full · \(s.booked) of \(s.capacity)" }
        return "open · \(s.booked) of \(s.capacity)"
    }

    // MARK: - Selection / gate-pass preview

    @ViewBuilder
    private var selectionPreview: some View {
        if let sel = selectedTime {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("\(sel) PT selected · gate 7")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("$0 fee")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Brand.success)
                }
                Text("create → CONF-______ · gate pass on confirm")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 6)
                Text("GP-XXXXXX issued · valid 4h from slot")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 4)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
        }
    }

    // MARK: - Confirmed card

    private func confirmedCard(_ conf: VesselCreateResult664) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Terminal appointment confirmed")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                }
                Text(conf.confirmationNumber ?? "CONF-\(conf.id)")
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Slot \(selectedTime ?? "—") PT · \(displayDate) · LBCT Pier T gate 7")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                Text("GP-XXXXXX gate pass issued on confirm · valid 4 h from slot")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                Text("MSKU 709 234-5 · import dray gate-out enabled")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: - Reserve CTA

    private var reserveCTA: some View {
        CTAButton(
            title: submitting
                ? "Reserving…"
                : (selectedTime.map { "Reserve \($0) slot" } ?? "Select a slot"),
            action: { Task { await reserve() } },
            isLoading: submitting || selectedTime == nil
        )
    }

    // MARK: - Load + mutate

    private func loadSlots() async {
        loading = true
        struct SlotsIn: Encodable { let facilityId: String; let date: String; let type: String }
        do {
            // Vessel import dray gate-out → "pickup" (trucker collects the box).
            let result: VesselSlotResult664 = try await EusoTripAPI.shared.query(
                "appointments.getAvailableSlots",
                input: SlotsIn(facilityId: facilityId, date: dateString, type: "pickup"))
            self.slots = result.slots
            // Drop the selection if the previously-chosen slot is now full
            // on the freshly-loaded date.
            if let prev = selectedTime,
               !result.slots.contains(where: { $0.time == prev && $0.available }) {
                selectedTime = result.slots.first(where: { $0.available })?.time
            }
        } catch {
            self.slots = []
            errorText = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func reserve() async {
        guard let time = selectedTime else { return }
        submitting = true; errorText = nil
        struct CreateIn: Encodable {
            let type: String
            let loadId: String
            let facilityId: String
            let catalystId: String
            let scheduledDate: String
            let scheduledTime: String
        }
        do {
            let result: VesselCreateResult664 = try await EusoTripAPI.shared.mutation(
                "appointments.create",
                input: CreateIn(
                    type: "pickup",
                    loadId: loadId,
                    facilityId: facilityId,
                    catalystId: "0",
                    scheduledDate: dateString,
                    scheduledTime: time
                )
            )
            confirmation = result
        } catch {
            errorText = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
    }
}

#Preview("664 · Vessel Terminal Appointment · Night") {
    VesselTerminalAppointmentScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("664 · Vessel Terminal Appointment · Light") {
    VesselTerminalAppointmentScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
