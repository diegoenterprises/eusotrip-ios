//
//  EusoPDFViewer.swift
//  EusoTrip — Canonical in-app PDF viewer with optional signing.
//
//  Founder doctrine 2026-05-07: every contract / BOL / EusoTicket /
//  legal doc renders IN-APP. No more `UIApplication.open(URL)` to
//  the web. Signing capabilities use the Eusorone gradient ink
//  (Brand.blue → Brand.magenta) instead of flat black.
//
//  Usage:
//
//      EusoPDFViewer(
//          source: .url(pdfURL),
//          allowSigning: true,
//          onSigned: { signaturePNG, signatureBase64 in
//              // upload to backend
//          }
//      )
//
//  Or with raw PDF Data:
//
//      EusoPDFViewer(source: .data(pdfData))
//

import SwiftUI
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// What to render. URL covers downloaded files; Data covers
/// in-memory PDFs (e.g. `eusoTicket.generateBOLPDF` returns a
/// base64 string the caller decodes).
enum EusoPDFSource {
    case url(URL)
    case data(Data)
}

/// Identifiable URL wrapper for `.sheet(item:)` / `.fullScreenCover(item:)`
/// presentation across all the in-app PDF surfaces (BOL, run ticket,
/// settlement, statement, hazmat manifest, partner agreement,
/// insurance certificate, etc.). Re-presents per-tap when the URL
/// changes — the UUID id ensures SwiftUI doesn't dedupe identical
/// repeat presentations.
struct EusoPDFPresentation: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let title: String
    let subtitle: String?
    let loadIdForWalletPass: String?

    init(url: URL,
         title: String,
         subtitle: String? = nil,
         loadIdForWalletPass: String? = nil) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.loadIdForWalletPass = loadIdForWalletPass
    }
}

struct EusoPDFViewer: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String?
    let source: EusoPDFSource
    var allowSigning: Bool = false
    var onSigned: ((UIImage, String) -> Void)? = nil
    /// When non-nil, surfaces an "Add to Apple Wallet" affordance in
    /// the top bar — the underlying load id is used to fetch the
    /// signed `.pkpass` via `EusoWalletPassService.addPass`.
    var loadIdForWalletPass: String? = nil

    @State private var doc: PDFDocument? = nil
    @State private var loadError: String? = nil
    @State private var showSignSheet: Bool = false
    @State private var fetchedData: Data? = nil
    @State private var showShareSheet: Bool = false
    @State private var fileURLForExport: URL? = nil
    @State private var walletBusy: Bool = false
    @State private var walletAck: String? = nil
    @State private var savedAck: String? = nil
    /// Drives the SwiftUI fileExporter for Download. Was previously
    /// a manual UIDocumentPickerViewController presentation that
    /// walked the UIWindowScene topmost VC and presented on top of
    /// the already-sheet'd PDF viewer. iOS 17/18 punished that
    /// with the "presenting view controller already presenting"
    /// path that the founder reported as the download-glitch /
    /// must-force-close-app symptom on 2026-05-24.
    @State private var showFileExporter: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().background(palette.borderFaint)
            content
            if allowSigning {
                signFooter
            }
        }
        .background(palette.bgPrimary)
        .task { await loadDoc() }
        .sheet(isPresented: $showSignSheet) {
            EusoSignaturePadSheet { image in
                showSignSheet = false
                if let onSigned, let data = image.pngData() {
                    onSigned(image, data.base64EncodedString())
                }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = fileURLForExport ?? writeShareTempIfNeeded() {
                EusoShareSheet(items: [url])
            }
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: PDFExportDocument(data: fetchedData ?? doc?.dataRepresentation() ?? Data()),
            contentType: .pdf,
            defaultFilename: title.replacingOccurrences(of: "/", with: "-")
        ) { result in
            switch result {
            case .success:
                savedAck = "Saved to Files"
            case .failure(let err):
                savedAck = "Save canceled — \(err.localizedDescription)"
            }
            scheduleAckClear()
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 6) {
                if let toast = walletAck { toastChip(text: toast, success: true) }
                if let toast = savedAck  { toastChip(text: toast, success: true) }
            }
            .padding(.bottom, 24)
        }
    }

    private func toastChip(text: String, success: Bool) -> some View {
        Text(text)
            .font(EType.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(success ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Brand.danger)))
    }

    private struct ExportTarget: Identifiable { let id = UUID(); let url: URL }

    // MARK: - Bars

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // Apple Wallet — only when a load id is provided.
            if let _ = loadIdForWalletPass {
                Button { Task { await addToAppleWallet() } } label: {
                    HStack(spacing: 4) {
                        if walletBusy {
                            ProgressView().tint(.white).scaleEffect(0.7)
                        } else {
                            Image(systemName: "wallet.pass.fill")
                                .font(.system(size: 13, weight: .heavy))
                        }
                        Text("Wallet")
                            .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
                .disabled(walletBusy)
            }
            // Download — surfaces SwiftUI's fileExporter (system Files
            // picker) instead of presenting UIDocumentPickerViewController
            // manually on top of the already-presented sheet. Bug
            // 2026-05-24 ("download glitches the app, must force close")
            // was caused by the previous manual presentation racing
            // with the sheet's own presentation chain.
            Button { showFileExporter = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Download")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                }
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)
            // Share sheet — printer / iMessage / mail / etc.
            Button { showShareSheet = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.s5)
        .padding(.vertical, Space.s3)
    }

    @ViewBuilder
    private var content: some View {
        if let doc {
            EusoPDFKitView(document: doc)
                .background(palette.bgCardSoft)
        } else if let err = loadError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("Couldn't load document")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                ProgressView().tint(LinearGradient.diagonal)
                Text("Loading document…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var signFooter: some View {
        Button { showSignSheet = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "signature")
                    .font(.system(size: 13, weight: .heavy))
                Text("Sign with gradient ink")
                    .font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(LinearGradient.diagonal)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var shareItem: URL {
        switch source {
        case .url(let u):  return u
        case .data:
            // Write to a temp file for share-sheet compatibility.
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).pdf")
            if case .data(let d) = source {
                try? d.write(to: tmp)
            }
            return tmp
        }
    }

    private func loadDoc() async {
        switch source {
        case .url(let url):
            // Async fetch on a background queue so the main thread
            // doesn't stall on remote PDFs.
            do {
                let data = try await Self.fetchData(from: url)
                if let pdf = PDFDocument(data: data) {
                    await MainActor.run {
                        doc = pdf
                        fetchedData = data
                    }
                } else {
                    await MainActor.run { loadError = "Document is not a valid PDF." }
                }
            } catch {
                await MainActor.run {
                    loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        case .data(let d):
            if let pdf = PDFDocument(data: d) {
                doc = pdf
                fetchedData = d
            } else {
                loadError = "Document is not a valid PDF."
            }
        }
    }

    private static func fetchData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }
        // Route through EusoTripAPI so the bearer token is attached
        // when the URL is on our origin (auth-protected docs would
        // otherwise return 401 here and the viewer would render the
        // "not a valid PDF" empty state). Falls back to the
        // unauthenticated URLSession for fully-public URLs.
        let (data, _) = try await EusoTripAPI.shared.fetchAuthenticatedData(url)
        return data
    }

    /// Writes the current PDF bytes to a temp .pdf file so the
    /// share sheet / Files picker can hand it to other apps.
    private func writeShareTempIfNeeded() -> URL? {
        if let url = fileURLForExport { return url }
        guard let data = fetchedData ?? doc?.dataRepresentation() else { return nil }
        let safeTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeTitle)-\(Int(Date().timeIntervalSince1970)).pdf")
        do {
            try data.write(to: tmp, options: .atomic)
            fileURLForExport = tmp
            return tmp
        } catch {
            return nil
        }
    }

    /// Save-to-Files via UIDocumentPickerViewController. Hosts the
    /// pickerand presents from the topmost view controller.
    private func downloadPDF() async {
        guard let url = writeShareTempIfNeeded() else {
            savedAck = "Couldn't prepare PDF."
            scheduleAckClear()
            return
        }
        await MainActor.run {
            let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            picker.shouldShowFileExtensions = true
            picker.modalPresentationStyle = .formSheet
            // Best-effort topmost-presentation; uses the connected
            // UIWindowScene root.
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
               let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                var top = root
                while let p = top.presentedViewController { top = p }
                top.present(picker, animated: true)
            }
            savedAck = "Saved · pick a destination"
            scheduleAckClear()
        }
    }

    /// Adds the underlying load to Apple Wallet via the platform's
    /// signed `.pkpass` flow — surfaces the system PKAddPassesViewController.
    private func addToAppleWallet() async {
        guard let loadId = loadIdForWalletPass else { return }
        walletBusy = true
        defer { walletBusy = false }
        let result = await EusoWalletPassService.shared.addPass(forLoadId: loadId)
        await MainActor.run {
            switch result {
            case .presented:
                walletAck = "Apple Wallet sheet presented"
            case .signingUnavailable:
                walletAck = "Wallet pass not yet available — try after dispatch"
            case .failure(let msg):
                walletAck = "Wallet error: \(msg)"
            }
            scheduleAckClear()
        }
    }

    private func scheduleAckClear() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            walletAck = nil
            savedAck = nil
        }
    }
}

/// Bridge to UIActivityViewController — needed so we can present
/// the share sheet with a saved file URL without depending on
/// SwiftUI ShareLink's URL-only restrictions.
private struct EusoShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// FileDocument wrapper for SwiftUI's `.fileExporter` modifier.
/// Backs the Download button — replaces the manual UIDocumentPicker
/// presentation that glitched the app (founder bug 2026-05-24).
private struct PDFExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    static var writableContentTypes: [UTType] { [.pdf] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - PDFKit bridge

private struct EusoPDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = document
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .clear
        v.usePageViewController(false)
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}

// MARK: - Signature pad (gradient ink)

struct EusoSignaturePadSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let onCommit: (UIImage) -> Void

    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign here")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(Space.s4)

            // Pad
            ZStack {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
                    )
                Canvas { context, size in
                    // Render committed strokes + active stroke with
                    // the EusoTrip gradient ink.
                    let allStrokes = strokes + (current.isEmpty ? [] : [current])
                    for stroke in allStrokes {
                        guard stroke.count > 1 else { continue }
                        var path = Path()
                        path.addLines(stroke)
                        context.stroke(
                            path,
                            with: .linearGradient(
                                Gradient(colors: [Brand.blue, Brand.magenta]),
                                startPoint: .zero,
                                endPoint: CGPoint(x: size.width, y: size.height)
                            ),
                            style: StrokeStyle(
                                lineWidth: 3,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                }
                if strokes.isEmpty && current.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "signature")
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal.opacity(0.6))
                        Text("Sign with your finger")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                    .allowsHitTesting(false)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in current.append(v.location) }
                    .onEnded { _ in
                        if !current.isEmpty {
                            strokes.append(current)
                            current = []
                        }
                    }
            )
            .padding(Space.s4)

            // Footer actions
            HStack(spacing: Space.s2) {
                Button {
                    strokes.removeAll()
                    current.removeAll()
                } label: {
                    Text("Clear")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(palette.bgCard)
                        .overlay(Capsule().strokeBorder(palette.borderFaint))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(strokes.isEmpty)

                Button {
                    if let img = renderImage() {
                        onCommit(img)
                    }
                } label: {
                    Text("Commit signature")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(strokes.isEmpty)
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s5)
        }
        .background(palette.bgPrimary)
    }

    /// Rasterizes the committed strokes into a 600×240 PNG. Caller
    /// receives the UIImage; can also encode to base64 for upload.
    private func renderImage() -> UIImage? {
        let size = CGSize(width: 600, height: 240)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // Solid white background — most BOLs / contracts expect
            // a clean signature on white.
            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            // Approximate the on-screen pad → render-target scale.
            // Strokes are stored in pad-local coordinates (~ 0..360
            // wide). Rough scale to 600 keeps proportions.
            let scaleX: CGFloat = size.width / 360.0
            let scaleY: CGFloat = size.height / 200.0
            cg.translateBy(x: 0, y: 0)
            cg.scaleBy(x: scaleX, y: scaleY)
            cg.setLineWidth(3 / max(scaleX, 1))
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            // Gradient ink: render each stroke segment with a linear
            // gradient. Keep simple — UIKit doesn't expose
            // CGContext.linearGradient on a stroked path directly,
            // so use brand magenta as the rasterized ink color
            // (the SwiftUI canvas already shows the gradient
            // preview).
            let cgColors = [
                UIColor(Brand.blue).cgColor,
                UIColor(Brand.magenta).cgColor
            ]
            for stroke in strokes {
                guard stroke.count > 1 else { continue }
                cg.beginPath()
                cg.move(to: stroke[0])
                for p in stroke.dropFirst() {
                    cg.addLine(to: p)
                }
                cg.replacePathWithStrokedPath()
                cg.clip()
                if let grad = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: cgColors as CFArray,
                    locations: [0.0, 1.0]
                ) {
                    cg.drawLinearGradient(
                        grad,
                        start: .zero,
                        end: CGPoint(x: size.width / scaleX, y: size.height / scaleY),
                        options: []
                    )
                }
                cg.resetClip()
            }
        }
    }
}

// MARK: - Previews

#Preview("Empty PDF · Loading state") {
    EusoPDFViewer(
        title: "Sample contract",
        subtitle: "Eusorone · 2026-05-07",
        source: .data(Data()),
        allowSigning: true
    )
    .preferredColorScheme(.dark)
}
