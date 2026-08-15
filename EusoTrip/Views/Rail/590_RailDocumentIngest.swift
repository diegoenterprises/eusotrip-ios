//
//  590_RailDocumentIngest.swift
//  EusoTrip — Rail 590 · Document Ingest (ESANG AI)
//

import SwiftUI

// MARK: - Outer shell

struct RailDocumentIngestScreen: View {
    let theme: Theme.Palette
    let documentId: String

    var body: some View {
        Shell(theme: theme) {
            RailDocumentIngestBody(documentId: documentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else {
            value = NSNull()
        }
    }

    var displayValue: String {
        switch value {
        case let string as String: return string
        case let int as Int: return String(int)
        case let double as Double: return String(format: "%g", double)
        case let bool as Bool: return bool ? "Yes" : "No"
        default: return ""
        }
    }

}

private struct DocDashboard590: Decodable {
    let totalDocuments: Int?
    let pendingReview: Int?
    let expiringSoon: Int?
    let expired: Int?
    let recentUploads: [[String: AnyCodable]]?
    let byCategory: [[String: AnyCodable]]?
    let byType: [[String: AnyCodable]]?
    let byStatus: [[String: AnyCodable]]?
    let activeWorkflows: Int?
    let pendingSignatures: Int?
    let templatesAvailable: Int?

    // Backward-compat computed properties for the view
    var docsToday: Int? { totalDocuments }
    var docsStatusLabel: String? {
        if let pending = pendingReview, pending > 0 {
            return "\(pending) pending review"
        }
        return nil
    }
}

private struct DocIdIn590: Encodable { let documentId: String }

private struct DocumentExtractionWire590: Decodable {
    struct Classification: Decodable {
        let type: String
        let confidence: Double
    }

    let success: Bool
    let status: String
    let extractedData: [String: AnyCodable]?
    let fieldsExtracted: Int
    let confidence: Double
    let classification: Classification
    let regulatedFields: [String]
    let grounded: Bool
    let requiresHumanConfirmation: Bool
    let warnings: [String]
    let error: String?
}

// MARK: - Body

private struct RailDocumentIngestBody: View {
    @Environment(\.palette) private var palette
    let documentId: String

    @State private var extraction: DocumentExtractionWire590? = nil
    @State private var dashboard: DocDashboard590? = nil
    @State private var isCreating = false
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil

    // MARK: Derived

    private var confidencePct: Double { min(max((extraction?.confidence ?? 0) * 100, 0), 100) }
    private var confidenceLabel: String { extraction == nil ? "—" : "\(Int(confidencePct.rounded()))%" }
    private var parseStatusLabel: String {
        switch extraction?.status.lowercased() {
        case "read": return "READ"
        case "pending": return "READING"
        case "nothing_read": return "NOTHING READ"
        case "unreadable_type": return "UNREADABLE TYPE"
        case "scanner_unavailable": return "SCANNER OFFLINE"
        default: return "NOT READ"
        }
    }
    private var parseStatusOk: Bool {
        extraction?.status.lowercased() == "read"
    }
    private var docTypeLabel: String {
        switch extraction?.classification.type.lowercased() {
        case "bill_of_lading": return "BILL OF LADING"
        case "booking":        return "BOOKING"
        case "rail_waybill", "waybill": return "RAIL WAYBILL"
        case let value?: return value.replacingOccurrences(of: "_", with: " ").uppercased()
        default: return "UNCLASSIFIED DOCUMENT"
        }
    }
    private var fieldsNormalized: Int { extraction?.fieldsExtracted ?? 0 }
    private var docsToday: Int        { dashboard?.docsToday      ?? 0 }
    private var docsStatusLabel: String { dashboard?.docsStatusLabel ?? "-" }
    private var regulatedCount: Int { extraction?.regulatedFields.count ?? 0 }
    private var extractedRows: [(String, String)] {
        (extraction?.extractedData ?? [:])
            .compactMap { key, value in
                let rendered = value.displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
                return rendered.isEmpty ? nil : (key, rendered)
            }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    // MARK: View

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrow
                titleRow
                IridescentHairline()
                heroParseCard
                extractedFieldsCard
                if let loadError { statusBanner(loadError, color: Brand.danger) }
                if let actionMessage { statusBanner(actionMessage, color: Brand.success) }
                kpiStrip
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .eusoRefreshTask { await loadAll() }
    }

    // MARK: Eyebrow

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            EusoTripEyebrow(verbatim: "RAIL ENGINEER · DOC INTAKE")
                .font(.system(size: 9, weight: .black))
                .kerning(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("ESANG AI")
                .font(.system(size: 9, weight: .heavy).monospaced())
                .kerning(0.6)
                .foregroundColor(palette.textTertiary)
        }
    }

    // MARK: Title row (back button + title + right meta)

    private var titleRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            // Back button circle
            ZStack {
                Circle()
                    .fill(palette.bgCard)
                    .overlay(Circle().stroke(Color.black.opacity(0.10), lineWidth: 1))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Document Ingest")
                    .font(.system(size: 22, weight: .bold))
                    .kerning(-0.3)
                    .foregroundColor(palette.textPrimary)
                Text("Extraction proposal · human review required")
                    .font(.system(size: 11).monospaced())
                    .kerning(0.4)
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(docTypeLabel)
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.6)
                    .foregroundColor(palette.textTertiary)
                Text(parseStatusLabel)
                    .font(.system(size: 11).monospaced())
                    .kerning(0.4)
                    .foregroundColor(palette.textSecondary)
            }
        }
    }

    // MARK: Hero parse card

    private var heroParseCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("LATEST READ · \(docTypeLabel)")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.6)
                    .foregroundColor(palette.textTertiary)
                Spacer()
                Text("PROPOSAL")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.6)
                    .foregroundColor(palette.textTertiary)
            }

            HStack(alignment: .lastTextBaseline, spacing: Space.s2) {
                Text(confidenceLabel)
                    .font(.system(size: 34, weight: .semibold))
                    .kerning(-0.3)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("confidence")
                    .font(.system(size: 13, weight: .medium))
                    .kerning(0.4)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Text(parseStatusLabel)
                    .font(.system(size: 20, weight: .semibold).monospaced())
                    .kerning(0.2)
                    .foregroundColor(parseStatusOk ? Brand.success : Brand.danger)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * confidencePct / 100, height: 6)
                }
            }
            .frame(height: 6)

            Text("\(fieldsNormalized) field\(fieldsNormalized == 1 ? "" : "s") read from the stored document")
                .font(.system(size: 11, weight: .medium))
                .kerning(0.2)
                .foregroundColor(palette.textPrimary)

            Text(extraction?.grounded == true
                 ? "Spatial grounding recorded · confirmation still required"
                 : "No spatial grounding recorded · confirmation required")
                .font(.system(size: 9).monospaced())
                .kerning(0.3)
                .foregroundColor(palette.textTertiary)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1)
                        .opacity(0.22)
                )
        )
    }

    // MARK: Extracted fields card

    private var extractedFieldsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("EXTRACTED FIELDS · REVIEW REQUIRED")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.6)
                    .foregroundColor(palette.textTertiary)
                Spacer()
                Text("\(fieldsNormalized)")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.6)
                    .foregroundColor(palette.textTertiary)
            }
            .padding(.bottom, Space.s3)

            if extractedRows.isEmpty {
                Text(extraction?.error ?? extraction?.warnings.first ?? "No fields have been read from this document.")
                    .font(.system(size: 11))
                    .foregroundColor(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                ForEach(Array(extractedRows.enumerated()), id: \.offset) { index, row in
                    fieldRow(
                        label: row.0.replacingOccurrences(of: "_", with: " ").capitalized,
                        value: row.1,
                        mono: true,
                        isLast: index == extractedRows.count - 1
                    )
                }
            }
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func fieldRow(label: String, value: String, mono: Bool, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundColor(palette.textTertiary)
                Spacer()
                Group {
                    if mono {
                        Text(value)
                            .font(.system(size: 11, weight: .bold).monospaced())
                    } else {
                        Text(value)
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .foregroundColor(palette.textPrimary)
            }
            .padding(.vertical, 10)
            if !isLast {
                Divider().overlay(Color.black.opacity(0.06))
            }
        }
    }

    // MARK: KPI strip (custom — first tile is gradient)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // Gradient tile
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DOCUMENTS")
                        .font(.system(size: 9, weight: .black))
                        .kerning(0.6)
                        .foregroundColor(.white.opacity(0.85))
                    Text("\(docsToday)")
                        .font(.system(size: 18, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                    Text(docsStatusLabel)
                        .font(.system(size: 9).monospaced())
                        .kerning(0.4)
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)

            MetricTile(label: "FIELDS",  value: "\(fieldsNormalized)")
            MetricTile(label: "REGULATED", value: "\(regulatedCount)",
                       accent: regulatedCount > 0 ? Brand.warning : Brand.success)
        }
    }

    // MARK: CTA pair

    private var rawDocumentLines: [String] {
        var lines = [
            "Document: \(documentId)",
            "Type proposal: \(docTypeLabel)",
            "Status: \(parseStatusLabel)",
            "Confidence: \(confidenceLabel)",
            "Grounded: \(extraction?.grounded == true ? "yes" : "no")",
            "Human confirmation required: \(extraction?.requiresHumanConfirmation == true ? "yes" : "no")",
        ]
        lines.append(contentsOf: extractedRows.map { "\($0.0): \($0.1)" })
        lines.append(contentsOf: (extraction?.warnings ?? []).map { "Warning: \($0)" })
        return lines
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button(action: { isCreating = true; Task { await rereadStoredDocument() } }) {
                HStack {
                    if isCreating {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    }
                    Text("Re-read stored document")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient.primary))
            }

            RailSecondaryActionButton(
                title: "Raw doc",
                sheetTitle: "Raw document extraction",
                lines: rawDocumentLines,
                fillWidth: true,
                systemImage: "doc.viewfinder"
            )
        }
    }

    // MARK: Data loading

    private func loadAll() async {
        loadError = nil
        do {
            extraction = try await EusoTripAPI.shared.mutation(
                "documentManagement.extractDocumentData",
                input: DocIdIn590(documentId: documentId)
            )
        } catch {
            extraction = nil
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        do {
            dashboard = try await EusoTripAPI.shared.queryNoInput(
                "documentManagement.getDocumentDashboard"
            )
        } catch {
            dashboard = nil
            if loadError == nil {
                loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func rereadStoredDocument() async {
        defer { isCreating = false }
        loadError = nil
        actionMessage = nil
        do {
            struct ReReadResult: Decodable {
                let success: Bool
                let status: String
                let error: String?
            }
            let result: ReReadResult = try await EusoTripAPI.shared.mutation(
                "documentManagement.classifyDocument",
                input: DocIdIn590(documentId: documentId)
            )
            await loadAll()
            if result.success {
                actionMessage = "Stored document re-read. Review every proposed value before filing."
            } else {
                loadError = result.error ?? "The scanner did not classify this document."
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func statusBanner(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
