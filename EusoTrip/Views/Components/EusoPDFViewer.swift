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

/// What to render. URL covers downloaded files; Data covers
/// in-memory PDFs (e.g. `eusoTicket.generateBOLPDF` returns a
/// base64 string the caller decodes).
enum EusoPDFSource {
    case url(URL)
    case data(Data)
}

struct EusoPDFViewer: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String?
    let source: EusoPDFSource
    var allowSigning: Bool = false
    var onSigned: ((UIImage, String) -> Void)? = nil

    @State private var doc: PDFDocument? = nil
    @State private var loadError: String? = nil
    @State private var showSignSheet: Bool = false

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
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
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
            ShareLink(item: shareItem)
                .labelStyle(.iconOnly)
                .tint(LinearGradient.diagonal)
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
                    await MainActor.run { doc = pdf }
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
            } else {
                loadError = "Document is not a valid PDF."
            }
        }
    }

    private static func fetchData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(
                domain: "EusoPDFViewer", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server returned status \(http.statusCode)"]
            )
        }
        return data
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
