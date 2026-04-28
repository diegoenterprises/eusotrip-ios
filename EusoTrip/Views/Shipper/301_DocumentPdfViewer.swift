//
//  301_DocumentPdfViewer.swift
//  EusoTrip — Shipper · PDF viewer (Arc H).
//

import SwiftUI
import PDFKit

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
    let docId: String
    @State private var doc: PdfDoc? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            header
            content
        }
        .padding(.horizontal, 14).padding(.top, 8)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · PDF VIEWER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(doc?.name ?? "—").font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading PDF…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if let url = doc?.pdfUrl, let u = URL(string: url) {
            PDFKitView(url: u)
                .frame(maxWidth: .infinity)
                .frame(height: 600)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        } else {
            LifecycleCard { Text("Document has no PDF on file.").font(EType.caption).foregroundStyle(palette.textSecondary) }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let id: String }
        do {
            let d: PdfDoc = try await EusoTripAPI.shared.api.query("documents.getById", input: In(id: docId))
            doc = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        Task.detached {
            if let doc = PDFDocument(url: url) {
                await MainActor.run { v.document = doc }
            }
        }
        return v
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}

#Preview("301 · PDF viewer · Night") {
    DocumentPdfViewerScreen(theme: Theme.dark, docId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("301 · PDF viewer · Afternoon") {
    DocumentPdfViewerScreen(theme: Theme.light, docId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
