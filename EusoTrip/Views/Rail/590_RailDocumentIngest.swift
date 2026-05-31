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

private struct ParsedDocument590: Decodable {
    let confidence: Double?
    let parseStatus: String?
    let documentType: String?
    let fieldsNormalized: Int?
    let totalFields: Int?
    let missingField: String?
    let parseTimeSeconds: Double?
    let parsedAgoLabel: String?
}

private struct ExtractedFields590: Decodable {
    let waybillNumber: String?
    let carrierName: String?
    let trainSymbol: String?
    let lane: String?
    let etdLabel: String?
    let etaLabel: String?
    let containerDesc: String?
    let commodity: String?
    let terms: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode as flat structure first (direct field access)
        var wb = try? c.decodeIfPresent(String.self, forKey: .waybillNumber)
        var cn = try? c.decodeIfPresent(String.self, forKey: .carrierName)
        var ts = try? c.decodeIfPresent(String.self, forKey: .trainSymbol)
        var ln = try? c.decodeIfPresent(String.self, forKey: .lane)
        var etd = try? c.decodeIfPresent(String.self, forKey: .etdLabel)
        var eta = try? c.decodeIfPresent(String.self, forKey: .etaLabel)
        var cd = try? c.decodeIfPresent(String.self, forKey: .containerDesc)
        var cm = try? c.decodeIfPresent(String.self, forKey: .commodity)
        var tm = try? c.decodeIfPresent(String.self, forKey: .terms)

        // If the flat fields are empty, fall back to the server envelope (extractedData)
        if wb == nil && cn == nil && ts == nil,
           let ext = try? c.decodeIfPresent([String: AnyCodable].self, forKey: .extractedData) {
            wb = ext["waybillNumber"]?.value as? String
            cn = ext["carrierName"]?.value as? String
            ts = ext["trainSymbol"]?.value as? String
            ln = ext["lane"]?.value as? String
            etd = ext["etdLabel"]?.value as? String
            eta = ext["etaLabel"]?.value as? String
            cd = ext["containerDesc"]?.value as? String
            cm = ext["commodity"]?.value as? String
            tm = ext["terms"]?.value as? String
        }

        waybillNumber = wb
        carrierName = cn
        trainSymbol = ts
        lane = ln
        etdLabel = etd
        etaLabel = eta
        containerDesc = cd
        commodity = cm
        terms = tm
    }

    enum CodingKeys: String, CodingKey {
        case waybillNumber, carrierName, trainSymbol, lane, etdLabel, etaLabel, containerDesc, commodity, terms
        case extractedData
    }
}

private struct AnyCodable: Codable {
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let int = value as? Int {
            try container.encode(int)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let double = value as? Double {
            try container.encode(double)
        }
    }
}

private struct DraftShipment590: Decodable {
    let railId: String?
    let companyName: String?
    let status: String?
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

// MARK: - Body

private struct RailDocumentIngestBody: View {
    @Environment(\.palette) private var palette
    let documentId: String

    @State private var parsed: ParsedDocument590? = nil
    @State private var fields: ExtractedFields590? = nil
    @State private var draft: DraftShipment590? = nil
    @State private var dashboard: DocDashboard590? = nil
    @State private var isCreating = false

    // MARK: Derived

    private var confidence: Double   { parsed?.confidence ?? 0 }
    private var confidencePct: Double { min(max(confidence, 0), 100) }
    private var confidenceLabel: String { "\(Int(confidencePct))%" }
    private var parseStatusLabel: String {
        switch (parsed?.parseStatus ?? "parsed").lowercased() {
        case "parsed": return "PARSED"
        case "failed": return "FAILED"
        default:       return "REVIEWING"
        }
    }
    private var parseStatusOk: Bool {
        (parsed?.parseStatus ?? "parsed").lowercased() == "parsed"
    }
    private var docTypeLabel: String {
        switch (parsed?.documentType ?? "rail_waybill").lowercased() {
        case "bill_of_lading": return "BILL OF LADING"
        case "booking":        return "BOOKING"
        default:               return "RAIL WAYBILL"
        }
    }
    private var fieldsNormalized: Int { parsed?.fieldsNormalized ?? 0 }
    private var totalFields: Int      { parsed?.totalFields      ?? 14 }
    private var missingField: String  { parsed?.missingField     ?? "—" }
    private var parsedAgoLabel: String { parsed?.parsedAgoLabel  ?? "—" }
    private var parseTimeLabel: String {
        guard let t = parsed?.parseTimeSeconds else { return "" }
        return " · \(Int(t))s parse"
    }
    private var docsToday: Int        { dashboard?.docsToday      ?? 0 }
    private var docsStatusLabel: String { dashboard?.docsStatusLabel ?? "—" }
    private var draftRailId: String   { draft?.railId     ?? "—" }
    private var draftCompany: String  { draft?.companyName ?? "Eusorone Technologies" }
    private var missingCount: Int     { totalFields - fieldsNormalized }

    // MARK: View

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrow
                titleRow
                IridescentHairline()
                heroParseCard
                extractedFieldsCard
                activeDraftCard
                kpiStrip
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .task { await loadAll() }
    }

    // MARK: Eyebrow

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · DOC INTAKE")
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
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(palette.textPrimary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Document Ingest")
                    .font(.system(size: 22, weight: .bold))
                    .kerning(-0.3)
                    .foregroundColor(palette.textPrimary)
                Text("extractDocumentData · parse ok")
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
                Text("parsed \(parsedAgoLabel)")
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
                Text("LAST PARSE · \(docTypeLabel)")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.6)
                    .foregroundColor(palette.textTertiary)
                Spacer()
                Text("CLASSIFIED")
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

            Text("\(fieldsNormalized) of \(totalFields) rail_shipments fields normalized")
                .font(.system(size: 11, weight: .medium))
                .kerning(0.2)
                .foregroundColor(palette.textPrimary)

            Text("\(missingCount) missing · \(missingField) · ESANG AI\(parseTimeLabel)")
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
                Text("EXTRACTED FIELDS · classifyDocument")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.6)
                    .foregroundColor(palette.textTertiary)
                Spacer()
                Text("\(fieldsNormalized) / \(totalFields)")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.6)
                    .foregroundColor(palette.textTertiary)
            }
            .padding(.bottom, Space.s3)

            fieldRow(label: "Waybill",         value: fields?.waybillNumber  ?? "—", mono: true)
            fieldRow(label: "Carrier · Train",  value: [fields?.carrierName, fields?.trainSymbol].compactMap { $0 }.joined(separator: " · "), mono: true)
            fieldRow(label: "Lane",             value: fields?.lane           ?? "—", mono: false)
            fieldRow(label: "ETD · ETA",        value: [fields?.etdLabel, fields?.etaLabel].compactMap { $0 }.joined(separator: " → "), mono: false)
            fieldRow(label: "Containers",       value: fields?.containerDesc  ?? "—", mono: true)
            fieldRow(label: "Commodity · Terms", value: [fields?.commodity, fields?.terms].compactMap { $0 }.joined(separator: " · "), mono: false, isLast: true)
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

    // MARK: Active draft card

    private var activeDraftCard: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Brand.blue.opacity(0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: "doc.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Brand.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("New draft · awaiting confirm")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                Text("\(draftRailId) · DU · \(draftCompany)")
                    .font(.system(size: 10).monospaced())
                    .kerning(0.3)
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
            Text("DRAFT")
                .font(.system(size: 10, weight: .black))
                .kerning(0.4)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Brand.blue.opacity(0.12)))
                .foregroundColor(Brand.blue)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: KPI strip (custom — first tile is gradient)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // Gradient tile
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DOCS TODAY")
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
            MetricTile(label: "MISSING", value: "\(missingCount)",
                       accent: missingCount > 0 ? Brand.warning : Brand.success)
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button(action: { isCreating = true; Task { await createShipment() } }) {
                HStack {
                    if isCreating {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    }
                    Text("Create shipment from extract")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient.primary))
            }

            Button("Raw doc") {}
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.10), lineWidth: 1))
                )
        }
    }

    // MARK: Data loading

    private func loadAll() async {
        async let parseTask: ParsedDocument590 = EusoTripAPI.shared.query(
            "documentManagement.classifyDocument",
            input: DocIdIn590(documentId: documentId)
        )
        async let fieldsTask: ExtractedFields590 = EusoTripAPI.shared.query(
            "documentManagement.extractDocumentData",
            input: DocIdIn590(documentId: documentId)
        )
        async let draftTask: DraftShipment590 = EusoTripAPI.shared.query(
            "documentManagement.extractDocumentData",
            input: DocIdIn590(documentId: documentId)
        )
        async let dashTask: DocDashboard590 = EusoTripAPI.shared.queryNoInput(
            "documentManagement.getDocumentDashboard"
        )

        parsed    = try? await parseTask
        fields    = try? await fieldsTask
        draft     = try? await draftTask
        dashboard = try? await dashTask
    }

    private func createShipment() async {
        defer { isCreating = false }
        let _: ParsedDocument590? = try? await EusoTripAPI.shared.query(
            "documentManagement.classifyDocument",
            input: DocIdIn590(documentId: documentId)
        )
    }
}
