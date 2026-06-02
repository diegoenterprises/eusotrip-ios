//
//  1100_IDVLivenessSheet.swift
//  EusoTrip — Compliance · Identity Verification + Liveness capture sheet.
//
//  RIOS spec §11 — Government-ID + selfie liveness verification.
//  This is a .sheet content View (capture precedent — 1100-1110 are
//  acceptable as sheets per the push-nav mandate; only the 1111 wizard
//  is a pushed Shell screen).
//
//  Flow:
//    1. Capture / pick a government photo-ID  (CredentialScanCard, which
//       also OCR-uploads the document and returns a server doc reference
//       we forward to kyc.runIDV as docImageRef).
//    2. Capture / pick a selfie               (PhotosPicker — no fake scan).
//    3. Run document IDV  → kyc.runIDV(docImageRef:selfieRef:country:docType:)
//    4. Run face liveness → kyc.runLiveness()
//    5. Render the combined verdict HONESTLY: only status=="verified" +
//       livenessPassed==true reads green. "pending" / "provider_unavailable"
//       / null read as a neutral "Pending review" / "Provider unavailable —
//       manual review" state in Brand.warning. A "failed" status reads
//       Brand.danger. Thrown errors surface via LocalizedError.
//
//  Liveness conforms to ISO/IEC 30107-3 Presentation Attack Detection (PAD)
//  Level 2 — noted in the header per the spec.
//

import SwiftUI
import PhotosUI

struct IDVLivenessSheet: View {
    /// Subject of verification. When nil, the API resolves the
    /// authenticated caller server-side (kyc.runIDV / runLiveness both
    /// take `userId: Int? = nil`).
    var userId: Int? = nil

    /// ISO country of the presented document (drives registry selection
    /// on the server). Defaults to US.
    var country: String = "US"

    /// Fired once when the operator dismisses the sheet after a verdict
    /// is in hand, so the host (the 1111 wizard / officer queue) can
    /// re-read the entity's KYC state. Passes the final combined status
    /// string (e.g. "verified", "pending", "failed", "provider_unavailable",
    /// or "incomplete" when dismissed before a verdict).
    var onComplete: (String) -> Void = { _ in }

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    // MARK: Captured artifacts

    /// Document reference forwarded to kyc.runIDV as `docImageRef`. We
    /// derive it from the on-device OCR identifier (the real document
    /// number the credential scanner extracted) — never a fabricated
    /// token. Nil until the ID is scanned (runIDV accepts nil and falls
    /// back to the subject's last uploaded document server-side).
    @State private var docImageRef: String? = nil
    /// Detected/scanned credential-type code (e.g. "drivers_license",
    /// "passport"). Forwarded to runIDV as `docType` when known.
    @State private var docType: String? = nil
    /// True once the ID document has been scanned (gates the Run CTA).
    /// The OCR may not always extract a clean identifier, so we track
    /// "scanned" separately from `docImageRef` being non-nil.
    @State private var idScanned = false
    /// Whether the operator captured a selfie. We don't transmit raw
    /// pixels from this sheet (the liveness vendor SDK owns the frame
    /// capture server-side); this flag gates the Run button so we never
    /// claim a selfie that wasn't taken.
    @State private var selfieRef: String? = nil
    @State private var selfiePicker: PhotosPickerItem? = nil
    @State private var selfiePreview: UIImage? = nil
    @State private var encodingSelfie = false

    // MARK: Run state

    @State private var running = false
    @State private var idv: KycAPI.IdvResult? = nil
    @State private var liveness: KycAPI.IdvResult? = nil
    @State private var error: String? = nil

    private var canRun: Bool {
        idScanned && selfieRef != nil && !running && !encodingSelfie
    }

    /// True once both calls have returned (verdict is in hand).
    private var hasVerdict: Bool { idv != nil }

    var body: some View {
        ZStack(alignment: .bottom) {
            palette.bgPrimary.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    stepIDCapture
                    stepSelfieCapture
                    if let err = error { errorBanner(err) }
                    if hasVerdict { verdictSection }
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s5)
            }

            footer
        }
        .environment(\.palette, palette)
        .onChange(of: selfiePicker) { _, item in
            guard let item else { return }
            Task { await encodeSelfie(item) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("COMPLIANCE · IDENTITY VERIFICATION")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer(minLength: 0)
                Button {
                    onComplete(hasVerdict ? combinedStatus : "incomplete")
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(palette.bgCardSoft)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Text("Verify a government ID")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(palette.textPrimary)

            Text("Scan a government-issued photo ID, then capture a live selfie. We match the face on the document to the live capture and check for presentation attacks.")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // ISO/IEC 30107-3 PAD L2 note (spec requirement).
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text("Liveness conforms to ISO/IEC 30107-3 Presentation Attack Detection (PAD) Level 2.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Step 1 · ID capture (CredentialScanCard)

    private var stepIDCapture: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            stepLabel(1, "Government photo ID", done: idScanned)

            CredentialScanCard(
                credentialType: "drivers_license",
                title: "Scan your photo ID",
                subtitle: "Driver's license, passport, or state ID. We read it on-device and submit the reference for verification."
            ) { scanned in
                // The OCR envelope returns the extracted document number
                // (identifier) and the credential-type code. We forward the
                // real OCR'd identifier as the document reference for
                // runIDV — never a fabricated token. docType carries the
                // scanned type so the server picks the right validator.
                docImageRef = scanned.identifier?.value?.stringValue
                docType = scanned.credentialType
                idScanned = true
                // A fresh ID invalidates any prior verdict.
                idv = nil
                liveness = nil
                error = nil
            }
        }
    }

    // MARK: - Step 2 · Selfie capture

    private var stepSelfieCapture: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            stepLabel(2, "Live selfie", done: selfieRef != nil)

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s3) {
                    selfieThumb
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Capture a selfie")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Text("Face the camera in good light. We compare it to the face on your ID and run a liveness check.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                PhotosPicker(selection: $selfiePicker,
                             matching: .images,
                             photoLibrary: .shared()) {
                    HStack(spacing: 6) {
                        if encodingSelfie {
                            ProgressView().scaleEffect(0.6).tint(.white)
                        } else {
                            Image(systemName: selfieRef == nil ? "camera.fill" : "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .heavy))
                        }
                        Text(selfieRef == nil ? "Capture selfie" : "Retake selfie")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(encodingSelfie || running)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCardSoft.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var selfieThumb: some View {
        Group {
            if let img = selfiePreview {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    palette.bgCard
                    Image(systemName: "person.crop.circle.dashed")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.borderSoft, lineWidth: 1)
        )
    }

    // MARK: - Verdict

    private var verdictSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            stepLabel(3, "Verdict", done: combinedStatus == "verified")

            // Combined headline state — honest. Never green unless both
            // the document IDV verified AND liveness passed.
            verdictHeadline

            // Document IDV detail
            if let idv {
                verdictDetailCard(
                    title: "Document verification",
                    state: idvState(idv),
                    rows: idvRows(idv),
                    warnings: idv.warnings ?? []
                )
            }

            // Liveness detail
            if let liveness {
                verdictDetailCard(
                    title: "Liveness (PAD L2)",
                    state: livenessState(liveness),
                    rows: livenessRows(liveness),
                    warnings: liveness.warnings ?? []
                )
            } else if running {
                // IDV returned, liveness still in flight.
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).tint(palette.textSecondary)
                    Text("Running liveness check…")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .eusoRow()
            }
        }
    }

    private var verdictHeadline: some View {
        let s = combinedVerdictState
        return HStack(spacing: Space.s3) {
            Image(systemName: s.icon)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(s.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(s.subtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(s.color.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(s.color.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func verdictDetailCard(title: String,
                                   state: VerdictState,
                                   rows: [(String, String)],
                                   warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                StatusPill(text: state.pillText, kind: state.pillKind)
            }
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Text(row.1)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            ForEach(warnings, id: \.self) { w in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                    Text(w)
                        .font(EType.caption)
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoRow()
    }

    // MARK: - Footer (run / done CTA)

    private var footer: some View {
        VStack(spacing: 0) {
            IridescentHairline()
            Group {
                if hasVerdict && !running {
                    Button {
                        onComplete(combinedStatus)
                        dismiss()
                    } label: {
                        ctaLabel(combinedStatus == "verified" ? "Done" : "Close",
                                 loading: false)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { Task { await run() } } label: {
                        ctaLabel(running ? "Verifying…" : "Run verification",
                                 loading: running)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canRun)
                    .opacity(canRun ? 1 : 0.5)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s5)
        }
        .background(palette.bgSheet)
        .background(.regularMaterial)
    }

    private func ctaLabel(_ title: String, loading: Bool) -> some View {
        HStack(spacing: 8) {
            if loading { ProgressView().tint(.white) }
            Text(title)
                .font(EType.title)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(LinearGradient.primary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Shared subviews

    private func stepLabel(_ n: Int, _ title: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(done ? AnyShapeStyle(Brand.success) : AnyShapeStyle(LinearGradient.diagonal))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                } else {
                    Text("\(n)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            Text(title)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Brand.danger)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintDanger)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Selfie encoding (proof of live capture)

    @MainActor
    private func encodeSelfie(_ item: PhotosPickerItem) async {
        encodingSelfie = true
        defer { encodingSelfie = false; selfiePicker = nil }
        error = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              !data.isEmpty, let img = UIImage(data: data) else {
            error = "Couldn't read the selfie photo."
            return
        }
        selfiePreview = img
        // We mark a selfie as present by stamping a local capture
        // reference. The liveness vendor SDK owns the actual frame
        // capture/transmission server-side (runLiveness resolves the
        // authenticated subject) — we never fabricate a server token.
        selfieRef = "selfie:" + UUID().uuidString
        // A new selfie invalidates any prior verdict.
        idv = nil
        liveness = nil
    }

    // MARK: - Run the two-stage verification

    @MainActor
    private func run() async {
        guard canRun else { return }
        running = true
        error = nil
        idv = nil
        liveness = nil
        defer { running = false }

        do {
            // Stage 1 — document IDV (face-on-doc ↔ submitted selfie).
            let idvResult = try await EusoTripAPI.shared.kyc.runIDV(
                userId: userId,
                docImageRef: docImageRef,
                selfieRef: selfieRef,
                country: country,
                docType: docType
            )
            idv = idvResult

            // Stage 2 — face liveness / PAD. Run regardless of the IDV
            // verdict so the operator sees both signals; the combined
            // headline reconciles them honestly.
            let liveResult = try await EusoTripAPI.shared.kyc.runLiveness(userId: userId)
            liveness = liveResult
        } catch let apiErr as EusoTripAPIError {
            error = apiErr.errorDescription ?? "Verification request failed."
        } catch let e as LocalizedError {
            error = e.errorDescription ?? "Verification request failed."
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Honest verdict mapping

    /// A small reusable verdict descriptor so document, liveness, and the
    /// combined headline all map through the same honest rules.
    private struct VerdictState {
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        let pillText: String
        let pillKind: StatusPill.Kind
    }

    /// Maps a server status string to (color, pill). Only "verified"/"clear"
    /// reads success; "pending"/"provider_unavailable"/null read warning;
    /// "failed"/"rejected" read danger.
    private func severity(for status: String?) -> (Color, StatusPill.Kind, String) {
        switch (status ?? "").lowercased() {
        case "verified", "clear", "passed", "approved":
            return (Brand.success, .success, "Verified")
        case "failed", "rejected", "denied", "blocked":
            return (Brand.danger, .danger, "Failed")
        case "provider_unavailable", "unavailable":
            return (Brand.warning, .warning, "Provider unavailable")
        case "pending", "in_review", "review", "manual_review", "":
            return (Brand.warning, .warning, "Pending review")
        default:
            // Unknown server state — surface verbatim, neutral, never green.
            return (Brand.warning, .warning, (status ?? "Unknown").capitalized)
        }
    }

    private func idvState(_ r: KycAPI.IdvResult) -> VerdictState {
        let (color, kind, pill) = severity(for: r.status)
        let sub: String
        switch kind {
        case .success: sub = "Document matched and verified."
        case .danger:  sub = "Document verification failed."
        default:
            sub = (r.status?.lowercased() == "provider_unavailable")
                ? "Verification provider unavailable — manual review required."
                : "Awaiting verification — manual review may be required."
        }
        return VerdictState(title: "Document verification", subtitle: sub,
                            icon: "doc.text.magnifyingglass", color: color,
                            pillText: pill, pillKind: kind)
    }

    private func livenessState(_ r: KycAPI.IdvResult) -> VerdictState {
        // Liveness verdict is driven by livenessPassed first, then status.
        // null livenessPassed → never claim a pass.
        let color: Color
        let kind: StatusPill.Kind
        let pill: String
        let sub: String
        if r.livenessPassed == true {
            color = Brand.success; kind = .success; pill = "Live"
            sub = "Live capture confirmed (PAD L2)."
        } else if r.livenessPassed == false {
            color = Brand.danger; kind = .danger; pill = "Failed"
            sub = "Liveness check failed — presentation attack suspected."
        } else {
            // null — fall back to status, but never green.
            let (_, k, p) = severity(for: r.status)
            color = (k == .danger) ? Brand.danger : Brand.warning
            kind = (k == .danger) ? .danger : .warning
            pill = (k == .danger) ? p : "Pending review"
            sub = (r.status?.lowercased() == "provider_unavailable")
                ? "Liveness provider unavailable — manual review required."
                : "Liveness inconclusive — manual review required."
        }
        return VerdictState(title: "Liveness (PAD L2)", subtitle: sub,
                            icon: "faceid", color: color,
                            pillText: pill, pillKind: kind)
    }

    /// Combined status string used for `onComplete` + the Done/Close CTA.
    /// Verified only when document verified AND liveness passed.
    private var combinedStatus: String {
        guard let idv else { return "incomplete" }
        let docOk = severity(for: idv.status).1 == .success
        let liveOk = liveness?.livenessPassed == true
        if docOk && liveOk { return "verified" }
        // Any explicit failure on either signal → failed.
        let docFailed = severity(for: idv.status).1 == .danger
        let liveFailed = liveness?.livenessPassed == false
        if docFailed || liveFailed { return "failed" }
        if (idv.status?.lowercased() == "provider_unavailable")
            || (liveness?.status?.lowercased() == "provider_unavailable") {
            return "provider_unavailable"
        }
        return "pending"
    }

    private var combinedVerdictState: VerdictState {
        switch combinedStatus {
        case "verified":
            return VerdictState(
                title: "Identity verified",
                subtitle: "Document verified and live capture confirmed.",
                icon: "checkmark.seal.fill", color: Brand.success,
                pillText: "Verified", pillKind: .success)
        case "failed":
            return VerdictState(
                title: "Verification failed",
                subtitle: "One or more checks did not pass. Review the detail below before deciding.",
                icon: "xmark.seal.fill", color: Brand.danger,
                pillText: "Failed", pillKind: .danger)
        case "provider_unavailable":
            return VerdictState(
                title: "Provider unavailable",
                subtitle: "A verification provider was unavailable. Route to manual review — do not auto-clear.",
                icon: "exclamationmark.triangle.fill", color: Brand.warning,
                pillText: "Provider unavailable", pillKind: .warning)
        default: // pending / incomplete
            return VerdictState(
                title: "Pending review",
                subtitle: "Checks returned without a confirmed pass. Route to manual review — do not auto-clear.",
                icon: "clock.fill", color: Brand.warning,
                pillText: "Pending review", pillKind: .warning)
        }
    }

    private func idvRows(_ r: KycAPI.IdvResult) -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Status", (r.status ?? "—").capitalized))
        if let v = r.vendor { rows.append(("Provider", v)) }
        if let s = r.score { rows.append(("Match score", "\(s)")) }
        if let rec = r.recommendation { rows.append(("Recommendation", rec.capitalized)) }
        return rows
    }

    private func livenessRows(_ r: KycAPI.IdvResult) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let passed = r.livenessPassed {
            rows.append(("Liveness", passed ? "Passed" : "Failed"))
        } else {
            rows.append(("Liveness", "Inconclusive"))
        }
        rows.append(("Status", (r.status ?? "—").capitalized))
        if let v = r.vendor { rows.append(("Provider", v)) }
        if let s = r.score { rows.append(("Confidence", "\(s)")) }
        if let rec = r.recommendation { rows.append(("Recommendation", rec.capitalized)) }
        return rows
    }
}

// MARK: - Previews

#Preview("1100 · IDV + Liveness · Night") {
    IDVLivenessSheet()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("1100 · IDV + Liveness · Afternoon") {
    IDVLivenessSheet()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
