//
//  400_BulkUploadShell.swift
//  EusoTrip — Cross-role bulk upload shell.
//
//  Single shared mobile surface for all 24 roles. Detects the session
//  role and surfaces role-specific entity types via
//  `bulkUpload.getSupportedEntityTypes` (server keys the response by
//  role). Job submission via `bulkUpload.uploadAndProcess`; status
//  polling via `bulkUpload.getJobStatus`.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BulkUploadShellScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { BulkUploadShellBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct EntityType: Decodable, Identifiable, Hashable {
    let key: String          // "loads" / "vehicles" / "drivers" / "contacts" / etc.
    let label: String
    let templateCsvUrl: String?
    let columns: [String]?
    var id: String { key }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Server sends "type", iOS property is "key"
        self.key = try c.decode(String.self, forKey: .type)
        self.label = try c.decode(String.self, forKey: .label)
        // Server sends "templateUrl", iOS property is "templateCsvUrl"
        self.templateCsvUrl = try c.decodeIfPresent(String.self, forKey: .templateUrl)
        // Server returns requiredFields + optionalFields; iOS expects merged "columns"
        let req = try c.decodeIfPresent([String].self, forKey: .requiredFields) ?? []
        let opt = try c.decodeIfPresent([String].self, forKey: .optionalFields) ?? []
        self.columns = (req + opt).isEmpty ? nil : (req + opt)
    }
    
    enum CodingKeys: String, CodingKey {
        case type, label, templateUrl, requiredFields, optionalFields
    }
}

private struct SupportedEntityTypesResponse: Decodable {
    let entityTypes: [EntityType]
}

private struct UploadJob: Decodable, Identifiable, Hashable {
    let id: String
    let status: String       // "queued" / "processing" / "completed" / "failed"
    let entityType: String?
    let total: Int?
    let processed: Int?
    let errors: Int?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "jobId"
        case status
        case entityType
        case total = "totalRows"
        case processed = "successCount"
        case errors = "failCount"
        case createdAt
    }
    
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = String(try c.decode(Int.self, forKey: .id))
        status = try c.decode(String.self, forKey: .status)
        entityType = try c.decodeIfPresent(String.self, forKey: .entityType)
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        processed = try c.decodeIfPresent(Int.self, forKey: .processed)
        errors = try c.decodeIfPresent(Int.self, forKey: .errors)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }

    /// Local optimistic placeholder built on submit (the server response
    /// decodes via init(from:) above, mapping jobId/totalRows/successCount).
    init(id: String, status: String, entityType: String?, total: Int?, processed: Int?, errors: Int?, createdAt: String?) {
        self.id = id; self.status = status; self.entityType = entityType
        self.total = total; self.processed = processed; self.errors = errors; self.createdAt = createdAt
    }
}

private struct BulkHistoryResponse: Decodable {
    let jobs: [UploadJob]
}

private struct BulkUploadShellBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @State private var entityTypes: [EntityType] = []
    @State private var selected: EntityType? = nil
    @State private var rawCsv: String = ""
    @State private var uploading = false
    @State private var lastJob: UploadJob? = nil
    @State private var jobHistory: [UploadJob] = []
    @State private var actionError: String? = nil
    @State private var loading = true
    @State private var fileImporterPresented = false
    /// In-app share-sheet state for the "Download template CSV" tap.
    /// Replaces the previous raw Safari
    /// punt with an authed-fetch + UIActivityViewController flow so
    /// the user can save into Files / AirDrop / Mail without leaving
    /// the app. Identifiable wrapper around the temp URL so SwiftUI
    /// `.sheet(item:)` re-presents per-fetch.
    private struct BulkTemplateShareItem: Identifiable, Hashable {
        let id: UUID
        let url: URL
    }
    @State private var templateShareItem: BulkTemplateShareItem? = nil
    @State private var templateFetching: Bool = false
    @State private var templateFetchError: String? = nil
    /// ESANG AI parse mode toggle. When ON, the upload routes through
    /// the platform's Gemini-backed structured-extraction pipeline
    /// (`payloadKind: "ai-parse"` per founder doctrine 2026-05-07).
    /// The server detects file format (CSV / JSON / XLS / PDF), runs
    /// Gemini OCR + structured extraction, maps rows into the
    /// selected entity's table schema, and returns a job id we poll
    /// the same way as the deterministic CSV path. ON by default for
    /// XLS/PDF inputs (deterministic CSV parsing is enough for
    /// straight CSV); user can override either way.
    @State private var aiParseEnabled: Bool = true
    // MARK: — Scanned-document intake (PDF / XLSX / photo)
    //
    // 2026-08-12 (WIRE-GAP) — the picker below has advertised .pdf,
    // .xls, .xlsx and .spreadsheet since 2026-05-07, but `handleFile`
    // only ever did `String(data:encoding:.utf8)`. A PDF failed that
    // guard and the closure returned: no error, no toast, no state
    // change. The primary import path silently did nothing.
    //
    // The bytes now go to `bulkUpload.processDocument`, which reads
    // the document server-side (Gemini vision) and returns the rows it
    // actually found. Nothing lands in `rawCsv` — and Run upload stays
    // disabled — until a human has looked at the extraction and
    // accepted it. Extraction PROPOSES; the user confirms.
    @State private var scanning: Bool = false
    /// Non-nil while an extraction is awaiting the user's decision.
    /// While this is set the submit button is blocked: unaccepted
    /// scanned rows are never importable.
    @State private var pendingScan: BulkUploadAPI.BulkScannedExtraction? = nil
    @State private var pendingScanFileName: String? = nil
    @State private var scanError: String? = nil
    /// Provenance of whatever is currently in `rawCsv`, so the surface
    /// can never present machine-read rows as if the user typed them.
    @State private var acceptedScanNote: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                roleStripCard
                entityTypeCard
                if scanning { scanningCard }
                if let e = scanError { LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true) } }
                if let scan = pendingScan {
                    ScannedExtractionReviewCard(
                        extraction: scan,
                        fileName: pendingScanFileName ?? "the picked file",
                        onAccept: { acceptPendingScan() },
                        onDiscard: { discardPendingScan() }
                    )
                }
                if selected != nil { dataSourceCard; submitRow }
                if let job = lastJob { jobStatusCard(job) }
                historyCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .eusoRefreshTask { await loadEntityTypes(); await loadHistory() }
        // Founder ask 2026-05-07: shippers, brokers, dispatchers
        // need bulk upload from the file formats they actually use.
        // Server expects CSV/JSON in the payload string; XLSX +
        // PDF are accepted at the picker level, the parsing handler
        // converts them to CSV before submit. UTType.xlsx is not in
        // the SDK's enum on iOS 17+ — use the explicit MIME-derived
        // identifier.
        .fileImporter(
            isPresented: $fileImporterPresented,
            allowedContentTypes: [
                .commaSeparatedText,
                .json,
                .text,
                .pdf,
                UTType(filenameExtension: "xls")  ?? .data,
                UTType(filenameExtension: "xlsx") ?? .data,
                UTType.spreadsheet
            ],
            allowsMultipleSelection: false
        ) { result in
            handleFile(result)
        }
        // In-app share sheet for the fetched template CSV. Presents
        // UIActivityViewController so the user can Save to Files,
        // AirDrop, Mail, etc. — no Safari punt.
        .sheet(item: $templateShareItem) { item in
            BulkTemplateActivitySheet(url: item.url)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Template CSV fetch

    @MainActor
    private func fetchTemplateCsv(urlString: String) async {
        guard !templateFetching else { return }
        templateFetching = true
        templateFetchError = nil
        defer { templateFetching = false }
        guard let url = URL(string: urlString) else {
            templateFetchError = "Couldn't parse the template URL."
            return
        }
        do {
            let (data, _) = try await EusoTripAPI.shared.fetchAuthenticatedData(url)
            guard !data.isEmpty else {
                templateFetchError = "The template downloaded as zero bytes — nothing was saved to this device. Try again."
                return
            }
            let suggested = url.lastPathComponent.isEmpty
                ? "\(selected?.key ?? "template").csv"
                : url.lastPathComponent
            let safeName = suggested.lowercased().hasSuffix(".csv") ? suggested : "\(suggested).csv"
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(safeName)
            try data.write(to: tmp, options: .atomic)
            templateShareItem = BulkTemplateShareItem(id: UUID(), url: tmp)
        } catch let apiErr as EusoTripAPIError {
            templateFetchError = apiErr.errorDescription ?? "Network error"
        } catch {
            templateFetchError = error.localizedDescription
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up.on.square.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("\(roleLabel.uppercased()) · BULK UPLOAD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Bulk upload").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Import many records at once. Pick an entity type, paste CSV or attach a file, run the job. Status tracked here on completion.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var roleStripCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ROLE", icon: "person.crop.circle")
            LifecycleRow(label: "Active role", value: roleLabel)
            LifecycleRow(label: "Account",     value: session.user?.email ?? "-")
        }
    }

    @ViewBuilder
    private var entityTypeCard: some View {
        if loading { LifecycleCard { Text("Loading supported entity types…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if entityTypes.isEmpty {
            LifecycleCard { Text("This role has no bulk-upload entity types configured yet.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true) }
        } else {
            LifecycleCard {
                LifecycleSection(label: "ENTITY TYPE", icon: "tag")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(entityTypes) { et in
                            Button { selected = et } label: {
                                Text(et.label).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                    .foregroundStyle(selected?.id == et.id ? .white : palette.textPrimary)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(selected?.id == et.id ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                                    .clipShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if let s = selected, let cols = s.columns, !cols.isEmpty {
                    Text("EXPECTED COLUMNS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary).padding(.top, 6)
                    Text(cols.joined(separator: ", ")).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                if let url = selected?.templateCsvUrl {
                    Button {
                        Task { await fetchTemplateCsv(urlString: url) }
                    } label: {
                        HStack(spacing: 6) {
                            if templateFetching {
                                ProgressView().scaleEffect(0.7).tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.system(size: 11, weight: .heavy))
                            }
                            Text(templateFetching ? "Fetching…" : "Download template CSV")
                                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .disabled(templateFetching)
                    if let err = templateFetchError {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var dataSourceCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DATA", icon: "tray.and.arrow.down")
            // ESANG AI smart-parse toggle. ON → server routes through
            // Gemini for structured extraction so XLS / XLSX / PDF
            // (and even messy CSVs from legacy systems) get mapped
            // into the entity's table columns automatically.
            Toggle(isOn: $aiParseEnabled.animation(.spring(response: 0.22, dampingFraction: 0.85))) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Smart parse with ESANG AI")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text("Gemini OCR + structured extraction · XLS, PDF, messy CSV → \(selected?.label.lowercased() ?? "rows")")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .toggleStyle(GradientToggleStyle())
            .padding(.bottom, 4)
            HStack(spacing: 8) {
                Button { fileImporterPresented = true } label: {
                    Text(aiParseEnabled ? "Pick file (CSV / XLS / PDF)" : "Pick file (CSV / JSON)")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(palette.tintNeutral).clipShape(Capsule())
                }.buttonStyle(.plain)
                Button { rawCsv = ""; acceptedScanNote = nil } label: {
                    Text("Clear").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(palette.tintNeutral).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(rawCsv.isEmpty)
            }
            Text(aiParseEnabled ? "OR PASTE ANY TABULAR DATA - ESANG INFERS COLUMNS" : "OR PASTE CSV / JSON").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary).padding(.top, 6)
            TextEditor(text: $rawCsv)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 280)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Rows detected: \(rowCount)").font(EType.caption).foregroundStyle(palette.textSecondary)
            if let note = acceptedScanNote {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                    Text(note)
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
    }

    private var submitRow: some View {
        Button { Task { await submit() } } label: {
            HStack(spacing: 6) {
                if uploading { ProgressView().tint(.white) }
                Text(uploading ? "Uploading…" : "Run upload").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        // A scan awaiting review can never be imported. The user has
        // to accept or discard it first.
        .disabled(uploading || rawCsv.isEmpty || selected == nil || pendingScan != nil || scanning)
    }

    private func jobStatusCard(_ job: UploadJob) -> some View {
        LifecycleCard(accentDanger: job.status == "failed", accentWarning: job.status == "processing", accentGradient: job.status == "completed") {
            LifecycleSection(label: "LATEST JOB", icon: "doc.text.below.ecg")
            LifecycleRow(label: "ID",        value: job.id)
            LifecycleRow(label: "Entity",     value: dashIfEmpty(job.entityType))
            LifecycleRow(label: "Status",     value: job.status.uppercased())
            LifecycleRow(label: "Total",      value: job.total.map { "\($0)" } ?? "-")
            LifecycleRow(label: "Processed",  value: job.processed.map { "\($0)" } ?? "-")
            LifecycleRow(label: "Errors",     value: job.errors.map { "\($0)" } ?? "-")
            LifecycleRow(label: "Submitted",  value: humanISO(job.createdAt))
        }
    }

    @ViewBuilder
    private var historyCard: some View {
        if !jobHistory.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "RECENT JOBS", icon: "clock")
                ForEach(jobHistory.prefix(8)) { j in
                    HStack {
                        Image(systemName: iconFor(j.status)).foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dashIfEmpty(j.entityType?.uppercased())).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text(humanISO(j.createdAt)).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Text(j.status.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(j.status == "failed" ? Brand.danger : palette.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var rowCount: Int {
        rawCsv.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    private var roleLabel: String {
        let r = (session.user?.role ?? "").uppercased()
        return r.isEmpty ? "-" : r.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func iconFor(_ status: String) -> String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "processing": return "hourglass"
        case "failed":     return "exclamationmark.triangle.fill"
        default:           return "tray"
        }
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await ingestPickedFile(url) }
        case .failure(let err):
            actionError = err.localizedDescription
        }
    }

    /// Read the picked file's bytes and get them where they can be
    /// understood. Two honest outcomes, never a third silent one:
    ///
    ///   • text-decodable (CSV / JSON / TXT) → straight into the editor
    ///     where the user can SEE every row before submitting.
    ///   • anything else (PDF / XLSX / photograph) → the BYTES go to
    ///     `bulkUpload.processDocument`. What comes back is parked in
    ///     `pendingScan` as scanned-and-unconfirmed until accepted.
    ///
    /// Every failure path says what happened and leaves `rawCsv`
    /// untouched. A file that could not be read is never allowed to
    /// look like a file that contained nothing.
    @MainActor
    private func ingestPickedFile(_ url: URL) async {
        actionError = nil
        scanError = nil
        pendingScan = nil
        pendingScanFileName = nil

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            actionError = "Couldn't open \(url.lastPathComponent) — it read as zero bytes. Nothing was attached."
            return
        }

        if let text = ScannedDocumentIntake.decodeText(data),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawCsv = text
            acceptedScanNote = nil
            return
        }

        // Binary. Only the server can read this.
        guard let entity = selected else {
            actionError = "Pick an entity type first — the reader needs to know what fields it is looking for in \(url.lastPathComponent)."
            return
        }
        let mime = ScannedDocumentIntake.mimeType(url: url, data: data)
        guard ScannedDocumentIntake.isServerReadable(mime) else {
            actionError = "\(url.lastPathComponent) is a \(mime) file. The reader handles PDFs, photos and text exports — this format isn't one of them, so nothing was attached. Export it to CSV or PDF and pick it again."
            return
        }

        scanning = true
        pendingScanFileName = url.lastPathComponent
        defer { scanning = false }
        do {
            let out = try await EusoTripAPI.shared.bulkUpload.processDocument(
                entityType: entity.key,
                fileBase64: data.base64EncodedString(),
                mimeType: mime,
                fileName: url.lastPathComponent
            )
            if out.isEmptyRead {
                // Explicitly NOT "the document was empty".
                pendingScanFileName = nil
                scanError = "\(url.lastPathComponent) was sent to the reader and came back with no rows. That means it could not be read — not that it was blank. Nothing was attached. Try a sharper photo, an unlocked PDF, or a CSV export."
            } else {
                pendingScan = out
            }
        } catch {
            pendingScanFileName = nil
            scanError = "Couldn't read \(url.lastPathComponent): \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription) Nothing was attached."
        }
    }

    /// The human said yes. Only now do the machine-read rows become
    /// the payload — and the surface keeps saying where they came from.
    private func acceptPendingScan() {
        guard let scan = pendingScan else { return }
        rawCsv = scan.csvText
        acceptedScanNote = "These \(scan.recordCount) row\(scan.recordCount == 1 ? "" : "s") were read out of \(pendingScanFileName ?? "a scanned file") by the document reader and accepted by you. Edit anything below before running the upload."
        pendingScan = nil
    }

    private func discardPendingScan() {
        pendingScan = nil
        pendingScanFileName = nil
        acceptedScanNote = nil
    }

    private var scanningCard: some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 8) {
                ProgressView().tint(Brand.blue)
                Text("Reading \(pendingScanFileName ?? "the file") on the server — no data is imported from a scan until you accept it.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadEntityTypes() async {
        loading = true; actionError = nil
        do {
            let resp: SupportedEntityTypesResponse = try await EusoTripAPI.shared.queryNoInput("bulkUpload.getSupportedEntityTypes")
            entityTypes = resp.entityTypes
            selected = resp.entityTypes.first
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func loadHistory() async {
        do {
            let resp: BulkHistoryResponse = try await EusoTripAPI.shared.queryNoInput("bulkUpload.getJobHistory")
            jobHistory = resp.jobs
        } catch let apiErr as EusoTripAPIError {
            // History is a secondary panel; record the error to the
            // shared `actionError` only when nothing else has populated
            // it yet, so the primary upload flow stays the priority.
            if actionError == nil {
                actionError = "Job history: \(apiErr.errorDescription ?? "couldn't load")"
            }
        } catch {
            if actionError == nil {
                actionError = "Job history: \(error.localizedDescription)"
            }
        }
    }

    private func submit() async {
        guard let entity = selected else { return }
        uploading = true; actionError = nil
        struct Opts: Encodable { let aiMapping: Bool }
        struct In: Encodable { let entityType: String; let csvText: String; let fileName: String; let options: Opts }
        struct Out: Decodable { let jobId: Int? }
        // options.aiMapping picks the server parser: false = deterministic CSV;
        // true = ESANG/Gemini structured extraction (XLS/XLSX/PDF + messy CSV).
        do {
            let r: Out = try await EusoTripAPI.shared.mutation(
                "bulkUpload.uploadAndProcess",
                input: In(entityType: entity.key, csvText: rawCsv, fileName: "bulk_\(entity.key).csv", options: Opts(aiMapping: aiParseEnabled))
            )
            if let jid = r.jobId {
                lastJob = UploadJob(id: String(jid), status: "queued", entityType: entity.key, total: rowCount, processed: 0, errors: 0, createdAt: ISO8601DateFormatter().string(from: Date()))
                await pollJob(jid)
            }
            await loadHistory()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        uploading = false
    }

    private func pollJob(_ jobId: Int) async {
        struct In: Encodable { let jobId: Int }
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            do {
                let j: UploadJob = try await EusoTripAPI.shared.query("bulkUpload.getJobStatus", input: In(jobId: jobId))
                lastJob = j
                if j.status == "completed" || j.status == "failed" { return }
            } catch { return }
        }
    }
}

// MARK: - In-app activity sheet for the downloaded template CSV.

/// Hosts UIActivityViewController so the template CSV opens in the
/// system share sheet (Save to Files / AirDrop / Mail / Messages)
/// instead of bouncing the user out to Safari.
private struct BulkTemplateActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview("400 · Bulk upload · Night") { BulkUploadShellScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("400 · Bulk upload · Afternoon") { BulkUploadShellScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }

// MARK: - Scanned-document intake (shared by every bulk-import surface)
//
// Lives in this file rather than a new one because the Xcode project
// carries an explicit file list — an unregistered .swift is silently
// skipped at build time (see the orphaned-screens note). These types
// are `internal`, so 709 DispatchBulkUploadKanban and any future
// import surface can use them without a project-file edit.
//
// The contract these enforce, in order:
//   1. The BYTES go to the server. iOS does not read documents.
//   2. What comes back is a PROPOSAL, rendered as such.
//   3. A field the reader could not find is ABSENT and is shown as
//      absent — never blanked, never zeroed, never guessed.
//   4. Nothing is imported until a human accepts it.

enum ScannedDocumentIntake {

    /// UTF-8 first, then Latin-1 — covers the CSV/JSON exports legacy
    /// TMS systems emit. Returns nil for true binary (PDF / XLS /
    /// image), which the caller must send to the server rather than
    /// dropping.
    static func decodeText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    /// Sniff the real type from the magic bytes and fall back to the
    /// UTType for the extension. The extension is a claim; the header
    /// is evidence, and the server's mime check runs on what we send.
    static func mimeType(url: URL, data: Data) -> String {
        let head = [UInt8](data.prefix(12))
        func matches(_ sig: [UInt8], at offset: Int = 0) -> Bool {
            guard head.count >= offset + sig.count else { return false }
            for (i, b) in sig.enumerated() where head[offset + i] != b { return false }
            return true
        }
        if matches([0x25, 0x50, 0x44, 0x46]) { return "application/pdf" }                 // %PDF
        if matches([0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if matches([0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if matches([0x52, 0x49, 0x46, 0x46]), matches([0x57, 0x45, 0x42, 0x50], at: 8) { return "image/webp" }
        if matches([0x00, 0x00, 0x00]), matches([0x66, 0x74, 0x79, 0x70], at: 4) { return "image/heic" }
        if matches([0x50, 0x4B, 0x03, 0x04]) {                                             // ZIP container
            let ext = url.pathExtension.lowercased()
            if ext == "xlsx" { return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }
            return "application/zip"
        }
        if matches([0xD0, 0xCF, 0x11, 0xE0]) { return "application/vnd.ms-excel" }         // legacy OLE .xls
        return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    /// The mime types the server's vision pass can actually open.
    /// Anything else is refused at the picker with a reason, instead
    /// of being posted and failing opaquely on the wire.
    static func isServerReadable(_ mime: String) -> Bool {
        switch mime {
        case "application/pdf", "image/jpeg", "image/png", "image/webp", "image/heic":
            return true
        default:
            return false
        }
    }

    /// Confidence phrasing that never overstates. The server reports a
    /// 0-100 number; we say what it means for the person deciding.
    static func confidenceLabel(_ confidence: Double) -> String {
        switch confidence {
        case ..<50:  return "LOW CONFIDENCE — CHECK EVERY FIELD"
        case ..<80:  return "MEDIUM CONFIDENCE — CHECK THE FLAGGED ROWS"
        default:     return "HIGH CONFIDENCE — STILL YOUR CALL"
        }
    }
}

/// Renders a `bulkUpload.processDocument` result as what it is: an
/// unconfirmed machine reading of a document, with the server's own
/// warnings on the face of it and two explicit exits.
///
/// Deliberate omissions:
///   • no "looks good!" affirmation — the card never editorialises
///     about a document it did not read itself;
///   • missing required fields are listed by NAME, not filled with
///     placeholders. An absent field stays absent all the way to the
///     import job, where the server will reject the row honestly.
struct ScannedExtractionReviewCard: View {
    @Environment(\.palette) private var palette

    let extraction: BulkUploadAPI.BulkScannedExtraction
    let fileName: String
    let onAccept: () -> Void
    let onDiscard: () -> Void

    private var invalidCount: Int { extraction.records.filter { !$0.isValid }.count }

    var body: some View {
        LifecycleCard(accentWarning: true) {
            HStack(spacing: 6) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text("SCANNED · UNCONFIRMED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.warning)
                Spacer(minLength: 0)
                Text("\(Int(extraction.confidence.rounded()))%")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            Text("The reader found \(extraction.recordCount) row\(extraction.recordCount == 1 ? "" : "s") in \(fileName). Nothing has been imported. Read them, then accept or discard.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            LifecycleRow(label: "Detected as", value: extraction.documentType.replacingOccurrences(of: "_", with: " ").uppercased())
            if let label = extraction.entityLabel {
                LifecycleRow(label: "Imports as", value: label)
            }
            LifecycleRow(label: "Confidence", value: ScannedDocumentIntake.confidenceLabel(extraction.confidence))
            if invalidCount > 0 {
                LifecycleRow(label: "Rows flagged", value: "\(invalidCount) of \(extraction.records.count)")
            }

            let missing = extraction.missingRequiredFields
            if !missing.isEmpty {
                Text("NOT FOUND IN THE DOCUMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary).padding(.top, 4)
                Text(missing.joined(separator: ", "))
                    .font(EType.mono(.micro)).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Text("These are left empty on purpose. Fill them in yourself below — the reader did not see them.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !extraction.warnings.isEmpty {
                Text("READER WARNINGS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary).padding(.top, 4)
                ForEach(Array(extraction.warnings.prefix(6).enumerated()), id: \.offset) { _, w in
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Brand.warning).padding(.top, 2)
                        Text(w).font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let first = extraction.records.first, !first.data.isEmpty {
                Text("FIRST ROW AS READ")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary).padding(.top, 4)
                ForEach(first.data.keys.sorted().prefix(6), id: \.self) { k in
                    LifecycleRow(label: k, value: first.data[k] ?? "-")
                }
            }

            HStack(spacing: 8) {
                Button(action: onAccept) {
                    Text("Accept these rows")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain)
                Button(action: onDiscard) {
                    Text("Discard")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(palette.tintNeutral).clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }
}

/// Generic review card for a single-document `documentRouter`
/// classification, for surfaces that read ONE paper form rather than a
/// table of rows (run tickets, credentials, COIs).
///
/// The rule it exists to hold: a value the reader proposed is drawn in
/// the warning tone under a SCANNED · UNCONFIRMED header and is not the
/// screen's state until Accept is tapped. It also states plainly which
/// of the values will actually be written when the user accepts, so
/// nobody is left believing a number was filed that was not.
struct ScannedFieldsReviewCard: View {
    @Environment(\.palette) private var palette

    let title: String
    let detectedType: String
    let confidence: Double
    let warnings: [String]
    /// (label, value) pairs the reader FOUND. A field the reader could
    /// not read must be absent from this array — never present with an
    /// empty string or a zero.
    let fields: [(label: String, value: String)]
    /// Human-readable statement of what accepting actually commits.
    /// Pass the plain truth, including "nothing else is stored".
    let commitNote: String
    let acceptTitle: String
    let onAccept: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        LifecycleCard(accentWarning: true) {
            HStack(spacing: 6) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text("SCANNED · UNCONFIRMED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.warning)
                Spacer(minLength: 0)
                Text("\(Int(confidence.rounded()))%")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            Text(title)
                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            LifecycleRow(label: "Detected as", value: detectedType.replacingOccurrences(of: "_", with: " ").uppercased())
            LifecycleRow(label: "Confidence", value: ScannedDocumentIntake.confidenceLabel(confidence))

            if fields.isEmpty {
                Text("The reader opened the document but could not pull a single field out of it. Nothing has been filled in. Type the values yourself, or scan again with better light.")
                    .font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("READ FROM THE DOCUMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary).padding(.top, 4)
                ForEach(Array(fields.enumerated()), id: \.offset) { _, f in
                    LifecycleRow(label: f.label, value: f.value)
                }
            }

            if !warnings.isEmpty {
                Text("READER WARNINGS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary).padding(.top, 4)
                ForEach(Array(warnings.prefix(6).enumerated()), id: \.offset) { _, w in
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Brand.warning).padding(.top, 2)
                        Text(w).font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text(commitNote)
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            HStack(spacing: 8) {
                Button(action: onAccept) {
                    Text(acceptTitle)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(fields.isEmpty)
                Button(action: onDiscard) {
                    Text("Discard")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(palette.tintNeutral).clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }
}
