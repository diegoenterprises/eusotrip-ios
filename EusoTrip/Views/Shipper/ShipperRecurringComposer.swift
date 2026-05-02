//
//  ShipperRecurringComposer.swift
//  EusoTrip — Shipper inline recurring-load composer.
//
//  Closes the shipper-side half of Phase 19 (Recurring loads) of the
//  8000-scenario shipper↔driver parity audit
//  (docs/parity-2026/EXECUTIVE_VERDICT.md §4.6). Phase 19 was PARTIAL
//  because backend `loadTemplates.create` + `loads.createFromTemplate`
//  shipped, the iOS surface listed templates and tap-detail worked,
//  but the "+ New recurring schedule" CTA still routed to a web
//  Continuity hand-off (`MeAction.fire("shipper.recurring.schedule")`).
//
//  This sheet replaces that hand-off with an in-app composer:
//    1. Lane block — origin city/state + destination city/state
//    2. Cargo block — commodity, weight, equipment
//    3. Schedule block — first pickup date + first delivery date,
//       optional preferred-days chips (Mon-Sun)
//    4. Pricing block — flat rate (USD) + rate type
//    5. Submit -> loadTemplates.create -> loads.createFromTemplate
//       fires for the first occurrence so the shipper sees an
//       active load on the schedule immediately.
//
//  Production-grade per [feedback_swiftui_previews] mandate. Dark +
//  Light previews ship.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct ShipperRecurringComposer: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// Optional: pre-fill the form from an existing template (e.g.,
    /// "Schedule next pickup" tap on a row in 221_ShipperRecurringLoads
    /// can pass the existing template through). When provided the
    /// composer becomes an "add next occurrence" path that skips
    /// loadTemplates.create and goes straight to
    /// loads.createFromTemplate.
    let prefilledTemplate: LoadTemplatesAPI.Template?

    init(prefilledTemplate: LoadTemplatesAPI.Template? = nil) {
        self.prefilledTemplate = prefilledTemplate
    }

    // Lane
    @State private var name: String = ""
    @State private var originCity: String = ""
    @State private var originState: String = ""
    @State private var destCity: String = ""
    @State private var destState: String = ""

    // Cargo
    @State private var commodity: String = ""
    @State private var equipmentType: String = ""
    @State private var weightLbs: String = ""

    // Schedule
    @State private var pickupDate: Date = Date().addingTimeInterval(60 * 60 * 24)   // tomorrow
    @State private var deliveryDate: Date = Date().addingTimeInterval(60 * 60 * 48) // +2d
    @State private var preferredDays: Set<Weekday> = []

    // Pricing
    @State private var ratePerLoad: String = ""

    // Submit
    @State private var inFlight: Bool = false
    @State private var error: String? = nil
    @State private var success: Bool = false

    enum Weekday: String, CaseIterable, Identifiable, Hashable {
        case mon = "Mon", tue = "Tue", wed = "Wed", thu = "Thu", fri = "Fri", sat = "Sat", sun = "Sun"
        var id: String { rawValue }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    headerCard
                    laneCard
                    cargoCard
                    scheduleCard
                    pricingCard
                    if let err = error {
                        errorBanner(err)
                    }
                    Color.clear.frame(height: 132)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(inFlight)
                }
                ToolbarItem(placement: .principal) {
                    Text(prefilledTemplate == nil ? "NEW RECURRING" : "ADD OCCURRENCE")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .safeAreaInset(edge: .bottom) {
                submitBar
                    .background(palette.bgPrimary)
            }
            .overlay(alignment: .bottom) {
                if success {
                    Text(prefilledTemplate == nil
                         ? "Recurring template saved · first pickup scheduled"
                         : "Next pickup scheduled")
                        .font(EType.caption).fontWeight(.semibold)
                        .foregroundStyle(palette.textOnGradient)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s2)
                        .background(Brand.success,
                                    in: RoundedRectangle(cornerRadius: Radius.md))
                        .padding(.bottom, 132)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear { applyPrefill() }
        }
    }

    private func applyPrefill() {
        guard let t = prefilledTemplate else { return }
        if name.isEmpty { name = t.name }
        if originCity.isEmpty { originCity = t.origin?.city ?? "" }
        if originState.isEmpty { originState = t.origin?.state ?? "" }
        if destCity.isEmpty { destCity = t.destination?.city ?? "" }
        if destState.isEmpty { destState = t.destination?.state ?? "" }
        if commodity.isEmpty { commodity = t.commodity ?? "" }
        if equipmentType.isEmpty { equipmentType = t.equipmentType ?? "" }
        if weightLbs.isEmpty { weightLbs = t.weight ?? "" }
        if ratePerLoad.isEmpty, let r = t.rate { ratePerLoad = r }
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prefilledTemplate == nil
                 ? "Schedule a recurring lane"
                 : "Schedule the next pickup")
                .font(EType.display)
                .foregroundStyle(palette.textPrimary)
            Text(prefilledTemplate == nil
                 ? "Save the lane once. Materialize a load whenever you need a pickup. Shipper of record + carrier-of-record routing carries through every occurrence."
                 : "We'll seed a fresh load from this template. Pick the dates and we'll post it to the available board the moment you submit.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var laneCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("01 · LANE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 4) {
                Text("Template name")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. HOU → DAL · UN1203 · weekly",
                          text: $name)
                    .font(EType.body)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(palette.borderFaint))
                    .disabled(prefilledTemplate != nil)
            }
            cityStateRow(label: "ORIGIN", city: $originCity, state: $originState)
            cityStateRow(label: "DESTINATION", city: $destCity, state: $destState)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func cityStateRow(label: String, city: Binding<String>, state: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                TextField("City", text: city)
                    .font(EType.body)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(palette.borderFaint))
                    .disabled(prefilledTemplate != nil)
                TextField("ST", text: state)
                    .font(EType.body)
                    .textInputAutocapitalization(.characters)
                    .frame(width: 64)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(palette.borderFaint))
                    .disabled(prefilledTemplate != nil)
            }
        }
    }

    private var cargoCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("02 · CARGO")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            HStack(spacing: 8) {
                fieldColumn(label: "Commodity", text: $commodity, placeholder: "e.g. UN1203 gasoline")
                fieldColumn(label: "Equipment", text: $equipmentType, placeholder: "e.g. tanker")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Weight (lbs)")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. 45000", text: $weightLbs)
                    .font(EType.body)
                    .keyboardType(.numberPad)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(palette.borderFaint))
                    .disabled(prefilledTemplate != nil)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func fieldColumn(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.caption).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: text)
                .font(EType.body)
                .padding(Space.s3)
                .background(palette.bgCardSoft,
                            in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(palette.borderFaint))
                .disabled(prefilledTemplate != nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("03 · SCHEDULE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            DatePicker("First pickup", selection: $pickupDate, in: Date()..., displayedComponents: .date)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
            DatePicker("First delivery", selection: $deliveryDate, in: pickupDate..., displayedComponents: .date)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
            if prefilledTemplate == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PREFERRED DAYS (OPTIONAL)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    HStack(spacing: 4) {
                        ForEach(Weekday.allCases) { day in
                            Button {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    if preferredDays.contains(day) {
                                        preferredDays.remove(day)
                                    } else {
                                        preferredDays.insert(day)
                                    }
                                }
                            } label: {
                                Text(day.rawValue)
                                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                    .foregroundStyle(preferredDays.contains(day)
                                                     ? palette.textOnGradient
                                                     : palette.textPrimary)
                                    .frame(width: 36, height: 32)
                                    .background(
                                        Capsule().fill(
                                            preferredDays.contains(day)
                                            ? AnyShapeStyle(LinearGradient.diagonal)
                                            : AnyShapeStyle(palette.bgCardSoft)
                                        )
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(
                                            preferredDays.contains(day)
                                            ? Color.clear
                                            : palette.borderFaint
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var pricingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("04 · PRICING")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 4) {
                Text("Flat rate (USD per load)")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                HStack {
                    Text("$")
                        .font(EType.bodyStrong.monospaced())
                        .foregroundStyle(palette.textSecondary)
                    TextField("e.g. 1900", text: $ratePerLoad)
                        .font(EType.body)
                        .keyboardType(.numberPad)
                        .disabled(prefilledTemplate != nil)
                }
                .padding(Space.s3)
                .background(palette.bgCardSoft,
                            in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(palette.borderFaint))
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            IridescentHairline()
            HStack(spacing: Space.s3) {
                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCard,
                                    in: RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(palette.borderSoft))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)

                CTAButton(
                    title: prefilledTemplate == nil
                        ? (inFlight ? "Saving…" : "Save + schedule")
                        : (inFlight ? "Scheduling…" : "Schedule pickup"),
                    action: { Task { await submit() } },
                    isLoading: inFlight
                )
                .opacity(canSubmit ? 1.0 : 0.55)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
    }

    private var canSubmit: Bool {
        guard !inFlight else { return false }
        if prefilledTemplate != nil { return true }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && !originCity.isEmpty && !originState.isEmpty
            && !destCity.isEmpty && !destState.isEmpty
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Submit

    private func submit() async {
        guard canSubmit else { return }
        inFlight = true
        error = nil
        defer { inFlight = false }

        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM-dd"
        let pickup = isoFmt.string(from: pickupDate)
        let delivery = isoFmt.string(from: deliveryDate)

        do {
            let templateId: Int
            if let existing = prefilledTemplate {
                templateId = existing.id
            } else {
                let preferred = preferredDays.isEmpty
                    ? nil
                    : Array(preferredDays.map(\.rawValue))
                let createInput = LoadTemplatesAPI.CreateInput(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: nil,
                    origin: .init(
                        city: originCity, state: originState.uppercased(),
                        zipCode: nil, address: nil, facilityName: nil
                    ),
                    destination: .init(
                        city: destCity, state: destState.uppercased(),
                        zipCode: nil, address: nil, facilityName: nil
                    ),
                    distance: nil,
                    commodity: commodity.isEmpty ? nil : commodity,
                    cargoType: nil,
                    equipmentType: equipmentType.isEmpty ? nil : equipmentType,
                    weight: weightLbs.isEmpty ? nil : weightLbs,
                    weightUnit: weightLbs.isEmpty ? nil : "lbs",
                    rate: Double(ratePerLoad),
                    rateType: ratePerLoad.isEmpty ? nil : "flat",
                    preferredDays: preferred,
                    preferredPickupTime: nil,
                    specialInstructions: nil
                )
                let ack = try await EusoTripAPI.shared.loadTemplates.create(createInput)
                guard let id = ack.id else {
                    throw NSError(domain: "EusoTrip", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Server didn't return a template id."])
                }
                templateId = id
            }

            // Materialize the first occurrence so the shipper sees a
            // live load on the schedule the moment the sheet dismisses.
            _ = try await EusoTripAPI.shared.loads.createFromTemplate(
                templateId: templateId,
                pickupDate: pickup,
                deliveryDate: delivery
            )

            withAnimation { success = true }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("Recurring composer · Dark") {
    ShipperRecurringComposer()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("Recurring composer · Light") {
    ShipperRecurringComposer()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
