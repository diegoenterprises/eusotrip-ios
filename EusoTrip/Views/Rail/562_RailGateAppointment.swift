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
//  §W OFFLINE POLICY (Encyclopedia v2 · honesty law):
//    · READ_CACHED(5m) — the slot grid paints from the last decoded read of
//      appointments.getAvailableSlots and states its own age on a monospaced
//      staleness line directly above the grid: "LIVE · read HH:mm:ss" in
//      textTertiary, "STALE · N min old · not live" in Brand.warning past the
//      five-minute ttl, and "OFFLINE · N min old · not refreshing" when the
//      device cannot reach the network at all. Cached, stale and offline are
//      VISIBLY distinct from live — a slot's availability is never presented as
//      current when it is not, and a failed refresh keeps the last real grid on
//      screen (labelled) instead of collapsing to an empty gate.
//    · ONLINE_ONLY(gate capacity is contended; a queued reservation would
//      double-book a slot) — the Reserve commit refuses offline rather than
//      queueing. This is not a preference: appointments.create is absent from
//      the offline-eligibility table at Services/EusoTripAPI.swift:1947-2010,
//      so mutation() cannot enqueue it; offline it would hard-fail and the slot
//      would be lost. The CTA renders visibly disabled with the reason stated.
//
//  PHANTOM PROCEDURE REMOVED (rail lane, 2026-08-26): this screen called a
//    railGate cutoffs procedure to flag and disable slots landing after a
//    yard's ingate cutoff. THAT PROCEDURE DOES NOT EXIST. server/routers/
//    railGate.ts is 360 lines and exports exactly two procedures —
//    recordGateEvent (:85) and getGateActivity (:305) — and neither is it; a
//    grep for the phantom name across all 375 router files returns nothing, and
//    no rail_service_cutoffs table is modeled anywhere in the frontend. The
//    phantom identifier is recorded in the §18 lane report and deliberately not
//    spelled here, so a repo grep for it stays clean. The call could only ever
//    fail, and the failure
//    was coalesced to "no cutoff", which rendered every slot as inside the
//    ingate window — unknown converted to clear, which the Truth Contract
//    forbids. There is no modeled source, so the cutoff row now renders
//    explicitly UNAVAILABLE with the reason named on screen, and no slot is
//    flagged, disabled or cleared against a cutoff this app cannot read.
//
//  ESANG: esangCoach.forScreen (esangCoach.ts:264) is a DRIVER in-cab coach —
//    its SCREEN_ENUM (esangCoach.ts:112) carries no rail or gate key and its
//    system prompt speaks HOS/DVIR, so calling it here would answer about the
//    wrong entity. The ESANG band is composed on device from fields this screen
//    already decoded and is labelled as a derived read. Same call the sibling
//    yard screens 559 and 665 made. No model call is made or claimed.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
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

// MARK: - Rail service cutoff — NO MODELED SOURCE
//
// There is deliberately no cutoff data shape here. The decode target that used
// to sit at this spot existed only to receive the phantom railGate cutoffs
// procedure, which exists in no router. Keeping the type would keep the promise.
// The cutoff row is rendered as an explicit UNAVAILABLE state instead — see
// `cutoffBanner` below.

// MARK: - Body

private struct RailGateAppointmentBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    /// §W READ_CACHED(5m) needs BOTH halves to be honest: staleness alone can
    /// only say how old the last good read is, never that the device cannot
    /// reach the network at all. Reachability also arms the ONLINE_ONLY refusal
    /// on Reserve, so a contended slot is never queued.
    @ObservedObject private var reach = OfflineReachabilityHub.shared
    @EnvironmentObject private var session: EusoTripSession
    let facilityId: String
    let shipmentId: String

    /// §W READ_CACHED(5m) — a slot grid older than five minutes is labelled
    /// stale, in Brand.warning, and is never presented as live.
    private static let slotTTL: TimeInterval = 5 * 60

    @State private var slots: [AvailableSlot562] = []
    /// READ_CACHED(5m) bookkeeping — the instant the grid on screen was actually
    /// decoded from the server. Nil until the first successful read lands.
    @State private var slotsFetchedAt: Date? = nil
    /// The last slot-read failure, kept separate from `errorText` (which is the
    /// Reserve commit's error). A failed refresh must never be dressed as an
    /// empty gate, so this labels the grid rather than clearing it.
    @State private var slotsLoadError: String? = nil
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
                    esangBand
                    if let e = errorText {
                        Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                            .accessibilityLabel("Reservation error")
                            .accessibilityValue(e)
                    }
                    actions
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, 8)
        }
        .eusoRefreshTask { await loadSlots() }
        .onChange(of: selectedDate) { _, _ in Task { await loadSlots() } }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.plus").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · GATE APPOINTMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Reserve gate slot").font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("appointments.create · gate-in · capacity 2 per slot")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .accessibilityLabel("Gate-in appointment, capacity 2 per slot")
            IridescentHairline()
                .accessibilityHidden(true)
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
                    Text("Shipment \(shipmentId.isEmpty ? "-" : shipmentId)")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shipment \(shipmentId.isEmpty ? "not reported" : shipmentId)")
        .accessibilityValue("Facility \(facilityId). Container gate-in, pickup. Service date \(displayDate).")
    }

    // MARK: Date Picker

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SELECT DATE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                .accessibilityHidden(true)
            DatePicker("", selection: $selectedDate, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Brand.info)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCard)
                )
                .accessibilityLabel("Service date")
                .accessibilityValue(displayDate)
                .accessibilityHint("Changing the date reloads the gate slot grid for that service date.")
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Available gate slots, capacity 2 per slot")
            .accessibilityValue(displayDate)
            stalenessRow
            cutoffBanner
            if loading && slots.isEmpty {
                LifecycleCard {
                    Text("Loading slots…").font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                .accessibilityLabel("Loading gate slots")
            } else if slots.isEmpty, let e = slotsLoadError {
                // A read that FAILED is not a gate with no slots. Say which.
                LifecycleCard(accentDanger: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gate slots could not be read")
                            .font(EType.bodyStrong).foregroundStyle(Brand.danger)
                        Text(e).font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Nothing is being shown from cache — no grid has been decoded on this device for \(displayDate). Pull to retry.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Gate slots could not be read")
                .accessibilityValue("\(e). No grid has been decoded on this device for \(displayDate).")
            } else if slots.isEmpty {
                LifecycleCard {
                    Text("The facility returned no gate slots for \(displayDate). That is the facility's own answer, not a failed read.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No gate slots for \(displayDate)")
                .accessibilityValue("The facility returned no slot rows for this service date. This is the facility's own answer, not a failed read.")
            } else {
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(slots) { slot in slotTile(slot) }
                }
            }
        }
    }

    // MARK: §W READ_CACHED(5m) staleness register

    /// Monospaced 10pt register — textTertiary while the grid is a live read,
    /// Brand.warning the moment it is a snapshot instead. OFFLINE outranks
    /// STALE: "stale" implies the network was tried and the answer is merely
    /// old; offline says it cannot be refreshed at all, and the two are never
    /// conflated.
    private var slotStaleness: (text: String, warn: Bool) {
        guard let at = slotsFetchedAt else {
            if !reach.isOnline {
                return ("READ_CACHED(5m) · OFFLINE · no grid decoded on this device", true)
            }
            return ("READ_CACHED(5m) · awaiting first read", false)
        }
        let age = max(0, Date().timeIntervalSince(at))
        let mins = Int(age / 60)
        let old = mins < 1 ? "under a minute" : (mins == 1 ? "1 min" : "\(mins) min")
        let failed = slotsLoadError == nil ? "" : " · last refresh failed"
        if !reach.isOnline {
            return ("READ_CACHED(5m) · OFFLINE · \(old) old · not refreshing", true)
        }
        if age > Self.slotTTL {
            return ("READ_CACHED(5m) · STALE · \(old) old · not live\(failed)", true)
        }
        if slotsLoadError != nil {
            return ("READ_CACHED(5m) · CACHED · \(old) old · last refresh failed", true)
        }
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "America/Chicago")
        return ("READ_CACHED(5m) · LIVE · read \(f.string(from: at)) CT", false)
    }

    private var stalenessRow: some View {
        let s = slotStaleness
        return HStack(spacing: 6) {
            Image(systemName: s.warn ? "clock.badge.exclamationmark" : "dot.radiowaves.left.and.right")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(s.warn ? Brand.warning : palette.textTertiary)
            Text(s.text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(s.warn ? Brand.warning : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Slot grid freshness")
        .accessibilityValue(s.text)
    }

    /// Ingate cutoff — UNAVAILABLE, with the reason named on screen.
    ///
    /// This row used to be driven by a phantom railGate cutoffs procedure that
    /// does not exist: railGate.ts exports only recordGateEvent (:85) and getGateActivity
    /// (:305), and no rail_service_cutoffs table is modeled anywhere. The read
    /// could only ever fail, and the failure was coalesced to "no cutoff", which
    /// silently declared every slot inside the ingate window. There is no
    /// modeled source, so the row states that, names why, and asserts nothing
    /// about any slot. Unknown is never rendered as clear.
    private var cutoffBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ingate cutoff unavailable")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.warning)
                Text("No rail service cutoff is modeled server-side, so this screen cannot say whether a slot makes its train. Slots below are shown on gate capacity only — none of them is screened against a cutoff.")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Brand.warning.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.warning.opacity(0.30))))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ingate cutoff unavailable")
        .accessibilityValue("No rail service cutoff is modeled server-side. Slots are shown on gate capacity only and none of them is screened against a cutoff.")
    }

    private func slotTile(_ s: AvailableSlot562) -> some View {
        // A slot is disabled on the facility's OWN capacity answer and nothing
        // else. The `isPast` cutoff verdict that used to gate this tile was
        // derived from a phantom railGate cutoffs procedure that does not exist, so
        // no slot is flagged, tinted or disabled against a cutoff this app has
        // no source for. The unavailable state is stated once, in `cutoffBanner`.
        let isFull     = !s.available
        let disabled   = isFull
        let isSelected = selectedTime == s.time
        let timeTint: AnyShapeStyle =
            isSelected ? AnyShapeStyle(LinearGradient.diagonal)
            : (isFull ? AnyShapeStyle(palette.textTertiary) : AnyShapeStyle(palette.textPrimary))
        let labelTint: Color =
            isFull ? palette.textTertiary : (isSelected ? Brand.info : Brand.success)
        return Button {
            guard !disabled else { return }
            selectedTime = s.time
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(s.time).foregroundStyle(timeTint)
                    .font(.system(size: 16, weight: .bold)).monospacedDigit()
                // `isPast: false` is not a claim that the slot is inside a
                // cutoff window — it is the absence of any cutoff source. The
                // banner above the grid carries that fact.
                Text(slotLabel(s, isPast: false))
                    .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(labelTint)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(disabled ? palette.bgCardSoft.opacity(0.5) : palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.borderFaint),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel("Gate slot \(s.time) central time")
        .accessibilityValue(slotAccessibilityValue(s))
        .accessibilityHint(disabled
                           ? "Full. This slot cannot be selected."
                           : "Selects this gate slot. It is not screened against a rail service cutoff.")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The spoken equivalent of a slot tile. Every number is the facility's own
    /// booked-versus-capacity answer; nothing is inferred about a cutoff.
    private func slotAccessibilityValue(_ s: AvailableSlot562) -> String {
        var parts: [String] = []
        if s.available {
            parts.append(selectedTime == s.time ? "Selected" : "Open")
            parts.append("\(s.capacity - s.booked) of \(s.capacity) free")
        } else {
            parts.append("Full")
            parts.append("\(s.booked) of \(s.capacity) booked")
        }
        parts.append("Not screened against a rail service cutoff")
        return parts.joined(separator: ". ")
    }

    /// `isPast` stays in the signature: it is the hook a REAL rail service
    /// cutoff source would drive if one is ever modeled. Today no such source
    /// exists, so every call site passes false and the "past cutoff" string is
    /// never rendered — the unavailability is declared once, in `cutoffBanner`,
    /// rather than being implied slot by slot.
    private func slotLabel(_ s: AvailableSlot562, isPast: Bool) -> String {
        if isPast { return "past cutoff" }
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
                Text("GP-XXXXXX · gate pass valid 4h from slot")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected slot \(time) central time, gate 3")
        .accessibilityValue("No fee. A confirmation number and a gate pass valid four hours from the slot time are issued on confirm.")
    }

    // MARK: ESANG derived read
    //
    // esangCoach.forScreen (esangCoach.ts:264) is a DRIVER in-cab coach: its
    // SCREEN_ENUM (esangCoach.ts:112) carries no rail or gate key and its system
    // prompt speaks HOS/DVIR, so wiring this band to it would return the wrong
    // entity. The band is therefore composed on device from fields already
    // decoded on this screen and is labelled as such. Same call 559 and 665
    // made. No model call is made or claimed.

    private var esangBand: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 30, height: 30)
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG AI")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Text(esangRead.headline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(esangRead.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("DERIVED ON DEVICE FROM THIS SCREEN · NOT AN ASSISTANT")
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ESANG derived read")
        .accessibilityValue("\(esangRead.headline). \(esangRead.detail). Derived on device from this screen, not an assistant.")
    }

    /// Every noun and number here is a field this screen already decoded from
    /// appointments.getAvailableSlots. Nothing is inferred about a cutoff, a
    /// train symbol or a fee, because this screen has no source for any of them.
    private var esangRead: (headline: String, detail: String) {
        if slots.isEmpty && loading {
            return ("Reading the gate slot grid",
                    "Nothing is claimed about \(displayDate) until the facility answers.")
        }
        if slots.isEmpty, slotsLoadError != nil {
            return ("The slot grid could not be read",
                    "No grid has been decoded on this device for \(displayDate), so there is nothing to read against. This is a failed read, not an empty gate.")
        }
        if slots.isEmpty {
            return ("No gate slots returned for \(displayDate)",
                    "The facility returned no slot rows for this service date. That is its own answer, and it is not the same as a full gate.")
        }
        let open = slots.filter { $0.available }
        guard let first = open.first else {
            return ("Every returned slot is full on \(displayDate)",
                    "\(slots.count) slot\(slots.count == 1 ? "" : "s") returned, none open. No cutoff screening is applied — see the row above the grid.")
        }
        return ("\(open.count) of \(slots.count) slots open · earliest \(first.time) CT",
                "Counts are the facility's own booked-versus-capacity figures for \(displayDate). No cutoff screening is applied — see the row above the grid.")
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
                Text("Slot \(selectedTime ?? "-") · \(displayDate)")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                Text("Gate pass issued · valid 4 h from slot time")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gate appointment confirmed")
        .accessibilityValue("Confirmation \(conf.confirmationNumber ?? "CONF-\(conf.id)"). Slot \(selectedTime ?? "not reported"), \(displayDate). Gate pass issued, valid four hours from the slot time.")
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if !reach.isOnline { onlineOnlyNotice }
            HStack(spacing: Space.s2) {
                CTAButton(
                    title: reserveTitle,
                    action: { Task { await reserve() } },
                    leadingIcon: "checkmark",
                    isLoading: submitting || selectedTime == nil || !reach.isOnline
                )
                .accessibilityLabel(reserveTitle)
                .accessibilityHint(reserveHint)
                // rail §18: was `dismiss()`, which is the SHEET idiom and a
                // no-op inside the pushed RailEngineerSurface — the control was
                // styled, compiler-clean and permanently inert. Posts the shared
                // NavBack the surface actually pops on, same as 563/564/565/566.
                CTAButton(title: "Cancel", action: {
                    NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
                })
                    .accessibilityLabel("Cancel")
                    .accessibilityHint("Leaves the gate appointment screen without reserving a slot.")
            }
        }
    }

    /// The Reserve CTA's own label. §W ONLINE_ONLY is stated on the button
    /// itself, not only in a note beside it — the commit is refused, never
    /// queued, and the button must never look like it took the tap.
    private var reserveTitle: String {
        if !reach.isOnline { return "Offline · reserve unavailable" }
        if submitting { return "Reserving…" }
        return selectedTime.map { "Reserve \($0) slot" } ?? "Select a slot"
    }

    private var reserveHint: String {
        if !reach.isOnline {
            return "Offline. A gate reservation is never queued: gate capacity is contended, so a queued reservation would double-book a slot."
        }
        if selectedTime == nil { return "Select a gate slot above to enable this." }
        return "Commits the reservation and issues a confirmation number."
    }

    /// §W ONLINE_ONLY(gate capacity is contended; a queued reservation would
    /// double-book a slot). Offline is a state of the DEVICE, not of the data,
    /// so it gets its own band above the CTA rather than being folded into the
    /// staleness stamp on the grid.
    private var onlineOnlyNotice: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("Offline · reserving a slot is ONLINE_ONLY")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text("Gate capacity is contended, so a queued reservation would double-book a slot. appointments.create is not one of the actions the offline outbox can replay, so nothing would be held — it would simply be lost. Reconnect to reserve. The slot grid above is a stored snapshot.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.warning.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.30))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline. Reserving a gate slot is online only.")
        .accessibilityValue("Gate capacity is contended, so a queued reservation would double-book a slot. Nothing is queued. Reconnect to reserve.")
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
            self.slotsFetchedAt = Date()
            self.slotsLoadError = nil
            if let prev = selectedTime, !result.slots.contains(where: { $0.time == prev && $0.available }) {
                selectedTime = nil
            }
        } catch {
            // §W READ_CACHED(5m): a failed read must not be dressed as an empty
            // gate. Keep the last decoded grid on screen and let the staleness
            // register above it say how old it is — and, offline, that it is not
            // refreshing at all. Only a first load with nothing decoded leaves
            // the grid empty, and that renders as a failed read, not "no slots".
            self.slotsLoadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// §W ONLINE_ONLY(gate capacity is contended; a queued reservation would
    /// double-book a slot). The CTA is already disabled offline; this guard is
    /// the second lock, so a reservation can never be latched on a device that
    /// cannot confirm it against live capacity.
    private func reserve() async {
        guard let time = selectedTime else { return }
        guard reach.isOnline else {
            errorText = "Offline — a gate reservation is never queued. Gate capacity is contended, so a queued reservation would double-book a slot. Reconnect to reserve."
            return
        }
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

    // MARK: Ingate-cutoff helpers — REMOVED WITH THE PHANTOM CALL
    //
    // cutoffDate / cutoffDisplay / isPastIngateCutoff / slotInstant existed only
    // to turn a phantom railGate cutoffs payload into a per-slot verdict. That
    // procedure does not exist, so every one of them resolved against nil and
    // returned "not past" — an unknown rendered as clear. They are gone rather
    // than left dormant: dead cutoff arithmetic invites the verdict back.

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
