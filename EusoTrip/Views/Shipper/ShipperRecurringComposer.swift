//
//  ShipperRecurringComposer.swift
//  EusoTrip — Shipper inline recurring-load composer.
//
//  Closes the shipper-side half of Phase 19 (Recurring loads) of the
//  8000-scenario shipper↔driver parity audit
//  (docs/parity-2026/EXECUTIVE_VERDICT.md §4.6). Phase 19 was PARTIAL
//  because backend `loadTemplates.create` + `loadTemplates.useTemplate`
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
//    5. Submit -> loadTemplates.create -> loadTemplates.useTemplate
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
    /// loadTemplates.useTemplate.
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
    @State private var assessment: PortIntelAssessment? = nil
    @State private var assessmentSignature: String? = nil
    @State private var assessing: Bool = false
    @State private var assessmentAcknowledged: Bool = false

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
                    if requiresPortIntelligence {
                        portIntelligenceCard
                    }
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
        if weightLbs.isEmpty { weightLbs = t.quantity ?? t.weight ?? "" }
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
                Text("Quantity (\(prefilledTemplate?.quantityUnit ?? prefilledTemplate?.weightUnit ?? "lbs"))")
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

    private var requiresPortIntelligence: Bool {
        (prefilledTemplate?.transportMode ?? "truck").lowercased() != "truck"
    }

    private var currentAssessmentSignature: String {
        let template = prefilledTemplate
        let fields = [
            template?.commodity ?? commodity,
            template?.category ?? template?.cargoType ?? "general",
            template?.physicalState ?? "",
            template?.unNumber ?? "",
            template?.hazmatClass ?? "",
            template?.transportMode ?? "truck",
            weightLbs,
            template?.quantityUnit ?? template?.weightUnit ?? "lbs",
            templateLocationLabel(template?.origin, fallbackCity: originCity, fallbackState: originState),
            templateLocationLabel(template?.destination, fallbackCity: destCity, fallbackState: destState),
            template?.originCountry ?? template?.origin?.countryCode ?? LoadAnimationContext.countryCode(forState: originState),
            template?.destinationCountry ?? template?.destination?.countryCode ?? LoadAnimationContext.countryCode(forState: destState),
            template?.equipmentType ?? template?.trailerType ?? equipmentType,
            template?.vesselClass ?? "",
            template?.permitType ?? "",
            isoDay(pickupDate),
        ]
        return fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
    }

    private var hasCurrentAssessment: Bool {
        assessment != nil && assessmentSignature == currentAssessmentSignature
    }

    private var assessmentAllowsSubmit: Bool {
        guard requiresPortIntelligence else { return true }
        guard hasCurrentAssessment, let gate = assessment?.preflight.gate else { return false }
        if gate == "ready" { return true }
        return gate == "acknowledgement_required" && assessmentAcknowledged
    }

    private var portIntelligenceCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(LinearGradient.diagonal)
                Text("05 · PORT INTELLIGENCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                if hasCurrentAssessment, let gate = assessment?.preflight.gate {
                    Text(gate.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(EType.micro)
                        .foregroundStyle(gate == "blocked" ? Brand.danger : Brand.success)
                }
            }
            Text("Each rail, vessel, or barge occurrence needs current evidence for its exact cargo, quantity, lane, equipment, and pickup date.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if hasCurrentAssessment,
               assessment?.preflight.gate == "acknowledgement_required" {
                Toggle("Acknowledge the documented evidence gaps", isOn: $assessmentAcknowledged)
                    .font(EType.caption)
            }
            Button {
                Task { await runPortIntelligence() }
            } label: {
                Label(assessing ? "Checking live evidence…" : (hasCurrentAssessment ? "Refresh evidence" : "Run Port Intelligence"),
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(EType.bodyStrong)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.blue)
            .disabled(assessing)
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let product = commodity.trimmingCharacters(in: .whitespacesAndNewlines)
        let validWeight = Double(weightLbs).map { $0 > 0 } == true
        return !trimmed.isEmpty
            && !originCity.isEmpty && !originState.isEmpty
            && !destCity.isEmpty && !destState.isEmpty
            && !product.isEmpty && validWeight
            && deliveryDate > pickupDate
            && assessmentAllowsSubmit
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

    private func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func templateLocationLabel(
        _ location: LoadTemplatesAPI.Template.Location?,
        fallbackCity: String,
        fallbackState: String
    ) -> String {
        let city = location?.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallbackCity
        let state = location?.state?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallbackState
        let zip = location?.zipCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let locality = [city, state, zip].filter { !$0.isEmpty }.joined(separator: " ")
        let address = location?.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [address, locality].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func runPortIntelligence() async {
        guard let template = prefilledTemplate,
              let quantity = Double(weightLbs), quantity > 0 else {
            error = "A saved template with a positive cargo quantity is required before assessment."
            return
        }
        let origin = templateLocationLabel(template.origin, fallbackCity: originCity, fallbackState: originState)
        let destination = templateLocationLabel(template.destination, fallbackCity: destCity, fallbackState: destState)
        let originCountry = (template.originCountry
            ?? template.origin?.countryCode
            ?? LoadAnimationContext.countryCode(forState: originState)).uppercased()
        let destinationCountry = (template.destinationCountry
            ?? template.destination?.countryCode
            ?? LoadAnimationContext.countryCode(forState: destState)).uppercased()
        guard !origin.isEmpty, !destination.isEmpty,
              originCountry.count == 2, destinationCountry.count == 2 else {
            error = "Verified lane and country details are required before assessment."
            return
        }
        assessing = true
        assessmentAcknowledged = false
        error = nil
        defer { assessing = false }
        let request = PortIntelAssessmentInput(
            requestKey: UUID().uuidString,
            title: "\(template.commodity ?? commodity) · \(origin) to \(destination)",
            draft: .init(
                productName: template.commodity ?? commodity,
                category: template.category ?? template.cargoType,
                physicalState: template.physicalState,
                unNumber: template.unNumber,
                hazmatClass: template.hazmatClass,
                transportMode: template.transportMode ?? "truck",
                quantity: quantity,
                quantityUnit: template.quantityUnit ?? template.weightUnit ?? "lbs",
                origin: origin,
                destination: destination,
                originCountry: originCountry,
                destinationCountry: destinationCountry,
                equipment: template.equipmentType ?? template.trailerType,
                vesselClass: template.vesselClass,
                multiVehicleCount: nil,
                pickupDate: isoDay(pickupDate),
                specialPermit: template.permitType == "none" ? nil : template.permitType
            )
        )
        do {
            let result: PortIntelAssessment = try await EusoTripAPI.shared.mutation(
                "portIntelligence.assessLoadDraft",
                input: request
            )
            assessment = result
            assessmentSignature = currentAssessmentSignature
        } catch {
            assessment = nil
            assessmentSignature = nil
            self.error = error.eusoUserCopy
        }
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
                let originCountry = LoadAnimationContext.countryCode(forState: originState).uppercased()
                let destinationCountry = LoadAnimationContext.countryCode(forState: destState).uppercased()
                let createInput = LoadTemplatesAPI.CreateInput(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: nil,
                    origin: .init(
                        city: originCity, state: originState.uppercased(),
                        zipCode: nil, address: nil, facilityName: nil,
                        countryCode: originCountry
                    ),
                    destination: .init(
                        city: destCity, state: destState.uppercased(),
                        zipCode: nil, address: nil, facilityName: nil,
                        countryCode: destinationCountry
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
                    specialInstructions: nil,
                    quantity: weightLbs,
                    quantityUnit: "lbs",
                    originCountry: originCountry,
                    destinationCountry: destinationCountry
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
            _ = try await EusoTripAPI.shared.loadTemplates.useTemplate(
                templateId: templateId,
                pickupDate: pickup,
                deliveryDate: delivery,
                portIntelligenceAssessmentId: hasCurrentAssessment ? assessment?.publicId : nil,
                portIntelligenceAcknowledged: assessmentAcknowledged
            )

            withAnimation { success = true }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch {
            self.error = error.eusoUserCopy
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
