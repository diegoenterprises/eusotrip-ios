//
//  693_VesselDocumentIngest.swift
//  EusoTrip — Vessel Operator · Document Ingest (CARRIER-SIDE · BOARD/QUEUE class).
//
//  Verbatim port of "693 Vessel Document Ingest.svg" (Dark + Light). A bespoke
//  OCR INGEST QUEUE (FourKites/project44 doc-parsing parity): an ingest-progress
//  hero (parsed ring), then a document queue where every row carries a doc-type
//  chip, a parse-state pill (PARSED / REVIEW / CLASSIFYING) and a re-scan action.
//  Deliberately NOT the batch-stamped stat-banner + 3-tile skeleton.
//
//  Web parity: DocumentIntelligence.tsx (`/documents`).
//
//  DATA (endpoints confirmed on disk this fire):
//    documentManagement.getDocumentDashboard → { totalDocuments, pendingReview,
//                                               expiringSoon, expired, byType, byStatus, recentUploads }
//                                               (protectedProcedure · server/routers/documentManagement.ts:350)
//    documentManagement.getDocuments {page,pageSize,sortBy,sortOrder}
//                                     → { documents[], total, page, pageSize, totalPages }
//                                               (protectedProcedure · documentManagement.ts:454)
//    documentManagement.extractDocumentData {documentId} → { success, extractedData }
//                                               (MUTATION · re-scan/re-extract · documentManagement.ts:807)
//
//  HONEST GAPS (surfaced to the-oath — NOT papered over):
//    • The `documents` row carries NO numeric OCR-confidence field (mapDocRow
//      ships an ocrExtractedData JSON blob, not a 0–100 score). This port shows
//      the parse-STATE pill from the real `status`, not a fabricated 61%/98%
//      gauge. Propose a numeric documents.ocrConfidence column so the confidence
//      gauge binds to a stored value.
//    • The vessel-specific document→booking AUTO-LINK with a confidence score is
//      not a typed field — propose documentManagement.linkToBooking
//      {docId, shipmentId, confidence}.
//    • "Upload document" needs the native file picker to hand bytes to
//      documentManagement.uploadDocument; the primary CTA here re-extracts the
//      first review-state doc (a real mutation) rather than dead-tapping.
//
//  NAV (VesselOperatorNavController): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//  transportMode=vessel · US import doc-set. PERSONA Vessel Operator · Aurora Ocean Division.
//

import SwiftUI

struct VesselDocumentIngestScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselDocumentIngestBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct DocDashboardStatus: Decodable { let status: String?; let count: Int? }
private struct DocDashboard: Decodable {
    let totalDocuments: Int
    let pendingReview: Int
    let expiringSoon: Int
    let expired: Int
    let byStatus: [DocDashboardStatus]
}

private struct DocRow: Decodable, Identifiable {
    let id: String
    let name: String?
    let type: String?
    let status: String?
    let category: String?
    let uploadedAt: String?
}
private struct DocumentsResponse: Decodable {
    let documents: [DocRow]
    let total: Int
    let totalPages: Int
}
private struct ExtractOut: Decodable { let success: Bool }

// MARK: - Body

private struct VesselDocumentIngestBody: View {
    @Environment(\.palette) private var palette

    @State private var dashboard: DocDashboard? = nil
    @State private var docs: DocumentsResponse? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var rescanning: String? = nil
    @State private var actionAck: String? = nil
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline().padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s4) {
                    ingestHero
                    ingestQueue
                    ctaPair
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var rows: [DocRow] { docs?.documents ?? [] }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ VESSEL OPERATOR · DOCUMENT INGEST")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("\(dashboard?.totalDocuments ?? 0) DOCS")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Booking documents")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary).padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5)
    }

    // MARK: Ingest hero (parsed ring)

    private var ingestHero: some View {
        HStack(spacing: Space.s4) {
            ZStack {
                Circle().stroke(palette.borderFaint, lineWidth: 7)
                Circle().trim(from: 0, to: max(0.001, min(1, parsedFraction)))
                    .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(parsedCount)/\(dashboard?.totalDocuments ?? 0)")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("PARSED").font(.system(size: 7, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 4) {
                Text("getDocumentDashboard")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary)
                Text("\(dashboard?.pendingReview ?? 0) in review")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(dashboard?.expiringSoon ?? 0) expiring · \(dashboard?.expired ?? 0) expired")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            StatusPill(text: "AI Parsing", kind: .info)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    private var parsedCount: Int {
        guard let d = dashboard else { return 0 }
        return max(0, d.totalDocuments - d.pendingReview)
    }
    private var parsedFraction: Double {
        guard let d = dashboard, d.totalDocuments > 0 else { return 0 }
        return Double(parsedCount) / Double(d.totalDocuments)
    }

    // MARK: Ingest queue

    private var ingestQueue: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("INGEST QUEUE · getDocuments · extractDocumentData")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            if loading {
                LifecycleCard { Text("Loading ingest queue…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
            } else if rows.isEmpty {
                EusoEmptyState(icon: Image(systemName: "tray.and.arrow.down"),
                               title: "Inbox is empty",
                               subtitle: "Booking documents you upload or that arrive by EDI land here for auto-classification.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, doc in
                        docRow(doc)
                        if idx < rows.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s1)
                        }
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.lg)
            }

            if let actionAck { Text(actionAck).font(EType.caption).foregroundStyle(Brand.success) }
            if let actionError { Text(actionError).font(EType.caption).foregroundStyle(Brand.danger) }
        }
    }

    private func docRow(_ doc: DocRow) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(parseTint(doc.status).opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: docIcon(doc.type)).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(parseTint(doc.status))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.name?.isEmpty == false ? doc.name! : humanType(doc.type))
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(humanType(doc.type)) · \(doc.category ?? "document")")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(text: parseState(doc.status), kind: parseKind(doc.status))
                Button {
                    Task { await rescan(doc) }
                } label: {
                    Text(rescanning == doc.id ? "…" : "Re-scan")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.info)
                }
                .buttonStyle(.plain)
                .disabled(rescanning != nil)
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await rescanFirstReview() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.viewfinder").font(.system(size: 15, weight: .bold))
                    Text("Re-scan next in review").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .opacity(rescanning != nil ? 0.6 : 1)
            }
            .buttonStyle(.plain).disabled(rescanning != nil)

            Button { Task { await load() } } label: {
                Text("Resync").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary).frame(width: 110, height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct DocsIn: Encodable { let page = 1; let pageSize = 20; let sortBy = "uploadedAt"; let sortOrder = "desc" }
        do {
            async let d: DocDashboard = EusoTripAPI.shared.queryNoInput("documentManagement.getDocumentDashboard")
            async let q: DocumentsResponse = EusoTripAPI.shared.query("documentManagement.getDocuments", input: DocsIn())
            self.dashboard = try await d
            self.docs = try await q
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func rescan(_ doc: DocRow) async {
        actionAck = nil; actionError = nil; rescanning = doc.id
        struct In: Encodable { let documentId: String }
        do {
            let out: ExtractOut = try await EusoTripAPI.shared.mutation("documentManagement.extractDocumentData", input: In(documentId: doc.id))
            actionAck = out.success ? "Re-extracted \(humanType(doc.type))." : "Server could not re-extract that document."
            await load()
        } catch {
            actionError = error.eusoUserCopy
        }
        rescanning = nil
    }

    private func rescanFirstReview() async {
        guard let target = rows.first(where: { parseKind($0.status) == .warning }) ?? rows.first else {
            actionError = "No documents to re-scan."
            return
        }
        await rescan(target)
    }

    // MARK: helpers

    private func humanType(_ t: String?) -> String {
        switch (t ?? "").lowercased() {
        case "bol": return "Bill of lading"
        case "invoice", "commercial_invoice": return "Commercial invoice"
        case "packing_list": return "Packing list"
        case "isf": return "ISF 10+2"
        case "customs": return "Customs entry"
        case "", "other": return "Document"
        default: return (t ?? "Document").replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    private func docIcon(_ t: String?) -> String {
        switch (t ?? "").lowercased() {
        case "bol": return "doc.text.fill"
        case "invoice", "commercial_invoice": return "dollarsign.square"
        case "packing_list": return "shippingbox"
        case "isf", "customs": return "checkmark.seal"
        default: return "doc"
        }
    }
    private func parseState(_ s: String?) -> String {
        switch (s ?? "").lowercased() {
        case "active", "approved", "parsed", "signed": return "Parsed"
        case "pending_review", "pending", "review": return "Review"
        case "processing", "classifying": return "Classifying"
        case "rejected", "expired": return "Attention"
        default: return (s ?? "—").replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    private func parseKind(_ s: String?) -> StatusPill.Kind {
        switch (s ?? "").lowercased() {
        case "active", "approved", "parsed", "signed": return .success
        case "pending_review", "pending", "review": return .warning
        case "processing", "classifying": return .info
        case "rejected", "expired": return .danger
        default: return .neutral
        }
    }
    private func parseTint(_ s: String?) -> Color {
        switch parseKind(s) {
        case .success: return Brand.success
        case .warning: return Brand.warning
        case .danger: return Brand.danger
        case .info: return Brand.info
        default: return Brand.neutral
        }
    }
}

#Preview("693 · Vessel Document Ingest · Night") {
    VesselDocumentIngestScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("693 · Vessel Document Ingest · Light") {
    VesselDocumentIngestScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
