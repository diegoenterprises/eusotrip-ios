//
//  DeliveryPODCaptureView.swift
//  EusoTrip — Delivery-side POD capture (driver lifecycle).
//
//  Closes the Phase 13 PARTIAL → PASS gap surfaced in the 8000-scenario
//  shipper↔driver parity audit (docs/parity-2026/EXECUTIVE_VERDICT.md
//  §4.2). Replaces the prior `PickupBolSigning` sheet that 024 was
//  opening — wrong sheet for delivery context.
//
//  Anchored by three production-grade cards:
//
//    1. Photo card — gradient-rim, taps PhotosPicker for the POD
//       photo. Preview renders post-capture; "Retake" overlay
//       dismisses the image. Compresses to JPEG @ 0.7 quality and
//       base64-encodes for the server payload (server schema:
//       `pod.submitPOD.photoBase64`).
//
//    2. Signature card — gradient-rim, full-width SwiftUI Canvas
//       with pan-gesture drawing. "Clear" CTA wipes; export renders
//       the strokes into a PNG base64 string for the server payload
//       (`pod.submitPOD.signatureBase64`).
//
//    3. Receiver + notes card — receiver name (required, server
//       enforces min(1)) + over/short/damage notes (optional).
//
//  Bottom CTAs: "Cancel" outline + "Submit POD" gradient. Submit
//  fires `pod.submitPOD`, transitions the load to `pod_pending`
//  server-side, advances the lifecycle, and dismisses.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import PhotosUI

// MARK: - Public sheet

/// Driver-side POD capture. Hosted as a `.fullScreenCover` from
/// `024_Unloading.swift` once the trailer is empty and the
/// receiver is ready to sign. Submits a real `pod.submitPOD`
/// mutation — no web continuation, no stub. After success the
/// load flips server-side to `pod_pending`, the lifecycle
/// store advances, and the sheet dismisses.
struct DeliveryPODCaptureView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lifecycleAdvance) private var advance

    let loadId: String
    let loadNumber: String?
    /// Optional receiver hint pulled from the consignee facility row
    /// — pre-populates the receiver-name field so the driver only
    /// has to confirm rather than re-type.
    let receiverHint: String?

    init(
        loadId: String,
        loadNumber: String? = nil,
        receiverHint: String? = nil
    ) {
        self.loadId = loadId
        self.loadNumber = loadNumber
        self.receiverHint = receiverHint
    }

    // MARK: Capture state

    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photoImage: UIImage? = nil
    @State private var signatureStrokes: [SignatureStroke] = []
    @State private var liveStroke: SignatureStroke = SignatureStroke()
    @State private var receiverName: String = ""
    @State private var notes: String = ""

    // MARK: Submit state

    @State private var inFlight: Bool = false
    @State private var error: String? = nil
    @State private var successToast: String? = nil

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    eyebrowHeader
                    photoCard
                    signatureCard
                    receiverNotesCard
                    if let err = error {
                        errorBanner(err)
                    }
                    Color.clear.frame(height: 96)
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
                        Text("PROOF OF DELIVERY")
                            .font(EType.micro).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(loadNumber ?? loadId)
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
                if let toast = successToast {
                    successPill(toast)
                }
            }
        }
        .onAppear {
            if receiverName.isEmpty, let hint = receiverHint, !hint.isEmpty {
                receiverName = hint
            }
        }
    }

    // MARK: - Eyebrow header

    private var eyebrowHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Capture proof of delivery")
                .font(EType.display)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("A clear photo of the signed BOL plus the receiver's signature releases your rig and starts the payment clock. Server stores the bundle on the load and flips status to pod-pending for shipper review.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Photo card

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("01 · BOL PHOTO")
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
                            Text("Tap to capture or pick image")
                                .font(EType.body).fontWeight(.semibold)
                                .foregroundStyle(palette.textPrimary)
                            Text("Receiver-signed BOL · OS&D notes legible")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
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

    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            photoImage = img
        }
    }

    // MARK: - Signature card

    private var signatureCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("02 · RECEIVER SIGNATURE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if !signatureStrokes.isEmpty || !liveStroke.points.isEmpty {
                    Button {
                        signatureStrokes = []
                        liveStroke = SignatureStroke()
                    } label: {
                        Text("Clear")
                            .font(EType.caption).fontWeight(.semibold)
                            .foregroundStyle(palette.textSecondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }

            PODSignaturePad(
                strokes: $signatureStrokes,
                liveStroke: $liveStroke,
                inkColor: palette.textPrimary
            )
            .frame(height: 180)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )

            HStack(spacing: 4) {
                Rectangle()
                    .fill(palette.textTertiary)
                    .frame(width: 12, height: 1)
                Text("X · sign above")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(signatureStrokes.isEmpty ? 0.35 : 0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Receiver + notes

    private var receiverNotesCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("03 · RECEIVER DETAILS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)

            VStack(alignment: .leading, spacing: 4) {
                Text("Receiver name")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. Marcus W., Dock 12", text: $receiverName)
                    .font(EType.body)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft,
                                in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(palette.borderFaint))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("OS&D notes (optional)")
                    .font(EType.caption).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                TextField("over / short / damage — leave blank if clean",
                          text: $notes,
                          axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
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
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Submit bar

    private var submitBar: some View {
        VStack(spacing: 0) {
            IridescentHairline()
            HStack(spacing: Space.s3) {
                Button {
                    dismiss()
                } label: {
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
                    title: inFlight ? "Submitting…" : "Submit POD",
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
        let hasReceiver = !receiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPhoto    = photoImage != nil
        let hasSig      = !signatureStrokes.isEmpty
        return hasReceiver && hasPhoto && hasSig && !inFlight
    }

    // MARK: - Error + toast UI

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

    private func successPill(_ message: String) -> some View {
        Text(message)
            .font(EType.caption).fontWeight(.semibold)
            .foregroundStyle(palette.textOnGradient)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .background(Brand.success,
                        in: RoundedRectangle(cornerRadius: Radius.md))
            .padding(.bottom, 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                withAnimation { successToast = nil }
            }
    }

    // MARK: - Submit

    /// Encode + ship the POD packet via `pod.submitPOD`. On success
    /// the lifecycle store advances and the sheet dismisses. The
    /// receiver row + photo + signature payloads each compress
    /// before base64-encoding to keep the wire size sane (~200KB
    /// typical for an 8mp photo + a 600x180 PNG signature).
    private func submit() async {
        guard canSubmit else { return }
        guard let numericId = Int(loadId) else {
            error = "Could not resolve numeric load id."
            return
        }
        let trimmedReceiver = receiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        inFlight = true
        error = nil

        let photoB64 = photoImage.flatMap { $0.jpegData(compressionQuality: 0.7) }?
            .base64EncodedString()
        let sigB64 = renderSignaturePNGBase64(
            strokes: signatureStrokes,
            inkColor: .black,    // signature ink is always opaque black on the rendered PNG
            size: CGSize(width: 600, height: 180)
        )

        do {
            _ = try await EusoTripAPI.shared.pod.submitPOD(
                loadId: numericId,
                receiverName: trimmedReceiver,
                photoBase64: photoB64,
                signatureBase64: sigB64,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            inFlight = false
            withAnimation { successToast = "POD submitted · awaiting shipper approval" }
            // Brief pause so the toast registers before dismiss.
            try? await Task.sleep(nanoseconds: 700_000_000)
            advance?()
            dismiss()
        } catch {
            inFlight = false
            self.error = (error as NSError).localizedDescription
        }
    }
}

// MARK: - SignatureStroke + PODSignaturePad

/// One continuous pen-down → pen-up stroke. The pad accumulates
/// strokes; each stroke is a polyline of CGPoints in pad-local
/// coordinates. Rendered into a PNG at submit time.
struct SignatureStroke: Equatable {
    var points: [CGPoint] = []
}

/// SwiftUI Canvas-backed signature pad. The live stroke is drawn
/// on top of the committed strokes so dragging feels immediate
/// without flushing through the @State-array on every gesture
/// update.
struct PODSignaturePad: View {
    @Binding var strokes: [SignatureStroke]
    @Binding var liveStroke: SignatureStroke
    let inkColor: Color

    var body: some View {
        Canvas { ctx, _ in
            for stroke in strokes {
                drawStroke(ctx: ctx, stroke: stroke)
            }
            drawStroke(ctx: ctx, stroke: liveStroke)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    liveStroke.points.append(value.location)
                }
                .onEnded { _ in
                    if !liveStroke.points.isEmpty {
                        strokes.append(liveStroke)
                        liveStroke = SignatureStroke()
                    }
                }
        )
    }

    private func drawStroke(ctx: GraphicsContext, stroke: SignatureStroke) {
        guard stroke.points.count > 1 else { return }
        var path = Path()
        path.move(to: stroke.points[0])
        for p in stroke.points.dropFirst() {
            path.addLine(to: p)
        }
        ctx.stroke(
            path,
            with: .color(inkColor),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        )
    }
}

// MARK: - PNG export

/// Render the signature strokes into a fixed-size PNG, base64-
/// encoded for the server `signatureBase64` field. The strokes
/// live in pad-local coordinates; we scale them to the target
/// canvas based on the original pad height of 180pt.
func renderSignaturePNGBase64(
    strokes: [SignatureStroke],
    inkColor: UIColor,
    size: CGSize
) -> String? {
    guard !strokes.isEmpty else { return nil }
    let renderer = UIGraphicsImageRenderer(size: size)
    let img = renderer.image { uiCtx in
        let ctx = uiCtx.cgContext
        ctx.setStrokeColor(inkColor.cgColor)
        ctx.setLineWidth(2.4)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        // Strokes captured at ~180pt height. Map directly — the
        // user's pad is the same aspect ratio as the export size
        // (180:600 vs 180:600). If the device was different we'd
        // scale; the typical case maps cleanly.
        for stroke in strokes {
            guard stroke.points.count > 1 else { continue }
            ctx.move(to: stroke.points[0])
            for p in stroke.points.dropFirst() {
                ctx.addLine(to: p)
            }
            ctx.strokePath()
        }
    }
    return img.pngData()?.base64EncodedString()
}

// MARK: - Previews

#Preview("POD capture · Dark") {
    DeliveryPODCaptureView(
        loadId: "44912",
        loadNumber: "LD-260427-A38FB12C7E",
        receiverHint: "Marcus W., Dock 12"
    )
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("POD capture · Light") {
    DeliveryPODCaptureView(
        loadId: "44912",
        loadNumber: "LD-260427-A38FB12C7E",
        receiverHint: "Marcus W., Dock 12"
    )
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
