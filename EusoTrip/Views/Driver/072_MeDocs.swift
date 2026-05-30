//
//  072_MeDocs.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · documents vault)
//
//  Screen 072 · Me · Docs — the driver's personal document vault.
//  Four canonical buckets — CDL, Medical, TWIC, Hazmat — plus an
//  "Other" bucket for registrations, insurance, permits, and anything
//  the server returns that doesn't match one of the four. Every row
//  renders an expiration chip derived from server-computed urgency
//  (critical / high / medium / low) rather than a local date-math pass,
//  so the banner and the per-row chips agree by construction.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Document rows come from `documentManagement.getDocuments` —
//      MCP-verified at `frontend/server/routers/documentManagement.ts:386`.
//      The server scopes the query to `ctx.user.id`, so a newly signed-
//      in driver sees only their own vault. Uploaded-at sort is
//      enforced server-side (`sortBy: uploadedAt, sortOrder: desc`).
//
//    • The top banner reads from `documentManagement.getExpiringDocuments`
//      (same router, line 1520). `daysAhead` is pinned to 90 so the
//      driver sees a full quarter of upcoming renewals — TSA's TWIC
//      processing window is long, and CDL / Medical renewals benefit
//      from early warning too. Urgency labels ("critical" / "high" /
//      "medium" / "low") come straight from the server — no client
//      recomputation.
//
//    • Download buttons resolve the server-returned `url` against
//      `EusoTripAPI.baseURL` when the URL is relative (the backend
//      hands back `/api/documents/:id/download` paths for in-app
//      resolution). Absolute blob URLs pass through untouched.
//
//    • Upload IS wired on this screen. The driver picks which
//      credential they're scanning (CDL / Medical / TWIC / Hazmat),
//      captures it with the in-house VisionKit document camera (the
//      same auto-crop / perspective-correct capture surface the
//      registration `CredentialScanCard` uses) or pulls it from the
//      photo library, and the bytes go straight to the document-
//      intelligence spine — `documentRouter.classifyAndRoute`
//      (EusoTripAPI.swift:19004, Gemini + NVIDIA). The classifier
//      auto-detects the credential type and extracts the expiry +
//      identifier; we map the classified type onto the server's
//      document-bucket vocabulary and hand the bytes + classified
//      type + extracted expiry to the real
//      `documentManagement.uploadDocument` round-trip. The driver's
//      picked bucket rides along as the classifier `callerContext`
//      hint so an ambiguous scan still files correctly. No stub
//      buttons, no "go to desktop" deferral.
//
//    • Empty state is server-confirmed. A driver with zero documents
//      on file sees an `EusoEmptyState` hero rather than a placeholder
//      list, with the in-app scan affordance one tap below it.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on header numerals, section titles,
//         and the download capsule. Urgency chips use palette tokens +
//         Brand.warning for "critical" / expired states.
//    §4   Tokenized spacing (Space.sN), radii (Radius.sm/md/lg),
//         type (EType.*). No magic numbers.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle expressions wrapped in `AnyShapeStyle`.
//    §10  Previews compile in isolation — stores land in `.error` via
//         `notConfigured` under the preview's no-baseURL runtime. No
//         fixtures.
//

import SwiftUI
import PhotosUI
import VisionKit

// MARK: - Document category buckets
//
// The backend's `documentTypeSchema` enum does not include standalone
// values for "CDL" or "TWIC" — CDLs typically land under `other` or
// `operating_authority`, TWIC under `permit` or `other`. This local
// classifier maps both the canonical enum value and a lowercased-name
// keyword scan into one of five buckets, so the driver sees their
// licence, medical card, TWIC, and hazmat endorsement in distinct
// sections regardless of how they were tagged at upload.

private enum DocCategory: String, CaseIterable, Identifiable {
    case cdl
    case medical
    case twic
    case hazmat
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cdl:     return "CDL"
        case .medical: return "Medical Card"
        case .twic:    return "TWIC"
        case .hazmat:  return "Hazmat Endorsement"
        case .other:   return "Other Documents"
        }
    }

    var icon: String {
        switch self {
        case .cdl:     return "creditcard"
        case .medical: return "cross.case"
        case .twic:    return "person.badge.shield.checkmark"
        case .hazmat:  return "exclamationmark.triangle"
        case .other:   return "folder"
        }
    }

    var emptyCopy: String {
        switch self {
        case .cdl:     return "No CDL on file. Tap Scan a credential below to add yours."
        case .medical: return "No medical card on file. DOT medical certificates expire every 24 months."
        case .twic:    return "No TWIC on file. Port / terminal access requires an active TWIC card."
        case .hazmat:  return "No hazmat endorsement on file. Required for placarded loads."
        case .other:   return "Registrations, insurance, permits, and miscellaneous documents land here."
        }
    }

    /// Classify a document into one of the five buckets. Checks the
    /// canonical type first, then falls back to lowercased-name keyword
    /// scan so docs uploaded under `other` still find their bucket.
    static func from(document d: DocumentManagementAPI.Document) -> DocCategory {
        let name = d.name.lowercased()
        let type = d.type.lowercased()
        if type == "medical_card" || name.contains("medical") || name.contains("dot card") {
            return .medical
        }
        if type == "hazmat_placard" || name.contains("hazmat") {
            return .hazmat
        }
        if name.contains("twic") {
            return .twic
        }
        if name.contains("cdl") || name.contains("commercial driver") || name.contains("driver's license") || name.contains("drivers license") {
            return .cdl
        }
        return .other
    }
}

// MARK: - Screen root

struct MeDocs: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var docs = DriverDocumentsStore()
    @StateObject private var expiring = ExpiringDocumentsStore()
    /// Credential-scan upload sheet. The driver picks which credential
    /// they're scanning (CDL / Medical / TWIC / Hazmat), captures it on
    /// the in-house VisionKit document camera (the registration
    /// `CredentialScanCard` capture surface), and the bytes route
    /// through the document-intelligence spine
    /// (`documentRouter.classifyAndRoute`, Gemini + NVIDIA) before the
    /// real `documentManagement.uploadDocument`. The picked bucket
    /// rides along as the classifier hint so the user never has to
    /// pick a doc type from a 60-option dropdown.
    @State private var showCredentialSheet: Bool = false
    @State private var uploadInflight: Bool = false
    @State private var uploadAck: String? = nil
    @State private var uploadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                expirationBanner
                if let ack = uploadAck {
                    ackBanner(ack, isError: false)
                }
                if let err = uploadError {
                    ackBanner(err, isError: true)
                }
                switch docs.state {
                case .loading:
                    loadingSkeleton
                case .empty:
                    emptyHero
                case .error(let e):
                    errorBanner(e)
                case .loaded(let all):
                    ForEach(DocCategory.allCases) { bucket in
                        section(bucket: bucket, rows: all.filter { DocCategory.from(document: $0) == bucket })
                    }
                }
                uploadCTA
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showCredentialSheet) {
            DriverCredentialScanSheet(
                onClassified: { doc in
                    showCredentialSheet = false
                    Task { await uploadClassified(doc) }
                }
            )
        }
    }

    private func ackBanner(_ msg: String, isError: Bool) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(isError ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(LinearGradient.diagonal))
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                if isError { uploadError = nil } else { uploadAck = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(
                    isError
                        ? AnyShapeStyle(Brand.danger.opacity(0.45))
                        : AnyShapeStyle(LinearGradient.diagonal.opacity(0.45))
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func reload() async {
        async let a: Void = docs.refresh()
        async let b: Void = expiring.refresh()
        _ = await (a, b)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Documents")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CDL · Medical · TWIC · Hazmat")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(state: (docs.isLoading || expiring.isLoading) ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Expiration banner

    @ViewBuilder
    private var expirationBanner: some View {
        if let resp = expiring.state.value {
            let totalExpiring = resp.totalExpiring
            let totalExpired = resp.totalExpired
            if totalExpiring > 0 || totalExpired > 0 {
                HStack(spacing: Space.s3) {
                    Image(systemName: totalExpired > 0 ? "exclamationmark.octagon.fill" : "clock.badge.exclamationmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(totalExpired > 0 ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(LinearGradient.diagonal))
                    VStack(alignment: .leading, spacing: 2) {
                        if totalExpired > 0 {
                            Text("\(totalExpired) expired · \(totalExpiring) expiring soon")
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                        } else {
                            Text("\(totalExpiring) expiring within 90 days")
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                        }
                        Text("Renew before the next dispatch to avoid holds.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                }
                .padding(Space.s3)
                .eusoCard(radius: Radius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(
                            totalExpired > 0 ? Brand.warning.opacity(0.6) : palette.borderFaint,
                            lineWidth: 1
                        )
                )
            }
        }
    }

    // MARK: States

    private var loadingSkeleton: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.35))
                    .frame(height: 88)
            }
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "folder",
            title: "No documents on file",
            subtitle: "Scan your CDL, medical card, TWIC, or hazmat endorsement below — ESANG reads the type and expiry and files it in the right bucket."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load documents")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await reload() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Category sections

    @ViewBuilder
    private func section(bucket: DocCategory, rows: [DocumentManagementAPI.Document]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: bucket.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(bucket.title.uppercased())
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if !rows.isEmpty {
                    Text("\(rows.count)")
                        .font(EType.micro)
                        .tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            if rows.isEmpty {
                notOnFileRow(bucket: bucket)
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(rows) { doc in
                        docRow(doc)
                    }
                }
            }
        }
    }

    private func notOnFileRow(bucket: DocCategory) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: bucket.icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text(bucket.emptyCopy)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            Spacer()
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    private func docRow(_ d: DocumentManagementAPI.Document) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if let uploaded = shortDate(d.uploadedAt) {
                    Text("Uploaded \(uploaded)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                expirationChip(for: d)
            }
            Spacer(minLength: Space.s2)
            downloadButton(for: d)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    // MARK: Expiration chip (server-urgency aware)

    @ViewBuilder
    private func expirationChip(for d: DocumentManagementAPI.Document) -> some View {
        if let (label, urgency) = expirationLabel(for: d) {
            let capsuleStyle = urgencyStyle(urgency)
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(capsuleStyle.foreground)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .strokeBorder(capsuleStyle.border, lineWidth: 1)
                        .background(Capsule().fill(capsuleStyle.fill))
                )
        }
    }

    private struct ChipStyle {
        let foreground: AnyShapeStyle
        let border: Color
        let fill: AnyShapeStyle
    }

    private func urgencyStyle(_ urgency: String) -> ChipStyle {
        switch urgency.lowercased() {
        case "expired":
            return ChipStyle(
                foreground: AnyShapeStyle(.white),
                border: Brand.warning,
                fill: AnyShapeStyle(Brand.warning)
            )
        case "critical", "high":
            return ChipStyle(
                foreground: AnyShapeStyle(Brand.warning),
                border: Brand.warning.opacity(0.6),
                fill: AnyShapeStyle(Color.clear)
            )
        case "medium":
            return ChipStyle(
                foreground: AnyShapeStyle(palette.textSecondary),
                border: palette.borderFaint,
                fill: AnyShapeStyle(Color.clear)
            )
        default:
            // "low" or anything else: subtle neutral
            return ChipStyle(
                foreground: AnyShapeStyle(palette.textTertiary),
                border: palette.borderFaint.opacity(0.6),
                fill: AnyShapeStyle(Color.clear)
            )
        }
    }

    /// Build the chip label + urgency string for a document by
    /// cross-referencing it against `ExpiringDocumentsStore`. The server
    /// is authoritative on urgency — we only fall back to "Expires DATE"
    /// when the doc isn't in either the expiring or expired list (e.g.
    /// expires > 90 days out).
    private func expirationLabel(for d: DocumentManagementAPI.Document) -> (String, String)? {
        guard let resp = expiring.state.value else {
            // Pre-load — fall back to local date math off expiresAt so
            // the chip isn't blank while the expirations call is in
            // flight. Server urgency lands on the next tick.
            return localExpirationFallback(for: d)
        }
        if let hit = resp.expired.first(where: { $0.id == d.id }) {
            return ("EXPIRED \(hit.daysExpired)d", "expired")
        }
        if let hit = resp.expiring.first(where: { $0.id == d.id }) {
            let label = hit.daysUntilExpiry <= 0 ? "EXPIRES TODAY" : "EXPIRES IN \(hit.daysUntilExpiry)d"
            return (label, hit.urgency)
        }
        return localExpirationFallback(for: d)
    }

    private func localExpirationFallback(for d: DocumentManagementAPI.Document) -> (String, String)? {
        guard let exp = d.expiresAt, !exp.isEmpty,
              let date = parseIso(exp)
        else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM yyyy"
        return ("EXPIRES \(out.string(from: date).uppercased())", "low")
    }

    // MARK: Download button

    @ViewBuilder
    private func downloadButton(for d: DocumentManagementAPI.Document) -> some View {
        if let url = resolveDownloadURL(d.url) {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("OPEN")
                        .font(EType.micro)
                        .tracking(1.2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 8)
                .background(Capsule().fill(LinearGradient.diagonal))
            }
        } else {
            Text("NO FILE")
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 8)
                .background(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    // MARK: Upload CTA
    //
    // Replaces the prior "uploads live on the desktop dashboard"
    // disclosure with a real in-app credential-scan affordance. The
    // driver picks the credential (CDL / Medical / TWIC / Hazmat),
    // captures it on the VisionKit document camera, and the bytes
    // route through `documentRouter.classifyAndRoute` (Gemini + NVIDIA)
    // — which auto-detects the type + extracts expiry / identifier —
    // before the real `documentManagement.uploadDocument`.

    private var uploadCTA: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Scan with ESANG AI")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                if uploadInflight {
                    ProgressView().scaleEffect(0.75).tint(palette.textPrimary)
                }
            }
            Text("Snap your CDL, medical card, TWIC, or hazmat endorsement — ESANG reads the credential type and expiry and files it in the right bucket. No 60-option dropdown.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                uploadError = nil
                showCredentialSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.viewfinder.fill")
                        .font(.system(size: 12, weight: .heavy))
                    Text("Scan a credential")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s4).padding(.vertical, 10)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(uploadInflight)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: Upload pipeline
    //
    // The classifier hands back the bytes + classified type +
    // extracted fields. We map the classified type onto the server's
    // document-bucket vocabulary, then call
    // `documentManagement.uploadDocument` with the binary so the
    // server-side vault row + file land in one round-trip. The
    // expiration date (when Gemini extracted one) gets stamped onto
    // the row so the expiration banner immediately picks it up.

    @MainActor
    private func uploadClassified(_ doc: ClassifiedDocument) async {
        guard !uploadInflight else { return }
        guard let userId = session.user?.id else {
            uploadError = "Sign in before uploading documents."
            return
        }
        uploadInflight = true
        uploadError = nil
        defer { uploadInflight = false }

        // Map the documentRouter type onto the server's
        // documentManagement bucket vocabulary so the vault rows
        // file under the right tab.
        let bucket = bucketForClassifiedType(doc.classifiedType)
        let humanName = humanNameForClassifiedType(doc.classifiedType)
        // Decode base64 → byte count so the server-side size check
        // doesn't reject the row. (uploadDocument expects the raw
        // base64 string in fileData + a byte-count Int.)
        let bytesEstimate = Int(Double(doc.documentBase64.count) * 0.75)

        // Expiration date — only pass through if Gemini extracted
        // a parseable ISO date string.
        let expiresAt: String? = doc.fields["expirationDate"]
            ?? doc.fields["expirationDateIso"]
            ?? doc.fields["expiration"]

        do {
            _ = try await EusoTripAPI.shared.documentManagement.uploadDocument(
                name: humanName,
                type: bucket,
                mimeType: doc.mimeType,
                size: bytesEstimate,
                fileData: doc.documentBase64,
                entityType: "driver",
                entityId: String(userId),
                tags: [doc.classifiedType],
                expiresAt: expiresAt
            )
            uploadAck = "Uploaded · \(humanName)"
            await reload()
        } catch let apiErr as EusoTripAPIError {
            uploadError = apiErr.errorDescription ?? "Upload failed"
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func bucketForClassifiedType(_ raw: String) -> String {
        switch raw {
        case "us_cdl", "ca_cdl", "mx_cdl": return "cdl"
        case "us_medical_card", "ca_medical_card", "mx_medical_card": return "medical_card"
        case "us_twic": return "twic"
        case "us_hazmat_endorsement", "us_hazmat_certificate", "us_tanker_endorsement": return "hazmat"
        case "us_coi", "ca_coi": return "insurance"
        case "us_dot_authority", "us_mc_authority": return "fmcsa_authority"
        case "w9": return "tax"
        case "form_1099": return "tax"
        case "us_ein_letter": return "tax"
        default: return "other"
        }
    }

    private func humanNameForClassifiedType(_ raw: String) -> String {
        switch raw {
        case "us_cdl": return "CDL"
        case "us_medical_card": return "Medical Card"
        case "us_twic": return "TWIC"
        case "us_hazmat_endorsement": return "Hazmat Endorsement"
        case "us_hazmat_certificate": return "Hazmat Certificate"
        case "us_tanker_endorsement": return "Tanker Endorsement"
        case "us_coi": return "Certificate of Insurance"
        case "ca_coi": return "CA Certificate of Insurance"
        case "us_dot_authority": return "DOT Authority"
        case "us_mc_authority": return "MC Authority"
        case "w9": return "W-9"
        case "form_1099": return "1099-NEC"
        case "us_ein_letter": return "EIN Letter"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: Helpers

    private func parseIso(_ iso: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    private func shortDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty, let d = parseIso(iso) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM d, yyyy"
        return out.string(from: d)
    }

    /// Resolve a server `url` field against `EusoTripAPI.baseURL` when
    /// relative; pass absolute blob URLs through. Returns nil when the
    /// server handed back an empty string or the base URL isn't set
    /// (preview runtime).
    private func resolveDownloadURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        guard let base = EusoTripAPI.shared.baseURL else { return nil }
        return URL(string: raw, relativeTo: base)?.absoluteURL
    }
}

// MARK: - Screen wrapper

struct MeDocsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeDocs()
        } nav: {
            BottomNav(
                leading: driverNavLeading_072(),
                trailing: driverNavTrailing_072(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_072() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_072() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Driver credential-scan sheet
//
// Bespoke to the driver document vault: the driver first tells us
// which of the four credentials they're scanning (CDL / Medical /
// TWIC / Hazmat), then captures it. We feed that picked credential as
// the classifier hint so an ambiguous scan still files correctly, but
// the document-intelligence spine (`documentRouter.classifyAndRoute`)
// is authoritative on the final classified type + extracted fields.
//
// Capture mirrors the registration `CredentialScanCard`: VisionKit's
// document camera (auto-crop, perspective-correct) for the primary
// path, PhotosPicker for the library fallback. The camera UI itself is
// untouched — we only own the post-capture handling: compress →
// base64 → classifyAndRoute → ClassifiedDocument → host upload.

/// The four canonical driver credentials, each carrying the
/// `documentRouter` type code used as the classifier hint.
private enum CredentialHint: String, CaseIterable, Identifiable {
    case cdl
    case medical
    case twic
    case hazmat

    var id: String { rawValue }

    /// Human label for the picker chip.
    var label: String {
        switch self {
        case .cdl:     return "CDL"
        case .medical: return "Medical Card"
        case .twic:    return "TWIC"
        case .hazmat:  return "Hazmat"
        }
    }

    var icon: String {
        switch self {
        case .cdl:     return "creditcard"
        case .medical: return "cross.case"
        case .twic:    return "person.badge.shield.checkmark"
        case .hazmat:  return "exclamationmark.triangle"
        }
    }

    /// Caller-context hint handed to `classifyAndRoute` so Gemini can
    /// disambiguate overlapping credential shapes. The spine stays
    /// authoritative — this only nudges it.
    var callerContext: String {
        switch self {
        case .cdl:     return "driver Me·Docs credential scan — commercial driver's license (CDL)"
        case .medical: return "driver Me·Docs credential scan — DOT medical examiner's certificate"
        case .twic:    return "driver Me·Docs credential scan — TWIC transportation worker identification credential"
        case .hazmat:  return "driver Me·Docs credential scan — hazmat endorsement / certificate"
        }
    }
}

private struct DriverCredentialScanSheet: View {
    /// Fired with the classifier envelope (carrying the captured
    /// base64) so the host runs its real `uploadDocument`.
    let onClassified: (ClassifiedDocument) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var hint: CredentialHint = .cdl
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var showCamera: Bool = false
    @State private var inflight: Bool = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    hero
                    hintPicker
                    captureRow
                    if let e = error { errorBanner(e) }
                    if inflight { progressBlock }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
            }
            .background(palette.bgPage)
            .navigationTitle("Scan a credential")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await classifyFromLibrary(item) }
            }
            .sheet(isPresented: $showCamera) {
                DriverCredentialCameraSheet { data in
                    showCamera = false
                    guard let data else { return }
                    Task { await classify(data: data, mime: "image/jpeg") }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var hero: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text("ESANG reads it for you")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Pick the credential, snap it, and we'll auto-detect the type and expiry before filing it.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.35), lineWidth: 1)
        )
    }

    private var hintPicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("WHICH CREDENTIAL?")
                .font(EType.micro)
                .tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(CredentialHint.allCases) { c in
                    let selected = c == hint
                    Button {
                        guard !inflight else { return }
                        hint = c
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: c.icon)
                                .font(.system(size: 16, weight: .semibold))
                            Text(c.label)
                                .font(EType.micro)
                                .tracking(0.6)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s2)
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textSecondary))
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(selected ? Color.clear : palette.borderFaint, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(inflight)
                }
            }
        }
    }

    private var captureRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                guard !inflight else { return }
                error = nil
                showCamera = true
            } label: {
                captureLabel(systemImage: "camera.fill", title: "Scan", filled: true)
            }
            .buttonStyle(.plain)
            .disabled(inflight)

            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                captureLabel(systemImage: "photo.on.rectangle", title: "Library", filled: false)
            }
            .buttonStyle(.plain)
            .disabled(inflight)
        }
    }

    private func captureLabel(systemImage: String, title: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .heavy))
            Text(title)
                .font(.system(size: 13, weight: .heavy))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textPrimary))
        .background(filled ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
        .overlay(
            Capsule().strokeBorder(filled ? Color.clear : palette.borderSoft, lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private var progressBlock: some View {
        HStack(spacing: Space.s2) {
            ProgressView().scaleEffect(0.8).tint(palette.textPrimary)
            Text("Reading the credential…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Brand.danger)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Capture → classify pipeline

    @MainActor
    private func classifyFromLibrary(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
            error = "Couldn't read that photo. Try another."
            pickerItem = nil
            return
        }
        pickerItem = nil
        await classify(data: data, mime: "image/jpeg")
    }

    @MainActor
    private func classify(data: Data, mime: String) async {
        guard !inflight else { return }
        inflight = true
        error = nil
        defer { inflight = false }

        // Compress to keep the Gemini payload under ~900KB, mirroring
        // the registration CredentialScanCard's capture handling.
        var jpeg = data
        if mime != "application/pdf", data.count > 900_000, let img = UIImage(data: data) {
            for q in [CGFloat(0.85), 0.75, 0.65, 0.55, 0.45] {
                if let d = img.jpegData(compressionQuality: q), d.count <= 900_000 {
                    jpeg = d
                    break
                }
            }
        }
        let base64 = jpeg.base64EncodedString()
        let mt = DocumentRouterAPI.MimeType(rawValue: mime) ?? .jpeg

        do {
            let resp = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                documentBase64: base64,
                mimeType: mt,
                callerContext: hint.callerContext
            )
            let fields: [String: String] = resp.extractedFields.compactMapValues { $0.asString }
            let doc = ClassifiedDocument(
                id: UUID().uuidString,
                classifiedType: resp.classifiedType,
                confidence: resp.confidence,
                summary: resp.summary,
                dispatchTarget: resp.dispatchTarget,
                warnings: resp.warnings,
                fields: fields,
                mimeType: mt.rawValue,
                documentBase64: base64
            )
            onClassified(doc)
            dismiss()
        } catch let apiErr as EusoTripAPIError {
            error = "Couldn't read the credential: \(apiErr.errorDescription ?? "classification failed")"
        } catch {
            self.error = "Couldn't read the credential: \(error.localizedDescription)"
        }
    }
}

// MARK: - Driver credential document-camera wrapper
//
// SwiftUI wrapper around VisionKit's document camera — the same
// auto-crop / perspective-correct capture the registration
// CredentialScanCard uses. We only need page 0 for a single
// credential, so we return its JPEG-encoded data. The camera UI
// (blue-glow edge detection, realtime sizing) is system-owned and
// untouched.

private struct DriverCredentialCameraSheet: UIViewControllerRepresentable {
    let onResult: (Data?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(onResult: onResult) }

    final class Coord: NSObject, VNDocumentCameraViewControllerDelegate {
        let onResult: (Data?) -> Void
        init(onResult: @escaping (Data?) -> Void) { self.onResult = onResult }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else { onResult(nil); return }
            let image = scan.imageOfPage(at: 0)
            onResult(image.jpegData(compressionQuality: 0.9))
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onResult(nil)
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onResult(nil)
        }
    }
}

// MARK: - Previews
//
// Previews never run `.task` — stores stay in `.loading` so both
// registers render deterministic skeletons without hitting the network.
// No fixtures.

#Preview("072 · Me Docs · Night") {
    MeDocsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("072 · Me Docs · Afternoon") {
    MeDocsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
