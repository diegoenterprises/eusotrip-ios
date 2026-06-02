//
//  308_PodPhotoCapture.swift
//  EusoTrip — Shipper · POD photo capture (Arc H).
//

import SwiftUI
import PhotosUI

struct PodPhotoCaptureScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { PodCaptureBody(loadId: loadId) } nav: { shipperLifecycleNav() }
    }
}

private struct PodCaptureBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil
    @State private var sending: Bool = false
    @State private var sent: Bool = false
    @State private var actionError: String? = nil

    // Document-intelligence vision spine — classify the captured POD so
    // the capture point KNOWS what it's looking at before/while it
    // uploads, surfacing receiver name / signature-present / PRO#.
    @State private var classifying: Bool = false
    @State private var classification: DocumentRouterAPI.ClassifyResponse? = nil
    @State private var classifyError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { LifecycleCard(accentGradient: true) { Text("POD attached. Receiver counter-signature pending.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                pickerCard
                preview
                classifierCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "camera.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · POD CAPTURE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Capture POD").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var pickerCard: some View {
        LifecycleCard {
            LifecycleSection(label: "PHOTO", icon: "camera")
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text(pickedImage == nil ? "Pick or capture POD" : "Replace photo")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let i = item, let data = try? await i.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        pickedImage = img
                        sent = false
                        await classify(img)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let img = pickedImage {
            Image(uiImage: img)
                .resizable().scaledToFit()
                .frame(maxHeight: 320)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: — Document-intelligence classifier card

    @ViewBuilder
    private var classifierCard: some View {
        if classifying {
            LifecycleCard {
                LifecycleSection(label: "DOCUMENT INTELLIGENCE", icon: "sparkles.tv")
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).tint(palette.textPrimary)
                    Text("Reading the document…").font(EType.caption).foregroundStyle(palette.textTertiary)
                }
            }
        } else if let err = classifyError {
            LifecycleCard(accentWarning: true) {
                LifecycleSection(label: "DOCUMENT INTELLIGENCE", icon: "sparkles.tv")
                Text("Couldn't read the document — \(err). You can still submit; we'll review it after upload.")
                    .font(EType.caption).foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let c = classification {
            classifierResult(c)
        }
    }

    @ViewBuilder
    private func classifierResult(_ c: DocumentRouterAPI.ClassifyResponse) -> some View {
        let conf = Int((c.confidence * 100).rounded())
        let isPod = c.classifiedType == "proof_of_delivery"
        let lowConfidence = c.confidence < 0.6 || c.classifiedType == "unknown"
        let confColor: Color = c.confidence >= 0.85 ? Brand.success : c.confidence >= 0.6 ? Brand.warning : Brand.danger
        // Detected receiver name / signature / PRO# — keys are
        // doc-type-specific so we probe the common POD field aliases.
        let receiver = firstField(c, ["receiverName", "consigneeName", "signedBy", "deliveredTo", "recipient"])
        let pro = firstField(c, ["proNumber", "pro", "trackingNumber", "bolNumber", "loadNumber", "referenceNumber"])
        let signaturePresent = signatureField(c)

        LifecycleCard(accentWarning: lowConfidence) {
            LifecycleSection(label: "DOCUMENT INTELLIGENCE", icon: "sparkles.tv")
            HStack(spacing: 6) {
                Image(systemName: isPod ? "checkmark.seal.fill" : "doc.text.magnifyingglass")
                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(confColor)
                Text(humanType(c.classifiedType))
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("\(conf)%")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7).foregroundStyle(confColor)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(confColor.opacity(0.12)))
                Spacer(minLength: 0)
            }

            if lowConfidence {
                Text(c.classifiedType == "unknown"
                     ? "We couldn't confidently identify this document. Please confirm it's the proof of delivery before submitting."
                     : "Low confidence this is a proof of delivery — please double-check the photo before submitting.")
                    .font(EType.caption).foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !isPod {
                Text("This looks like a \(humanType(c.classifiedType).lowercased()), not a proof of delivery. Confirm before submitting.")
                    .font(EType.caption).foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !c.summary.isEmpty {
                Text(c.summary).font(EType.caption).foregroundStyle(palette.textSecondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }

            // Confirmation fields — only render what the classifier
            // actually extracted; never fabricate a value.
            if receiver != nil || pro != nil || signaturePresent != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let receiver { LifecycleRow(label: "Receiver", value: receiver) }
                    if let pro { LifecycleRow(label: "PRO #", value: pro) }
                    if let signaturePresent {
                        LifecycleRow(label: "Signature", value: signaturePresent ? "Captured" : "Not detected")
                    }
                }
                .padding(.top, 2)
            }

            ForEach(c.warnings, id: \.self) { w in
                Text("⚠ \(w)").font(EType.caption).foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Returns the first non-empty extracted field matching any of the
    /// supplied keys (case-insensitive), or nil.
    private func firstField(_ c: DocumentRouterAPI.ClassifyResponse, _ keys: [String]) -> String? {
        for key in keys {
            if let match = c.extractedFields.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }),
               let s = match.value.asString, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s
            }
        }
        return nil
    }

    /// Resolves whether the classifier reported a signature — handles
    /// boolean flags and presence of a signed-by name.
    private func signatureField(_ c: DocumentRouterAPI.ClassifyResponse) -> Bool? {
        for key in ["signaturePresent", "hasSignature", "signed", "signatureCaptured"] {
            if let match = c.extractedFields.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
                switch match.value {
                case .bool(let b): return b
                case .string(let s):
                    let v = s.lowercased()
                    if ["true", "yes", "present", "captured", "signed"].contains(v) { return true }
                    if ["false", "no", "absent", "missing", "unsigned"].contains(v) { return false }
                default: break
                }
            }
        }
        // A populated signer name implies a captured signature.
        if firstField(c, ["signedBy", "signatureName", "signerName"]) != nil { return true }
        return nil
    }

    private func humanType(_ raw: String) -> String {
        switch raw {
        case "proof_of_delivery": return "Proof of Delivery"
        case "bill_of_lading": return "Bill of Lading"
        case "rate_confirmation": return "Rate Confirmation"
        case "weight_ticket", "scale_ticket": return "Weight Ticket"
        case "run_ticket": return "Run Ticket"
        case "unknown": return "Unrecognized document"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var ctaRow: some View {
        Button { Task { await submit() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Uploading…" : "Submit POD")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || pickedImage == nil)
    }

    /// Runs the captured POD through the homegrown document-intelligence
    /// vision spine so the capture point knows exactly what it is before
    /// the upload. Honest: renders the real classifier result; never
    /// claims a type it isn't.
    @MainActor
    private func classify(_ img: UIImage) async {
        guard let data = jpegPayload(img) else { return }
        classifying = true
        classifyError = nil
        classification = nil
        defer { classifying = false }
        do {
            classification = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                documentBase64: data.base64EncodedString(),
                mimeType: .jpeg,
                callerContext: "proof_of_delivery"
            )
        } catch {
            classifyError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// JPEG-encode, compressing so the vision payload stays under ~900KB.
    private func jpegPayload(_ img: UIImage) -> Data? {
        for q in [CGFloat(0.85), 0.75, 0.65, 0.55, 0.45] {
            if let d = img.jpegData(compressionQuality: q), d.count <= 900_000 { return d }
        }
        return img.jpegData(compressionQuality: 0.45)
    }

    private func submit() async {
        guard let img = pickedImage, let data = img.jpegData(compressionQuality: 0.85) else { return }
        sending = true; actionError = nil
        struct In: Encodable { let loadId: Int; let imageBase64: String }
        struct Out: Decodable { let success: Bool; let documentId: String? }
        let n = Int(loadId.replacingOccurrences(of: "load_", with: "")) ?? 0
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("documents.uploadPod", input: In(loadId: n, imageBase64: data.base64EncodedString()))
            sent = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("308 · POD · Night") {
    PodPhotoCaptureScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("308 · POD · Afternoon") {
    PodPhotoCaptureScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
