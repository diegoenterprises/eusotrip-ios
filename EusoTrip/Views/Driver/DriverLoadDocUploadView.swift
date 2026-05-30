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

    // MARK: - Document-intelligence state
    //
    // After a capture, the bytes run through
    // `documentRouter.classifyAndRoute(...)` (Gemini + NVIDIA) BEFORE
    // the raw upload. The classifier auto-detects the doc type, so the
    // chip row flips from "you pick" to "we picked — override if we're
    // wrong". The classified envelope (server type + extracted fields +
    // dispatch target + summary) is retained so the upload payload
    // carries it downstream and the dispatch target gets routed.

    /// Compressed base64 of the captured image, computed once at
    /// classify-time and reused for the upload so we don't re-encode.
    @State private var capturedBase64: String? = nil
    /// True while the classify pass is in flight (separate from the
    /// upload `inFlight`).
    @State private var classifying: Bool = false
    /// The server's verbatim classifiedType (e.g. "bill_of_lading"),
    /// kept distinct from the local `kind` so the upload can carry the
    /// canonical type even when it doesn't map to a chip.
    @State private var classifiedType: String? = nil
    @State private var confidence: Double? = nil
    @State private var classifiedSummary: String? = nil
    @State private var classifiedWarnings: [String] = []
    @State private var dispatchTarget: String? = nil
    @State private var extractedFields: [String: String] = [:]
    /// Set true once the user taps a chip after auto-detect, so we stop
    /// implying the type is AI-chosen and respect the manual override.
    @State private var manualOverride: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    headerCard
                    photoCard
                    if classifying || classifiedType != nil {
                        classificationCard
                    }
                    docKindCard
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
            HStack(spacing: 6) {
                Text("01 · DOC TYPE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if confidence != nil && !manualOverride {
                    confidenceBadge
                } else if manualOverride {
                    Text("MANUAL")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(palette.bgCardSoft))
                }
            }
            Text(docKindHint)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DriverLoadDocKind.allCases) { k in
                        Button {
                            withAnimation(.easeOut(duration: 0.12)) {
                                kind = k
                                // The driver disagreed with (or is
                                // pre-empting) the classifier — respect
                                // the manual choice from here on.
                                if classifiedType != nil { manualOverride = true }
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

    /// Sub-line under the DOC TYPE header. Before a classify it tells
    /// the driver they can pick; after, it tells them we already picked
    /// (and how to override).
    private var docKindHint: String {
        if classifying { return "ESANG is reading the document…" }
        if confidence != nil && !manualOverride {
            return "Auto-detected from your capture. Tap a chip to override."
        }
        if manualOverride { return "You set this type — we'll upload as you chose." }
        return "Pick the document type, or just snap it and we'll detect it."
    }

    /// Confidence pill shown beside the DOC TYPE header once the
    /// classifier returns. Color tracks the same 85/60 thresholds the
    /// 204 reference uses so the whole app reads confidence the same way.
    private var confidenceBadge: some View {
        let pct = Int(((confidence ?? 0) * 100).rounded())
        let tint: Color = pct >= 85 ? Brand.success : (pct >= 60 ? Brand.warning : Brand.danger)
        return HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 8, weight: .heavy))
            Text("AI · \(pct)%")
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    /// Result card surfacing what the classifier saw: the human type,
    /// the summary, any warnings, and the downstream dispatch target it
    /// routed to. Sits between the photo and the (now-override) chip row.
    private var classificationCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESANG · DOCUMENT ROUTER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if confidence != nil { confidenceBadge }
            }

            if classifying {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).tint(palette.textPrimary)
                    Text("Classifying the capture…")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                }
            } else if let ct = classifiedType {
                HStack(spacing: 6) {
                    Text(humanType(ct))
                        .font(EType.body).fontWeight(.bold)
                        .foregroundStyle(palette.textPrimary)
                    if mappedKind(for: ct) == nil {
                        Text("· filed as \(kind.label)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if let s = classifiedSummary, !s.isEmpty {
                    Text(s)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let dt = dispatchTarget, !dt.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                        Text("Routed → \(dt)")
                            .font(EType.mono(.micro)).tracking(0.2)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if !extractedFields.isEmpty {
                    Text("\(extractedFields.count) field\(extractedFields.count == 1 ? "" : "s") extracted · attached to upload")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
                ForEach(classifiedWarnings.prefix(2), id: \.self) { w in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Brand.warning)
                        Text(w)
                            .font(EType.caption).foregroundStyle(Brand.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
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
        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        photoImage = img
        // Hand the raw bytes to the document-intelligence spine FIRST,
        // before any manual naming/typing, so the auto-detected type
        // can drive the prefill.
        await classifyCapture(img)
        // Auto-prefill name with the (possibly classifier-chosen) doc
        // kind + load number for a scannable label in the docs hub.
        if name.isEmpty {
            let stamp = ISO8601DateFormatter().string(from: Date())
            name = "\(kind.defaultName) · \(loadNumber ?? loadId) · \(stamp.prefix(10))"
        }
    }

    // MARK: - Document-intelligence pass
    //
    // Runs `documentRouter.classifyAndRoute(...)` on the captured bytes
    // (Gemini + NVIDIA). Auto-detects the doc type → flips the chip row
    // to AI-chosen (driver can still override), surfaces the summary +
    // warnings, retains extractedFields for the upload payload, and
    // emits the dispatchTarget envelope so the host shell can route it.

    /// Maps the server's canonical `classifiedType` onto the local
    /// chip enum. Nil when the classifier returns a type with no chip
    /// (e.g. a weight ticket) — we still upload, just without changing
    /// the chip selection.
    private func mappedKind(for classifiedType: String) -> DriverLoadDocKind? {
        switch classifiedType {
        case "bill_of_lading", "bol":
            return .bol
        case "rate_confirmation", "load_tender":
            return .rateCon
        case "us_coi", "ca_coi", "mx_coi", "insurance", "certificate_of_insurance":
            return .insurance
        case "customs_declaration", "commercial_invoice", "customs",
             "usmca_certificate", "bill_of_entry", "pedimento", "aces", "aci":
            return .customs
        case "photo", "image":
            return .photo
        default:
            return nil
        }
    }

    /// Human label for the server type — mirrors the 204 reference so
    /// the same raw type reads identically across the app.
    private func humanType(_ raw: String) -> String {
        switch raw {
        case "bill_of_lading", "bol": return "Bill of Lading"
        case "rate_confirmation": return "Rate Confirmation"
        case "load_tender": return "Load Tender"
        case "run_ticket": return "Run Ticket"
        case "proof_of_delivery": return "Proof of Delivery"
        case "weight_ticket", "scale_ticket": return "Weight Ticket"
        case "us_coi", "ca_coi", "mx_coi", "certificate_of_insurance":
            return "Insurance Certificate"
        case "commercial_invoice": return "Commercial Invoice"
        case "customs_declaration": return "Customs Declaration"
        case "usmca_certificate": return "USMCA Certificate"
        case "us_cdl": return "CDL"
        case "us_medical_card": return "Medical Card"
        case "unknown", "": return "Unrecognized document"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    @MainActor
    private func classifyCapture(_ img: UIImage) async {
        // Reset any prior classification so a re-capture starts clean.
        classifiedType = nil
        confidence = nil
        classifiedSummary = nil
        classifiedWarnings = []
        dispatchTarget = nil
        extractedFields = [:]
        manualOverride = false
        capturedBase64 = nil

        // Compress to keep the wire payload under ~900KB (same budget
        // the 204 reference uses).
        let raw = img.jpegData(compressionQuality: 0.7) ?? Data()
        var payload = raw
        if payload.count > 900_000 {
            for q in [CGFloat(0.6), 0.5, 0.4] {
                if let d = img.jpegData(compressionQuality: q), d.count <= 900_000 {
                    payload = d; break
                }
            }
        }
        guard !payload.isEmpty else { return }
        let base64 = payload.base64EncodedString()
        capturedBase64 = base64

        classifying = true
        defer { classifying = false }
        do {
            let resp = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                documentBase64: base64,
                mimeType: .jpeg,
                callerContext: "driver per-load in-flight capture · load \(loadNumber ?? loadId) · driver-selected \(kind.rawValue)"
            )
            classifiedType = resp.classifiedType
            confidence = resp.confidence
            classifiedSummary = resp.summary
            classifiedWarnings = resp.warnings
            dispatchTarget = resp.dispatchTarget
            extractedFields = resp.extractedFields.compactMapValues { $0.asString }

            // Auto-select the chip the classifier detected (unless the
            // driver already overrode in the brief classify window).
            if !manualOverride, let mapped = mappedKind(for: resp.classifiedType) {
                withAnimation(.easeOut(duration: 0.15)) { kind = mapped }
            }

            // Emit the dispatch envelope so the host shell can route the
            // doc to its canonical downstream procedure — same pattern
            // as the 204 Bulk classifier's routed signal.
            if let dt = resp.dispatchTarget, !dt.isEmpty {
                NotificationCenter.default.post(
                    name: .eusoDriverLoadDocClassifiedRouted,
                    object: nil,
                    userInfo: [
                        "loadId": loadId,
                        "classifiedType": resp.classifiedType,
                        "dispatchTarget": dt,
                        "confidence": resp.confidence,
                        "summary": resp.summary,
                        "fields": extractedFields,
                    ]
                )
            }
        } catch {
            // A classify miss must NOT block the upload — the driver
            // can still file the doc manually. Surface a soft note.
            classifiedSummary = nil
            classifiedType = nil
            confidence = nil
            self.error = "Auto-detect couldn't read this doc — pick the type below and upload as usual."
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
        // Reuse the base64 computed during the classify pass so we don't
        // re-encode; only fall back to a fresh encode if classify never ran.
        let base64: String
        let payloadSize: Int
        if let cached = capturedBase64,
           let decoded = Data(base64Encoded: cached) {
            base64 = cached
            payloadSize = decoded.count
        } else if let fresh = img.jpegData(compressionQuality: 0.7) {
            base64 = fresh.base64EncodedString()
            payloadSize = fresh.count
        } else {
            inFlight = false
            error = "Could not encode the photo for upload."
            return
        }
        let label = trimmedName.isEmpty ? "\(kind.defaultName) · \(loadNumber ?? loadId)" : trimmedName

        // Upload as today, now carrying the classified type + extracted
        // fields. When the driver didn't override and the classifier
        // produced a confident type, file under the canonical
        // classifiedType; otherwise honor the chip selection.
        let uploadType: String = (!manualOverride && (confidence ?? 0) >= 0.6 && classifiedType != nil && classifiedType != "unknown")
            ? (classifiedType ?? kind.rawValue)
            : kind.rawValue

        // Fold the extracted fields into tags as compact key=value
        // entries so the docs hub / downstream parsers see them on the
        // same upload (documentManagement.uploadDocument has no dedicated
        // metadata param — tags is the wire-stable carrier).
        let fieldTags: [String] = extractedFields
            .sorted { $0.key < $1.key }
            .prefix(12)
            .map { "field:\($0.key)=\($0.value)" }
        var classifierTags: [String] = []
        if let ct = classifiedType, !ct.isEmpty { classifierTags.append("classified:\(ct)") }
        if let c = confidence { classifierTags.append("confidence:\(Int((c * 100).rounded()))") }
        if let dt = dispatchTarget, !dt.isEmpty { classifierTags.append("dispatch:\(dt)") }
        if manualOverride { classifierTags.append("manual-override") }

        let tags = ([uploadType, "driver-captured"]
            + classifierTags
            + fieldTags
            + [trimmedNotes]).filter { !$0.isEmpty }

        do {
            _ = try await EusoTripAPI.shared.documentManagement.uploadDocument(
                name: label,
                type: uploadType,
                mimeType: "image/jpeg",
                size: payloadSize,
                fileData: base64,
                entityType: "load",
                entityId: loadId,
                tags: tags,
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

// MARK: - Doc-router dispatch signal

extension Notification.Name {
    /// Fired after the per-load capture is classified and the document
    /// router returns a non-empty `dispatchTarget`. `userInfo` carries
    /// `loadId`, `classifiedType`, `dispatchTarget`, `confidence`,
    /// `summary`, and `fields` ([String:String]). The driver shell can
    /// listen and route the doc into its canonical downstream procedure
    /// — mirrors the 204 shipper Bulk classifier's routed signal.
    static let eusoDriverLoadDocClassifiedRouted =
        Notification.Name("eusoDriverLoadDocClassifiedRouted")
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
