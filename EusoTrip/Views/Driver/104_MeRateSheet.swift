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
        case calculator, sheets, reconcile
        var id: String { rawValue }
        var label: String {
            switch self {
            case .calculator: return "Calculator"
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

    // EIA diesel auto-populate (FSC). nil until first fetch lands.
    @Published private(set) var diesel: RateSheetAPI.CurrentDiesel?

    // Latest live calc — driven by inputs above. nil while empty / loading.
    @Published private(set) var latest: RateSheetAPI.CalculatedRate?
    @Published private(set) var isCalculating: Bool = false

    // Active sheet selection (when nil, calculator uses defaults).
    @Published var selectedSheetId: Int? = nil
    @Published private(set) var selectedSheet: RateSheetAPI.RateSheetDetail?

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
        await recalc()
        await refreshSheets()
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
                let input = RateSheetAPI.CalculateRateInput(
                    netBarrels: netBarrels,
                    oneWayMiles: oneWayMiles,
                    waitTimeHours: waitTimeHours,
                    isSplitLoad: isSplitLoad,
                    isReject: isReject,
                    travelSurchargeMiles: travelSurchargeMiles,
                    currentDieselPrice: diesel?.price,
                    rateTiers: selectedSheet?.rateTiers,
                    surcharges: selectedSheet?.surcharges
                )
                let calc = try await api.rateSheet.calculateRate(input)
                if Task.isCancelled { return }
                self.latest = calc
                self.lastError = nil
            } catch {
                if !(error is CancellationError) {
                    self.lastError = "Couldn't calculate — try again."
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
            await recalc()
            return
        }
        do {
            selectedSheet = try await api.rateSheet.getRateSheet(id: id)
        } catch {
            selectedSheet = nil
        }
        await recalc()
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
        .padding(.top, Space.s3)
        .task { await store.bootstrap() }
        .refreshable {
            switch store.pane {
            case .calculator: await store.recalc()
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
    }

    // MARK: Upload pipeline

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            uploadError = err.localizedDescription
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
                        callerContext: "driver Schedule A rate sheet — extract lanes, rates, weight bands, effective + expiration dates"
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
            Spacer()
        }
    }

    // MARK: Pane body

    @ViewBuilder
    private var paneBody: some View {
        switch store.pane {
        case .calculator: calculatorPane
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
                Color.clear.frame(height: Space.s8)
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
                    Text("No lanes parsed — the document stored, but its rate table wasn't machine-readable. Open it in Sheets once your carrier publishes a structured version.")
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
                    text: (s.status ?? "—").capitalized,
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
            StatusPill(text: (r.status ?? "—").capitalized,
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
