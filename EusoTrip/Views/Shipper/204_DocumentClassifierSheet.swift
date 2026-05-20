//
//  204_DocumentClassifierSheet.swift
//  EusoTrip — Post-Load wizard: Templates + Bulk classifier sheet.
//
//  One reusable sheet that powers two affordances on 204 Post-Load:
//
//    • Templates (single-mode): scan a Rate Confirmation, BOL, POD,
//      Load Tender, Run Ticket, or saved template → classify via
//      Gemini Vision → call `applyExtracted(fields:type:)` so the
//      wizard's @State props get pre-filled (lane, equipment, cargo,
//      weight, rate, dates).
//
//    • Bulk (batch-mode): drop up to 30 docs → classify each →
//      route load-shaped docs into the existing bulkImport pipeline
//      and surface non-load docs (BOLs / PODs / agreements / etc.)
//      with the right dispatch target so the user can route them.
//
//  Single source of truth for the classifier UI surface so future
//  upload affordances (Driver Me·Docs, Carrier packet drop) can
//  re-use it.
//

import SwiftUI
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

// MARK: - Public callback shape

/// Per-document classification result + the extracted fields the
/// host should pre-fill into its view-model.
struct ClassifiedDocument: Hashable, Identifiable {
    let id: String
    let classifiedType: String
    let confidence: Double
    let summary: String
    let dispatchTarget: String?
    let warnings: [String]
    /// Extracted fields — keys are doc-type-specific. Caller picks
    /// the ones it needs and applies them to local state.
    let fields: [String: String]
    let mimeType: String
    /// Original base64 payload — retained so the host can hand off
    /// to a downstream parser without re-uploading.
    let documentBase64: String
}

/// Where the host wants to land users on apply-success. Templates
/// uses .prefillWizard; Bulk uses .dispatchBatch.
enum DocumentClassifierMode {
    case prefillWizard      // single-doc, applyExtracted fires
    case batch              // multi-doc, dispatchBatch fires
}

struct DocumentClassifierSheet: View {
    let mode: DocumentClassifierMode
    /// Caller context fed to Gemini — disambiguates overlapping doc
    /// shapes ("shipper Post-Load Templates" vs "driver post-trip").
    let callerContext: String
    let onApplySingle: (ClassifiedDocument) -> Void
    let onDispatchBatch: ([ClassifiedDocument]) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera: Bool = false
    @State private var showFilePicker: Bool = false
    @State private var inflight: Bool = false
    @State private var error: String? = nil
    @State private var results: [ClassifiedDocument] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    hero
                    if let e = error { errorBanner(e) }
                    captureRow
                    if !results.isEmpty { resultsList }
                    if inflight { progressBlock }
                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(palette.bgPage)
            .navigationTitle(mode == .prefillWizard ? "Scan to pre-fill" : "Bulk upload")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .sheet(isPresented: $showCamera) {
                DocumentClassifierCameraSheet { data in
                    showCamera = false
                    guard let data else { return }
                    Task { await classify(data: data, mime: "image/jpeg", source: "camera") }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await classifyPickerItems(items) }
                pickerItems = []
            }
        }
    }

    // MARK: — Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESANG AI · DOCUMENT ROUTER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text(mode == .prefillWizard
                 ? "Drop a doc, we fill the form."
                 : "Drop up to 30 docs, we sort them.")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(mode == .prefillWizard
                 ? "Rate confirmations, BOLs, run tickets, load tenders — anything load-shaped. Gemini Vision extracts lane, equipment, cargo, weight, rate, and dates straight into the wizard."
                 : "CSV load batches, carrier packets, signed agreements, COIs, EIN letters, 1099s — anything. We classify each doc and route it to the right place.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Brand.danger.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.45))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: — Capture row

    private var captureRow: some View {
        HStack(spacing: 8) {
            Button { showCamera = true } label: {
                actionLabel(systemImage: "camera.fill", title: "Camera", filled: true)
            }
            .buttonStyle(.plain)
            .disabled(inflight)

            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: mode == .batch ? 30 : 1,
                matching: .any(of: [.images, .videos])
            ) {
                actionLabel(systemImage: "photo.on.rectangle.angled", title: mode == .batch ? "Photos (up to 30)" : "Photos", filled: false)
            }
            .disabled(inflight)

            Button { showFilePicker = true } label: {
                actionLabel(systemImage: "doc.fill", title: "Files / CSV", filled: false)
            }
            .buttonStyle(.plain)
            .disabled(inflight)
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.pdf, .image, .commaSeparatedText, .spreadsheet, .text],
                allowsMultipleSelection: mode == .batch
            ) { result in
                Task { await classifyFileImport(result) }
            }
        }
    }

    private func actionLabel(systemImage: String, title: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .heavy))
            Text(title)
                .font(.system(size: 12, weight: .heavy))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .padding(.horizontal, 10)
        .foregroundStyle(filled ? .white : palette.textPrimary)
        .background(filled ? AnyView(LinearGradient.diagonal) : AnyView(palette.bgCardSoft))
        .overlay(filled ? AnyView(EmptyView()) : AnyView(Capsule().strokeBorder(palette.borderSoft)))
        .clipShape(Capsule())
    }

    // MARK: — Progress + results

    private var progressBlock: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7).tint(palette.textPrimary)
            Text("Classifying…").font(EType.caption).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLASSIFIED · \(results.count)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            ForEach(results) { r in resultRow(r) }
            if mode == .batch && !results.isEmpty {
                Button {
                    onDispatchBatch(results)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 13, weight: .heavy))
                        Text("Route \(results.count) document\(results.count == 1 ? "" : "s")")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
    }

    private func resultRow(_ r: ClassifiedDocument) -> some View {
        let conf = Int((r.confidence * 100).rounded())
        let typeLabel = humanType(r.classifiedType)
        return HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.15))
                Image(systemName: glyphFor(r.classifiedType))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(typeLabel)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("\(conf)%")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(conf >= 85 ? Brand.success : conf >= 60 ? Brand.warning : Brand.danger)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill((conf >= 85 ? Brand.success : conf >= 60 ? Brand.warning : Brand.danger).opacity(0.12)))
                }
                if !r.summary.isEmpty {
                    Text(r.summary).font(EType.caption).foregroundStyle(palette.textSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                if !r.warnings.isEmpty {
                    ForEach(r.warnings.prefix(2), id: \.self) { w in
                        Text("⚠ \(w)").font(EType.caption).foregroundStyle(Brand.warning)
                    }
                }
            }
            Spacer(minLength: 0)

            if mode == .prefillWizard {
                Button {
                    onApplySingle(r)
                    dismiss()
                } label: {
                    Text("Apply")
                        .font(.system(size: 11, weight: .heavy))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(.white)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func humanType(_ raw: String) -> String {
        switch raw {
        case "bill_of_lading": return "Bill of Lading"
        case "rate_confirmation": return "Rate Confirmation"
        case "run_ticket": return "Run Ticket"
        case "proof_of_delivery": return "POD"
        case "load_csv": return "Load CSV"
        case "load_tender": return "Load Tender"
        case "weight_ticket", "scale_ticket": return "Weight Ticket"
        case "us_coi", "ca_coi": return "Insurance Certificate"
        case "us_cdl": return "CDL"
        case "us_medical_card": return "Medical Card"
        case "us_dot_authority", "us_mc_authority": return "FMCSA Authority"
        case "w9": return "W-9"
        case "form_1099": return "1099"
        case "us_ein_letter": return "EIN Letter"
        case "shipper_agreement", "broker_agreement", "carrier_packet", "factoring_agreement", "nda":
            return "Agreement"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func glyphFor(_ raw: String) -> String {
        switch raw {
        case "bill_of_lading", "load_tender", "load_csv", "rate_confirmation":
            return "shippingbox.fill"
        case "run_ticket", "weight_ticket", "scale_ticket":
            return "fuelpump.fill"
        case "proof_of_delivery":
            return "checkmark.seal.fill"
        case let t where t.hasPrefix("us_") || t.hasPrefix("ca_") || t.hasPrefix("mx_") || t.hasPrefix("fra_") || t.hasPrefix("uscg_"):
            return "creditcard.fill"
        case "w9", "form_1099", "us_ein_letter":
            return "doc.text.fill"
        case "shipper_agreement", "broker_agreement", "carrier_packet", "factoring_agreement", "nda":
            return "signature"
        default:
            return "doc.fill"
        }
    }

    // MARK: — Pipeline

    @MainActor
    private func classifyPickerItems(_ items: [PhotosPickerItem]) async {
        guard !inflight else { return }
        inflight = true
        defer { inflight = false }
        error = nil
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { continue }
            await classify(data: data, mime: detectMime(data), source: "photo")
        }
    }

    @MainActor
    private func classifyFileImport(_ result: Result<[URL], Error>) async {
        guard !inflight else { return }
        inflight = true
        defer { inflight = false }
        error = nil
        do {
            let urls = try result.get()
            for url in urls {
                let needsScope = url.startAccessingSecurityScopedResource()
                defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { continue }
                let mime = mimeFor(url: url) ?? detectMime(data)
                await classify(data: data, mime: mime, source: "file")
            }
        } catch {
            self.error = "Couldn't read the picked file: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func classify(data: Data, mime: String, source: String) async {
        let compressed = compressIfNeeded(data: data, mime: mime)
        let base64 = compressed.base64EncodedString()
        guard let mt = DocumentRouterAPI.MimeType(rawValue: mime)
            ?? DocumentRouterAPI.MimeType(rawValue: "image/jpeg") else { return }

        do {
            let resp = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                documentBase64: base64,
                mimeType: mt,
                callerContext: callerContext
            )
            let fields: [String: String] = resp.extractedFields.compactMapValues { $0.asString }
            let doc = ClassifiedDocument(
                id: UUID().uuidString,
                classifiedType: resp.classifiedType,
                confidence: resp.confidence,
                summary: resp.summary,
                dispatchTarget: resp.dispatchTarget,
                warnings: resp.warnings,
                fields: fields,
                mimeType: mime,
                documentBase64: base64
            )
            if mode == .prefillWizard {
                // Single-doc → replace results so the latest scan is
                // the one the user applies.
                results = [doc]
            } else {
                results.append(doc)
            }
        } catch {
            self.error = "Classify failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    // MARK: — Helpers

    private func detectMime(_ data: Data) -> String {
        // PDF: starts with "%PDF"
        if data.count > 4, data[0] == 0x25, data[1] == 0x50, data[2] == 0x44, data[3] == 0x46 {
            return "application/pdf"
        }
        // PNG: 89 50 4E 47
        if data.count > 4, data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47 {
            return "image/png"
        }
        // Fallback to JPEG (everything else, including HEIC after compress)
        return "image/jpeg"
    }

    private func mimeFor(url: URL) -> String? {
        if let t = UTType(filenameExtension: url.pathExtension) {
            if t.conforms(to: .pdf) { return "application/pdf" }
            if t.conforms(to: .png) { return "image/png" }
            if t.conforms(to: .jpeg) { return "image/jpeg" }
            if t.conforms(to: .heic) { return "image/heic" }
            // CSV / XLS / Text — treat as JPEG-of-pdf-shape isn't right;
            // pass as PDF mime so Gemini reads as text. (Gemini Vision
            // accepts text/plain via PDF wrapping when no native CSV
            // support; for now route via application/pdf to keep the
            // wire shape simple.)
            if t.conforms(to: .commaSeparatedText) || t.conforms(to: .spreadsheet) {
                return "application/pdf"
            }
        }
        return nil
    }

    private func compressIfNeeded(data: Data, mime: String) -> Data {
        if mime == "application/pdf" || data.count <= 900_000 { return data }
        guard let img = UIImage(data: data) else { return data }
        for q in [CGFloat(0.85), 0.75, 0.65, 0.55, 0.45] {
            if let d = img.jpegData(compressionQuality: q), d.count <= 900_000 {
                return d
            }
        }
        return img.jpegData(compressionQuality: 0.45) ?? data
    }
}

// MARK: - Document camera wrapper

private struct DocumentClassifierCameraSheet: UIViewControllerRepresentable {
    let onResult: (Data?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(onResult: onResult) }

    final class Coord: NSObject, VNDocumentCameraViewControllerDelegate {
        let onResult: (Data?) -> Void
        init(onResult: @escaping (Data?) -> Void) { self.onResult = onResult }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else { onResult(nil); return }
            let image = scan.imageOfPage(at: 0)
            onResult(image.jpegData(compressionQuality: 0.9))
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onResult(nil)
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onResult(nil)
        }
    }
}

// MARK: - Previews

#Preview("Templates · Pre-fill · Dark") {
    DocumentClassifierSheet(
        mode: .prefillWizard,
        callerContext: "shipper Post-Load Templates",
        onApplySingle: { _ in },
        onDispatchBatch: { _ in }
    )
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("Bulk · Batch · Light") {
    DocumentClassifierSheet(
        mode: .batch,
        callerContext: "shipper Post-Load Bulk",
        onApplySingle: { _ in },
        onDispatchBatch: { _ in }
    )
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
