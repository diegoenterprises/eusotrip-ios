//
//  HazmatPlacardScanView.swift
//  Astra hazmat placard scan + ERG read-aloud — IO 2026 P0-7.
//
//  Driver opens this view (from the load detail Hazmat tab or a
//  Siri shortcut, or — once P0-16 XR ships — via a "scan placard"
//  voice intent). They aim the camera, tap "Scan", and the
//  pipeline runs end-to-end:
//
//    1. UIImagePickerController captures one JPEG.
//    2. `ERGLookupService.scanPlacard(image:vehicleId:loadId:)`
//       posts to `astraDvir.placardScan`. Server runs Gemini Vision
//       OCR tuned for placards, JOINs with the local ERG database,
//       Ed25519-signs the canonical payload, writes the audit
//       chain entry (and a `HazmatOverlay.placardsAffixed` overlay
//       row when readable + UN-resolved), and returns the bundle.
//    3. iOS verifies the signature locally; rejects on mismatch.
//    4. `ESangTTSPlayer.shared.speak(response.spokenReply, ...)`
//       reads the result aloud in the driver's preferred dialect
//       (P0-4 wiring inherits automatically).
//    5. UI renders the structured guide (UN/class/guide/isolation
//       distance/protective clothing/emergency response) below
//       the photo with a follow-up text field for multi-turn
//       ERG questions ("can I haul with class 3?" → server
//       answers grounded in the guide via `erg.askFollowUp`).
//
//  Drop into: EusoTrip/Views/Driver/HazmatPlacardScanView.swift
//

import SwiftUI
import UIKit

public struct HazmatPlacardScanView: View {
    let vehicleId: String?
    let loadId: String?

    public init(vehicleId: String? = nil, loadId: String? = nil) {
        self.vehicleId = vehicleId
        self.loadId = loadId
    }

    @State private var showCamera: Bool = false
    @State private var capturedImage: UIImage? = nil
    @State private var scanResult: PlacardScanResponse? = nil
    @State private var isScanning: Bool = false
    @State private var scanError: String? = nil

    @State private var followUpQuestion: String = ""
    @State private var followUpAnswer: String? = nil
    @State private var isAsking: Bool = false

    // Document-intelligence spine pass (documentRouter.classifyAndRoute).
    // Runs ALONGSIDE the ERG placard upload so the capture point KNOWS
    // exactly what was photographed (classify + extract the UN number /
    // hazard class / proper shipping name) instead of trusting a raw
    // image. CRITICAL for hazmat compliance — surfaced honestly: low
    // confidence or `unknown` is reported as "couldn't confidently
    // identify", never claimed as a placard it isn't.
    @State private var classifyResult: DocumentRouterAPI.ClassifyResponse? = nil
    @State private var isClassifying: Bool = false
    @State private var classifyError: String? = nil

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                scanButton
                if let img = capturedImage {
                    capturedImageStrip(img)
                }
                if isScanning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Astra is reading the placard…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                if let err = scanError {
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.vertical, 4)
                }
                if isClassifying {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Identifying the document…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                if let cErr = classifyError {
                    Text(cErr)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.vertical, 4)
                }
                if let cls = classifyResult {
                    classifyBanner(cls)
                }
                if let result = scanResult {
                    resultBlock(result)
                    if result.material != nil {
                        followUpBlock(unNumber: result.unNumber ?? "")
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Hazmat Placard")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCamera) {
            HazmatCameraSheet { image in
                showCamera = false
                if let image {
                    capturedImage = image
                    Task { await runScan(image: image) }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("ASTRA · HAZMAT")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            Text("Scan the placard with your camera. ESang will read the ERG guide aloud in your preferred dialect.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var scanButton: some View {
        Button {
            showCamera = true
        } label: {
            HStack {
                Image(systemName: "camera.viewfinder")
                Text(scanResult == nil ? "Scan placard" : "Scan again")
                    .font(.body.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(LinearGradient(colors: [.orange, .red],
                                        startPoint: .leading, endPoint: .trailing))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isScanning)
    }

    @ViewBuilder
    private func capturedImageStrip(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func resultBlock(_ r: PlacardScanResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(r.ocr.unNumber.map { "UN \($0)" } ?? "UN —")
                    .font(.title3.bold())
                if let cls = r.material?.hazardClass ?? r.ocr.hazardClassNumber {
                    Text("Class \(cls)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.orange, in: Capsule())
                        .foregroundStyle(.white)
                }
                if r.placardsAffixed {
                    Label("Overlay signed", systemImage: "checkmark.shield.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
                Spacer(minLength: 0)
            }
            if let name = r.material?.name {
                Text(name)
                    .font(.headline)
            }
            if let guideNo = r.material?.guideNumber {
                Text("ERG Guide \(guideNo)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(r.spokenReply)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    Task { await ESangTTSPlayer.shared.speak(r.spokenReply, serverAudioBase64: nil) }
                } label: {
                    Label("Read aloud", systemImage: "speaker.wave.2.fill")
                        .font(.callout)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.gray.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                if r.material?.isTIH == true {
                    Label("Toxic by inhalation", systemImage: "wind")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.gray.opacity(0.08)))
        .onAppear {
            // Auto-read on first display.
            Task { await ESangTTSPlayer.shared.speak(r.spokenReply, serverAudioBase64: nil) }
        }
    }

    // MARK: - Document-intelligence identification banner
    //
    // Renders the REAL classifier result honestly. The capture point now
    // KNOWS what it photographed: detected document type + confidence,
    // plus the extracted UN number / hazard class / proper shipping name.
    // If the type is `unknown` or confidence is low, it says so plainly
    // and asks the driver to confirm — it never claims a placard it isn't.
    @ViewBuilder
    private func classifyBanner(_ r: DocumentRouterAPI.ClassifyResponse) -> some View {
        let confidencePct = Int((r.confidence * 100).rounded())
        let looksLikePlacard = r.classifiedType.lowercased().contains("placard")
            || r.classifiedType.lowercased().contains("hazmat")
        // Confident only when the server is sure AND it actually looks
        // like a placard — otherwise we ask the driver to confirm.
        let confident = r.confidence >= 0.7
            && r.classifiedType.lowercased() != "unknown"
            && looksLikePlacard

        let un = extracted(["unNumber", "unId", "unIdentifier", "identifier"])
        let hazardClass = extracted(["hazardClass", "hazardClassNumber", "class", "hazardDivision"])
        let shippingName = extracted(["properShippingName", "shippingName", "material", "materialName", "name"])

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: confident ? "doc.viewfinder.fill" : "questionmark.diamond.fill")
                    .foregroundStyle(confident ? .green : .orange)
                Text("DOCUMENT INTELLIGENCE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(confidencePct)% confidence")
                    .font(.caption.bold())
                    .foregroundStyle(confident ? .green : .orange)
            }

            if confident {
                // High-confidence placard read — show the detected type.
                Text("Identified: \(prettyType(r.classifiedType))")
                    .font(.headline)
            } else if r.classifiedType.lowercased() == "unknown" {
                Text("Couldn't confidently identify this as a hazmat placard — please confirm the values below by eye.")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // The server returned a type, but either confidence is low
                // or it doesn't read as a placard — be honest about it.
                Text("Read as “\(prettyType(r.classifiedType))” at \(confidencePct)% — not confident this is a hazmat placard. Please confirm before relying on it.")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Extracted hazmat identifiers — only render what was actually
            // returned; missing fields show an honest dash, never invented.
            if un != nil || hazardClass != nil || shippingName != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let un { fieldRow(label: "UN number", value: "UN \(un)") }
                    if let hazardClass { fieldRow(label: "Hazard class", value: hazardClass) }
                    if let shippingName { fieldRow(label: "Proper shipping name", value: shippingName) }
                }
                .padding(.top, 2)
            } else {
                Text("No UN number, hazard class, or proper shipping name could be read off this frame.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !r.summary.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(r.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(r.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill((confident ? Color.green : Color.orange).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder((confident ? Color.green : Color.orange).opacity(0.35), lineWidth: 1)
        )
    }

    private func fieldRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.callout.bold())
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Turn a server snake/code type ("hazmat_placard") into a readable
    /// label ("Hazmat placard"). No fabrication — purely cosmetic.
    private func prettyType(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        guard let first = spaced.first else { return raw }
        return first.uppercased() + spaced.dropFirst()
    }

    @ViewBuilder
    private func followUpBlock(unNumber: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient(
                        colors: [.cyan, .green],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text("Ask ESang about UN \(unNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField("e.g. \"What if it spills on hot asphalt?\"",
                          text: $followUpQuestion,
                          axis: .horizontal)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { Task { await askFollowUp(unNumber: unNumber) } }
                Button {
                    Task { await askFollowUp(unNumber: unNumber) }
                } label: {
                    if isAsking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.body)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(followUpQuestion.trimmingCharacters(in: .whitespaces).isEmpty || isAsking)
            }
            if let answer = followUpAnswer {
                Text(answer)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.gray.opacity(0.06)))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.gray.opacity(0.04)))
    }

    @MainActor
    private func runScan(image: UIImage) async {
        isScanning = true
        scanError = nil
        scanResult = nil
        followUpAnswer = nil
        // Reset the parallel document-intelligence pass.
        classifyResult = nil
        classifyError = nil
        defer { isScanning = false }

        // Fire the document-intelligence classify pass ALONGSIDE the ERG
        // placard upload (not in place of it). The ERG bundle stays the
        // compliance source of truth; the classifier independently
        // confirms what the camera actually saw (UN # / hazard class /
        // proper shipping name) so a mis-aimed or non-placard frame is
        // caught honestly instead of being uploaded as-if it were a real
        // placard.
        async let _classify: Void = runClassifyPass(image: image)

        do {
            let result = try await ERGLookupService.shared.scanPlacard(
                image: image,
                vehicleId: vehicleId,
                loadId: loadId
            )
            scanResult = result
        } catch {
            scanError = (error as NSError).localizedDescription
        }

        // Make sure the classify pass has settled before we drop the
        // spinner so the result/“couldn’t identify” banner is in place.
        await _classify
    }

    /// Document-intelligence spine pass — classifies the captured frame
    /// via `documentRouter.classifyAndRoute` with a `hazmat_placard`
    /// caller hint. Pure read: surfaces the detected type + extracted
    /// UN / class / proper shipping name. Never claims a type it isn't —
    /// low confidence or `unknown` is reported neutrally by the banner.
    @MainActor
    private func runClassifyPass(image: UIImage) async {
        isClassifying = true
        defer { isClassifying = false }

        // Compress so the base64 payload stays light (Gemini ~1MB cap).
        var jpeg = image.jpegData(compressionQuality: 0.7)
        if let d = jpeg, d.count > 900_000,
           let smaller = image.jpegData(compressionQuality: 0.5) {
            jpeg = smaller
        }
        guard let data = jpeg, !data.isEmpty else {
            classifyError = "Couldn't encode the placard photo for identification."
            return
        }

        do {
            let resp = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                documentBase64: data.base64EncodedString(),
                mimeType: .jpeg,
                callerContext: "hazmat_placard"
            )
            classifyResult = resp
        } catch {
            classifyError = "Couldn't identify the placard: \((error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription)"
        }
    }

    /// First non-empty extracted-field value across the candidate keys
    /// the server may emit for a hazmat placard (keys are doc-type
    /// specific). Honest helper — returns nil if nothing matched.
    private func extracted(_ keys: [String]) -> String? {
        guard let fields = classifyResult?.extractedFields else { return nil }
        for key in keys {
            if let v = fields[key]?.asString,
               !v.trimmingCharacters(in: .whitespaces).isEmpty {
                return v
            }
        }
        return nil
    }

    @MainActor
    private func askFollowUp(unNumber: String) async {
        let q = followUpQuestion.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isAsking = true
        defer { isAsking = false }
        do {
            let reply = try await ERGLookupService.shared.askFollowUp(
                unNumber: unNumber,
                question: q
            )
            followUpAnswer = reply.answer
            followUpQuestion = ""
            // Read the follow-up aloud too — driver is hands-busy.
            await ESangTTSPlayer.shared.speak(reply.answer, serverAudioBase64: nil)
        } catch {
            followUpAnswer = "Couldn't reach ESang: \((error as NSError).localizedDescription)"
        }
    }
}

// MARK: - Camera sheet bridge

private struct HazmatCameraSheet: UIViewControllerRepresentable {
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

#Preview("Hazmat Placard Scan · Dark") {
    NavigationStack {
        HazmatPlacardScanView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Hazmat Placard Scan · Light") {
    NavigationStack {
        HazmatPlacardScanView()
    }
    .preferredColorScheme(.light)
}
