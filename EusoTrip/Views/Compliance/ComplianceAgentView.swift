//
//  ComplianceAgentView.swift
//  Multi-class segregation matrix — IO 2026 P0-10.
//
//  Customs brokers + compliance officers compose multi-line
//  hazmat manifests (3-product LTL into a tanker, mixed
//  cross-border container, etc.). This view lets them add N
//  UN numbers / hazard classes and see the pair-wise verdict
//  matrix at a glance — every incompatible combination is
//  highlighted with the 49 CFR 177.848 citation.
//
//  Extends what shipped in P0-8 (pair-wise `compliance.segregationCheck`)
//  with the new `compliance.segregationMatrix` mutation.
//
//  Drop into: EusoTrip/Views/Compliance/ComplianceAgentView.swift
//

import SwiftUI

public struct ComplianceAgentView: View {
    @State private var lines: [ManifestLine] = [
        ManifestLine(unNumber: "", hazardClass: ""),
        ManifestLine(unNumber: "", hazardClass: ""),
    ]
    @State private var matrix: SegregationMatrixResponse? = nil
    @State private var isChecking: Bool = false
    @State private var errorMessage: String? = nil

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                manifestEditor
                actions
                if isChecking {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Checking segregation…").foregroundStyle(.secondary)
                    }
                }
                if let err = errorMessage {
                    Text(err).foregroundStyle(.red).font(.callout)
                }
                if let m = matrix {
                    verdictHeader(m)
                    matrixGrid(m)
                    incompatibleList(m)
                }
            }
            .padding(16)
        }
        .navigationTitle("Segregation Agent")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.3x3.fill")
                    .foregroundStyle(LinearGradient(
                        colors: [.cyan, .green],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text("ESANG · SEGREGATION AGENT")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            Text("Check whether multiple hazmat lines can ride together per 49 CFR 177.848.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var manifestEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manifest")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach($lines) { $line in
                manifestRow($line)
            }
            Button {
                if lines.count < 24 {
                    lines.append(ManifestLine(unNumber: "", hazardClass: ""))
                }
            } label: {
                Label("Add line", systemImage: "plus.circle")
                    .font(.callout)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .disabled(lines.count >= 24)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.06)))
    }

    @ViewBuilder
    private func manifestRow(_ line: Binding<ManifestLine>) -> some View {
        HStack(spacing: 8) {
            TextField("UN # (e.g. 1203)", text: line.unNumber)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 130)
                .autocorrectionDisabled(true)
                .keyboardType(.numberPad)
            TextField("Class", text: line.hazardClass)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 70)
                .autocorrectionDisabled(true)
            TextField("Label (optional)", text: line.label)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(true)
            if lines.count > 2 {
                Button(role: .destructive) {
                    if let idx = lines.firstIndex(where: { $0.id == line.id }) {
                        lines.remove(at: idx)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actions: some View {
        Button {
            Task { await runCheck() }
        } label: {
            HStack {
                Image(systemName: "checkmark.shield")
                Text("Check segregation").font(.body.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(LinearGradient(
                colors: [.cyan, .green],
                startPoint: .leading, endPoint: .trailing
            ))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isChecking || !canCheck)
    }

    private var canCheck: Bool {
        let filled = lines.filter {
            !$0.unNumber.trimmingCharacters(in: .whitespaces).isEmpty
            || !$0.hazardClass.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return filled.count >= 2
    }

    @ViewBuilder
    private func verdictHeader(_ m: SegregationMatrixResponse) -> some View {
        HStack(spacing: 6) {
            let (icon, color, label) = overallStyle(m.overall)
            Image(systemName: icon).foregroundStyle(color)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(color)
            Spacer(minLength: 0)
            Text(m.citation)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private func overallStyle(_ overall: String) -> (String, Color, String) {
        switch overall {
        case "co_load_allowed":
            return ("checkmark.seal.fill", .green, "Co-load allowed")
        case "incompatible_lines_present":
            return ("xmark.octagon.fill", .red, "Incompatible lines present")
        case "needs_review":
            return ("questionmark.circle.fill", .yellow, "Needs review")
        default:
            return ("questionmark.circle.fill", .secondary, overall)
        }
    }

    @ViewBuilder
    private func matrixGrid(_ m: SegregationMatrixResponse) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                // Column header row
                HStack(spacing: 4) {
                    Color.clear.frame(width: 60, height: 28)
                    ForEach(Array(m.lines.enumerated()), id: \.offset) { idx, line in
                        Text(line.hazardClass ?? "?")
                            .font(.caption.bold())
                            .frame(width: 36, height: 28)
                            .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                ForEach(Array(m.lines.enumerated()), id: \.offset) { rowIdx, rowLine in
                    HStack(spacing: 4) {
                        Text(rowLine.hazardClass ?? "?")
                            .font(.caption.bold())
                            .frame(width: 60, height: 28, alignment: .leading)
                        ForEach(Array(m.matrix[rowIdx].enumerated()), id: \.offset) { _, cell in
                            cellView(cell)
                        }
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.gray.opacity(0.04)))
        }
    }

    @ViewBuilder
    private func cellView(_ verdict: String) -> some View {
        let (icon, color) = cellStyle(verdict)
        Image(systemName: icon)
            .foregroundStyle(color)
            .frame(width: 36, height: 28)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
    }

    private func cellStyle(_ verdict: String) -> (String, Color) {
        switch verdict {
        case "compatible":           return ("checkmark", .green)
        case "separation_required":  return ("rectangle.split.2x1", .orange)
        case "incompatible":         return ("xmark", .red)
        default:                     return ("questionmark", .yellow)
        }
    }

    @ViewBuilder
    private func incompatibleList(_ m: SegregationMatrixResponse) -> some View {
        if !m.incompatiblePairs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Incompatible pairs (\(m.incompatiblePairs.count))")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(Array(m.incompatiblePairs.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(pair.labelI) (Class \(pair.classI ?? "?")) ⛔ \(pair.labelJ) (Class \(pair.classJ ?? "?"))")
                                .font(.callout)
                                .foregroundStyle(.primary)
                            Text(pair.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @MainActor
    private func runCheck() async {
        isChecking = true
        errorMessage = nil
        matrix = nil
        defer { isChecking = false }
        struct LineIn: Encodable {
            let unNumber: String?
            let hazardClass: String?
            let label: String?
        }
        struct In: Encodable { let lines: [LineIn] }
        let payload = In(lines: lines.map {
            LineIn(
                unNumber: $0.unNumber.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.unNumber.trimmingCharacters(in: .whitespaces),
                hazardClass: $0.hazardClass.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.hazardClass.trimmingCharacters(in: .whitespaces),
                label: $0.label.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.label.trimmingCharacters(in: .whitespaces)
            )
        })
        do {
            let response: SegregationMatrixResponse = try await EusoTripAPI.shared.mutation(
                "compliance.segregationMatrix",
                input: payload
            )
            matrix = response
        } catch {
            errorMessage = "Couldn't reach segregation service: \((error as NSError).localizedDescription)"
        }
    }

    // MARK: - Types

    struct ManifestLine: Identifiable, Hashable {
        let id: UUID = UUID()
        var unNumber: String
        var hazardClass: String
        var label: String = ""
    }
}

public struct SegregationMatrixLine: Decodable, Hashable, Sendable {
    public let unNumber: String?
    public let hazardClass: String?
    public let label: String?
    public let name: String?
}

public struct SegregationIncompatiblePair: Decodable, Hashable, Sendable {
    public let i: Int
    public let j: Int
    public let labelI: String
    public let labelJ: String
    public let classI: String?
    public let classJ: String?
    public let verdict: String
    public let reason: String
}

public struct SegregationMatrixResponse: Decodable, Hashable, Sendable {
    public let lines: [SegregationMatrixLine]
    public let matrix: [[String]]
    public let incompatiblePairs: [SegregationIncompatiblePair]
    public let overall: String
    public let citation: String
}

// MARK: - Previews

#Preview("Compliance Agent · Dark") {
    NavigationStack { ComplianceAgentView() }
        .preferredColorScheme(.dark)
}

#Preview("Compliance Agent · Light") {
    NavigationStack { ComplianceAgentView() }
        .preferredColorScheme(.light)
}
