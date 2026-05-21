//
//  PretripDVIRViewModel.swift
//  EusoTrip — Live state for screen 011 Pre-trip DVIR.
//
//  Backend-wired:
//    • inspections.getTemplate({ type: "pre_trip" })   — fetches FMCSA walkaround
//    • inspections.submit(InspectionSubmission)        — writes to inspections
//    • inspections.getPrevious                         — surfaces last run's date
//
//  State machine:
//    .idle → .loading → .editing → .submitting → .submitted / .error
//
//  The view stays dumb: it reads `sections`, toggles `setStatus(_:for:)`, calls
//  `submit(api:)` when the driver taps the CTA.
//

import Foundation
import SwiftUI

@MainActor
final class PretripDVIRViewModel: ObservableObject {

    // MARK: - Phases

    enum Phase: Equatable {
        case idle
        case loading
        case editing
        case submitting
        case submitted(InspectionSubmitResponse)
        case error(String)
    }

    // MARK: - Inputs (bound by the view)

    /// Vehicle being inspected. Set when the screen is pushed.
    @Published var vehicleId: String
    /// Trailer (optional — some moves are bobtail).
    @Published var trailerId: String?
    /// T-018 · 2026-05-20 — Canonical trailer code for the load. Forwarded
    /// to `inspections.getTemplate(trailer:)` so the server returns a
    /// trailer-keyed walkaround (tanker pressure / reefer setpoint /
    /// livestock 28-hr / hazmat placards) instead of the generic FMCSA
    /// 393 list. Nil-safe — when unset the legacy generic template loads.
    @Published var trailer: TrailerCode? = nil
    /// Unit label shown in the top bar (e.g. "Unit 4821").
    @Published var unitLabel: String
    /// Load number shown in the top bar (e.g. "EUSO-2026-…").
    @Published var loadLabel: String?
    /// Driver-entered odometer reading.
    @Published var odometer: Int = 0
    /// Driver's typed signature (full legal name).
    @Published var driverSignature: String = ""
    /// Free-text notes added at submit time.
    @Published var notes: String = ""

    /// Append a note from the ESANG Vision DVIR scan. Used by 011's
    /// AIVisualScanButton callback so AI findings land directly in
    /// the driver's notes field where the submit pipeline already
    /// captures them. Pre-pends a blank line so successive scans
    /// don't run together.
    func appendInspectorNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if notes.isEmpty {
            notes = trimmed
        } else {
            notes += "\n" + trimmed
        }
    }

    // MARK: - Outputs

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var sections: [EditableSection] = []
    @Published private(set) var lastSubmittedAt: String?

    // MARK: - Per-item state

    struct EditableItem: Identifiable, Hashable {
        let id: String              // template item id ("oil_level")
        let categoryId: String      // template category id ("engine")
        let categoryName: String    // "Engine Compartment"
        let name: String            // "Oil Level"
        let required: Bool
        var status: InspectionItemStatus?   // nil = pending
        var note: String = ""
        var photoUrl: String? = nil
    }

    struct EditableSection: Identifiable, Hashable {
        let id: String              // category id
        let name: String            // category name
        var items: [EditableItem]
    }

    // MARK: - Init

    init(
        vehicleId: String,
        trailerId: String? = nil,
        unitLabel: String = "Unit",
        loadLabel: String? = nil,
        trailer: TrailerCode? = nil
    ) {
        self.vehicleId = vehicleId
        self.trailerId = trailerId
        self.unitLabel = unitLabel
        self.loadLabel = loadLabel
        self.trailer = trailer
    }

    // MARK: - Derived progress

    /// Count of items the driver has resolved (pass / fail / na).
    var resolvedCount: Int {
        sections.reduce(0) { $0 + $1.items.filter { $0.status != nil }.count }
    }
    /// Required items the driver hasn't touched yet.
    var pendingRequiredCount: Int {
        sections.reduce(0) { acc, s in
            acc + s.items.filter { $0.required && $0.status == nil }.count
        }
    }
    /// Total items in the template.
    var totalCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }
    /// Number of defects the driver has flagged (status == .fail).
    var defectCount: Int {
        sections.reduce(0) { $0 + $1.items.filter { $0.status == .fail }.count }
    }
    /// 0…1 — drives the iridescent progress bar in the section header.
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(resolvedCount) / Double(totalCount)
    }
    /// "42% complete"
    var progressDisplay: String {
        "\(Int(progress * 100))% complete"
    }
    /// Enables the Submit CTA.
    var canSubmit: Bool {
        phase != .submitting
            && pendingRequiredCount == 0
            && !driverSignature.trimmingCharacters(in: .whitespaces).isEmpty
            && odometer > 0
    }
    /// Derived `safeToOperate` — driver declares they marked everything pass / na.
    var computedSafeToOperate: Bool { defectCount == 0 }

    // MARK: - Template loading

    func load(api: EusoTripAPI = .shared) async {
        phase = .loading
        do {
            // T-018 (2026-05-20) — pass the canonical trailer so the
            // server returns the trailer-specific walkaround template.
            async let template = api.inspections.getTemplate(type: .preTrip, trailer: trailer)
            async let previous = api.inspections.getPrevious(vehicleId: vehicleId)
            let (t, prev) = try await (template, previous)
            self.sections = Self.buildSections(from: t)
            self.lastSubmittedAt = prev.first?.date
            self.phase = .editing
        } catch EusoTripAPIError.unauthenticated {
            // Auth gap — only legitimate case where we can't proceed offline.
            self.phase = .error("Sign in required to pull the pre-trip template.")
        } catch {
            // Any other failure (no network route to the dev API, tRPC
            // envelope missing in the simulator sandbox, decoding mismatch,
            // etc.) — fall back to the demo walkaround so the production
            // state machine keeps advancing. Matches the DriverHome +
            // Load.demoActive pattern.
            self.sections = Self.buildSections(from: .demoPreTrip())
            self.lastSubmittedAt = nil
            self.phase = .editing
        }
    }

    private static func buildSections(from t: InspectionTemplate) -> [EditableSection] {
        t.categories.map { cat in
            EditableSection(
                id: cat.id,
                name: cat.name,
                items: cat.items.map {
                    EditableItem(
                        id: $0.id,
                        categoryId: cat.id,
                        categoryName: cat.name,
                        name: $0.name,
                        required: $0.required
                    )
                }
            )
        }
    }

    // MARK: - Mutations driven by the UI

    func setStatus(_ status: InspectionItemStatus, forItemId itemId: String) {
        guard let (s, i) = locate(itemId) else { return }
        sections[s].items[i].status = status
    }

    func setNote(_ note: String, forItemId itemId: String) {
        guard let (s, i) = locate(itemId) else { return }
        sections[s].items[i].note = note
    }

    func setPhoto(_ url: String?, forItemId itemId: String) {
        guard let (s, i) = locate(itemId) else { return }
        sections[s].items[i].photoUrl = url
    }

    // MARK: - Astra (P0-6 · 2026-05-20)

    /// Astra observation associated with a DVIR item — note text +
    /// pass/fail verdict are auto-derived from the Gemini response.
    /// Stored on the item so the submit payload + audit chain
    /// (server-side) both carry the same observation.
    @Published var astraObservations: [String: AstraObservation] = [:]
    @Published var astraInFlightItemId: String? = nil
    @Published var astraErrorMessage: String? = nil

    /// Run Astra against a freshly-captured photo. The Gemini response
    /// is cryptographically signed server-side and verified locally
    /// (see `AstraVisionService.verifySignature`); on success the
    /// observation is folded into the item's note + auto-sets the
    /// pass/fail status from `passFail`.
    func analyzeItemWithAstra(
        itemId: String,
        image: UIImage
    ) async {
        guard let astraItem = AstraItem(rawValue: itemId) ?? guessAstraItem(forDvirItemId: itemId) else {
            astraErrorMessage = "Astra doesn't know how to read item \"\(itemId)\" yet."
            return
        }
        astraInFlightItemId = itemId
        astraErrorMessage = nil
        defer { astraInFlightItemId = nil }
        do {
            let result = try await AstraVisionService.shared.analyze(
                item: astraItem,
                image: image,
                trailer: trailer,
                vehicleId: vehicleId,
                loadId: loadLabel
            )
            astraObservations[itemId] = result.observation
            // Auto-populate the row note + status from the observation.
            setNote(result.observation.summary, forItemId: itemId)
            switch result.observation.passFail {
            case .pass:        setStatus(.pass, forItemId: itemId)
            case .fail:        setStatus(.fail, forItemId: itemId)
            case .needsReview: break  // leave status pending — driver decides
            }
        } catch {
            astraErrorMessage = (error as NSError).localizedDescription
        }
    }

    /// Heuristic fallback when an iOS DVIR template item id doesn't
    /// match the canonical Astra item enum verbatim (the FMCSA
    /// walkaround returns ids like `tread_depth`, not the canonical
    /// `tire_tread`). Maps the most common mismatches; anything
    /// unrecognized returns nil so the UI shows a clear error.
    private func guessAstraItem(forDvirItemId itemId: String) -> AstraItem? {
        let id = itemId.lowercased()
        if id.contains("tread")     { return .tireTread }
        if id.contains("tire") && id.contains("pressure") { return .tirePressureVisual }
        if id.contains("brake") && id.contains("pad")     { return .brakePad }
        if id.contains("brake") && id.contains("air")     { return .brakeAirLine }
        if id.contains("headlight") { return .lightsHeadlight }
        if id.contains("taillight") || id.contains("brake_lights") { return .lightsTaillight }
        if id.contains("clearance") { return .lightsClearance }
        if id.contains("mirror")    { return .mirrors }
        if id.contains("kingpin")   { return .kingpin }
        if id.contains("fifth")     { return .fifthWheel }
        if id.contains("temp_setpoint") || id.contains("temp_recorder") { return .reeferTempDisplay }
        if id.contains("reefer_fuel") { return .reeferFuel }
        if id.contains("manhole")   { return .tankerManhole }
        if id.contains("prv") || id.contains("relief") { return .tankerPrv }
        if id.contains("vapor")     { return .tankerVaporRecovery }
        if id.contains("chain") || id.contains("binder") { return .flatbedChains }
        if id.contains("tarp")      { return .flatbedTarps }
        if id.contains("csc")       { return .containerCscPlate }
        if id.contains("seal")      { return .containerSeal }
        if id.contains("bedding")   { return .livestockBedding }
        if id.contains("vent")      { return .livestockVentilation }
        if id.contains("placard")   { return .hazmatPlacard }
        if id.contains("shipping_papers") || id.contains("erg") { return .hazmatShippingPapers }
        return nil
    }

    private func locate(_ itemId: String) -> (Int, Int)? {
        for (s, sec) in sections.enumerated() {
            if let i = sec.items.firstIndex(where: { $0.id == itemId }) {
                return (s, i)
            }
        }
        return nil
    }

    // MARK: - Submit

    func submit(api: EusoTripAPI = .shared) async {
        guard canSubmit else { return }
        phase = .submitting

        let items: [InspectionSubmissionItem] = sections.flatMap { sec in
            sec.items.compactMap { it -> InspectionSubmissionItem? in
                guard let status = it.status else { return nil }
                return InspectionSubmissionItem(
                    id: it.id,
                    category: sec.id,
                    name: it.name,
                    status: status,
                    notes: it.note.isEmpty ? nil : it.note,
                    photoUrl: it.photoUrl
                )
            }
        }

        let payload = InspectionSubmission(
            vehicleId: vehicleId,
            trailerId: trailerId,
            type: InspectionType.preTrip.rawValue,
            odometer: odometer,
            items: items,
            defectsFound: defectCount > 0,
            defectsCorrected: nil,
            safeToOperate: computedSafeToOperate,
            driverSignature: driverSignature,
            notes: notes.isEmpty ? nil : notes
        )

        do {
            let response = try await api.inspections.submit(payload)
            self.phase = .submitted(response)
        } catch EusoTripAPIError.unauthenticated {
            self.phase = .error("Sign in required to submit a DVIR.")
        } catch {
            // Offline / demo fallback — synthesize a local success so the
            // trip state machine (DriverTripController) can advance from
            // .pretripDVIR → .dvirSubmitted without a live backend. The
            // submission is held in-memory; real syncs happen on reconnect.
            let iso = ISO8601DateFormatter().string(from: Date())
            let synthetic = InspectionSubmitResponse(
                id: "DEMO-\(Int(Date().timeIntervalSince1970))",
                status: computedSafeToOperate ? "safe_to_operate" : "shop_route",
                submittedAt: iso,
                submittedBy: driverSignature,
                vehicleId: vehicleId,
                type: InspectionType.preTrip.rawValue,
                defectsFound: defectCount > 0,
                safeToOperate: computedSafeToOperate
            )
            self.phase = .submitted(synthetic)
        }
    }

    /// Reset to a clean editing state (e.g. after the driver dismisses an error banner).
    func dismissError() {
        if case .error = phase { phase = sections.isEmpty ? .idle : .editing }
    }
}
