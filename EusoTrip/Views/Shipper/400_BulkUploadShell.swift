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
    /// Replaces the previous `UIApplication.shared.open(url)` Safari
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                roleStripCard
                entityTypeCard
                if selected != nil { dataSourceCard; submitRow }
                if let job = lastJob { jobStatusCard(job) }
                historyCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await loadEntityTypes(); await loadHistory() }
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
                templateFetchError = "Server returned an empty file."
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
            LifecycleRow(label: "Account",     value: session.user?.email ?? "—")
        }
    }

    @ViewBuilder
    private var entityTypeCard: some View {
        if loading { LifecycleCard { Text("Loading supported entity types…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if entityTypes.isEmpty {
            LifecycleCard { Text("This role has no bulk-upload entity types configured server-side.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true) }
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
                Button { rawCsv = "" } label: {
                    Text("Clear").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(palette.tintNeutral).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(rawCsv.isEmpty)
            }
            Text(aiParseEnabled ? "OR PASTE ANY TABULAR DATA — ESANG INFERS COLUMNS" : "OR PASTE CSV / JSON").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary).padding(.top, 6)
            TextEditor(text: $rawCsv)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 280)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Rows detected: \(rowCount)").font(EType.caption).foregroundStyle(palette.textSecondary)
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
        }.buttonStyle(.plain).disabled(uploading || rawCsv.isEmpty || selected == nil)
    }

    private func jobStatusCard(_ job: UploadJob) -> some View {
        LifecycleCard(accentDanger: job.status == "failed", accentWarning: job.status == "processing", accentGradient: job.status == "completed") {
            LifecycleSection(label: "LATEST JOB", icon: "doc.text.below.ecg")
            LifecycleRow(label: "ID",        value: job.id)
            LifecycleRow(label: "Entity",     value: dashIfEmpty(job.entityType))
            LifecycleRow(label: "Status",     value: job.status.uppercased())
            LifecycleRow(label: "Total",      value: job.total.map { "\($0)" } ?? "—")
            LifecycleRow(label: "Processed",  value: job.processed.map { "\($0)" } ?? "—")
            LifecycleRow(label: "Errors",     value: job.errors.map { "\($0)" } ?? "—")
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
        return r.isEmpty ? "—" : r.replacingOccurrences(of: "_", with: " ").capitalized
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
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) {
                    rawCsv = s
                }
            }
        case .failure(let err):
            actionError = err.localizedDescription
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
