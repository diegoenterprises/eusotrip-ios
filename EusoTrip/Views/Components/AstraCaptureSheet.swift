//
//  AstraCaptureSheet.swift
//  EusoTrip — IO 2026 Tier 1 #18 (reefer temp-log) + Tier 3 #19 (OS&D)
//
//  Unified capture flow that drives both Astra Vision endpoints:
//    .reeferTempLog → astraDvir.reeferTempLog
//    .osdReport     → astraDvir.osdReport
//
//  Both endpoints accept a base64 JPEG + load context and return
//  a structured observation + verdict + Ed25519 signature. iOS
//  verifies the signature locally (handled inside AstraVisionService)
//  before the verdict surfaces in the UI. When the server writes an
//  overlay row (REEFER.TEMP_LOG_SEALED on a pass, CARGO.OSD_CLAIM on
//  a claim_filed) the sheet shows an "auto-overlay written" badge so
//  the driver knows the audit chain captured it.
//
//  Driver-facing screens (013-051 lifecycle, 011_PretripDVIR,
//  receiver-paperwork) present this sheet at the moment the
//  corresponding scan is needed.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import UIKit

// MARK: - Mode

public enum AstraCaptureMode: Equatable {
    /// Tier 1 #18 — reefer unit display panel scan.
    case reeferTempLog(expectedSetpointF: Double?, vehicleId: String?, loadId: String?)
    /// Tier 3 #19 — OS&D photo against expected BOL line items.
    case osdReport(expectedItems: [AstraOSDExpectedItem], loadId: String?, note: String?)

    var title: String {
        switch self {
        case .reeferTempLog: return "Reefer Temp Log"
        case .osdReport:     return "OS&D Photo Report"
        }
    }

    var promptCopy: String {
        switch self {
        case .reeferTempLog: return "Aim the camera at the reefer unit display. Astra reads setpoint, return-air temp, mode, and active alarms."
        case .osdReport:     return "Photograph the cargo at delivery. Astra reconciles visible counts + damage against the BOL line items."
        }
    }

    var ctaCopy: String {
        switch self {
        case .reeferTempLog: return "Read Reefer Display"
        case .osdReport:     return "Capture OS&D Photo"
        }
    }

    var sfSymbol: String {
        switch self {
        case .reeferTempLog: return "thermometer.snowflake"
        case .osdReport:     return "shippingbox.and.arrow.backward"
        }
    }
}

// MARK: - Verdict union

private enum AstraCaptureResult: Equatable {
    case reefer(AstraReeferTempLogResponse)
    case osd(AstraOSDReportResponse)

    var verdictText: String {
        switch self {
        case .reefer(let r):
            switch r.verdict {
            case .pass:        return "PASS"
            case .fail:        return "FAIL"
            case .needsReview: return "NEEDS REVIEW"
            }
        case .osd(let r):
            switch r.verdict {
            case .clean:                  return "CLEAN"
            case .inspectionRecommended:  return "INSPECTION RECOMMENDED"
            case .claimFiled:             return "CLAIM FILED"
            }
        }
    }

    var verdictColor: Color {
        switch self {
        case .reefer(let r):
            switch r.verdict {
            case .pass:        return .green
            case .fail:        return .red
            case .needsReview: return .orange
            }
        case .osd(let r):
            switch r.verdict {
            case .clean:                  return .green
            case .inspectionRecommended:  return .orange
            case .claimFiled:             return .red
            }
        }
    }

    var overlayBadge: String? {
        switch self {
        case .reefer(let r): return r.tempLogSealedEligible ? "TEMP-LOG SEALED" : nil
        case .osd(let r):    return r.claimOverlayWritten ? "OS&D CLAIM FILED" : nil
        }
    }

    var auditId: Int? {
        switch self {
        case .reefer(let r): return r.auditId
        case .osd(let r):    return r.auditId
        }
    }

    /// Compact summary lines for the verdict surface. Each line is
    /// (label, value) — derived directly from the observation map.
    var summaryRows: [(String, String)] {
        switch self {
        case .reefer(let r):
            return [
                ("Setpoint",    (r.observation["setpointF"]?.displayString ?? "—").withSuffix("°F")),
                ("Return Air",  (r.observation["returnAirTempF"]?.displayString ?? "—").withSuffix("°F")),
                ("Mode",         r.observation["mode"]?.displayString ?? "—"),
                ("Data Logger",  r.observation["dataLoggerOk"]?.displayString ?? "—"),
            ]
        case .osd(let r):
            return [
                ("Pallet damage visible", r.observation["anyVisiblePalletDamage"]?.displayString ?? "—"),
                ("Seal breach visible",   r.observation["anyVisibleSealBreach"]?.displayString ?? "—"),
                ("Confidence",            r.observation["confidence"]?.displayString ?? "—"),
            ]
        }
    }
}

// Small helper so summary lines can append units without if/else noise.
private extension String {
    func withSuffix(_ s: String) -> String { self.hasSuffix("—") ? self : self + " " + s }
}

// MARK: - Sheet

public struct AstraCaptureSheet: View {
    public let mode: AstraCaptureMode
    public let onAuditPersisted: ((Int) -> Void)?

    public init(
        mode: AstraCaptureMode,
        onAuditPersisted: ((Int) -> Void)? = nil
    ) {
        self.mode = mode
        self.onAuditPersisted = onAuditPersisted
    }

    @Environment(\.dismiss) private var dismiss
    @State private var showCamera: Bool = false
    @State private var capturedImage: UIImage? = nil
    @State private var result: AstraCaptureResult? = nil
    @State private var running: Bool = false
    @State private var error: String? = nil

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    promptCard
                    if let img = capturedImage {
                        capturedStrip(img)
                    }
                    captureCTA
                    if running {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Astra is reading the photo…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let err = error {
                        Text(err)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    if let result {
                        verdictCard(result)
                    }
                }
                .padding(16)
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            AstraCameraSheet { img in
                showCamera = false
                if let img {
                    capturedImage = img
                    Task { await runCapture(img) }
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: subviews

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: mode.sfSymbol)
                    .font(.caption.weight(.bold))
                Text("ASTRA · \(mode.title.uppercased())")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
            }
            .foregroundStyle(.secondary)
            Text(mode.promptCopy)
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var captureCTA: some View {
        Button {
            showCamera = true
        } label: {
            Label(mode.ctaCopy, systemImage: "camera.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(running)
    }

    private func capturedStrip(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func verdictCard(_ r: AstraCaptureResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(r.verdictText)
                    .font(.headline)
                    .foregroundStyle(r.verdictColor)
                Spacer()
                if let badge = r.overlayBadge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(
                            Capsule().fill(r.verdictColor.opacity(0.18))
                        )
                        .foregroundStyle(r.verdictColor)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(r.summaryRows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.0)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(row.1)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemBackground))
            )

            if let auditId = r.auditId {
                Text("Audit row #\(auditId) · Ed25519 verified")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(r.verdictColor.opacity(0.5), lineWidth: 1.0)
        )
    }

    // MARK: capture pipeline

    private func runCapture(_ image: UIImage) async {
        running = true
        defer { running = false }
        error = nil
        do {
            switch mode {
            case .reeferTempLog(let expectedSetpointF, let vehicleId, let loadId):
                let resp = try await AstraVisionService.shared.reeferTempLog(
                    image: image,
                    expectedSetpointF: expectedSetpointF,
                    vehicleId: vehicleId,
                    loadId: loadId
                )
                self.result = .reefer(resp)
                if let id = resp.auditId { onAuditPersisted?(id) }
            case .osdReport(let expectedItems, let loadId, let note):
                let resp = try await AstraVisionService.shared.osdReport(
                    image: image,
                    expectedItems: expectedItems,
                    loadId: loadId,
                    note: note
                )
                self.result = .osd(resp)
                if let id = resp.auditId { onAuditPersisted?(id) }
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - Camera bridge

private struct AstraCameraSheet: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            onImage(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onImage(nil)
        }
    }
}

// MARK: - Previews

#Preview("Reefer · Dark") {
    AstraCaptureSheet(
        mode: .reeferTempLog(expectedSetpointF: 34.0, vehicleId: nil, loadId: "load_1077")
    )
    .preferredColorScheme(.dark)
}

#Preview("OS&D · Light") {
    AstraCaptureSheet(
        mode: .osdReport(
            expectedItems: [
                .init(sku: "SKU-001", description: "Frozen poultry", expectedQty: 12),
                .init(sku: "SKU-002", description: "Frozen beef",    expectedQty: 8),
            ],
            loadId: "load_1077",
            note: nil
        )
    )
    .preferredColorScheme(.light)
}
