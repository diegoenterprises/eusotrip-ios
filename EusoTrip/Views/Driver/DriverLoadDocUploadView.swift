//
//  DriverLoadDocUploadView.swift
//  EusoTrip — Driver-side per-load document capture.
//
//  Closes Phase 7 (Document exchange) of the 8000-scenario shipper↔
//  driver parity audit (docs/parity-2026/EXECUTIVE_VERDICT.md §4.4).
//  Phase 7 was PARTIAL because backend bol.* + documentManagement.*
//  shipped, the driver's general-purpose Me-Docs hub (083) handles
//  account documents (W-9, MVR, insurance), but there was no
//  load-scoped capture surface for in-flight doc exchange (pre-pickup
//  BOL scan, rate-con re-scan, customs-doc photo, signed BOL post-
//  pickup, etc).
//
//  Shares photo-capture infrastructure with DeliveryPODCaptureView —
//  PhotosPicker + JPEG@0.7 base64 — so the build cost is small. Where
//  POD demanded a signature, this surface drops it (most in-flight
//  document exchange is just a photo of the printed paperwork).
//
//  Surface anatomy:
//    1. Doc-type chip row — BOL / Rate-con / Insurance / Customs /
//       Photo / Other. The chip choice maps to the server's
//       `documentManagement.uploadDocument(type:)` enum.
//    2. Photo capture card — gradient-rim, taps PhotosPicker; preview
//       after capture; "Retake" overlay clears the image.
//    3. Optional name override + notes.
//    4. Submit bar with Cancel + gradient Upload CTAs.
//
//  Server contract: `documentManagement.uploadDocument(
//    name, type, mimeType, size, fileData, entityType:"load",
//    entityId:loadId, tags:[doc-type, "driver-captured"])`.
//
//  Production-grade per [feedback_swiftui_previews] mandate. Dark +
//  Light previews ship.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import PhotosUI

// MARK: - DocumentKind

/// Per-load doc types the driver can capture inline. Maps 1:1 to
/// the server's `documentManagement.uploadDocument(type:)` enum
/// values — strings stay stable across the wire.
enum DriverLoadDocKind: String, CaseIterable, Identifiable, Hashable {
    case bol           = "bol"
    case rateCon       = "rate_confirmation"
    case insurance     = "insurance"
    case customs       = "customs"
    case photo         = "photo"
    case other         = "other"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bol:        return "BOL"
        case .rateCon:    return "Rate-con"
        case .insurance:  return "Insurance"
        case .customs:    return "Customs"
        case .photo:      return "Photo"
        case .other:      return "Other"
        }
    }

    var icon: String {
        switch self {
        case .bol:        return "doc.text"
        case .rateCon:    return "dollarsign.square"
        case .insurance:  return "checkmark.shield"
        case .customs:    return "globe.americas"
        case .photo:      return "photo"
        case .other:      return "ellipsis.rectangle"
        }
    }

    /// Default file-name prefix used in the upload payload. Server
    /// suffixes with timestamp + extension; this just keeps the
    /// downstream label scannable in the docs hub.
    var defaultName: String {
        switch self {
        case .bol:        return "BOL"
        case .rateCon:    return "Rate Confirmation"
        case .insurance:  return "Insurance"
        case .customs:    return "Customs Doc"
        case .photo:      return "Photo"
        case .other:      return "Document"
        }
    }
}

// MARK: - View

struct DriverLoadDocUploadView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let loadId: String
    let loadNumber: String?
    /// Pre-select a doc type (e.g., the host screen knows the driver
    /// is at pickup and wants a BOL). Default lands on `.bol` because
    /// that's the most common in-flight capture.
    let initialKind: DriverLoadDocKind

    init(
        loadId: String,
        loadNumber: String? = nil,
        initialKind: DriverLoadDocKind = .bol
    ) {
        self.loadId = loadId
        self.loadNumber = loadNumber
        self.initialKind = initialKind
    }

    @State private var kind: DriverLoadDocKind = .bol
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photoImage: UIImage? = nil
    @State private var name: String = ""
    @State private var notes: String = ""

    @State private var inFlight: Bool = false
    @State private var error: String? = nil
    @State private var success: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    headerCard
                    docKindCard
                    photoCard
                    namingCard
                    if let err = error {
                        errorBanner(err)
                    }
                    Color.clear.frame(height: 132)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(inFlight)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("UPLOAD DOC")
                            .font(EType.micro).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(loadNumber ?? "Load #\(loadId)")
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                submitBar
                    .background(palette.bgPrimary)
            }
            .overlay(alignment: .bottom) {
                if success {
                    Text("Uploaded · attached to this load")
                        .font(EType.caption).fontWeight(.semibold)
                        .foregroundStyle(palette.textOnGradient)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s2)
                        .background(Brand.success,
                                    in: RoundedRectangle(cornerRadius: Radius.md))
                        .padding(.bottom, 132)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear { kind = initialKind }
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Attach a document to this load")
                .font(EType.display)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("Snap the printed paperwork — BOL, rate-con, insurance, customs — and we'll attach it to the load envelope so the shipper sees it instantly. ESANG OCR auto-flags any defects on the same upload.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var docKindCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("01 · DOC TYPE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DriverLoadDocKind.allCases) { k in
                        Button {
                            withAnimation(.easeOut(duration: 0.12)) {
                                kind = k
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: k.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(k.label)
                                    .font(EType.caption).fontWeight(.semibold)
                            }
                            .foregroundStyle(kind == k ? palette.textOnGradient : palette.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(
                                Capsule().fill(
                                    kind == k
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.bgCardSoft)
                                )
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    kind == k ? Color.clear : palette.borderFaint
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("02 · PHOTO")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if photoImage != nil {
                    Button {
                        photoImage = nil
                        photoItem = nil
                    } label: {
                        Text("Retake")
                            .font(EType.caption).fontWeight(.semibold)
                            .foregroundStyle(palette.textSecondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
            ZStack {
                if let img = photoImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                } else {
                    PhotosPicker(selection: $photoItem,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        VStack(spacing: 10) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(LinearGradient.diagonal)
                            Text("Tap to capture")
                                .font(EType.body).fontWeight(.semibold)
                                .foregroundStyle(palette.textPrimary)
                            Text(captureHint)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .padding(Space.s4)
                        .background(palette.bgCardSoft)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(photoImage == nil ? 0.35 : 0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onChange(of: photoItem) { _, newItem in
            Task { await loadPickedPhoto(newItem) }
        }
    }

    private var captureHint: String {
        switch kind {
        case .bol:
            return "Whole BOL legible · all four corners · seal numbers visible"
        case .rateCon:
            return "Rate confirmation · MC# legible · accessorial schedule visible"
        case .insurance:
            return "Insurance certificate · effective dates legible · carrier-named"
        case .customs:
            return "Customs declaration · entry number + tariff codes legible"
        case .photo, .other:
            return "Capture the document at an angle that keeps the type/edges sharp"
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            photoImage = img
            // Auto-prefill name with the doc kind + load number for
            // a scannable label in the docs hub.
            if name.isEmpty {
                let stamp = ISO8601DateFormatter().string(from: Date())
                name = "\(kind.defaultName) · \(loadNumber ?? loadId) · \(stamp.prefix(10))"
            }
        }
    }

    private var namingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("03 · NAMING")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 4) {
                Text("Name (auto-filled, editable)")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. BOL · LD-260427 · 2026-04-30",
                          text: $name)
                    .font(EType.body)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(palette.borderFaint))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes (optional)")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                TextField("Anything the shipper should know about this doc",
                          text: $notes,
                          axis: .vertical)
                    .lineLimit(2, reservesSpace: true)
                    .font(EType.body)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(palette.borderFaint))
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            IridescentHairline()
            HStack(spacing: Space.s3) {
                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCard,
                                    in: RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(palette.borderSoft))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)

                CTAButton(
                    title: inFlight ? "Uploading…" : "Upload doc",
                    action: { Task { await submit() } },
                    isLoading: inFlight
                )
                .opacity(canSubmit ? 1.0 : 0.55)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
    }

    private var canSubmit: Bool {
        photoImage != nil && !inFlight
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md)
            .strokeBorder(Brand.danger.opacity(0.4)))
    }

    // MARK: - Submit

    private func submit() async {
        guard canSubmit, let img = photoImage else { return }
        inFlight = true
        error = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: Data? = img.jpegData(compressionQuality: 0.7)
        guard let payload else {
            inFlight = false
            error = "Could not encode the photo for upload."
            return
        }
        let base64 = payload.base64EncodedString()
        let label = trimmedName.isEmpty ? "\(kind.defaultName) · \(loadNumber ?? loadId)" : trimmedName

        do {
            _ = try await EusoTripAPI.shared.documentManagement.uploadDocument(
                name: label,
                type: kind.rawValue,
                mimeType: "image/jpeg",
                size: payload.count,
                fileData: base64,
                entityType: "load",
                entityId: loadId,
                tags: [kind.rawValue, "driver-captured", trimmedNotes].filter { !$0.isEmpty },
                expiresAt: nil
            )
            inFlight = false
            withAnimation { success = true }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch {
            inFlight = false
            self.error = (error as NSError).localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("Doc upload · BOL · Dark") {
    DriverLoadDocUploadView(
        loadId: "44912",
        loadNumber: "LD-260427-A38FB12C7E",
        initialKind: .bol
    )
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("Doc upload · Rate-con · Light") {
    DriverLoadDocUploadView(
        loadId: "44912",
        loadNumber: "LD-260427-A38FB12C7E",
        initialKind: .rateCon
    )
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
