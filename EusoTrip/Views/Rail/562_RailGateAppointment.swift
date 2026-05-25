//
//  562_RailGateAppointment.swift
//  EusoTrip — Rail Engineer · Gate Appointment (reserve slot, carrier-side).
//
//  Target of the 561 Facility Status "Reserve gate appointment" CTA.
//  Faithful port of "05 Rail/Light-SVG/562 Rail Gate Appointment.svg"
//  (Light + Dark). RECONSTRUCTED to flagship DETAIL grammar per
//  FOUNDER CADENCE DIRECTIVE 2026-05-24.
//  Nav anchored to RailEngineerNavController, Shipments tab current.
//
//  Data:
//    appointments.getAvailableSlots (EXISTS appointments.ts:267)
//      → {facilityId, date, slots:[{time, available, capacity, booked}]}
//    appointments.create            (EXISTS appointments.ts:114)
//      → {id, confirmationNumber, status, createdAt}
//    appointments.updateStatus      (EXISTS appointments.ts:194)
//      → issues GP-XXXXXX gatePass + qrCodeData valid 4h
//

import SwiftUI

struct RailGateAppointmentScreen: View {
    let theme: Theme.Palette
    let facilityId: String
    let shipmentId: String
    var body: some View {
        Shell(theme: theme) {
            RailGateAppointmentBody(facilityId: facilityId, shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct AvailableSlot562: Decodable, Identifiable {
    var id: String { time }
    let time: String
    let available: Bool
    let capacity: Int
    let booked: Int
}

private struct SlotResult562: Decodable {
    let facilityId: String?
    let date: String?
    let slots: [AvailableSlot562]
}

private struct CreateResult562: Decodable {
    let id: String
    let confirmationNumber: String?
    let status: String?
    let createdAt: String?
}

// MARK: - Body

private struct RailGateAppointmentBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    let facilityId: String
    let shipmentId: String

    @State private var slots: [AvailableSlot562] = []
    @State private var selectedTime: String? = nil
    @State private var selectedDate: Date = {
        var c = Calendar.current; c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    }()
    @State private var loading = true
    @State private var submitting = false
    @State private var confirmation: CreateResult562? = nil
    @State private var errorText: String? = nil

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/Chicago")
        return f.string(from: selectedDate)
    }
    private var displayDate: String {
        let f = DateFormatter(); f.dateFormat = "EEE · MMM d · yyyy"
        f.timeZone = TimeZone(identifier: "America/Chicago")
        return f.string(from: selectedDate)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let conf = confirmation {
                    confirmedCard(conf)
                } else {
                    heroCard
                    datePicker
                    slotSection
                    if let sel = selectedTime { summaryCard(sel) }
                    if let e = errorText {
                        Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    actions
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, 8)
        }
        .task { await loadSlots() }
        .onChange(of: selectedDate) { _, _ in Task { await loadSlots() } }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                Image(systemName: "calendar.badge.plus").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · GATE APPOINTMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Reserve gate slot").font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("appointments.create · gate-in · capacity 2 per slot")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            IridescentHairline()
        }
    }

    // MARK: Hero Card

    private var heroCard: some View {
        LifecycleCard(accentGradient: true) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Brand.info.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "shippingbox")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Brand.info)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shipment \(shipmentId.isEmpty ? "—" : shipmentId)")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("Facility \(facilityId) · container gate-in")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                    Text("PICKUP")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Brand.info)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.info.opacity(0.12)))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("DATE").font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    Text(dayOfWeek()).font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(shortDate()).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: Date Picker

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SELECT DATE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            DatePicker("", selection: $selectedDate, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Brand.info)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCard)
                )
        }
    }

    // MARK: Slot Grid

    private var slotSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("AVAILABLE SLOTS · cap 2")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(displayDate).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            if loading {
                LifecycleCard {
                    Text("Loading slots…").font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(slots) { slot in slotTile(slot) }
                }
            }
        }
    }

    private func slotTile(_ s: AvailableSlot562) -> some View {
        let isFull     = !s.available
        let isSelected = selectedTime == s.time
        return Button {
            guard s.available else { return }
            selectedTime = s.time
        } label: {
            VStack(alignment: .leading, spacing: 4) {
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
                Text(slotLabel(s))
                    .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isFull ? palette.textTertiary : isSelected ? Brand.info : Brand.success)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isFull ? palette.bgCardSoft.opacity(0.5) : palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isFull)
    }

    private func slotLabel(_ s: AvailableSlot562) -> String {
        guard s.available else { return "full · \(s.booked) of \(s.capacity)" }
        if selectedTime == s.time { return "selected · \(s.capacity - s.booked) of \(s.capacity)" }
        return "open · \(s.booked) of \(s.capacity)"
    }

    // MARK: Summary Card

    private func summaryCard(_ time: String) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("SELECTED SLOT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("$0 fee").font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.success)
                }
                Text("\(time) CT · gate 3")
                    .font(.system(size: 20, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 8)
                Divider().padding(.vertical, 10)
                Text("CONF-XXXXXX issued on confirm")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                Text("GP-XXXXXX · gatePass valid 4h from slot")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: Confirmed Card

    private func confirmedCard(_ conf: CreateResult562) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Gate appointment confirmed")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                }
                Text(conf.confirmationNumber ?? "CONF-\(conf.id)")
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Slot \(selectedTime ?? "—") · \(displayDate)")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                Text("Gate pass issued · valid 4 h from slot time")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: Space.s2) {
            CTAButton(
                title: submitting ? "Reserving…" : (selectedTime.map { "Reserve \($0) slot" } ?? "Select a slot"),
                action: { Task { await reserve() } },
                leadingIcon: "checkmark",
                isLoading: submitting || selectedTime == nil
            )
            CTAButton(title: "Cancel")
        }
    }

    // MARK: Load + Mutate

    private func loadSlots() async {
        loading = true
        struct SlotsIn: Encodable { let facilityId: String; let date: String; let type: String }
        do {
            let result: SlotResult562 = try await EusoTripAPI.shared.query(
                "appointments.getAvailableSlots",
                input: SlotsIn(facilityId: facilityId, date: dateString, type: "pickup"))
            self.slots = result.slots
            if let prev = selectedTime, !result.slots.contains(where: { $0.time == prev && $0.available }) {
                selectedTime = nil
            }
        } catch {
            self.slots = []
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
            let result: CreateResult562 = try await EusoTripAPI.shared.mutation(
                "appointments.create",
                input: CreateIn(
                    type: "pickup",
                    loadId: shipmentId,
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

    // MARK: Helpers

    private func dayOfWeek() -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        f.timeZone = TimeZone(identifier: "America/Chicago")
        return f.string(from: selectedDate)
    }
    private func shortDate() -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d · yyyy"
        f.timeZone = TimeZone(identifier: "America/Chicago")
        return f.string(from: selectedDate)
    }
}

#Preview("562 · Gate Appointment · Night") {
    RailGateAppointmentScreen(theme: Theme.dark, facilityId: "1", shipmentId: "RAIL-1001")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("562 · Gate Appointment · Light") {
    RailGateAppointmentScreen(theme: Theme.light, facilityId: "1", shipmentId: "RAIL-1001")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
