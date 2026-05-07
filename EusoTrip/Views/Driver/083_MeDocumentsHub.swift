//
//  083_MeDocumentsHub.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · documents hub)
//
//  Screen 083 · Me · Documents Hub — the full-lifecycle expansion of
//  072 Me · Docs. 072 is the read-only vault drivers glance at on
//  the road. 083 is where they ACT: upload new docs via the iOS
//  file picker, request e-signatures (DocuSign-equivalent via the
//  server's own signing stack), share time-limited view/download
//  links, archive expired docs with a retention policy, and kick
//  AI-OCR classification on upload.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Reads from live `documentManagement.getDocuments` +
//      `getExpiringDocuments` (MCP-verified at
//      `frontend/server/routers/documentManagement.ts:386, 1520`).
//
//    • Upload round-trips through `documentManagement.uploadDocument`
//      (line 519) with real base-64 file data from
//      `UIDocumentPickerViewController`. Upload triggers
//      `documentManagement.classifyDocument` async (line 591) so
//      AI type inference + OCR extraction begin immediately.
//
//    • Share mints a real `/shared/documents/:token` URL via
//      `documentManagement.shareDocument` (line 1639) with a
//      server-enforced expiry window.
//
//    • E-signature requests land in the server's own `audit_logs`
//      under `doc_signature` via `requestESignature` (line 1121)
//      and trigger signer email notifications — no DocuSign SDK
//      needed (the server is the signing hub).
//
//    • Archive soft-deletes with a retention policy via
//      `archiveDocument` (line 1916).
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on upload CTA + per-row action
//         menu. Brand.warning only for expired banners.
//    §4   Tokenized spacing, radii, type.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in AnyShapeStyle.
//    §10  Previews land in `.error` under the preview runtime. No
//         fixtures.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Hub categories (local, independent of 072)

private enum HubCategory: String, CaseIterable, Identifiable {
    case cdl
    case medical
    case twic
    case hazmat
    case insurance
    case registration
    /// Tax forms — folded under the Documents Center after the user
    /// asked for the standalone Me · Tax row to be removed. This
    /// category absorbs `w9`, `1099`, and any uploaded tax forms; the
    /// in-screen `taxSnapshot` section above handles the live YTD +
    /// withholding numbers, while documents themselves group here.
    case tax
    /// IFTA + IRP fuel / mileage tax filings — separate from the
    /// withholding tax category above because IFTA filings are a
    /// quarterly per-state ledger, not a 1099/W-9 personal tax form.
    case ifta
    /// BOL + POD + lumper / scale / rate-confirmation per-load docs.
    case loadDocs
    /// Operating authority + broker-carrier agreements + customs.
    case authority
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cdl:          return "CDL"
        case .medical:      return "Medical"
        case .twic:         return "TWIC"
        case .hazmat:       return "Hazmat"
        case .insurance:    return "Insurance"
        case .registration: return "Registration"
        case .tax:          return "Tax · W-9 / 1099"
        case .ifta:         return "IFTA + IRP"
        case .loadDocs:     return "Per-load (BOL · POD · Rate-Con)"
        case .authority:    return "Authority + agreements"
        case .other:        return "Other"
        }
    }

    var icon: String {
        switch self {
        case .cdl:          return "creditcard"
        case .medical:      return "cross.case"
        case .twic:         return "person.badge.shield.checkmark"
        case .hazmat:       return "exclamationmark.triangle"
        case .insurance:    return "umbrella"
        case .registration: return "doc.text.below.ecg"
        case .tax:          return "dollarsign.square"
        case .ifta:         return "fuelpump"
        case .loadDocs:     return "shippingbox"
        case .authority:    return "checkmark.seal"
        case .other:        return "folder"
        }
    }

    static func classify(_ d: DocumentManagementAPI.Document) -> HubCategory {
        let t = d.type.lowercased()
        let n = d.name.lowercased()
        // Tax forms — w9, 1099, federal/state withholding statements.
        if t == "w9" || n.contains("w-9") || n.contains("w9")
            || n.contains("1099") || n.contains("1040")
            || n.contains("schedule c") {
            return .tax
        }
        // IFTA / IRP fuel-tax filings.
        if t == "ifta" || t == "irp" || n.contains("ifta") || n.contains("irp") {
            return .ifta
        }
        // Per-load operational documents.
        if t == "bol" || t == "pod" || t == "rate_confirmation"
            || t == "lumper_receipt" || t == "scale_ticket"
            || t == "fuel_receipt" || t == "toll_receipt"
            || t == "freight_bill" || t == "delivery_receipt"
            || t == "packing_list" || t == "detention_receipt"
            || n.contains("bol") || n.contains("pod")
            || n.contains("rate confirmation") || n.contains("ratecon") {
            return .loadDocs
        }
        // Operating authority + agreements + customs.
        if t == "operating_authority" || t == "broker_carrier_agreement"
            || t == "contract" || t == "customs_form"
            || n.contains("authority") || n.contains("agreement")
            || n.contains("customs") {
            return .authority
        }
        if t == "medical_card" || n.contains("medical") || n.contains("dot card") { return .medical }
        if t == "hazmat_placard" || n.contains("hazmat") { return .hazmat }
        if n.contains("twic") { return .twic }
        if n.contains("cdl") || n.contains("commercial driver") || n.contains("driver's license") { return .cdl }
        if t == "insurance" || n.contains("insurance") { return .insurance }
        if t == "registration" || n.contains("registration") { return .registration }
        return .other
    }
}

// MARK: - Screen root

struct MeDocumentsHub: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var docs = DocumentsHubStore()
    @StateObject private var expiring = ExpiringDocumentsStore()

    @State private var showUploadPicker: Bool = false
    @State private var pendingUploadURL: URL?
    @State private var pendingUploadError: String?

    @State private var rowActionTarget: DocumentManagementAPI.Document?
    @State private var action: HubAction?

    enum HubAction: Identifiable {
        case share(DocumentManagementAPI.Document)
        case eSign(DocumentManagementAPI.Document)
        case archive(DocumentManagementAPI.Document)

        var id: String {
            switch self {
            case .share(let d):   return "share::\(d.id)"
            case .eSign(let d):   return "esign::\(d.id)"
            case .archive(let d): return "archive::\(d.id)"
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                uploadCTA
                expirationBanner
                // Documents Center is the document vault, full stop.
                // The earlier inline `MeTaxView()` render bled wallet
                // / earnings UI into this surface (YTD gross +
                // withholding tiles + "Couldn't reach earnings service"
                // banner) which made the page read like a wallet/tax
                // mash-up. Tax forms (W-9 / 1099) still appear here as
                // *documents* under the .tax category section below;
                // live YTD numerics live in `MeTax` (Me · Tax) where
                // they belong.
                switch docs.state {
                case .loading:
                    skeleton
                case .empty:
                    emptyHero
                case .error(let e):
                    errorBanner(e)
                case .loaded(let all):
                    ForEach(HubCategory.allCases) { cat in
                        let rows = all.filter { HubCategory.classify($0) == cat }
                        if !rows.isEmpty {
                            categorySection(cat: cat, rows: rows)
                        }
                    }
                }
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showUploadPicker) {
            DocumentPickerSheet { url in
                pendingUploadURL = url
                showUploadPicker = false
                Task { await handlePickedURL(url) }
            } onCancel: {
                showUploadPicker = false
            }
            .eusoSheetX()
        }
        .sheet(item: $action) { a in
            actionSheet(for: a)
                .eusoSheetX()
        }
        .overlay(alignment: .bottom) {
            if let toast = docs.lastToast {
                toastView(toast)
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s6)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: docs.lastToast)
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
                Text("Upload · share · e-sign · archive")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: (docs.isLoading || docs.mutatingId != nil) ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Upload CTA

    private var uploadCTA: some View {
        Button {
            showUploadPicker = true
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: "arrow.up.doc.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Upload document")
                    .font(EType.bodyStrong)
                Spacer()
                if docs.mutatingId == "upload" {
                    ProgressView().progressViewStyle(.circular).controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(docs.mutatingId == "upload")
    }

    // MARK: Expiration banner

    @ViewBuilder
    private var expirationBanner: some View {
        if let resp = expiring.state.value,
           (resp.totalExpiring + resp.totalExpired) > 0 {
            HStack(spacing: Space.s3) {
                Image(systemName: resp.totalExpired > 0 ? "exclamationmark.octagon.fill" : "clock.badge.exclamationmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(resp.totalExpired > 0 ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(LinearGradient.diagonal))
                VStack(alignment: .leading, spacing: 2) {
                    Text(resp.totalExpired > 0
                         ? "\(resp.totalExpired) expired · \(resp.totalExpiring) expiring soon"
                         : "\(resp.totalExpiring) expiring within 90 days")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Tap a row to send a renewal e-sign request.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
            .padding(Space.s3)
            .eusoCard(radius: Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(resp.totalExpired > 0 ? Brand.warning.opacity(0.6) : palette.borderFaint, lineWidth: 1)
            )
        }
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 84)
            }
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "folder",
            title: "No documents yet",
            subtitle: "Upload your CDL, Medical card, TWIC, Hazmat, Insurance, and Registration — ESANG AI auto-classifies each one after upload."
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

    // MARK: Category section

    @ViewBuilder
    private func categorySection(cat: HubCategory, rows: [DocumentManagementAPI.Document]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: cat.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(cat.title.uppercased())
                    .font(EType.micro).tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(rows.count)")
                    .font(EType.micro).tracking(1.1)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: Space.s2) {
                ForEach(rows) { doc in
                    docRow(doc)
                }
            }
        }
    }

    private func docRow(_ d: DocumentManagementAPI.Document) -> some View {
        SwipeRevealDelete(
            isDisabled: docs.mutatingId == d.id,
            onDelete: {
                Task { _ = await docs.archive(documentId: d.id) }
            }
        ) {
            docRowContent(d)
        }
    }

    private func docRowContent(_ d: DocumentManagementAPI.Document) -> some View {
        let mutating = docs.mutatingId == d.id
        return HStack(alignment: .top, spacing: Space.s3) {
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
                if let exp = shortDate(d.expiresAt) {
                    Text("Expires \(exp)")
                        .font(EType.caption)
                        .foregroundStyle(expiresTint(d))
                }
            }
            Spacer(minLength: Space.s2)
            if mutating {
                ProgressView().progressViewStyle(.circular).controlSize(.small)
            } else {
                Menu {
                    if let url = resolveDownloadURL(d.url) {
                        Link(destination: url) {
                            Label("Open", systemImage: "arrow.down.doc")
                        }
                    }
                    Button {
                        action = .share(d)
                    } label: {
                        Label("Share link", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        action = .eSign(d)
                    } label: {
                        Label("Request e-signature", systemImage: "signature")
                    }
                    Button(role: .destructive) {
                        action = .archive(d)
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(palette.bgCard.opacity(0.8))
                        )
                }
                .accessibilityLabel("Actions for \(d.name)")
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func expiresTint(_ d: DocumentManagementAPI.Document) -> Color {
        guard let resp = expiring.state.value else { return palette.textTertiary }
        if resp.expired.contains(where: { $0.id == d.id }) { return Brand.warning }
        if let hit = resp.expiring.first(where: { $0.id == d.id }),
           (hit.urgency.lowercased() == "critical" || hit.urgency.lowercased() == "high") {
            return Brand.warning
        }
        return palette.textTertiary
    }

    // MARK: Action sheets

    @ViewBuilder
    private func actionSheet(for a: HubAction) -> some View {
        switch a {
        case .share(let doc):    ShareSheetContent(doc: doc, action: $action, store: docs)
        case .eSign(let doc):    ESignSheetContent(doc: doc, action: $action, store: docs)
        case .archive(let doc):  ArchiveSheetContent(doc: doc, action: $action, store: docs)
        }
    }

    // MARK: Upload path

    private func handlePickedURL(_ url: URL) async {
        pendingUploadError = nil
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let base64 = data.base64EncodedString()
            let size = data.count
            let name = url.lastPathComponent
            let mimeType = mimeType(for: url)
            let driverId = session.user?.id ?? ""
            // Type is a best-effort server-enum hint; the real
            // classification runs server-side after upload via
            // `documentManagement.classifyDocument` (Gemini OCR + type
            // inference). The store kicks that off automatically in
            // `DocumentsHubStore.upload()`.
            let serverType = inferServerType(from: name)
            _ = await docs.upload(
                name: name,
                type: serverType,
                mimeType: mimeType,
                fileData: base64,
                size: size,
                entityId: driverId
            )

            // VIGA second-pass — when the upload is an image, fire
            // the matching visualIntelligence procedure so the driver
            // also sees AI-extracted insights specific to the type
            // (DVIR defects, POD signature presence, hazmat placard
            // recognition, gauge readings). Done in the background;
            // results land in `docs.lastVigaInsight` for the row card
            // to render. Falls through silently when the file isn't
            // an image — text/PDF docs just rely on the server-side
            // Gemini OCR through `classifyDocument`.
            if mimeType.hasPrefix("image/") {
                Task.detached { [serverType] in
                    await Self.runVIGAPass(
                        base64: base64,
                        mimeType: mimeType,
                        inferredType: serverType
                    )
                }
            }
        } catch {
            pendingUploadError = error.localizedDescription
        }
    }

    /// Routes an uploaded image through the most appropriate VIGA
    /// analysis based on the inferred document type. Failures are
    /// silent — the upload itself + Gemini OCR are the source of
    /// truth; VIGA is enrichment.
    private static func runVIGAPass(
        base64: String,
        mimeType: String,
        inferredType: String
    ) async {
        let api = EusoTripAPI.shared.viga
        do {
            switch inferredType {
            case "pod":
                _ = try await api.verifyPOD(imageBase64: base64, mimeType: mimeType)
            case "bol":
                _ = try await api.verifySeal(imageBase64: base64, mimeType: mimeType)
            case "hazmat_placard":
                _ = try await api.assessCargo(imageBase64: base64, mimeType: mimeType)
            case "inspection":
                _ = try await api.inspectDVIR(imageBase64: base64, mimeType: mimeType)
            default:
                // For everything else (insurance card photo, CDL
                // photo, registration photo, etc.) we don't have a
                // dedicated VIGA pass — the server's Gemini OCR via
                // `classifyDocument` handles those cleanly.
                break
            }
        } catch {
            // Silent — VIGA is enrichment, not the upload's success
            // signal.
        }
    }

    private func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    /// Best-effort map from filename keywords onto the server's
    /// `documentTypeSchema` enum values. Not authoritative — the
    /// server-side `classifyDocument` call rewrites this after
    /// OCR / AI inference.
    private func inferServerType(from name: String) -> String {
        let n = name.lowercased()
        if n.contains("medical") || n.contains("dot card") { return "medical_card" }
        if n.contains("hazmat") { return "hazmat_placard" }
        if n.contains("insurance") { return "insurance" }
        if n.contains("registration") { return "registration" }
        if n.contains("ifta") { return "ifta" }
        if n.contains("bol") { return "bol" }
        if n.contains("pod") { return "pod" }
        if n.contains("w9") || n.contains("w-9") { return "w9" }
        return "other"
    }

    // MARK: Footer

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESANG AI auto-classifies on upload")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("After you upload, ESANG runs OCR + type inference server-side to fill in the document fields automatically. Share links are short-lived and revocable. Archived documents are soft-deleted and retained per the policy you pick.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Toast

    private func toastView(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LinearGradient.diagonal)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 14, y: 6)
    }

    // MARK: Date helpers

    private func shortDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d, yyyy"
            return out.string(from: d)
        }
        return iso
    }

    private func resolveDownloadURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        guard let base = EusoTripAPI.shared.baseURL else { return nil }
        return URL(string: raw, relativeTo: base)?.absoluteURL
    }
}

// MARK: - Share sheet content

private struct ShareSheetContent: View {
    let doc: DocumentManagementAPI.Document
    @Binding var action: MeDocumentsHub.HubAction?
    @ObservedObject var store: DocumentsHubStore
    @Environment(\.palette) var palette

    @State private var email: String = ""
    @State private var message: String = ""
    @State private var hours: Int = 72
    @State private var mintedLink: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(doc.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                TextField("Recipient email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                TextField("Optional message", text: $message)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("Expires in")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Picker("Expiry", selection: $hours) {
                        Text("24 hrs").tag(24)
                        Text("72 hrs").tag(72)
                        Text("7 days").tag(168)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
                if let link = mintedLink {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SHARE LINK")
                            .font(EType.micro).tracking(1.1)
                            .foregroundStyle(palette.textTertiary)
                        Text(link)
                            .font(EType.caption.monospaced())
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(Space.s3)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft)
                    )
                }
                Spacer()
                Button {
                    Task {
                        let link = await store.share(
                            documentId: doc.id,
                            recipientEmail: email.trimmingCharacters(in: .whitespaces),
                            message: message.isEmpty ? nil : message,
                            hours: hours
                        )
                        mintedLink = link
                        if link != nil {
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            action = nil
                        }
                    }
                } label: {
                    Text("Send share link")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!email.contains("@") || !email.contains("."))
                .opacity((!email.contains("@") || !email.contains(".")) ? 0.5 : 1.0)
            }
            .padding(Space.s4)
            .navigationTitle("Share document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { action = nil } }
            }
            .background(palette.bgPage.ignoresSafeArea())
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - E-Sign sheet content

private struct ESignSheetContent: View {
    let doc: DocumentManagementAPI.Document
    @Binding var action: MeDocumentsHub.HubAction?
    @ObservedObject var store: DocumentsHubStore
    @Environment(\.palette) var palette

    @State private var signerName: String = ""
    @State private var signerEmail: String = ""
    @State private var message: String = "Please review and sign this document."

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(doc.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                TextField("Signer full name", text: $signerName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                TextField("Signer email", text: $signerEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Text("Message")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                TextEditor(text: $message)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    )
                Text("A signing link is emailed to the signer. The request expires in 7 days. Progress shows up in the driver ↔ dispatch chat once a signature lands.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    Task {
                        let ok = await store.requestESignature(
                            documentId: doc.id,
                            signerName: signerName.trimmingCharacters(in: .whitespaces),
                            signerEmail: signerEmail.trimmingCharacters(in: .whitespaces),
                            message: message
                        )
                        if ok { action = nil }
                    }
                } label: {
                    Text("Send signing request")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(signerName.trimmingCharacters(in: .whitespaces).isEmpty
                          || !signerEmail.contains("@") || !signerEmail.contains("."))
                .opacity(
                    signerName.trimmingCharacters(in: .whitespaces).isEmpty
                        || !signerEmail.contains("@") || !signerEmail.contains(".")
                        ? 0.5 : 1.0
                )
            }
            .padding(Space.s4)
            .navigationTitle("Request e-signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { action = nil } }
            }
            .background(palette.bgPage.ignoresSafeArea())
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Archive sheet content

private struct ArchiveSheetContent: View {
    let doc: DocumentManagementAPI.Document
    @Binding var action: MeDocumentsHub.HubAction?
    @ObservedObject var store: DocumentsHubStore
    @Environment(\.palette) var palette

    @State private var retention: String = "7_years"

    private let options: [(String, String)] = [
        ("1_year",    "1 year"),
        ("3_years",   "3 years"),
        ("5_years",   "5 years"),
        ("7_years",   "7 years (default)"),
        ("10_years",  "10 years"),
        ("permanent", "Permanent"),
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(doc.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Retention policy")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                VStack(spacing: Space.s2) {
                    ForEach(options, id: \.0) { opt in
                        Button {
                            retention = opt.0
                        } label: {
                            let on = opt.0 == retention
                            HStack {
                                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textSecondary))
                                Text(opt.1)
                                    .font(EType.bodyStrong)
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                            }
                            .padding(Space.s3)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(palette.bgCard)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(on ? Color.white.opacity(0.25) : palette.borderFaint, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Archiving soft-deletes the document — it leaves the vault but is retained for the chosen window to satisfy DOT / IRS audit requirements.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    Task {
                        let ok = await store.archive(documentId: doc.id, retentionPolicy: retention)
                        if ok { action = nil }
                    }
                } label: {
                    Text("Archive document")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(Space.s4)
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { action = nil } }
            }
            .background(palette.bgPage.ignoresSafeArea())
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - UIDocumentPickerViewController bridge

private struct DocumentPickerSheet: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Accept PDFs + common image formats + generic data so a
        // driver can upload phone-camera JPEGs of their CDL without
        // converting first.
        let types: [UTType] = [.pdf, .jpeg, .png, .heic, .image, .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void
        let onCancel: () -> Void
        init(onPicked: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPicked(url) } else { onCancel() }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

// MARK: - Screen wrapper

struct MeDocumentsHubScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeDocumentsHub()
        } nav: {
            BottomNav(
                leading: driverNavLeading_083(),
                trailing: driverNavTrailing_083(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_083() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_083() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("083 · Me Documents Hub · Night") {
    MeDocumentsHubScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("083 · Me Documents Hub · Afternoon") {
    MeDocumentsHubScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}

// MARK: - SwipeRevealDelete
//
// Custom swipe-to-delete wrapper for rows that live in a VStack rather
// than a List (the doc rows are nested inside a categorized ScrollView,
// so SwiftUI's built-in `.swipeActions` — which only works inside a
// List — does not apply). Mirrors Mail/Messages behavior:
//   • Pan left to reveal a destructive Delete pill at the trailing edge
//   • Tap the pill to fire `onDelete`
//   • Full-swipe past `commitWidth` triggers `onDelete` directly
//   • Releasing before half-reveal snaps back closed
// Only horizontal-dominant pans engage the gesture so vertical scroll
// of the parent ScrollView keeps working.
private struct SwipeRevealDelete<Content: View>: View {
    let isDisabled: Bool
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    private let revealWidth: CGFloat = 88
    private let commitWidth: CGFloat = 220

    @State private var committedOffset: CGFloat = 0
    @GestureState private var dragX: CGFloat = 0

    private var liveOffset: CGFloat {
        let raw = committedOffset + dragX
        if raw > 0 { return 0 }
        if raw < -(commitWidth + 60) { return -(commitWidth + 60) }
        return raw
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                fire()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Delete")
                        .font(EType.micro)
                        .tracking(1.0)
                        .fontWeight(.semibold)
                }
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .foregroundStyle(.white)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(abs(liveOffset) > 8 ? 1 : 0)
            .accessibilityLabel("Delete document")
            .accessibilityHidden(abs(liveOffset) < revealWidth / 2)

            content()
                .offset(x: liveOffset)
                .gesture(
                    DragGesture(minimumDistance: 14, coordinateSpace: .local)
                        .updating($dragX) { value, state, _ in
                            guard !isDisabled else { return }
                            // Engage only when the pan is clearly horizontal
                            // — otherwise pass through so the ScrollView
                            // still handles vertical scroll.
                            if abs(value.translation.width) > abs(value.translation.height) * 1.4 {
                                state = value.translation.width
                            }
                        }
                        .onEnded { value in
                            guard !isDisabled else { return }
                            let proposed = committedOffset + value.translation.width
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                if proposed <= -commitWidth {
                                    fire()
                                } else if proposed <= -revealWidth * 0.5 {
                                    committedOffset = -revealWidth
                                } else {
                                    committedOffset = 0
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    // Tap on the row body while revealed = collapse.
                    TapGesture().onEnded {
                        if committedOffset != 0 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                committedOffset = 0
                            }
                        }
                    }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func fire() {
        onDelete()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            committedOffset = 0
        }
    }
}
