//
//  AIVisualScanButton.swift
//  EusoTrip — reusable Gemini Vision scan button.
//
//  Wraps PhotosPicker → base64 → tRPC call → result sheet so any
//  surface can drop in a "Scan with AI" CTA without re-implementing
//  the upload + decode + inflight UI plumbing.
//
//  Used by 011 PretripDVIR (`visualIntelligence.inspectDVIR`),
//  086 MeIncidentReportFiler (`visualIntelligence.assessDamage`),
//  and any future surface that wants to attach a Gemini Vision pass
//  to a photo. Founder Gemini parity audit 2026-05-05.
//

import SwiftUI
import PhotosUI

/// Result envelope from the visualIntelligence procs. Shape:
///   { findings: [{ severity, description, recommendation }],
///     summary: String,
///     overallSeverity: "low" | "moderate" | "high" | "critical" }
public struct AIVisualScanResult: Decodable, Hashable {
    public let summary: String?
    public let overallSeverity: String?
    public let findings: [Finding]?

    public struct Finding: Decodable, Hashable {
        public let severity: String?
        public let description: String?
        public let recommendation: String?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode as a discriminated union { type, data }
        if let typeStr = try? container.decode(String.self, forKey: .type),
           typeStr == "DVIR_INSPECTION" {
            // Server returns { type: "DVIR_INSPECTION", data: {...} }
            let dataContainer = try container.nestedContainer(keyedBy: DVIRCodingKeys.self, forKey: .data)
            
            // Extract DVIR fields and synthesize iOS-compatible properties
            let inspectionPoint = try? dataContainer.decode(String.self, forKey: .inspectionPoint)
            let condition = try? dataContainer.decode(String.self, forKey: .condition)
            let defectsFound = try? dataContainer.decode([DVIRDefect].self, forKey: .defectsFound)
            let visualNotes = try? dataContainer.decode(String.self, forKey: .visualNotes)
            
            // Map DVIR response to iOS shape
            self.summary = [inspectionPoint, condition, visualNotes]
                .compactMap { $0 }.joined(separator: " · ")
            self.overallSeverity = condition?.lowercased()
            self.findings = defectsFound?.map { defect in
                Finding(
                    severity: defect.severity,
                    description: defect.description,
                    recommendation: nil
                )
            }
        } else {
            // Fall back to flat iOS shape (for testing, or if server shape changes)
            self.summary = try? container.decode(String.self, forKey: .summary)
            self.overallSeverity = try? container.decode(String.self, forKey: .overallSeverity)
            self.findings = try? container.decode([Finding].self, forKey: .findings)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, data, summary, overallSeverity, findings
    }

    enum DVIRCodingKeys: String, CodingKey {
        case inspectionPoint, condition, defectsFound, visualNotes
    }

    struct DVIRDefect: Decodable {
        let description: String
        let severity: String
        let requiresImmediate: Bool
    }
}

public struct AIVisualScanButton: View {
    public let title: String
    public let subtitle: String
    public let procPath: String
    public let context: [String: String]
    public let onResult: (AIVisualScanResult) -> Void

    @Environment(\.palette) private var palette
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var inflight: Bool = false
    @State private var error: String? = nil

    public init(
        title: String = "Scan with AI",
        subtitle: String = "Gemini Vision analyzes the photo for issues",
        procPath: String,
        context: [String: String] = [:],
        onResult: @escaping (AIVisualScanResult) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.procPath = procPath
        self.context = context
        self.onResult = onResult
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 10) {
                    if inflight {
                        ProgressView().progressViewStyle(.circular)
                            .tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "sparkles.tv.fill")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(inflight ? "Analyzing…" : title)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(inflight)

            if let err = error {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.danger)
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await scan(item: item) }
        }
    }

    @MainActor
    private func scan(item: PhotosPickerItem) async {
        guard !inflight else { return }
        inflight = true
        defer { inflight = false }
        error = nil
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
            error = "Couldn't read photo"
            pickerItem = nil
            return
        }
        // Compress to JPEG ≤ 800KB so the multimodal payload fits.
        var jpeg = data
        if let img = UIImage(data: data) {
            var quality: CGFloat = 0.85
            while quality > 0.3 {
                if let d = img.jpegData(compressionQuality: quality), d.count <= 800_000 {
                    jpeg = d
                    break
                }
                quality -= 0.1
            }
        }
        let base64 = jpeg.base64EncodedString()
        struct In: Encodable {
            let imageBase64: String
            let mimeType: String
            let inspectionPoint: String?
            let loadNumber: String?
        }
        do {
            let resp: AIVisualScanResult = try await EusoTripAPI.shared.mutation(
                procPath,
                input: In(
                    imageBase64: base64,
                    mimeType: "image/jpeg",
                    inspectionPoint: context["inspectionPoint"],
                    loadNumber: context["loadNumber"]
                )
            )
            onResult(resp)
        } catch let e {
            error = "Scan failed: \((e as? EusoTripAPIError)?.errorDescription ?? e.localizedDescription)"
        }
        pickerItem = nil
    }
}

#Preview("AI Visual Scan Button") {
    AIVisualScanButton(
        title: "Scan brakes with AI",
        subtitle: "Detects worn pads, missing components, fluid leaks",
        procPath: "visualIntelligence.inspectDVIR",
        context: ["inspectionPoint": "brakes"]
    ) { result in
        print("scan result:", result.summary ?? "—")
    }
    .padding(16)
    .preferredColorScheme(.dark)
}
