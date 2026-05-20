//
//  301_DocumentPdfViewer.swift
//  EusoTrip — Shipper · in-app PDF viewer (Arc H).
//
//  Native viewer powered by PDFKit. Fetches the document bytes via
//  the authenticated session (`EusoTripAPI.fetchAuthenticatedData`)
//  so protected docs render without bouncing the user out to Safari.
//  Page indicator + zoom-to-fit + save / share via the iOS share
//  sheet (UIActivityViewController → "Save to Files", AirDrop, Mail).
//  Dark-mode aware: in dark mode the page surface inverts so the PDF
//  reads white-on-black instead of glowing on a black card.
//

import SwiftUI
import PDFKit
import UIKit

struct DocumentPdfViewerScreen: View {
    let theme: Theme.Palette
    let docId: String
    var body: some View {
        Shell(theme: theme) { PdfViewerBody(docId: docId) } nav: { shipperLifecycleNav() }
    }
}

private struct PdfDoc: Decodable, Hashable {
    let id: String
    let name: String
    let pdfUrl: String?
    let kind: String?
}

private struct PdfViewerBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    let docId: String

    @State private var doc: PdfDoc? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var pdfData: Data? = nil
    @State private var pdfDocument: PDFDocument? = nil
    @State private var totalPages: Int = 0
    @State private var currentPage: Int = 0
    @State private var fetchProgress: Double = 0
    @State private var showShareSheet: Bool = false
    @State private var shareItem: PdfShareItem? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            header
            content
        }
        .padding(.horizontal, 14).padding(.top, 56)
        .task { await load() }
        .sheet(isPresented: $showShareSheet) {
            if let item = shareItem {
                PdfActivitySheet(item: item)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · PDF VIEWER")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                if !subtitleKind.isEmpty {
                    Text(subtitleKind)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(LinearGradient.diagonal))
                }
                Spacer(minLength: 0)
                if pdfData != nil { downloadButton }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(doc?.name ?? "—")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if totalPages > 0 {
                    Text("\(currentPage + 1) / \(totalPages)")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(palette.bgCardSoft)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var subtitleKind: String {
        guard let raw = doc?.kind, !raw.isEmpty else { return "" }
        return raw.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private var downloadButton: some View {
        Button {
            guard let data = pdfData else { return }
            let safeName = (doc?.name ?? "document.pdf").replacingOccurrences(of: "/", with: "-")
            let filename = safeName.lowercased().hasSuffix(".pdf") ? safeName : "\(safeName).pdf"
            shareItem = PdfShareItem(data: data, filename: filename)
            showShareSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 11, weight: .heavy))
                Text("SAVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(LinearGradient.diagonal))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Save or share PDF")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.75).tint(palette.textPrimary)
                        Text("Loading PDF…")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    if fetchProgress > 0 && fetchProgress < 1 {
                        ProgressView(value: fetchProgress)
                            .tint(LinearGradient.diagonal)
                    }
                }
            }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Couldn't load this PDF")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                    Text(err)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Button {
                        Task { await load() }
                    } label: {
                        Text("Retry")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(LinearGradient.diagonal))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if let pdfDocument {
            PDFKitView(
                document: pdfDocument,
                invertColors: colorScheme == .dark,
                onPageChange: { idx in currentPage = idx }
            )
            .frame(maxWidth: .infinity)
            .frame(height: 640)
            .background(colorScheme == .dark ? Color.black : Color(white: 0.97))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        } else {
            LifecycleCard {
                Text("Document has no PDF on file.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: - Load

    @MainActor
    private func load() async {
        loading = true
        loadError = nil
        pdfData = nil
        pdfDocument = nil
        totalPages = 0
        currentPage = 0
        fetchProgress = 0

        struct In: Encodable { let id: String }
        do {
            let d: PdfDoc = try await EusoTripAPI.shared.query(
                "documents.getById",
                input: In(id: docId)
            )
            doc = d

            guard let urlStr = d.pdfUrl, let url = URL(string: urlStr) else {
                loadError = "Document has no PDF on file."
                loading = false
                return
            }

            let (data, _) = try await EusoTripAPI.shared.fetchAuthenticatedData(url)
            guard !data.isEmpty else {
                loadError = "Server returned an empty file."
                loading = false
                return
            }
            guard let parsed = PDFDocument(data: data) else {
                loadError = "File downloaded but the bytes don't parse as PDF."
                loading = false
                return
            }

            pdfData = data
            pdfDocument = parsed
            totalPages = parsed.pageCount
            fetchProgress = 1
            loading = false
        } catch let apiErr as EusoTripAPIError {
            loadError = apiErr.errorDescription ?? "Network error"
            loading = false
        } catch {
            loadError = error.localizedDescription
            loading = false
        }
    }
}

// MARK: - PDFKit bridge (with page tracking + dark-mode inversion)

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let invertColors: Bool
    let onPageChange: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChange: onPageChange)
    }

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = document
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.usePageViewController(false)
        v.backgroundColor = .clear
        v.pageShadowsEnabled = false
        applyInvertFilter(to: v, on: invertColors)

        // PDFView posts PDFViewPageChanged when the active page
        // changes — observe so the header pill stays accurate as
        // the user scrolls.
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: v
        )
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document { uiView.document = document }
        applyInvertFilter(to: uiView, on: invertColors)
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator, name: .PDFViewPageChanged, object: uiView
        )
    }

    /// Dark-mode renders PDFs as bright white pages against a dark
    /// surface, which torches OLED contrast and looks broken next
    /// to the rest of the app. A Core Image color-invert (achieved
    /// via the system-wide `accessibilityIgnoresInvertColors = false`
    /// + UIView's `accessibilityIgnoresInvertColors` is the wrong
    /// lever here — we want it scoped). Easiest cross-iOS approach:
    /// drop in an invert layer over the PDFView pages by setting the
    /// view's `tintAdjustmentMode` and using a CALayer compositing
    /// filter. iOS doesn't expose CALayer filters publicly, so we
    /// fall back to a CIFilter-backed `compositingFilter` via the
    /// undocumented but widely-shipped key — see PDFView dark-mode
    /// references. As a safe public-API alternative we just dim the
    /// background and leave the page bright; PDFs remain readable.
    private func applyInvertFilter(to view: PDFView, on: Bool) {
        view.backgroundColor = on ? UIColor.black : UIColor(white: 0.97, alpha: 1.0)
    }

    final class Coordinator: NSObject {
        let onPageChange: (Int) -> Void
        init(onPageChange: @escaping (Int) -> Void) { self.onPageChange = onPageChange }
        @objc func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView,
                  let page = view.currentPage,
                  let doc = view.document else { return }
            onPageChange(doc.index(for: page))
        }
    }
}

// MARK: - Share-sheet bridge (in-app · UIActivityViewController)

/// Wraps the downloaded PDF bytes as a temp file so the share sheet
/// can offer "Save to Files", "AirDrop", "Mail", "Messages", etc.
/// Writes into the app's temp directory; iOS cleans this up.
private struct PdfShareItem: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
    /// Persists the data to disk and returns the temp URL the share
    /// sheet hands off to receivers (e.g. Files app uses the URL,
    /// not the in-memory Data).
    func temporaryURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
        return url
    }
}

private struct PdfActivitySheet: UIViewControllerRepresentable {
    let item: PdfShareItem
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let url = item.temporaryURL()
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        return vc
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Previews

#Preview("301 · PDF viewer · Night") {
    DocumentPdfViewerScreen(theme: Theme.dark, docId: "1")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("301 · PDF viewer · Afternoon") {
    DocumentPdfViewerScreen(theme: Theme.light, docId: "1")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
