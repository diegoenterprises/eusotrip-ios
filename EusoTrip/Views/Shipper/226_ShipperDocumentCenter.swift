//
//  226_ShipperDocumentCenter.swift
//  EusoTrip 2027 UI — Shipper · Document Center (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/226_ShipperDocumentCenter.swift. Persona: Diego
//  Usoro / Eusorone Technologies (companyId 1) per §11. Recent doc
//  rows surface the §11.2 MATRIX-50 audit-trail hex tails when
//  present (LD-260427-A38FB12C7E Houston→Dallas tanker BOL,
//  Eusotrans LLC USDOT 3 194 882 COI, LD-260427-7C3A09F18B LA→Phoenix
//  reefer rate-con).
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · DOCUMENT CENTER / "{N} DOCS · {C} CATEGORIES"
//    2. Title block      Documents (34pt) / "Eusorone Technologies · master library by category"
//    3. IridescentHairline
//    4. KPI summary      3-cell · TOTAL DOCS (gradient) · EXPIRES SOON (warn) · STORAGE
//    5. Search row       "Search by load ID, partner, or type…" + gradient + capsule (upload)
//    6. Filter chips     All / BOL / COI / Rate Con / Tax with derived counts
//    7. RECENT section   eyebrow + 3-row recent card (last 3 by uploadedAt)
//    8. BY CATEGORY      eyebrow + 2x2 status-rimmed tile grid (gradient/warn/success/info)
//    9. Retention footer
//
//  Real wiring preserved: `documents.getAll(search:category:)` +
//  `documents.getStats()` + `documents.getCategories()` +
//  `documents.delete(id:)` via `ShipperDocumentCenterStore`. Tap-row
//  fires `MeAction.fire("shipper.document.preview")` for the
//  Continuity hand-off to the web PDF viewer.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2139 — No `isFavorite` flag on Document. Favorite star
//                paints conditionally for COI / insurance / contract
//                rows as a pinning proxy until backend adds the flag.
//    EUSO-2140 — `Document` envelope ships `size: Int` but no
//                version, expirationDate, or last-modified-by. Meta
//                line surfaces only size + uploadedAt; expiry copy
//                is inferred from `status == "expiring"`.
//    EUSO-2141 — No storage-usage aggregate on `documents.getStats`.
//                STORAGE KPI cell paints "—" placeholder until
//                backend ships `storageBytes` + `planUsedPct`.
//
//  Doctrine refs: §2 ME-tab nav (handled by ContentView); §3
//  numbers-first copy; §4.3 single iridescent hairline; §11 / §11.2
//  Diego canon + audit-trail; §15.2 status-rimmed category tiles;
//  §16 KPI summary card; §17.2 download-pill grammar; §19.2 file-
//  scoped paint extensions; §20.4 no dead buttons; §22.2 textTertiary
//  informational counter.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Filter (wireframe canon)

private enum DocFilter: String, CaseIterable, Identifiable {
    case all
    case bol
    case coi
    case rateCon
    case tax

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:     return "All"
        case .bol:     return "BOL"
        case .coi:     return "COI"
        case .rateCon: return "Rate Con"
        case .tax:     return "Tax"
        }
    }

    /// Server-side category id (or nil for All). Server emits free-form
    /// category names so we match keywords client-side as well.
    var serverCategory: String? { nil }

    var matchKeywords: [String] {
        switch self {
        case .all:     return []
        case .bol:     return ["bol", "pod", "shipping"]
        case .coi:     return ["coi", "insurance", "liability"]
        case .rateCon: return ["rate_con", "rate", "rc", "rate confirmation"]
        case .tax:     return ["tax", "w9", "1099"]
        }
    }
}

// MARK: - Status helpers

private struct DocumentStatusStyle {
    let label: String
    let color: Color

    static func from(_ raw: String) -> DocumentStatusStyle {
        switch raw.lowercased() {
        case "active":     return .init(label: "Active",   color: Brand.success)
        case "valid":      return .init(label: "Valid",    color: Brand.success)
        case "expiring":   return .init(label: "Expiring", color: Brand.warning)
        case "expired":    return .init(label: "Expired",  color: Brand.danger)
        case "pending":    return .init(label: "Pending",  color: Brand.info)
        case "rejected":   return .init(label: "Rejected", color: Brand.danger)
        default:           return .init(label: raw.capitalized, color: Brand.neutral)
        }
    }
}

// MARK: - Store (preserved + extended)

@MainActor
final class ShipperDocumentCenterStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var search: String = ""
    @Published fileprivate var filter: DocFilter = .all {
        didSet {
            if oldValue != filter { Task { await load() } }
        }
    }
    @Published private(set) var documents: [DocumentsAPI.Document] = []
    @Published private(set) var stats: DocumentsAPI.Stats? = nil
    @Published private(set) var categories: [DocumentsAPI.Category] = []
    @Published private(set) var deleting: Set<String> = []

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        async let docs = api.documents.getAll(search: search.isEmpty ? nil : search,
                                              category: nil)
        async let stats: DocumentsAPI.Stats? = (try? await api.documents.getStats()) ?? nil
        async let cats: [DocumentsAPI.Category] = (try? await api.documents.getCategories()) ?? []
        do {
            self.documents  = try await docs
            self.stats      = await stats
            self.categories = await cats
            self.phase      = .loaded
        } catch {
            self.phase = .error("Couldn't load documents.")
        }
    }

    func filtered() -> [DocumentsAPI.Document] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let searched: [DocumentsAPI.Document]
        if q.isEmpty {
            searched = documents
        } else {
            searched = documents.filter { d in
                d.name.lowercased().contains(q) || d.category.lowercased().contains(q)
            }
        }
        guard !filter.matchKeywords.isEmpty else { return searched }
        return searched.filter { d in
            let cat = d.category.lowercased()
            let name = d.name.lowercased()
            return filter.matchKeywords.contains { k in
                cat.contains(k) || name.contains(k)
            }
        }
    }

    fileprivate func count(for filter: DocFilter) -> Int {
        if filter == .all { return documents.count }
        return documents.filter { d in
            let cat = d.category.lowercased()
            let name = d.name.lowercased()
            return filter.matchKeywords.contains { k in
                cat.contains(k) || name.contains(k)
            }
        }.count
    }

    func delete(id: String) async {
        deleting.insert(id)
        defer { deleting.remove(id) }
        _ = try? await api.documents.delete(id: id)
        await load()
    }
}

// MARK: - Screen root

struct ShipperDocumentCenter: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @StateObject private var store = ShipperDocumentCenterStore()
    /// Drives the system Files picker presented from `tapUpload()`.
    /// Replaces the prior openURL("https://app.eusotrip.com/shipper/
    /// documents/new") stub.
    @State private var showDocumentPicker: Bool = false
    @State private var uploadToast: String? = nil
    /// Drives the share sheet for `tapRow` / `tapDownload`. Each tap
    /// fetches the document bytes from the server, writes them to a
    /// tmp file, and pushes the URL into here so the system Share
    /// sheet pops with Save to Files / AirDrop / Mail / etc. Replaces
    /// the prior openURL("…/documents/{id}") + openURL("…/download")
    /// stubs.
    @State private var pendingShareDocs: [URL]? = nil
    /// Result of the homegrown document-intelligence pass on the
    /// just-picked file. Runs `documentRouter.classifyAndRoute` on the
    /// real file bytes (not just the filename) so the capture point
    /// KNOWS what the document is before it lands in the library. The
    /// review sheet surfaces the detected type + key extracted fields +
    /// any warnings honestly; low-confidence / `unknown` says so.
    @State private var pendingClassification: DocCenterClassification? = nil
    /// Latch so the review sheet only auto-presents once per scan.
    @State private var showClassificationReview: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s5)

                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        // RealtimeService → live updates refresh the document center
        // when a new doc lands (POD upload, signed contract, etc).
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await store.load() }
        }
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [.pdf, .image, .item],
            allowsMultipleSelection: false
        ) { result in
            Task { await handlePickedDocument(result) }
        }
        .sheet(isPresented: Binding(
            get: { pendingShareDocs != nil },
            set: { if !$0 { pendingShareDocs = nil } }
        )) {
            if let urls = pendingShareDocs {
                DocsCenterShareSheet(items: urls)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showClassificationReview) {
            if let c = pendingClassification {
                DocCenterClassificationReview(result: c)
                    .environment(\.palette, palette)
            }
        }
        .overlay(alignment: .top) {
            if let t = uploadToast {
                Text(t).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.green.opacity(0.92), in: Capsule())
                    .padding(.top, 12)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            await MainActor.run { uploadToast = nil }
                        }
                    }
            }
        }
    }

    /// Real upload pipeline — reads the picked file's bytes, detects
    /// the true mime from the magic bytes / UTType (not just the
    /// extension), runs the file through our homegrown document-
    /// intelligence spine (`documentRouter.classifyAndRoute`) against
    /// the actual bytes so the capture point KNOWS what the document
    /// is (classify + extract) before it lands, surfaces the detected
    /// type + key extracted fields + warnings honestly, then POSTs to
    /// `documents.upload` with the vision-derived category. Replaces
    /// the prior filename-only `aiDocProcessor.classifyDocument` hint.
    private func handlePickedDocument(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let err):
            await MainActor.run { uploadToast = "Pick failed: \(err.localizedDescription)" }
        case .success(let urls):
            guard let url = urls.first else { return }
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let mime = detectMime(url: url, data: data)
                let base64 = data.base64EncodedString()
                let dataURL = "data:\(mime);base64,\(base64)"

                // Step 1 — Document intelligence. Classify + extract on
                // the real file bytes via the vision spine so we KNOW
                // the document type instead of uploading a raw blob.
                // Best-effort: a thrown classifier error never blocks the
                // upload — we fall through to "operations" and say so.
                let classification = await classifyWithVisionSpine(
                    base64: base64,
                    mime: mime,
                    filename: url.lastPathComponent
                )
                let category = classification?.category ?? "operations"

                struct In: Encodable {
                    let name: String
                    let category: String
                    let fileData: String
                }
                struct Out: Decodable { let id: String?; let success: Bool? }
                let _: Out = try await EusoTripAPI.shared.mutation(
                    "documents.upload",
                    input: In(
                        name: url.lastPathComponent,
                        category: category,
                        fileData: dataURL
                    )
                )
                await MainActor.run {
                    uploadToast = "Uploaded \(url.lastPathComponent) → \(category)"
                    // Surface the honest detection result for review.
                    if let c = classification {
                        pendingClassification = c
                        showClassificationReview = true
                    }
                }
                await store.load()
            } catch {
                await MainActor.run {
                    uploadToast = "Upload failed: \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)"
                }
            }
        }
    }

    /// Detect the true mime type from the file's magic bytes and
    /// UTType — the extension alone lies (e.g. a `.jpg` that's really a
    /// HEIC, or a no-extension picked file). The vision router only
    /// accepts jpeg/png/webp/heic/pdf, so anything we can't positively
    /// identify as PDF/PNG/HEIC/WebP is treated as JPEG (the router's
    /// safe image default).
    private func detectMime(url: URL, data: Data) -> String {
        // Magic bytes first — most reliable.
        if data.count > 4, data[0] == 0x25, data[1] == 0x50, data[2] == 0x44, data[3] == 0x46 {
            return "application/pdf"            // %PDF
        }
        if data.count > 8, data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47 {
            return "image/png"                  // ‰PNG
        }
        if data.count > 12,
           data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46,
           data[8] == 0x57, data[9] == 0x45, data[10] == 0x42, data[11] == 0x50 {
            return "image/webp"                 // RIFF…WEBP
        }
        // UTType fallback for HEIC and friends the bytes didn't catch.
        if let t = UTType(filenameExtension: url.pathExtension.lowercased()) {
            if t.conforms(to: .pdf)  { return "application/pdf" }
            if t.conforms(to: .png)  { return "image/png" }
            if t.conforms(to: .heic) { return "image/heic" }
            if t.conforms(to: .webP) { return "image/webp" }
        }
        return "image/jpeg"
    }

    /// Runs the picked file through the homegrown document-intelligence
    /// spine (`documentRouter.classifyAndRoute`). Returns a structured
    /// classification (detected type + confidence + key extracted
    /// fields + warnings) and the mapped upload category, or `nil` if
    /// the file can't be sent to the vision router (unsupported mime)
    /// or the classifier throws — callers fall back to "operations".
    private func classifyWithVisionSpine(
        base64: String,
        mime: String,
        filename: String
    ) async -> DocCenterClassification? {
        guard let mt = DocumentRouterAPI.MimeType(rawValue: mime) else { return nil }
        do {
            let resp = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                documentBase64: base64,
                mimeType: mt,
                callerContext: "shipper document center"
            )
            // Honest fields — collapse heterogeneous values to display
            // strings, drop nulls, cap to the ones worth showing.
            let fields: [(String, String)] = resp.extractedFields
                .compactMap { key, value in
                    guard let s = value.asString, !s.isEmpty else { return nil }
                    return (prettyFieldKey(key), s)
                }
                .sorted { $0.0 < $1.0 }
            return DocCenterClassification(
                filename: filename,
                classifiedType: resp.classifiedType,
                confidence: resp.confidence,
                summary: resp.summary,
                fields: fields,
                warnings: resp.warnings,
                dispatchTarget: resp.dispatchTarget,
                category: mapTypeToCategory(resp.classifiedType, confidence: resp.confidence)
            )
        } catch {
            // Honest: surface the failure as a toast, store as
            // "operations", never fabricate a type.
            await MainActor.run {
                uploadToast = "Couldn't classify — stored as Operations · \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            }
            return nil
        }
    }

    /// Map the vision spine's `classifiedType` (60+ taxonomy) onto the
    /// existing `documents.upload` category enum (compliance,
    /// insurance, permits, contracts, invoices, bols, receipts,
    /// run_tickets, agreements, freight, operations, financial,
    /// company, vehicle, other). Low confidence or `unknown` → the
    /// neutral "operations" bucket; we never force a type we're unsure
    /// of into a specific category.
    private func mapTypeToCategory(_ raw: String, confidence: Double) -> String {
        guard confidence >= 0.55, raw != "unknown", !raw.isEmpty else { return "operations" }
        switch raw {
        case "bill_of_lading", "proof_of_delivery":
            return "bols"
        case "rate_confirmation", "load_tender", "load_csv", "customs_entry", "packing_list":
            return "freight"
        case "invoice", "freight_invoice":
            return "invoices"
        case "weight_ticket", "scale_ticket", "run_ticket":
            return "run_tickets"
        case "lumper_receipt", "fuel_receipt", "detention_receipt", "receipt":
            return "receipts"
        case "inspection_report", "dvir":
            return "compliance"
        case "us_coi", "ca_coi", "insurance_certificate":
            return "insurance"
        case "shipper_agreement", "broker_agreement", "carrier_packet",
             "factoring_agreement", "nda", "agreement":
            return "agreements"
        case "w9", "form_1099", "us_ein_letter":
            return "company"
        case "comcheck":
            return "financial"
        case let t where t.hasSuffix("_permit") || t.hasPrefix("permit"):
            return "permits"
        case let t where t.hasPrefix("us_") || t.hasPrefix("ca_") || t.hasPrefix("mx_"):
            // Driver / authority credentials → compliance bucket.
            return "compliance"
        default:
            return "operations"
        }
    }

    /// `bolNumber` → "Bol Number", `shipperName` → "Shipper Name".
    private func prettyFieldKey(_ key: String) -> String {
        var out = ""
        for ch in key {
            if ch.isUppercase, !out.isEmpty { out.append(" ") }
            out.append(ch)
        }
        return out
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · DOCUMENT CENTER")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s3)
    }

    private var counterEyebrow: String {
        let total = store.stats?.total ?? store.documents.count
        let cats = store.categories.count
        return "\(total) DOCS · \(cats) CATEGORIES"
    }

    private var counterAccessibility: String {
        let total = store.stats?.total ?? store.documents.count
        return "\(total) total documents in the master library"
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Documents")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · master library by category")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 92)
                }
            }
            .padding(.horizontal, Space.s3)
        case .error(let m):
            errorCard(m)
                .padding(.horizontal, Space.s3)
        case .loaded:
            VStack(alignment: .leading, spacing: 0) {
                kpiSummaryStrip
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s3)

                searchRow
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)

                chipRow
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s3)

                let filtered = store.filtered()
                let recent = recentRows(filtered)

                if !recent.isEmpty {
                    sectionLabel("RECENT · LAST UPLOADS · \(recent.count) OF \(filtered.count)")
                        .padding(.top, Space.s5)
                    recentCard(recent)
                        .padding(.horizontal, Space.s3)
                        .padding(.top, Space.s2)
                }

                if !store.categories.isEmpty {
                    sectionLabel("BY CATEGORY · \(store.categories.count) LIBRARIES · STATUS-RIMMED")
                        .padding(.top, Space.s5)
                    categoryGrid
                        .padding(.horizontal, Space.s3)
                        .padding(.top, Space.s2)
                }

                if filtered.isEmpty && recent.isEmpty {
                    emptyCard
                        .padding(.horizontal, Space.s3)
                        .padding(.top, Space.s4)
                }

                retentionFooter
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)
            }
        }
    }

    private func recentRows(_ docs: [DocumentsAPI.Document]) -> [DocumentsAPI.Document] {
        Array(docs.sorted(by: { $0.uploadedAt > $1.uploadedAt }).prefix(3))
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s3)
    }

    // MARK: KPI summary strip (3-cell · TOTAL DOCS / EXPIRES SOON / STORAGE)

    private var kpiSummaryStrip: some View {
        HStack(spacing: 0) {
            kpiCell(label: "TOTAL DOCS",
                    value: "\(store.stats?.total ?? store.documents.count)",
                    valueStyle: .gradient,
                    sub: nil)
            verticalSeparator
            kpiCell(label: "EXPIRES SOON",
                    value: "\(store.stats?.expiring ?? 0)",
                    valueStyle: (store.stats?.expiring ?? 0) > 0 ? .warn : .neutral,
                    sub: (store.stats?.expiring ?? 0) > 0 ? "in 30d" : "all clean")
            verticalSeparator
            // EUSO-2141 — storage aggregate not on API.
            kpiCell(label: "STORAGE",
                    value: "—",
                    valueStyle: .neutral,
                    sub: "plan pending")
        }
        .frame(minHeight: 72)
        .padding(.vertical, Space.s2)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var verticalSeparator: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 36)
    }

    private enum KpiValueStyle { case gradient, warn, neutral }

    @ViewBuilder
    private func kpiCell(label: String, value: String, valueStyle: KpiValueStyle, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Group {
                    switch valueStyle {
                    case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                    case .warn:     Text(value).foregroundStyle(Brand.warning)
                    case .neutral:  Text(value).foregroundStyle(palette.textPrimary)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                if let sub {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s4)
    }

    // MARK: Search row

    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            TextField("Search by load ID, partner, or type…", text: $store.search)
                .textFieldStyle(.plain)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { Task { await store.load() } }
            if !store.search.isEmpty {
                Button {
                    store.search = ""
                    Task { await store.load() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
            // §17.2 trailing gradient `+` capsule for upload (no dead buttons).
            Button(action: tapUpload) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Upload document")
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func tapUpload() {
        // Real action: present the system Files picker so the user
        // can pick a PDF / image / doc from on-device storage. The
        // picker handler in `pickedDocument` is wired below to
        // POST the file to the document store. Replaces the prior
        // openURL stub to a 404 web route.
        NotificationCenter.default.post(
            name: .eusoShipperDocumentUpload,
            object: nil,
            userInfo: [
                "source": "226_ShipperDocumentCenter",
                "shipperCompanyId": 1
            ]
        )
        showDocumentPicker = true
    }

    // MARK: Chip row

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DocFilter.allCases) { f in
                    chip(f, count: store.count(for: f))
                }
                Color.clear.frame(width: 16, height: 1)
            }
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [palette.bgPage.opacity(0), palette.bgPage],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 28)
            .allowsHitTesting(false)
        }
    }

    private func chip(_ f: DocFilter, count: Int) -> some View {
        let isActive = (store.filter == f)
        let label = "\(f.label) · \(count)"
        return Button(action: { tapFilter(f) }) {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .bold : .semibold))
                .foregroundStyle(isActive ? Color.white : palette.textPrimary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 7)
                .background {
                    if isActive {
                        Capsule().fill(LinearGradient.primary)
                    } else {
                        Capsule().fill(palette.bgCard)
                    }
                }
                .overlay {
                    if !isActive {
                        Capsule().strokeBorder(palette.borderFaint)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(f.label) filter")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func tapFilter(_ f: DocFilter) {
        store.filter = f
        // observability post — telemetry only; real effect is `store.filter = f` above
        NotificationCenter.default.post(
            name: .eusoShipperDocumentFilter,
            object: nil,
            userInfo: [
                "source": "226_ShipperDocumentCenter",
                "filter": f.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Recent card

    private func recentCard(_ rows: [DocumentsAPI.Document]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, doc in
                recentRow(doc)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                if idx < rows.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
        }
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func recentRow(_ d: DocumentsAPI.Document) -> some View {
        let style = DocumentStatusStyle.from(d.status)
        let isFav = isFavoriteHeuristic(d)
        return Button(action: { tapRow(d) }) {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(palette.bgCardSoft)
                    Image(systemName: categoryGlyph(d.category))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .frame(width: 36, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(palette.borderFaint)
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(d.name)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        if isFav {
                            DocStarShape().fill(Brand.hazmat).frame(width: 10, height: 10)
                        }
                        statusPill(style.label, color: style.color)
                    }
                    Text(metaSubtitle(d))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: { tapDownload(d) }) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Download \(d.name)")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DocRowStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(d.name), \(style.label), \(d.category)")
    }

    private func metaSubtitle(_ d: DocumentsAPI.Document) -> String {
        var parts: [String] = []
        parts.append(d.category.replacingOccurrences(of: "_", with: " ").capitalized)
        parts.append(formatBytes(d.size))
        if !d.uploadedAt.isEmpty {
            parts.append(relativeShort(d.uploadedAt))
        }
        if d.status.lowercased() == "expiring" {
            parts.append("expiring")
        }
        return parts.joined(separator: " · ")
    }

    private func formatBytes(_ b: Int) -> String {
        if b >= 1_048_576 {
            return String(format: "%.1f MB", Double(b) / 1_048_576.0)
        }
        if b >= 1024 {
            return String(format: "%.0f KB", Double(b) / 1024.0)
        }
        return "\(b) B"
    }

    private func relativeShort(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s/60))m ago" }
        if s < 86400 { return "\(Int(s/3600))h ago" }
        return "\(Int(s/86400))d ago"
    }

    private func isFavoriteHeuristic(_ d: DocumentsAPI.Document) -> Bool {
        // EUSO-2139 — no isFavorite flag on envelope. Pin COI / contract /
        // master-agreement docs as a relationship-grade-core heuristic.
        let cat = d.category.lowercased()
        let name = d.name.lowercased()
        return cat.contains("insurance") || cat.contains("coi")
            || cat.contains("contract") || cat.contains("master")
            || name.contains("coi") || name.contains("master")
    }

    private func categoryGlyph(_ c: String) -> String {
        switch c.lowercased() {
        case let s where s.contains("permit"):    return "lock.shield.fill"
        case let s where s.contains("insurance"): return "checkmark.shield.fill"
        case let s where s.contains("compliance"):return "checkmark.seal.fill"
        case let s where s.contains("contract"):  return "doc.text.fill"
        case let s where s.contains("invoice"):   return "creditcard.fill"
        case let s where s.contains("bol"):       return "shippingbox.fill"
        case let s where s.contains("ticket"):    return "ticket.fill"
        case let s where s.contains("rate"):      return "doc.richtext.fill"
        case let s where s.contains("tax") || s.contains("w9"): return "dollarsign.square.fill"
        default:                                   return "doc.fill"
        }
    }

    private func statusPill(_ s: String, color: Color) -> some View {
        Text(s.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    // MARK: Category grid (2x2 status-rimmed)

    private var categoryGrid: some View {
        let cats = Array(store.categories.prefix(4))
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.s2),
                GridItem(.flexible(), spacing: Space.s2),
            ],
            spacing: Space.s2
        ) {
            ForEach(Array(cats.enumerated()), id: \.element.id) { idx, c in
                categoryTile(c, family: tileFamily(for: idx, category: c))
            }
        }
    }

    private enum TileFamily { case gradient, warn, success, info }

    private func tileFamily(for index: Int, category: DocumentsAPI.Category) -> TileFamily {
        // First tile is the gradient anchor (highest count typically).
        // Insurance/COI categories paint warn (renewal-driven attention).
        // Contracts/agreements paint success. Everything else paints info.
        let n = category.name.lowercased()
        if index == 0 { return .gradient }
        if n.contains("insurance") || n.contains("coi") || n.contains("permit") { return .warn }
        if n.contains("contract") || n.contains("agreement") || n.contains("compliance") { return .success }
        return .info
    }

    @ViewBuilder
    private func categoryTile(_ c: DocumentsAPI.Category, family: TileFamily) -> some View {
        Button(action: { tapCategory(c) }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.name.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(eyebrowColor(for: family))
                Text(c.name.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(c.count)")
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(valuePaint(for: family))
                    Text("docs")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(rimPaint(for: family), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(DocRowStyle())
    }

    private func eyebrowColor(for family: TileFamily) -> Color {
        switch family {
        case .gradient: return palette.textSecondary
        case .warn:     return Brand.warning
        case .success:  return Brand.success
        case .info:     return Brand.info
        }
    }

    private func rimPaint(for family: TileFamily) -> AnyShapeStyle {
        switch family {
        case .gradient: return AnyShapeStyle(LinearGradient.diagonal.opacity(0.55))
        case .warn:     return AnyShapeStyle(Brand.warning.opacity(0.55))
        case .success:  return AnyShapeStyle(Brand.success.opacity(0.55))
        case .info:     return AnyShapeStyle(Brand.info.opacity(0.55))
        }
    }

    private func valuePaint(for family: TileFamily) -> AnyShapeStyle {
        switch family {
        case .gradient: return AnyShapeStyle(LinearGradient.diagonal)
        case .warn:     return AnyShapeStyle(Brand.warning)
        case .success:  return AnyShapeStyle(Brand.success)
        case .info:     return AnyShapeStyle(Brand.info)
        }
    }

    // MARK: Retention footer

    private var retentionFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RETENTION")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text("S3-versioned · 7-year retention · `documents.delete` is soft-archive (recoverable for 30 days)")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Notification posts (§20.4)

    private func tapRow(_ d: DocumentsAPI.Document) {
        // Real action: row tap behaves identically to "Download" —
        // fetch the document bytes and present share sheet so the
        // user can preview / save / forward. Replaces openURL stub.
        NotificationCenter.default.post(
            name: .eusoShipperDocumentRow,
            object: nil,
            userInfo: [
                "source": "226_ShipperDocumentCenter",
                "documentId": d.id,
                "shipperCompanyId": 1
            ]
        )
        Task { await fetchAndShare(d) }
    }

    private func tapDownload(_ d: DocumentsAPI.Document) {
        NotificationCenter.default.post(
            name: .eusoShipperDocumentDownload,
            object: nil,
            userInfo: [
                "source": "226_ShipperDocumentCenter",
                "documentId": d.id,
                "shipperCompanyId": 1
            ]
        )
        Task { await fetchAndShare(d) }
    }

    private func tapCategory(_ c: DocumentsAPI.Category) {
        // Real action: scroll the existing chip filter to this
        // category. Replaces openURL stub. Telemetry retained.
        NotificationCenter.default.post(
            name: .eusoShipperDocumentCategoryTile,
            object: nil,
            userInfo: [
                "source": "226_ShipperDocumentCenter",
                "categoryId": c.id,
                "shipperCompanyId": 1
            ]
        )
        if let f = DocFilter.allCases.first(where: { $0.id == c.id || $0.label.lowercased() == c.id.lowercased() }) {
            tapFilter(f)
        }
    }

    /// Fetch the document body via `documents.getFileData`, decode the
    /// data URL, write to a tmp file, and present `UIActivityView
    /// Controller` so the user can save / preview / share. The
    /// `pendingShareItems` and share sheet wiring lives at the top
    /// of the body modifier chain.
    private func fetchAndShare(_ d: DocumentsAPI.Document) async {
        struct In: Encodable { let id: String }
        struct Out: Decodable {
            let id: String?
            let name: String?
            let fileUrl: String?
            let type: String?
        }
        do {
            let resp: Out = try await EusoTripAPI.shared.query(
                "documents.getFileData",
                input: In(id: d.id)
            )
            guard let raw = resp.fileUrl, !raw.isEmpty else {
                await MainActor.run { uploadToast = "No file body for \(d.name)" }
                return
            }
            // Decode data: URL → raw bytes; pass through for normal URLs.
            var bytes: Data? = nil
            var ext = (d.name as NSString).pathExtension
            if ext.isEmpty { ext = "bin" }
            if raw.hasPrefix("data:") {
                if let comma = raw.firstIndex(of: ","),
                   let decoded = Data(base64Encoded: String(raw[raw.index(after: comma)...])) {
                    bytes = decoded
                    if raw.contains("application/pdf") { ext = "pdf" }
                    else if raw.contains("image/png")  { ext = "png" }
                    else if raw.contains("image/jpeg") { ext = "jpg" }
                }
            }
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("eusotrip-docs", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileName = (resp.name ?? d.name) + (ext.hasPrefix(".") ? ext : ".\(ext)")
            let url = dir.appendingPathComponent(fileName)
            if let bytes = bytes {
                try bytes.write(to: url, options: .atomic)
                await MainActor.run { pendingShareDocs = [url] }
            } else if let normal = URL(string: raw) {
                await MainActor.run { openURL(normal) }
            } else {
                await MainActor.run { uploadToast = "Couldn't decode \(d.name)" }
            }
        } catch {
            await MainActor.run {
                uploadToast = "Fetch failed: \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)"
            }
        }
    }

    // MARK: Empty / error

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.fill")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No documents yet")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("Tap the gradient + capsule above to add your first BOL, insurance cert, or W9.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Brand.info)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Press feedback

private struct DocRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - File-scoped Star (§19.2)

private struct DocStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [CGPoint] = [
            CGPoint(x: 5,   y: 0),
            CGPoint(x: 6.2, y: 3.6),
            CGPoint(x: 10,  y: 3.6),
            CGPoint(x: 7,   y: 5.8),
            CGPoint(x: 8.2, y: 9.4),
            CGPoint(x: 5,   y: 7.2),
            CGPoint(x: 1.8, y: 9.4),
            CGPoint(x: 3,   y: 5.8),
            CGPoint(x: 0,   y: 3.6),
            CGPoint(x: 3.8, y: 3.6),
        ]
        let sx = rect.width / 10.0
        let sy = rect.height / 9.4
        var path = Path()
        for (i, p) in pts.enumerated() {
            let x = rect.minX + p.x * sx
            let y = rect.minY + p.y * sy
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else      { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Filter chip tap (All / BOL / COI / Rate Con / Tax).
    static let eusoShipperDocumentFilter       = Notification.Name("eusoShipperDocumentFilter")
    /// Recent row tap — Continuity preview hand-off.
    static let eusoShipperDocumentRow          = Notification.Name("eusoShipperDocumentRow")
    /// Per-row download chevron tap.
    static let eusoShipperDocumentDownload     = Notification.Name("eusoShipperDocumentDownload")
    /// Category tile tap.
    static let eusoShipperDocumentCategoryTile = Notification.Name("eusoShipperDocumentCategoryTile")
    /// Search-row trailing `+` upload capsule tap.
    static let eusoShipperDocumentUpload       = Notification.Name("eusoShipperDocumentUpload")
}

// MARK: - Previews

#Preview("226 · Documents · Dark") {
    ShipperDocumentCenter()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("226 · Documents · Light") {
    ShipperDocumentCenter()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}

/// System share sheet wrapper for the document download / preview
/// flow. Local to this file so it doesn't collide with the same-name
/// helpers in 207 ShipperReports / 299 Reports.
private struct DocsCenterShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Document-intelligence result + review sheet

/// Structured outcome of the homegrown vision spine on a picked file:
/// the detected type, confidence, summary, key extracted fields, any
/// warnings, the downstream dispatch target, and the upload category
/// it was filed under. Surfaced honestly in `DocCenterClassification
/// Review` — never claims a type the classifier didn't return.
private struct DocCenterClassification: Identifiable, Hashable {
    let id = UUID()
    let filename: String
    let classifiedType: String
    let confidence: Double
    let summary: String
    /// (pretty key, value) pairs — already nulls-dropped + sorted.
    let fields: [(String, String)]
    let warnings: [String]
    let dispatchTarget: String?
    /// The `documents.upload` category bucket it was filed under.
    let category: String

    static func == (lhs: DocCenterClassification, rhs: DocCenterClassification) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var confidencePct: Int { Int((confidence * 100).rounded()) }
    var isUnknown: Bool { classifiedType == "unknown" || classifiedType.isEmpty }
    var isLowConfidence: Bool { confidence < 0.6 }

    /// Human label for the 60+-value taxonomy (mirrors 204's mapping).
    var humanType: String {
        switch classifiedType {
        case "bill_of_lading":            return "Bill of Lading"
        case "rate_confirmation":         return "Rate Confirmation"
        case "run_ticket":                return "Run Ticket"
        case "proof_of_delivery":         return "Proof of Delivery"
        case "load_csv":                  return "Load CSV"
        case "load_tender":               return "Load Tender"
        case "weight_ticket", "scale_ticket": return "Weight Ticket"
        case "invoice", "freight_invoice": return "Freight Invoice"
        case "packing_list":              return "Packing List"
        case "customs_entry":             return "Customs Entry"
        case "lumper_receipt":            return "Lumper Receipt"
        case "fuel_receipt":              return "Fuel Receipt"
        case "detention_receipt":         return "Detention Receipt"
        case "us_coi", "ca_coi", "insurance_certificate": return "Insurance Certificate"
        case "us_cdl":                    return "CDL"
        case "us_medical_card":           return "Medical Card"
        case "us_dot_authority", "us_mc_authority": return "FMCSA Authority"
        case "inspection_report", "dvir": return "Inspection Report"
        case "w9":                        return "W-9"
        case "form_1099":                 return "1099"
        case "us_ein_letter":             return "EIN Letter"
        case "comcheck":                  return "Comcheck"
        case "shipper_agreement", "broker_agreement", "carrier_packet",
             "factoring_agreement", "nda", "agreement":
            return "Agreement"
        case "unknown", "":               return "Unidentified"
        default:
            return classifiedType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var glyph: String {
        switch classifiedType {
        case "bill_of_lading", "load_tender", "load_csv", "rate_confirmation":
            return "shippingbox.fill"
        case "run_ticket", "weight_ticket", "scale_ticket", "fuel_receipt":
            return "fuelpump.fill"
        case "proof_of_delivery":
            return "checkmark.seal.fill"
        case "us_coi", "ca_coi", "insurance_certificate":
            return "checkmark.shield.fill"
        case let t where t.hasPrefix("us_") || t.hasPrefix("ca_") || t.hasPrefix("mx_"):
            return "creditcard.fill"
        case "w9", "form_1099", "us_ein_letter":
            return "doc.text.fill"
        case "shipper_agreement", "broker_agreement", "carrier_packet",
             "factoring_agreement", "nda", "agreement":
            return "signature"
        case "unknown", "":
            return "questionmark.folder.fill"
        default:
            return "doc.fill"
        }
    }

    /// Pretty category bucket label for the "filed under" line.
    var categoryLabel: String {
        category.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// Read-only review sheet shown after a picked file is classified +
/// uploaded. Renders the real classifier output: the detected type,
/// confidence, summary, extracted fields, warnings, and where it was
/// filed. Honest by construction — `unknown` / low confidence get a
/// neutral "couldn't confidently identify" banner, never a fake type.
private struct DocCenterClassificationReview: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let result: DocCenterClassification

    private var confColor: Color {
        if result.confidencePct >= 85 { return Brand.success }
        if result.confidencePct >= 60 { return Brand.warning }
        return Brand.danger
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    if result.isUnknown || result.isLowConfidence { uncertaintyBanner }
                    if !result.summary.isEmpty { summaryBlock }
                    if !result.fields.isEmpty { fieldsBlock }
                    if !result.warnings.isEmpty { warningsBlock }
                    filedUnderBlock
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(palette.bgPage)
            .navigationTitle("Document detected")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.15))
                Image(systemName: result.glyph)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("ESANG AI · DOCUMENT ROUTER")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(result.humanType)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text("\(result.confidencePct)% confidence")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(confColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(confColor.opacity(0.12)))
                    Text(result.filename)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var uncertaintyBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Brand.warning)
            Text(result.isUnknown
                 ? "Couldn't confidently identify this document — please confirm the type and re-file if needed. It was stored under \(result.categoryLabel)."
                 : "Low confidence on this read — please confirm before relying on the detected type.")
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Brand.warning.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.45))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SUMMARY")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(result.summary)
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fieldsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXTRACTED · \(result.fields.count) FIELD\(result.fields.count == 1 ? "" : "S")")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(result.fields.enumerated()), id: \.offset) { idx, pair in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                        Text(pair.0)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 130, alignment: .leading)
                        Text(pair.1)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    if idx < result.fields.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                            .padding(.horizontal, 14)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var warningsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WARNINGS · \(result.warnings.count)")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(Brand.warning)
            ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, w in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                    Text(w)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Brand.warning.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.4))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var filedUnderBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FILED UNDER")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(result.categoryLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            if let target = result.dispatchTarget, !target.isEmpty {
                Text("Route: \(target)")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
