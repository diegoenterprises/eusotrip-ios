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
//    3. Cargo-classification block — the poster's dangerous-goods
//       attestation for the FIRST OCCURRENCE (shared primitive,
//       Views/Components/CargoClassificationAttestation). A template can
//       suggest an identity; only a person can establish a classification.
//    4. Schedule block — first pickup date + first delivery date,
//       optional preferred-days chips (Mon-Sun)
//    5. Pricing block — flat rate (USD) + rate type
//    6. Submit -> loadTemplates.create -> loadTemplates.useTemplate
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

    // ─── 2026-08-07 · cargo-classification attestation ────────────────
    // This composer materializes the FIRST OCCURRENCE via
    // `loadTemplates.useTemplate`, which requires a fresh attestation for
    // that occurrence. The server deliberately does not forward the
    // template's stored hazard columns: a template can SUGGEST an identity
    // but never ESTABLISH one, because it carries no attestation, no
    // evidence reference and no confirming user. So the poster attests here,
    // for this pickup, every time.
    @State private var classification = CargoClassificationAttestation()

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
                    classificationCard
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
        // The template SUGGESTS the regulated identity so the poster does not
        // retype it. It cannot suggest the determination, the evidence source
        // or the evidence reference — those are attestations and only a
        // person makes them, for this occurrence.
        classification.seedRegulatedIdentity(
            unNumber: t.unNumber,
            hazmatClass: t.hazmatClass,
            properShippingName: t.properShippingName,
            packingGroup: t.packingGroup
        )
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

    /// The ONE shared attestation control. This composer captures none of the
    /// regulated identity itself, so the control asks for all of it.
    private var classificationCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("03 · CARGO CLASSIFICATION")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            CargoClassificationAttestationCard(
                attestation: $classification,
                context: classificationContext,
                titleSuffix: "· FIRST OCCURRENCE"
            )
        }
    }

    /// The load facts the server will classify this occurrence against —
    /// resolved off the template when there is one, because that is what
    /// `useTemplate` forwards, and off this screen's own fields when the
    /// template is about to be created from them.
    private var classificationContext: CargoClassificationAttestation.CargoContext {
        guard let template = prefilledTemplate else {
            let typedQuantity = Double(weightLbs).flatMap { $0 > 0 ? $0 : nil }
            return CargoClassificationAttestation.CargoContext(
                productName: commodity.trimmingCharacters(in: .whitespacesAndNewlines),
                equipmentType: equipmentType.trimmingCharacters(in: .whitespacesAndNewlines),
                transportMode: "truck",
                quantity: typedQuantity,
                quantityUnit: typedQuantity != nil ? "lbs" : ""
            )
        }
        let quantity = templateQuantity(template)
        return CargoClassificationAttestation.CargoContext(
            productName: Self.nonBlank(template.commodity) ?? "",
            equipmentType: templateEquipment(template) ?? "",
            transportMode: template.transportMode ?? "truck",
            quantity: quantity,
            quantityUnit: quantity != nil ? (templateQuantityUnit(template) ?? "") : ""
        )
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
            Text("04 · SCHEDULE")
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
            Text("05 · PRICING")
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

    /// Every value that feeds the server's binding hash. When any of them
    /// moves, the held assessment stops being an assessment OF THIS draft and
    /// the screen must reassess rather than post a stale one.
    private var currentAssessmentSignature: String {
        guard let template = prefilledTemplate else { return "" }
        let fields: [String?] = [
            template.commodity,
            template.category,
            template.physicalState,
            // The occurrence's regulated identity comes from the poster's
            // attestation — the server deliberately does NOT forward the
            // template's stored hazard columns — so the binding moves with the
            // attestation, not with the template.
            classification.wireUnNumber,
            classification.wireHazmatClass,
            template.transportMode ?? "truck",
            templateQuantity(template).map { String($0) },
            templateQuantityUnit(template),
            templateLocationLabel(template.origin),
            templateLocationLabel(template.destination),
            templateCountry(explicit: template.originCountry, location: template.origin),
            templateCountry(explicit: template.destinationCountry, location: template.destination),
            templateEquipment(template),
            template.vesselClass,
            templateSpecialPermit(template),
            isoDay(pickupDate),
        ]
        return fields
            .map { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
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
                Text("06 · PORT INTELLIGENCE")
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
            if let reason = submitBlockReason {
                Text(reason)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.s4)
                    .padding(.top, Space.s2)
            }
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
            // 2026-08-07 — the first occurrence needs its own attestation.
            && classification.blockReason(context: classificationContext) == nil
    }

    /// What is stopping the submit, in the poster's words. Rendered under the
    /// submit bar so the disabled button is never unexplained.
    private var submitBlockReason: String? {
        classification.blockReason(context: classificationContext)
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

    // MARK: - Template facts, resolved the way the server resolves them
    //
    // `loadTemplates.useTemplate` re-derives every cargo and lane fact from
    // the TEMPLATE ROW and hands them to `loads.create`, which recomputes the
    // Port Intelligence binding hash over exactly those values
    // (`loadDraftBindingHash`, sourceRequirements.ts). Anything this screen
    // assesses against a different value produces an assessment the server
    // rejects as stale. So each helper below mirrors one server expression
    // verbatim — no fallbacks the server does not have.

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Server: `templateLocationLabel(tmpl.origin)` — address, then
    /// "city state zip". It reads the template row only; there is no fallback
    /// to anything typed on this screen, so there is none here either.
    private func templateLocationLabel(_ location: LoadTemplatesAPI.Template.Location?) -> String {
        guard let location else { return "" }
        let locality = [location.city, location.state, location.zipCode]
            .compactMap(Self.nonBlank)
            .joined(separator: " ")
        return [Self.nonBlank(location.address), Self.nonBlank(locality)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    /// Server: `quantity ?? weight`, where a non-positive quantity is a hard
    /// PRECONDITION_FAILED rather than a fall-through.
    private func templateQuantity(_ template: LoadTemplatesAPI.Template) -> Double? {
        if let raw = Self.nonBlank(template.quantity) {
            guard let quantity = Double(raw), quantity > 0 else { return nil }
            return quantity
        }
        if let raw = Self.nonBlank(template.weight) {
            guard let weight = Double(raw), weight > 0 else { return nil }
            return weight
        }
        return nil
    }

    /// Server: `quantityUnit ?? weightUnit`, where `quantityUnit` only exists
    /// when the template carries a quantity and `weightUnit` falls back to
    /// "lbs" only when the template carries a weight.
    private func templateQuantityUnit(_ template: LoadTemplatesAPI.Template) -> String? {
        if Self.nonBlank(template.quantity) != nil,
           let unit = Self.nonBlank(template.quantityUnit) {
            return unit
        }
        if Self.nonBlank(template.weight) != nil {
            return Self.nonBlank(template.weightUnit) ?? "lbs"
        }
        return nil
    }

    /// The country the server will use: `tmpl.originCountry ||
    /// tmpl.origin?.countryCode`, and nothing else.
    ///
    /// It is deliberately NOT derived from the state code. The server's own
    /// `detectLoadCountryStrict` returns null rather than guessing, and
    /// `loads.create` then cross-checks whatever it has against the
    /// HERE-verified endpoint — so a synthesized country is either a hard
    /// "Origin country US does not match the verified HERE endpoint country
    /// MX" or a fabricated jurisdiction on the load row. The client-side state
    /// table cannot resolve this either: it returns "us" for everything it does
    /// not recognise and excludes CO/MI/MO/BC/NL from its Mexican set, so a
    /// Saltillo → Monterrey lane came out as a US movement.
    private func templateCountry(
        explicit: String?,
        location: LoadTemplatesAPI.Template.Location?
    ) -> String? {
        for candidate in [explicit, location?.countryCode] {
            if let code = Self.nonBlank(candidate)?.uppercased(), code.count == 2 {
                return code
            }
        }
        return nil
    }

    /// Server: `useTemplate` forwards `permitType` only when it is one of the
    /// six enum values, and `loads.create` drops "none" from the binding.
    private static let materializablePermitTypes: Set<String> = [
        "none", "trip_permit", "annual_oversize",
        "superload", "overweight_only", "hazmat_route",
    ]

    private func templateSpecialPermit(_ template: LoadTemplatesAPI.Template) -> String? {
        guard let raw = Self.nonBlank(template.permitType),
              Self.materializablePermitTypes.contains(raw),
              raw != "none" else { return nil }
        return raw
    }

    private func templateEquipment(_ template: LoadTemplatesAPI.Template) -> String? {
        Self.nonBlank(template.equipmentType) ?? Self.nonBlank(template.trailerType)
    }

    private func runPortIntelligence() async {
        guard let template = prefilledTemplate else {
            error = "A saved template is required before assessment."
            return
        }
        guard let productName = Self.nonBlank(template.commodity) else {
            error = "Add the product or commodity to this template before assessment."
            return
        }
        guard let quantity = templateQuantity(template),
              let quantityUnit = templateQuantityUnit(template) else {
            error = "This template needs a positive cargo quantity and its unit before assessment."
            return
        }
        let origin = templateLocationLabel(template.origin)
        let destination = templateLocationLabel(template.destination)
        guard !origin.isEmpty, !destination.isEmpty else {
            error = "This template needs a saved origin and destination before assessment."
            return
        }
        // No country is derived from the state code. The server refuses to
        // guess here and verifies whatever it is given against HERE, so an
        // assessment bound to a guessed country is an assessment the post will
        // reject — and the guess itself would be a fabricated jurisdiction.
        guard let originCountry = templateCountry(explicit: template.originCountry,
                                                  location: template.origin),
              let destinationCountry = templateCountry(explicit: template.destinationCountry,
                                                       location: template.destination) else {
            error = "This template has no recorded origin and destination country. Re-save the lane with verified endpoints before scheduling a rail, vessel, or barge occurrence."
            return
        }
        assessing = true
        assessmentAcknowledged = false
        error = nil
        defer { assessing = false }
        let request = PortIntelAssessmentInput(
            requestKey: UUID().uuidString,
            title: "\(productName) · \(origin) to \(destination)",
            draft: .init(
                productName: productName,
                category: Self.nonBlank(template.category),
                physicalState: Self.nonBlank(template.physicalState),
                // The poster's attestation for THIS occurrence — the same
                // values `useTemplate` forwards to `loads.create`, which is
                // what the binding hash is recomputed over.
                unNumber: classification.wireUnNumber,
                hazmatClass: classification.wireHazmatClass,
                transportMode: template.transportMode ?? "truck",
                quantity: quantity,
                quantityUnit: quantityUnit,
                origin: origin,
                destination: destination,
                originCountry: originCountry,
                destinationCountry: destinationCountry,
                equipment: templateEquipment(template),
                vesselClass: Self.nonBlank(template.vesselClass),
                multiVehicleCount: nil,
                pickupDate: isoDay(pickupDate),
                specialPermit: templateSpecialPermit(template)
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
        // 2026-08-07 — belt and braces: refuse here too, with the exact
        // missing inputs, so no code path can materialize an occurrence
        // without the poster's attestation.
        if let reason = classification.blockReason(context: classificationContext) {
            error = reason
            return
        }
        inFlight = true
        error = nil
        defer { inFlight = false }

        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM-dd"
        let pickup = isoFmt.string(from: pickupDate)
        let delivery = isoFmt.string(from: deliveryDate)

        var savedNewTemplate = false
        do {
            let templateId: Int
            if let existing = prefilledTemplate {
                templateId = existing.id
            } else {
                let preferred = preferredDays.isEmpty
                    ? nil
                    : Array(preferredDays.map(\.rawValue))
                // No country is minted from the state code. This screen
                // collects a city and a state, which is not a jurisdiction —
                // `LoadAnimationContext.countryCode(forState:)` answers "us"
                // for everything it does not recognise and deliberately
                // excludes CO/MI/MO/BC/NL from its Mexican table, so a
                // Saltillo → Monterrey lane was being saved as a US lane. The
                // server resolves and VERIFIES the country from the real
                // endpoint (HERE) when the occurrence is posted; leaving these
                // unset is what lets it.
                let createInput = LoadTemplatesAPI.CreateInput(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: nil,
                    origin: .init(
                        city: originCity, state: originState.uppercased(),
                        zipCode: nil, address: nil, facilityName: nil,
                        countryCode: nil
                    ),
                    destination: .init(
                        city: destCity, state: destState.uppercased(),
                        zipCode: nil, address: nil, facilityName: nil,
                        countryCode: nil
                    ),
                    distance: nil,
                    commodity: commodity.isEmpty ? nil : commodity,
                    cargoType: nil,
                    equipmentType: equipmentType.isEmpty ? nil : equipmentType,
                    // The figure this screen collects is a WEIGHT. It is not
                    // also sent as `quantity`: the server writes a template's
                    // quantityUnit into the load's VOLUME unit, and a mass is
                    // the wrong fact for that column.
                    weight: weightLbs.isEmpty ? nil : weightLbs,
                    weightUnit: weightLbs.isEmpty ? nil : "lbs",
                    rate: Double(ratePerLoad),
                    rateType: ratePerLoad.isEmpty ? nil : "flat",
                    preferredDays: preferred,
                    preferredPickupTime: nil,
                    specialInstructions: nil,
                    quantity: nil,
                    quantityUnit: nil,
                    originCountry: nil,
                    destinationCountry: nil
                )
                let ack = try await EusoTripAPI.shared.loadTemplates.create(createInput)
                guard let id = ack.id else {
                    throw NSError(domain: "EusoTrip", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Server didn't return a template id."])
                }
                templateId = id
                savedNewTemplate = true
            }

            // Materialize the first occurrence so the shipper sees a
            // live load on the schedule the moment the sheet dismisses.
            //
            // `loads.create` — which `useTemplate` hands the occurrence to —
            // requires an assessed industry workflow (its sector id and a
            // one-use assessment id) for EVERY post. This composer has no
            // industry-workflow surface, so it holds no assessment and cannot
            // manufacture one: an assessment is bound to the draft it was made
            // for, and a template can never carry it. The call therefore
            // carries what the poster genuinely established and lets the server
            // refuse in its own words if the evidence is short.
            do {
                _ = try await EusoTripAPI.shared.loadTemplates.useTemplate(
                    templateId: templateId,
                    classification: classification,
                    pickupDate: pickup,
                    deliveryDate: delivery,
                    portIntelligenceAssessmentId: hasCurrentAssessment ? assessment?.publicId : nil,
                    portIntelligenceAcknowledged: assessmentAcknowledged
                )
            } catch {
                // The template is real and saved. Say exactly that, and say
                // exactly what did not happen — never let a saved template read
                // as a scheduled pickup.
                self.error = savedNewTemplate
                    ? "Recurring template saved, but the first pickup was not scheduled — \(error.eusoUserCopy)"
                    : error.eusoUserCopy
                return
            }

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
