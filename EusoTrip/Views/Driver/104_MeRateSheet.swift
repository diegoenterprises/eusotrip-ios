//
//  104_MeRateSheet.swift
//  EusoTrip — Me · Rate Sheets (Schedule A) port from web platform.
//
//  Three-pane surface that mirrors the web `RateSheetReconciliation`
//  experience for drivers + owner-operators:
//
//    • CALCULATOR — net barrels + one-way miles → live pay preview.
//      Backed by `rateSheet.calculateRate`. The server is the
//      rounding authority; we render the breakdown verbatim. The
//      EIA diesel auto-populate runs once on appear via
//      `rateSheet.getCurrentDiesel` so the FSC math is real, not
//      a default placeholder.
//    • SHEETS — `rateSheet.listMyRateSheets` powers the list. Tap
//      to fetch full detail via `getRateSheet(id:)` — driver sees
//      every tier and surcharge that governs their settlement.
//    • RECONCILE — `listReconciliations` + `getStats`. Read-only
//      list of past statements with the running totals at the top.
//
//  Why we ship the authoring surfaces (create/update) from the
//  driver app and not just read views: owner-operators ARE the
//  carrier. The same human who hauls the load also signs the
//  Schedule A. Catalysts (carriers with paid drivers) get the same
//  CRUD against their own company-scoped sheets.
//
//  Doctrine refs:
//    SKILL.md §3 — no-mock pledge. Every value rendered comes from
//                  a live tRPC call. Calculator first-load uses
//                  `getDefaultTiers` so the math is real before the
//                  driver picks a sheet.
//    SKILL.md §4 — Tokenized Space/Radius/EType throughout.
//    Brand    — LinearGradient.diagonal on hero numerics; Brand.success
//               for "compliant" / settled, Brand.warning for pending.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Extracted rate-table structure
//
// The document-intelligence spine (`documentRouter.classifyAndRoute`)
// runs an ADDED pass around the real `uploadDocument` call. For a
// Schedule A the server emits these top-level `extractedFields`
// (visionPrimitive FIELD_HINTS.rate_sheet):
//
//   carrierName, effectiveDate, expirationDate,
//   lanes: [{ origin, destination, rate, equipment, minWeight, maxWeight }]
//
// Non-scalar values (the `lanes` array) arrive on the wire as a
// JSON STRING — the server's `normalizeFields` / classify coercion
// stringifies any object/array so the envelope stays scalar-keyed
// ([String: FieldValue] decodes them as `.string`). We parse that
// JSON back into typed lane rows here so the rate table renders as a
// real structure (lanes · rates · weight bands · effective dates),
// not raw image storage.
struct ExtractedRateTable: Equatable {
    struct Lane: Equatable, Identifiable {
        let id = UUID()
        var origin: String?
        var destination: String?
        var rate: String?
        var equipment: String?
        var minWeight: String?
        var maxWeight: String?

        /// "Origin → Destination" with graceful fallback.
        var laneLabel: String {
            switch (origin?.nilIfBlank, destination?.nilIfBlank) {
            case let (o?, d?): return "\(o) → \(d)"
            case let (o?, nil): return o
            case let (nil, d?): return "→ \(d)"
            case (nil, nil): return "Lane"
            }
        }

        var weightBand: String? {
            switch (minWeight?.nilIfBlank, maxWeight?.nilIfBlank) {
            case let (mn?, mx?): return "\(mn)–\(mx) lb"
            case let (mn?, nil): return "≥ \(mn) lb"
            case let (nil, mx?): return "≤ \(mx) lb"
            case (nil, nil): return nil
            }
        }
    }

    var carrierName: String?
    var effectiveDate: String?
    var expirationDate: String?
    var lanes: [Lane]
    var classifiedType: String
    var confidence: Double
    var summary: String
    var warnings: [String]

    var isEmpty: Bool {
        carrierName == nil && effectiveDate == nil
            && expirationDate == nil && lanes.isEmpty
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Store

@MainActor
final class RateSheetStore: ObservableObject {
    enum Pane: String, CaseIterable, Identifiable {
        case calculator, surcharges, sheets, reconcile
        var id: String { rawValue }
        var label: String {
            switch self {
            case .calculator: return "Calculator"
            case .surcharges: return "Surcharges"
            case .sheets:     return "Sheets"
            case .reconcile:  return "Reconcile"
            }
        }
    }

    // Pane selection
    @Published var pane: Pane = .calculator

    // Calculator inputs (driver-tunable)
    @Published var netBarrels: Double = 160
    @Published var oneWayMiles: Double = 50
    @Published var waitTimeHours: Double = 0
    @Published var isSplitLoad: Bool = false
    @Published var isReject: Bool = false
    @Published var travelSurchargeMiles: Double = 0
    @Published var criteriaRegion: String = ""
    @Published var criteriaProduct: String = ""
    @Published var criteriaTrailer: String = ""
    @Published var criteriaSheetName: String = ""

    // EIA diesel auto-populate (FSC). nil until first fetch lands.
    @Published private(set) var diesel: RateSheetAPI.CurrentDiesel?

    // Latest live calc — driven by inputs above. nil while empty / loading.
    @Published private(set) var latest: RateSheetAPI.CalculatedRate?
    @Published private(set) var isCalculating: Bool = false

    // Active sheet selection (when nil, calculator uses defaults).
    @Published var selectedSheetId: Int? = nil
    @Published private(set) var selectedSheet: RateSheetAPI.RateSheetDetail?
    @Published private(set) var smartDefaults: RateSheetAPI.SmartTiers?
    @Published private(set) var draftTiers: [RateSheetAPI.RateTier]?
    @Published private(set) var draftSurcharges: RateSheetAPI.Surcharges?
    @Published private(set) var criteriaSaving: Bool = false
    @Published var criteriaAck: String?

    // MARK: Surcharge editor (customizable rate-sheet surcharges)
    //
    // The hard-coded surcharge defaults become editable here. Edits feed
    // the live calculator immediately (the `surcharges` override on
    // `CalculateRateInput`) and persist to the selected sheet via
    // `rateSheet.updateRateSheet` — the same JSON-backed write the web
    // platform's surcharge editor uses (server-side `rate_sheet_surcharges`).
    //
    // Seeded from `getDefaultTiers` on bootstrap (honest defaults from the
    // server, not a fabricated table), then overwritten by the selected
    // sheet's own surcharges when a sheet is attached.
    @Published var editableSurcharges = RateSheetAPI.Surcharges()
    /// The surcharges last loaded (default or selected sheet) — used to
    /// detect unsaved edits so SAVE only enables when something changed.
    @Published private(set) var savedSurcharges = RateSheetAPI.Surcharges()
    @Published private(set) var isSavingSurcharges = false
    @Published var surchargeToast: String?

    /// True when the on-screen surcharge fields differ from what's saved.
    var surchargesDirty: Bool { editableSurcharges != savedSurcharges }
    /// Persistence requires a sheet to write to (the surcharges live ON a
    /// rate sheet). With no sheet attached, edits still tune the calculator
    /// but there's nowhere to persist them — the UI says so honestly.
    var canPersistSurcharges: Bool { selectedSheetId != nil }

    // Sheets pane data
    @Published private(set) var sheets: [RateSheetAPI.RateSheetSummary] = []
    @Published private(set) var sheetsLoading: Bool = false

    // Reconcile pane data
    @Published private(set) var reconciliations: [RateSheetAPI.RateSheetSummary] = []
    @Published private(set) var stats: RateSheetAPI.ReconcileStats?
    @Published private(set) var reconLoading: Bool = false

    @Published var lastError: String?

    private let api: EusoTripAPI
    private var calcTask: Task<Void, Never>?

    init(api: EusoTripAPI = .shared) { self.api = api }

    // MARK: Bootstrap (called from .task)

    func bootstrap() async {
        // Auto-populate diesel via EIA on first appear so the FSC math
        // reflects this week's PADD baseline.
        await refreshDiesel()
        await seedDefaultSurcharges()
        await refreshCriteriaDefaults(recalculate: false)
        await recalc()
        await refreshSheets()
    }

    /// Seed the surcharge editor from the server's honest Permian
    /// baseline (`getDefaultTiers`) so the fields start from a real,
    /// known-good config rather than a hand-coded guess. Falls back to
    /// the `Surcharges()` struct defaults (which mirror the same
    /// baseline) if the call fails.
    private func seedDefaultSurcharges() async {
        if let defaults = try? await api.rateSheet.getDefaultTiers() {
            editableSurcharges = defaults.surcharges
            savedSurcharges = defaults.surcharges
        } else {
            savedSurcharges = editableSurcharges
        }
    }

    // MARK: Live calc

    func recalc() async {
        // Cancel any in-flight calc — only the most recent input wins.
        calcTask?.cancel()
        calcTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isCalculating = true
            defer { self.isCalculating = false }
            do {
                // The editor IS the surcharge source for the live calc —
                // edits show up in the pay preview before they're saved.
                // (When a sheet is attached, selecting it copies the
                // sheet's surcharges into `editableSurcharges`, so this
                // still reflects the sheet until the driver tunes it.)
                let input = RateSheetAPI.CalculateRateInput(
                    netBarrels: netBarrels,
                    oneWayMiles: oneWayMiles,
                    waitTimeHours: waitTimeHours,
                    isSplitLoad: isSplitLoad,
                    isReject: isReject,
                    travelSurchargeMiles: travelSurchargeMiles,
                    currentDieselPrice: diesel?.price,
                    rateTiers: selectedSheet?.rateTiers ?? draftTiers,
                    surcharges: editableSurcharges
                )
                let calc = try await api.rateSheet.calculateRate(input)
                if Task.isCancelled { return }
                self.latest = calc
                self.lastError = nil
            } catch {
                if !(error is CancellationError) {
                    self.lastError = "Couldn't calculate, try again."
                }
            }
        }
        await calcTask?.value
    }

    func refreshDiesel(state: String? = nil) async {
        do {
            self.diesel = try await api.rateSheet.getCurrentDiesel(state: state)
        } catch {
            // Quiet — `latest` will still compute against the server's
            // own default baseline.
        }
    }

    func refreshCriteriaDefaults(recalculate: Bool = true) async {
        do {
            let smart = try await api.rateSheet.getSmartDefaultTiers(
                region: criteriaRegion.nilIfBlank,
                product: criteriaProduct.nilIfBlank,
                trailerType: criteriaTrailer.nilIfBlank
            )
            smartDefaults = smart
            draftTiers = smart.tiers
            draftSurcharges = smart.surcharges
            criteriaAck = nil
            lastError = nil
            if recalculate { await recalc() }
        } catch {
            lastError = "Couldn't load criteria defaults."
        }
    }

    func saveCriteriaSheet(issuedBy: String) async {
        criteriaSaving = true
        defer { criteriaSaving = false }
        do {
            if draftTiers == nil || draftSurcharges == nil {
                await refreshCriteriaDefaults(recalculate: false)
            }
            let tiers = draftTiers ?? []
            let surcharges = draftSurcharges ?? RateSheetAPI.Surcharges()
            let name = criteriaSheetName.nilIfBlank
                ?? selectedSheet?.name
                ?? generatedCriteriaName()
            let today = Self.dateOnly(Date())
            if let selected = selectedSheet {
                _ = try await api.rateSheet.update(.init(
                    id: selected.id,
                    name: name,
                    region: criteriaRegion.nilIfBlank,
                    productType: criteriaProduct.nilIfBlank,
                    trailerType: criteriaTrailer.nilIfBlank,
                    rateUnit: selected.rateUnit ?? "per_barrel",
                    effectiveDate: selected.effectiveDate ?? today,
                    expirationDate: selected.expirationDate,
                    agreementId: selected.agreementId,
                    rateTiers: tiers,
                    surcharges: surcharges,
                    notes: selected.notes
                ))
                criteriaAck = "Saved \(name)."
                await selectSheet(selected.id)
            } else {
                let ack = try await api.rateSheet.create(.init(
                    name: name,
                    effectiveDate: today,
                    issuedBy: issuedBy,
                    rateTiers: tiers,
                    surcharges: surcharges,
                    fuelSurchargeIncluded: surcharges.fscEnabled,
                    notes: "Created from Rate Sheets criteria editor",
                    region: criteriaRegion.nilIfBlank,
                    productType: criteriaProduct.nilIfBlank,
                    trailerType: criteriaTrailer.nilIfBlank,
                    rateUnit: "per_barrel"
                ))
                criteriaAck = "Saved \(ack.name ?? name)."
                await refreshSheets()
                await selectSheet(ack.id)
            }
        } catch {
            lastError = "Couldn't save rate sheet criteria."
        }
    }

    private func generatedCriteriaName() -> String {
        let bits = [criteriaRegion.nilIfBlank, criteriaProduct.nilIfBlank, criteriaTrailer.nilIfBlank]
            .compactMap { $0 }
        return bits.isEmpty ? "Schedule A" : "Schedule A - \(bits.joined(separator: " / "))"
    }

    private static func dateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: Sheets pane

    func refreshSheets() async {
        sheetsLoading = true
        defer { sheetsLoading = false }
        do {
            sheets = try await api.rateSheet.listMyRateSheets(includeExpired: false)
        } catch {
            lastError = "Couldn't load sheets."
        }
    }

    func selectSheet(_ id: Int?) async {
        selectedSheetId = id
        guard let id else {
            selectedSheet = nil
            // Detaching falls back to the server's default surcharges so
            // the editor + calculator have an honest baseline again.
            await seedDefaultSurcharges()
            await recalc()
            return
        }
        do {
            selectedSheet = try await api.rateSheet.getRateSheet(id: id)
            // Load the attached sheet's own surcharges INTO the editor so
            // edits + SAVE target this sheet. `savedSurcharges` mirrors it
            // so SAVE stays disabled until the driver actually changes one.
            if let s = selectedSheet?.surcharges {
                editableSurcharges = s
                savedSurcharges = s
            }
        } catch {
            selectedSheet = nil
        }
        await recalc()
    }

    // MARK: Surcharge persistence

    /// Persist the edited surcharges to the SELECTED sheet via
    /// `rateSheet.updateRateSheet`. This is the real write the web
    /// platform uses: the server merges the surcharge schedule into the
    /// sheet, snapshots the prior version for the audit trail, and bumps
    /// the sheet version (owner/company-scoped — the server re-verifies
    /// ownership before writing). No selected sheet → nothing to persist.
    func saveSurcharges() async {
        guard let id = selectedSheetId else {
            surchargeToast = "Attach a rate sheet to save surcharges"
            return
        }
        guard surchargesDirty else { return }
        isSavingSurcharges = true
        defer { isSavingSurcharges = false }
        do {
            let input = RateSheetAPI.UpdateInput(
                id: id,
                name: nil,
                region: nil,
                productType: nil,
                trailerType: nil,
                rateUnit: nil,
                effectiveDate: nil,
                expirationDate: nil,
                agreementId: nil,
                rateTiers: nil,
                surcharges: editableSurcharges,
                notes: nil
            )
            let ack = try await api.rateSheet.update(input)
            if ack.success {
                savedSurcharges = editableSurcharges
                surchargeToast = "Surcharges saved (v\(ack.version))"
                // Re-pull the sheet so `selectedSheet.surcharges` + the
                // calculator reflect the persisted, server-canonical values.
                // `try?` flattens `getRateSheet`'s own optional, so this
                // is a single unwrap to a non-optional RateSheetDetail.
                if let fresh = try? await api.rateSheet.getRateSheet(id: id) {
                    selectedSheet = fresh
                    editableSurcharges = fresh.surcharges
                    savedSurcharges = fresh.surcharges
                }
                await recalc()
                await refreshSheets()
            } else {
                surchargeToast = "Couldn't save surcharges"
            }
        } catch {
            surchargeToast = "Couldn't save surcharges"
        }
    }

    /// Revert in-progress edits back to the last-saved schedule.
    func resetSurcharges() {
        editableSurcharges = savedSurcharges
        Task { await recalc() }
    }

    // MARK: Reconcile pane

    func refreshReconciliations() async {
        reconLoading = true
        defer { reconLoading = false }
        do {
            async let listTask = api.rateSheet.listReconciliations(limit: 30)
            async let statsTask = api.rateSheet.getStats()
            let (l, s) = try await (listTask, statsTask)
            self.reconciliations = l
            self.stats = s
        } catch {
            lastError = "Couldn't load reconciliations."
        }
    }
}

// MARK: - Screen root

struct MeRateSheet: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = RateSheetStore()

    /// Upload-via-file-picker state. Driver picks a Schedule A PDF /
    /// image from Files / Photos; we round-trip through
    /// `documentManagement.uploadDocument` with type `"rate_sheet"`
    /// so the same OCR + Gemini classification pipeline that handles
    /// CDL / TWIC / insurance also tags it as a rate sheet, and the
    /// existing `rateSheet.listMyRateSheets` query picks it up on
    /// the next refresh.
    @State private var showUploadPicker: Bool = false
    @State private var uploadingName: String?
    @State private var uploadError: String?

    /// The rate-table structure ESANG extracted from the most-recently
    /// uploaded Schedule A. Surfaced in the Sheets pane so the driver
    /// sees the lanes / rates / weight bands / effective dates that
    /// were lifted out of the document — before this was raw image
    /// storage with nothing visible until the carrier published a
    /// machine-readable sheet.
    @State private var extracted: ExtractedRateTable?
    /// Phase label shown in the upload bar while the added
    /// classification pass runs ahead of the real upload.
    @State private var uploadPhase: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            paneTabs
            paneBody
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, 56)
        .task { await store.bootstrap() }
        .refreshable {
            switch store.pane {
            case .calculator: await store.recalc()
            case .surcharges: await store.recalc()
            case .sheets:     await store.refreshSheets()
            case .reconcile:  await store.refreshReconciliations()
            }
        }
        // RealtimeService → rate sheets + reconciliation rows refresh
        // when new sheets land from carriers or settlements clear.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.refreshSheets() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.refreshSheets() }
        }
        .fileImporter(
            isPresented: $showUploadPicker,
            allowedContentTypes: [.pdf, .image, .commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFilePick(result)
        }
        .alert("Upload failed", isPresented: Binding(
            get: { uploadError != nil },
            set: { if !$0 { uploadError = nil } }
        )) {
            Button("OK", role: .cancel) { uploadError = nil }
        } message: {
            Text(uploadError ?? "")
        }
        // Surcharge save / reset confirmation toast.
        .overlay(alignment: .bottom) {
            if let toast = store.surchargeToast {
                Text(toast)
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .background(palette.bgCard.opacity(0.96))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .padding(.bottom, Space.s6)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.surchargeToast)
        .onChange(of: store.surchargeToast) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run { store.surchargeToast = nil }
            }
        }
    }

    // MARK: Upload pipeline

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            uploadError = err.eusoUserCopy
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await uploadRateSheet(at: url) }
        }
    }

    private func uploadRateSheet(at url: URL) async {
        // The fileImporter returns a security-scoped URL — we must
        // call startAccessingSecurityScopedResource before reading or
        // the file read returns an empty Data on physical devices.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent
        uploadingName = name
        uploadError = nil
        defer { uploadingName = nil; uploadPhase = nil }

        do {
            let data = try Data(contentsOf: url)
            let mime = mimeType(for: url)
            let base64 = data.base64EncodedString()
            let driverId = session.user?.id ?? ""

            // ── ADDED PASS: run the document-intelligence spine FIRST so
            // we extract the rate-table structure (lanes · rates ·
            // weight bands · effective dates) into the screen, then
            // store. Classification is best-effort — a failure here
            // never blocks the real upload (the doc still lands and the
            // server-side pipeline tags it).
            uploadPhase = "Reading rate table…"
            if let routerMime = DocumentRouterAPI.MimeType(rawValue: mime) {
                do {
                    let resp = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                        documentBase64: base64,
                        mimeType: routerMime,
                        callerContext: "driver Schedule A rate sheet - extract lanes, rates, weight bands, effective + expiration dates"
                    )
                    extracted = Self.parseRateTable(from: resp)
                } catch {
                    // Quiet: extraction is additive. The real upload below
                    // is the source of truth; we just lose the preview.
                }
            }

            // ── REAL UPLOAD (preserved verbatim) — stores the document
            // so `rateSheet.listMyRateSheets` picks it up on refresh.
            uploadPhase = "Storing document…"
            _ = try await EusoTripAPI.shared.documentManagement.uploadDocument(
                name: name,
                type: "rate_sheet",
                mimeType: mime,
                size: data.count,
                fileData: base64,
                entityType: "driver",
                entityId: driverId,
                tags: ["rate-sheet", "schedule-a"],
                expiresAt: nil
            )
            await store.refreshSheets()
        } catch {
            uploadError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Build the typed rate table from the classifier envelope.
    /// `lanes` arrives as a JSON-string array (the server stringifies
    /// non-scalar `extractedFields` so the wire stays scalar-keyed);
    /// we decode it back into typed rows. Falls back gracefully when
    /// the model emits a single-lane flat shape instead of an array.
    private static func parseRateTable(
        from resp: DocumentRouterAPI.ClassifyResponse
    ) -> ExtractedRateTable {
        let f: [String: String] = resp.extractedFields.compactMapValues { $0.asString }

        var lanes: [ExtractedRateTable.Lane] = []
        if let raw = f["lanes"], let data = raw.data(using: .utf8) {
            // Each lane object → [String: FieldValue] so origin/dest
            // (strings) and rate/min/max (numbers) both survive.
            if let arr = try? JSONDecoder().decode([[String: DocumentRouterAPI.FieldValue]].self, from: data) {
                lanes = arr.map { obj in
                    ExtractedRateTable.Lane(
                        origin: obj["origin"]?.asString,
                        destination: obj["destination"]?.asString,
                        rate: obj["rate"]?.asString,
                        equipment: obj["equipment"]?.asString,
                        minWeight: obj["minWeight"]?.asString,
                        maxWeight: obj["maxWeight"]?.asString
                    )
                }
            }
        }
        // Flat single-lane fallback: model put origin/destination/rate
        // at the top level instead of inside a `lanes` array.
        if lanes.isEmpty,
           f["origin"] != nil || f["destination"] != nil || f["rate"] != nil {
            lanes = [ExtractedRateTable.Lane(
                origin: f["origin"],
                destination: f["destination"],
                rate: f["rate"],
                equipment: f["equipment"],
                minWeight: f["minWeight"],
                maxWeight: f["maxWeight"]
            )]
        }

        return ExtractedRateTable(
            carrierName: f["carrierName"],
            effectiveDate: f["effectiveDate"],
            expirationDate: f["expirationDate"],
            lanes: lanes,
            classifiedType: resp.classifiedType,
            confidence: resp.confidence,
            summary: resp.summary,
            warnings: resp.warnings
        )
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":  return "application/pdf"
        case "png":  return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "heic": return "image/heic"
        case "csv":  return "text/csv"
        case "txt":  return "text/plain"
        default:     return "application/octet-stream"
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rate Sheets")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Schedule A · live pay preview · reconciliation")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
        }
    }

    // MARK: Pane tabs

    private var paneTabs: some View {
        // Four panes now (added Surcharges) — scroll horizontally so the
        // chips never truncate on narrow devices. The chip styling is
        // unchanged from the original design language.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(RateSheetStore.Pane.allCases) { p in
                    Button {
                        store.pane = p
                        if p == .reconcile && store.reconciliations.isEmpty {
                            Task { await store.refreshReconciliations() }
                        }
                    } label: {
                        Text(p.label)
                            .font(EType.bodyStrong)
                            .foregroundStyle(p == store.pane ? .white : palette.textPrimary)
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, 8)
                            .background(p == store.pane
                                        ? AnyShapeStyle(LinearGradient.diagonal)
                                        : AnyShapeStyle(palette.bgCardSoft))
                            .overlay(
                                Capsule().stroke(palette.borderFaint, lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Pane body

    @ViewBuilder
    private var paneBody: some View {
        switch store.pane {
        case .calculator: calculatorPane
        case .surcharges: surchargesPane
        case .sheets:     sheetsPane
        case .reconcile:  reconcilePane
        }
    }

    // MARK: Calculator pane

    @ViewBuilder
    private var calculatorPane: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let diesel = store.diesel {
                    dieselChip(diesel)
                }
                criteriaCard
                inputsCard
                if let calc = store.latest {
                    heroPay(calc)
                    breakdownCard(calc)
                } else if store.isCalculating {
                    HStack {
                        ProgressView()
                        Text("Calculating…")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(Space.s3)
                }
                if let sheet = store.selectedSheet {
                    activeSheetCard(sheet)
                }
                Color.clear.frame(height: 172)
            }
        }
    }

    private func dieselChip(_ d: RateSheetAPI.CurrentDiesel) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text(String(format: "$%.2f / gal · %@",
                        d.price, d.padd ?? "PADD3"))
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text("· \(d.source.uppercased())")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
        .background(palette.bgCardSoft)
        .overlay(Capsule().stroke(palette.borderFaint))
        .clipShape(Capsule())
    }

    private var criteriaCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CRITERIA")
                            .font(EType.micro)
                            .tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        Text(store.selectedSheet?.name ?? "Custom Schedule A")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let ack = store.criteriaAck {
                        Text(ack)
                            .font(EType.micro.weight(.heavy))
                            .tracking(0.4)
                            .foregroundStyle(Brand.success)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                TextField("Sheet name", text: $store.criteriaSheetName)
                    .textFieldStyle(.plain)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, 10)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint.opacity(0.6)))

                HStack(spacing: Space.s2) {
                    criteriaMenu(
                        label: "Region",
                        value: store.criteriaRegion.nilIfBlank ?? "Any",
                        options: store.smartDefaults?.availableRegions.map { ($0.key, $0.label) } ?? []
                    ) { key in
                        store.criteriaRegion = key
                        Task { await store.refreshCriteriaDefaults() }
                    }
                    criteriaMenu(
                        label: "Product",
                        value: store.criteriaProduct.nilIfBlank ?? "Any",
                        options: store.smartDefaults?.availableProducts.map { ($0.name, $0.name) } ?? []
                    ) { key in
                        store.criteriaProduct = key
                        Task { await store.refreshCriteriaDefaults() }
                    }
                    criteriaMenu(
                        label: "Trailer",
                        value: store.criteriaTrailer.nilIfBlank ?? "Any",
                        options: store.smartDefaults?.availableTrailers.map { ($0.key, $0.key.replacingOccurrences(of: "_", with: " ").capitalized) } ?? []
                    ) { key in
                        store.criteriaTrailer = key
                        Task { await store.refreshCriteriaDefaults() }
                    }
                }

                HStack(spacing: Space.s2) {
                    if let tiers = store.draftTiers, !tiers.isEmpty {
                        Text("\(tiers.count) tier\(tiers.count == 1 ? "" : "s")")
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    if let fsc = store.draftSurcharges?.fscEnabled {
                        Text(fsc ? "FSC on" : "FSC off")
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(fsc ? Brand.success : palette.textTertiary)
                    }
                    Spacer()
                    Button {
                        Task {
                            await store.saveCriteriaSheet(issuedBy: session.user?.name ?? "EusoTrip account")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if store.criteriaSaving {
                                ProgressView().controlSize(.mini).tint(.white)
                            } else {
                                Image(systemName: "tray.and.arrow.down.fill")
                            }
                            Text(store.selectedSheet == nil ? "Save" : "Update")
                        }
                        .font(EType.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 8)
                        .background(LinearGradient.diagonal, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.criteriaSaving)
                }
            }
        }
    }

    private func criteriaMenu(
        label: String,
        value: String,
        options: [(String, String)],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        Menu {
            Button("Any \(label.lowercased())") { onSelect("") }
            ForEach(options, id: \.0) { option in
                Button(option.1) { onSelect(option.0) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 4) {
                    Text(value)
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint.opacity(0.6)))
        }
    }

    private var inputsCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("INPUTS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)

                stepperRow(
                    label: "Net barrels",
                    value: $store.netBarrels,
                    range: 0...600, step: 5, fmt: "%.0f BBL"
                )
                stepperRow(
                    label: "One-way miles",
                    value: $store.oneWayMiles,
                    range: 0...500, step: 1, fmt: "%.0f mi"
                )
                stepperRow(
                    label: "Wait time",
                    value: $store.waitTimeHours,
                    range: 0...8, step: 0.5, fmt: "%.1f hr"
                )
                stepperRow(
                    label: "Travel surcharge miles",
                    value: $store.travelSurchargeMiles,
                    range: 0...100, step: 1, fmt: "%.0f mi"
                )
                Toggle(isOn: $store.isSplitLoad) {
                    Text("Split load")
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                }
                .toggleStyle(GradientToggleStyle())
                Toggle(isOn: $store.isReject) {
                    Text("Reject (numbered ticket)")
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                }
                .toggleStyle(GradientToggleStyle())
            }
        }
        .onChange(of: store.netBarrels) { _, _ in Task { await store.recalc() } }
        .onChange(of: store.oneWayMiles) { _, _ in Task { await store.recalc() } }
        .onChange(of: store.waitTimeHours) { _, _ in Task { await store.recalc() } }
        .onChange(of: store.isSplitLoad) { _, _ in Task { await store.recalc() } }
        .onChange(of: store.isReject) { _, _ in Task { await store.recalc() } }
        .onChange(of: store.travelSurchargeMiles) { _, _ in Task { await store.recalc() } }
    }

    private func stepperRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        fmt: String
    ) -> some View {
        HStack {
            Text(label)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(String(format: fmt, value.wrappedValue))
                .font(EType.bodyStrong.monospacedDigit())
                .foregroundStyle(palette.textPrimary)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .fixedSize()
        }
    }

    private func heroPay(_ c: RateSheetAPI.CalculatedRate) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("ESTIMATED PAY")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(String(format: "$%.2f", c.totalAmount))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text(String(format: "$%.2f / BBL · base $%.2f", c.ratePerBarrel, c.baseAmount))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
        }
    }

    private func breakdownCard(_ c: RateSheetAPI.CalculatedRate) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("BREAKDOWN")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                ForEach(Array(c.breakdown.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(EType.body.monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func activeSheetCard(_ s: RateSheetAPI.RateSheetDetail) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 2) {
                Text("ACTIVE SHEET")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(s.name ?? "Unnamed sheet")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                if let r = s.region, let p = s.productType {
                    Text("\(r) · \(p) · v\(s.version)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Button("Detach (use defaults)") {
                    Task { await store.selectSheet(nil) }
                }
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.top, 4)
            }
        }
    }

    // MARK: Surcharges pane (customizable rate-sheet surcharges)
    //
    // The previously hard-coded surcharge values (wait-time rate, split-
    // load fee, reject fee, FSC baseline, travel surcharge, etc.) are now
    // editable fields. Edits feed the live calculator immediately; SAVE
    // persists them to the attached rate sheet via `rateSheet.updateRateSheet`
    // — the same JSON-backed write the web platform's surcharge editor uses.

    @ViewBuilder
    private var surchargesPane: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                surchargeContextBanner
                fscCard
                accessorialCard
                optionalFeesCard
                Color.clear.frame(height: Space.s8)
            }
        }
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
    }

    /// Tells the driver exactly where a SAVE lands: onto the attached
    /// sheet (named, real persistence) or — with no sheet attached —
    /// that edits tune the calculator only until they pick/upload a sheet.
    private var surchargeContextBanner: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: store.canPersistSurcharges ? "doc.text.fill" : "info.circle")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(store.canPersistSurcharges ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Brand.warning))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                if store.canPersistSurcharges, let sheet = store.selectedSheet {
                    Text("Editing surcharges for")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(sheet.name ?? "Unnamed sheet") · v\(sheet.version)")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                } else {
                    Text("No sheet attached")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Edits tune the calculator live. Attach a rate sheet in Sheets to save them.")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Fuel surcharge schedule (FSC).
    private var fscCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                surchargeSectionHeader("FUEL SURCHARGE (FSC)")
                Toggle(isOn: surchargeBinding(\.fscEnabled)) {
                    Text("FSC enabled")
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                }
                .toggleStyle(GradientToggleStyle())

                if store.editableSurcharges.fscEnabled {
                    surchargeField(
                        "Baseline diesel",
                        unit: "$/gal",
                        value: surchargeBinding(\.fscBaselineDieselPrice)
                    )
                    surchargeField(
                        "Truck efficiency",
                        unit: "mpg",
                        value: surchargeBinding(\.fscMilesPerGallon)
                    )
                    if let live = store.diesel {
                        Text(String(format: "Live EIA diesel: $%.2f / gal · PADD %@", live.price, live.padd ?? "3"))
                            .font(EType.micro)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
    }

    /// Per-load accessorial fees (wait time, split, reject, travel, min bbl).
    private var accessorialCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                surchargeSectionHeader("ACCESSORIALS")
                surchargeField(
                    "Wait-time rate",
                    unit: "$/hr",
                    value: surchargeBinding(\.waitTimeRatePerHour)
                )
                surchargeField(
                    "Free wait time",
                    unit: "hr",
                    value: surchargeBinding(\.waitTimeFreeHours)
                )
                surchargeField(
                    "Split-load fee",
                    unit: "$",
                    value: surchargeBinding(\.splitLoadFee)
                )
                surchargeField(
                    "Reject fee",
                    unit: "$",
                    value: surchargeBinding(\.rejectFee)
                )
                surchargeField(
                    "Travel surcharge",
                    unit: "$/mi",
                    value: surchargeBinding(\.travelSurchargePerMile)
                )
                surchargeField(
                    "Minimum barrels",
                    unit: "BBL",
                    value: surchargeBinding(\.minimumBarrels)
                )
            }
        }
    }

    /// Optional lease-road / multiple-gates fees (nil until set).
    private var optionalFeesCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                surchargeSectionHeader("OPTIONAL FEES")
                Text("Left blank when your carrier doesn't bill them.")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                optionalSurchargeField(
                    "Long-lease road fee",
                    unit: "$",
                    value: optionalSurchargeBinding(\.longLeaseRoadFee)
                )
                optionalSurchargeField(
                    "Multiple-gates fee",
                    unit: "$",
                    value: optionalSurchargeBinding(\.multipleGatesFee)
                )
            }
        }
    }

    private func surchargeSectionHeader(_ text: String) -> some View {
        Text(text)
            .font(EType.micro).tracking(0.8)
            .foregroundStyle(palette.textTertiary)
    }

    /// One editable surcharge row: label + trailing decimal field + unit.
    private func surchargeField(
        _ label: String,
        unit: String,
        value: Binding<Double>
    ) -> some View {
        HStack {
            Text(label)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            HStack(spacing: 4) {
                TextField("0", text: doubleText(value))
                    .font(EType.bodyStrong.monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                    .keyboardType(.decimalPad)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                Text(unit)
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 36, alignment: .leading)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 6)
            .overlay(Capsule().stroke(palette.borderFaint, lineWidth: 1))
        }
    }

    /// Optional-double variant: empty field = nil (fee not billed).
    private func optionalSurchargeField(
        _ label: String,
        unit: String,
        value: Binding<Double?>
    ) -> some View {
        HStack {
            Text(label)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            HStack(spacing: 4) {
                TextField("—", text: optionalDoubleText(value))
                    .font(EType.bodyStrong.monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                    .keyboardType(.decimalPad)
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                Text(unit)
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 36, alignment: .leading)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 6)
            .overlay(Capsule().stroke(palette.borderFaint, lineWidth: 1))
        }
    }

    /// SAVE / RESET bar, pinned to the bottom of the surcharges pane.
    /// SAVE is enabled only when there are unsaved edits AND a sheet is
    /// attached to persist into (honest: nothing to save against otherwise).
    private var saveBar: some View {
        HStack(spacing: Space.s2) {
            if store.surchargesDirty {
                Button {
                    store.resetSurcharges()
                } label: {
                    Text("Reset")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s3)
                        .overlay(Capsule().stroke(palette.borderFaint, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Button {
                Task { await store.saveSurcharges() }
            } label: {
                HStack(spacing: Space.s2) {
                    if store.isSavingSurcharges {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    Text(store.canPersistSurcharges ? "Save surcharges" : "Attach a sheet to save")
                        .font(EType.bodyStrong)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s3)
                .background(
                    (store.surchargesDirty && store.canPersistSurcharges)
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.tintNeutral.opacity(0.5))
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!store.surchargesDirty || !store.canPersistSurcharges || store.isSavingSurcharges)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(.ultraThinMaterial)
    }

    // MARK: Surcharge field bindings (String <-> Double bridges)

    /// A two-way binding into the editable surcharge struct that re-runs
    /// the live calculator on every change so the pay preview tracks edits.
    private func surchargeBinding<V>(
        _ keyPath: WritableKeyPath<RateSheetAPI.Surcharges, V>
    ) -> Binding<V> {
        Binding(
            get: { store.editableSurcharges[keyPath: keyPath] },
            set: {
                store.editableSurcharges[keyPath: keyPath] = $0
                Task { await store.recalc() }
            }
        )
    }

    private func optionalSurchargeBinding(
        _ keyPath: WritableKeyPath<RateSheetAPI.Surcharges, Double?>
    ) -> Binding<Double?> {
        Binding(
            get: { store.editableSurcharges[keyPath: keyPath] },
            set: {
                store.editableSurcharges[keyPath: keyPath] = $0
                Task { await store.recalc() }
            }
        )
    }

    /// Bridge a Double binding to the TextField's String. Parses on commit;
    /// keeps the field usable mid-typing (e.g. "3." before the decimals).
    private func doubleText(_ value: Binding<Double>) -> Binding<String> {
        Binding(
            get: {
                let v = value.wrappedValue
                // Whole numbers print clean (50, not 50.0); fractions keep 2dp.
                return v == v.rounded()
                    ? String(format: "%.0f", v)
                    : String(format: "%.2f", v)
            },
            set: { text in
                let cleaned = text.replacingOccurrences(of: ",", with: "")
                if let d = Double(cleaned) { value.wrappedValue = d }
                else if cleaned.isEmpty { value.wrappedValue = 0 }
            }
        )
    }

    private func optionalDoubleText(_ value: Binding<Double?>) -> Binding<String> {
        Binding(
            get: {
                guard let v = value.wrappedValue else { return "" }
                return v == v.rounded()
                    ? String(format: "%.0f", v)
                    : String(format: "%.2f", v)
            },
            set: { text in
                let cleaned = text.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: ",", with: "")
                if cleaned.isEmpty { value.wrappedValue = nil }
                else if let d = Double(cleaned) { value.wrappedValue = d }
            }
        )
    }

    // MARK: Sheets pane

    @ViewBuilder
    private var sheetsPane: some View {
        VStack(spacing: Space.s3) {
            uploadBar
            if let table = extracted, !table.isEmpty {
                extractedTableCard(table)
            }
            if store.sheetsLoading && store.sheets.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(Space.s4)
            } else if store.sheets.isEmpty {
                EusoEmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No rate sheets yet",
                    subtitle: "Upload your carrier's Schedule A above, or wait for your carrier to publish one. Once attached, the calculator pulls its tiers automatically."
                )
                .padding(.top, Space.s4)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(store.sheets) { s in
                            sheetRow(s)
                        }
                        Color.clear.frame(height: Space.s8)
                    }
                }
            }
        }
    }

    /// "Upload rate sheet" gradient button + in-flight state. Lets the
    /// driver attach a Schedule A PDF/image directly from Files —
    /// classified server-side by the same Gemini + VIGA pipeline that
    /// classifies CDL / TWIC / insurance documents.
    private var uploadBar: some View {
        Button {
            showUploadPicker = true
        } label: {
            HStack(spacing: Space.s2) {
                if uploadingName != nil {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white)
                    Text(uploadPhase ?? "Uploading \(uploadingName ?? "")…")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else {
                    Image(systemName: "arrow.up.doc.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Upload rate sheet")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(uploadingName != nil)
    }

    // MARK: Extracted rate table (document-intelligence pass)

    /// Renders the rate-table structure ESANG lifted out of the
    /// uploaded Schedule A: header (carrier · effective/expiration ·
    /// confidence), then one row per lane with its rate, equipment,
    /// and weight band.
    private func extractedTableCard(_ t: ExtractedRateTable) -> some View {
        let conf = Int((t.confidence * 100).rounded())
        return ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                // Title row
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("EXTRACTED RATE TABLE")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(conf)%")
                        .font(EType.micro.weight(.heavy)).tracking(0.6)
                        .foregroundStyle(conf >= 85 ? Brand.success : conf >= 60 ? Brand.warning : Brand.danger)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill((conf >= 85 ? Brand.success : conf >= 60 ? Brand.warning : Brand.danger).opacity(0.12)))
                }

                if let carrier = t.carrierName?.nilIfBlank {
                    Text(carrier)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                }

                // Effective / expiration dates
                if t.effectiveDate?.nilIfBlank != nil || t.expirationDate?.nilIfBlank != nil {
                    HStack(spacing: Space.s4) {
                        if let eff = t.effectiveDate?.nilIfBlank {
                            extractedDate(label: "EFFECTIVE", value: eff, color: Brand.success)
                        }
                        if let exp = t.expirationDate?.nilIfBlank {
                            extractedDate(label: "EXPIRES", value: exp, color: Brand.warning)
                        }
                        Spacer(minLength: 0)
                    }
                }

                if !t.summary.isEmpty {
                    Text(t.summary)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Lanes
                if t.lanes.isEmpty {
                    Text("No lanes parsed, the document stored, but its rate table wasn't machine-readable. Open it in Sheets once your carrier publishes a structured version.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Divider().overlay(palette.borderFaint)
                    Text("LANES · \(t.lanes.count)")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    VStack(spacing: 6) {
                        ForEach(t.lanes) { lane in
                            laneRow(lane)
                        }
                    }
                }

                // Warnings
                ForEach(Array(t.warnings.prefix(3).enumerated()), id: \.offset) { _, w in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Brand.warning)
                        Text(w)
                            .font(EType.caption)
                            .foregroundStyle(Brand.warning)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func extractedDate(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(EType.micro).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func laneRow(_ lane: ExtractedRateTable.Lane) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 28, height: 28)
                .background(Circle().fill(palette.bgCardSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(lane.laneLabel)
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let eq = lane.equipment?.nilIfBlank {
                        metaChip(eq, system: "shippingbox")
                    }
                    if let band = lane.weightBand {
                        metaChip(band, system: "scalemass")
                    }
                }
            }
            Spacer(minLength: 0)
            if let rate = lane.rate?.nilIfBlank {
                Text(formattedRate(rate))
                    .font(EType.bodyStrong.monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private func metaChip(_ text: String, system: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: system)
                .font(.system(size: 8, weight: .heavy))
            Text(text)
                .font(EType.micro.weight(.semibold))
        }
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(palette.bgCardSoft))
    }

    /// Server emits rate as a normalized number string (e.g. "2.85").
    /// Prefix "$" when it parses as a number; otherwise show verbatim.
    private func formattedRate(_ raw: String) -> String {
        if let d = Double(raw) {
            return String(format: "$%.2f", d)
        }
        return raw
    }

    private func sheetRow(_ s: RateSheetAPI.RateSheetSummary) -> some View {
        Button {
            Task {
                await store.selectSheet(s.id)
                store.pane = .calculator
            }
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(palette.bgCardSoft))
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.name ?? "Unnamed sheet")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(s.createdAt.prefix(10))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                StatusPill(
                    text: (s.status ?? "-").capitalized,
                    kind: pillKind(s.status)
                )
                if store.selectedSheetId == s.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }

    private func pillKind(_ raw: String?) -> StatusPill.Kind {
        switch (raw ?? "").lowercased() {
        case "active":  return .success
        case "expired": return .warning
        case "draft":   return .neutral
        default:        return .info
        }
    }

    // MARK: Reconcile pane

    @ViewBuilder
    private var reconcilePane: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let s = store.stats {
                    statsCard(s)
                }
                if store.reconLoading && store.reconciliations.isEmpty {
                    ProgressView().padding()
                } else if store.reconciliations.isEmpty {
                    EusoEmptyState(
                        systemImage: "tablecells",
                        title: "No reconciliations yet",
                        subtitle: "Generated billing statements live here once a period closes."
                    )
                } else {
                    Text("STATEMENTS")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    VStack(spacing: 6) {
                        ForEach(store.reconciliations) { r in
                            reconRow(r)
                        }
                    }
                }
                Color.clear.frame(height: Space.s8)
            }
        }
    }

    private func statsCard(_ s: RateSheetAPI.ReconcileStats) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("RECONCILIATION STATS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: Space.s3) {
                    MetricTile(label: "Statements", value: "\(s.totalStatements ?? 0)")
                    MetricTile(label: "Total paid",
                               value: String(format: "$%.0f", s.totalPaid ?? 0))
                    MetricTile(label: "Pending", value: "\(s.pending ?? 0)")
                }
            }
        }
    }

    private func reconRow(_ r: RateSheetAPI.RateSheetSummary) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "tablecells")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 32, height: 32)
                .background(Circle().fill(palette.bgCardSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name ?? "Statement")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(r.createdAt.prefix(10))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            StatusPill(text: (r.status ?? "-").capitalized,
                       kind: pillKind(r.status))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }
}

// MARK: - Screen wrapper (registered in ContentView ScreenRegistry)

struct MeRateSheetScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeRateSheet()
        } nav: {
            BottomNav(
                leading: driverNavLeading_104(),
                trailing: driverNavTrailing_104(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_104() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_104() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("104 · Rate Sheets · Night") {
    MeRateSheetScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("104 · Rate Sheets · Afternoon") {
    MeRateSheetScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
