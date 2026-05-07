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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { LifecycleCard(accentGradient: true) { Text("POD attached. Receiver counter-signature pending.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                pickerCard
                preview
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
                Task { if let i = item, let data = try? await i.loadTransferable(type: Data.self), let img = UIImage(data: data) { pickedImage = img } }
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
