//
//  PricedRouteRateSheetAuthorityPanel.swift
//  EusoTrip
//
//  Reusable Truck / Rail / Vessel rate-sheet evidence surface. Files become
//  immutable proposals; a human confirms one exact draft hash; activation is
//  intentionally a separate server-authorized operation.
//

import SwiftUI
import UniformTypeIdentifiers

struct PricedRouteRateSheetAuthorityPanel: View {
    let mode: PricedRouteCommerceClient.Mode

    @Environment(\.palette) private var palette
    @State private var drafts: [PricedRouteCommerceClient.RateSheetDraft] = []
    @State private var loading = true
    @State private var importing = false
    @State private var selectedFileName: String?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var confirmationStatements: [String: String] = [:]
    @State private var confirmingDraftId: String?

    private let client = PricedRouteCommerceClient.shared

    var body: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: Space.s3) {
                heading
                truthNotice
                uploadControl

                if let statusMessage {
                    statusRow(statusMessage, color: Brand.success, icon: "checkmark.seal.fill")
                }
                if let errorMessage {
                    statusRow(errorMessage, color: Brand.danger, icon: "exclamationmark.triangle.fill")
                }

                if loading && drafts.isEmpty {
                    HStack(spacing: Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Loading immutable proposals…")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                } else if drafts.isEmpty {
                    Text("No \(mode.accessibilityLabel.lowercased()) rate-sheet proposals are recorded for this company.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: Space.s3) {
                        ForEach(drafts) { draft in
                            draftCard(draft)
                        }
                    }
                }
            }
        }
        .task { await refresh() }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(mode.accessibilityLabel) immutable rate-sheet authority")
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 34, height: 34)
                Image(systemName: modeIcon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(mode.accessibilityLabel.uppercased()) · RATE AUTHORITY")
                    .font(EType.micro.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Text(modeTitle)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: Space.s2)
            Text("IMMUTABLE")
                .font(EType.micro.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Brand.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Brand.blue.opacity(0.10))
                .clipShape(Capsule())
        }
    }

    private var truthNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Upload creates a proposal, never a live price", systemImage: "doc.badge.clock")
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text("EusoTrip preserves the original file and source hash, exposes parser confidence and blockers, then requires an exact-hash human confirmation of the draft. A separate rights and activation gate must pass before the policy can price a route.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var uploadControl: some View {
        Button {
            errorMessage = nil
            statusMessage = nil
            importing = true
        } label: {
            HStack(spacing: Space.s2) {
                if selectedFileName != nil {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Reading \(selectedFileName ?? "document")…")
                        .lineLimit(1)
                } else {
                    Image(systemName: "arrow.up.doc.fill")
                    Text("Upload \(modeUploadLabel)")
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .heavy))
                    .opacity(0.72)
            }
            .font(EType.bodyStrong)
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selectedFileName != nil)
        .accessibilityHint("Selects an original document and submits it as a non-executable proposal")
    }

    private func draftCard(_ draft: PricedRouteCommerceClient.RateSheetDraft) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.sourceDocument.originalFileName)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                    Text("\(draft.proposal.policyKind.replacingOccurrences(of: "_", with: " ")) · \(shortHash(draft.draftHashSha256))")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                        .textCase(.uppercase)
                }
                Spacer(minLength: Space.s2)
                statePill(draft)
            }

            HStack(spacing: Space.s2) {
                evidencePill(
                    draft.proposal.parser.grounded ? "GROUNDED" : "UNVERIFIED",
                    color: draft.proposal.parser.grounded ? Brand.success : Brand.warning
                )
                evidencePill(
                    "\(draft.sourceDocument.pageCount.map(String.init) ?? "—") PAGES",
                    color: palette.textSecondary
                )
                evidencePill(
                    draft.proposal.activationState.replacingOccurrences(of: "_", with: " ").uppercased(),
                    color: Brand.warning
                )
            }

            Text("Parser \(draft.proposal.parser.parserId) v\(draft.proposal.parser.parserVersion) · source \(shortHash(draft.sourceDocument.originalFileHashSha256))")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if !draft.proposal.parser.warnings.isEmpty {
                ForEach(Array(draft.proposal.parser.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.bubble")
                        .font(EType.caption)
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !draft.proposal.validationBlockers.isEmpty {
                Divider().overlay(palette.borderFaint)
                Text("REVIEW BLOCKERS")
                    .font(EType.micro.weight(.heavy))
                    .tracking(0.7)
                    .foregroundStyle(Brand.danger)
                ForEach(draft.proposal.validationBlockers) { blocker in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(blocker.message)
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text(blocker.recovery)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else if draft.effectiveState == "confirmed" {
                Label("Human-confirmed. Still awaiting source-rights authorization and activation.", systemImage: "person.crop.circle.badge.checkmark")
                    .font(EType.caption)
                    .foregroundStyle(Brand.success)
                    .fixedSize(horizontal: false, vertical: true)
            } else if draft.canConfirm {
                confirmationControl(draft)
            } else {
                Label("This proposal cannot be confirmed until its evidence is complete.", systemImage: "lock.trianglebadge.exclamationmark")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(draft.sourceDocument.originalFileName), \(draft.effectiveState) proposal")
    }

    private func confirmationControl(_ draft: PricedRouteCommerceClient.RateSheetDraft) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Divider().overlay(palette.borderFaint)
            Text("HUMAN REVIEW STATEMENT")
                .font(EType.micro.weight(.heavy))
                .tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            TextField(
                "Describe what you checked against the original document",
                text: confirmationBinding(for: draft.draftPublicId),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(EType.caption)
            .foregroundStyle(palette.textPrimary)
            .lineLimit(2...5)
            .padding(Space.s3)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )

            Button {
                Task { await confirm(draft) }
            } label: {
                HStack(spacing: Space.s2) {
                    if confirmingDraftId == draft.draftPublicId {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    Text("Confirm exact draft")
                    Spacer()
                    Text("HASH \(shortHash(draft.draftHashSha256))")
                        .font(EType.micro.weight(.heavy))
                        .opacity(0.72)
                }
                .font(EType.bodyStrong)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s3)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(confirmingDraftId != nil || reviewStatement(for: draft).count < 20)
            .opacity(reviewStatement(for: draft).count < 20 ? 0.55 : 1)
            .accessibilityHint("Confirms only this immutable draft hash; it does not activate pricing")
        }
    }

    private func statePill(_ draft: PricedRouteCommerceClient.RateSheetDraft) -> some View {
        let confirmed = draft.effectiveState == "confirmed"
        let blocked = !draft.proposal.validationBlockers.isEmpty
        let color = confirmed ? Brand.success : (blocked ? Brand.danger : Brand.warning)
        let label = confirmed ? "CONFIRMED" : (blocked ? "BLOCKED" : "PROPOSAL")
        return Text(label)
            .font(EType.micro.weight(.heavy))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }

    private func evidencePill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(EType.micro.weight(.heavy))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.08))
            .clipShape(Capsule())
    }

    private func statusRow(_ text: String, color: Color, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(EType.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }

    private func confirmationBinding(for draftId: String) -> Binding<String> {
        Binding(
            get: { confirmationStatements[draftId, default: ""] },
            set: { confirmationStatements[draftId] = $0 }
        )
    }

    private func reviewStatement(for draft: PricedRouteCommerceClient.RateSheetDraft) -> String {
        confirmationStatements[draft.draftPublicId, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.eusoUserCopy
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await ingest(url) }
        }
    }

    private func ingest(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        selectedFileName = url.lastPathComponent
        errorMessage = nil
        statusMessage = nil
        defer { selectedFileName = nil }

        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= 28_000_000 else {
                throw PanelError.fileTooLarge
            }
            guard let mediaType = mediaType(for: url) else {
                throw PanelError.unsupportedDocument
            }
            let result = try await client.ingestRateSheet(
                mode: mode,
                data: data,
                fileName: url.lastPathComponent,
                mediaType: mediaType
            )
            drafts = result.drafts + drafts.filter { existing in
                !result.drafts.contains(where: { $0.draftPublicId == existing.draftPublicId })
            }
            let blocked = result.drafts.filter { !$0.proposal.validationBlockers.isEmpty }.count
            statusMessage = blocked == 0
                ? "Proposal stored. Review and confirm the exact extracted terms; nothing was activated."
                : "Proposal stored with \(blocked) blocked draft\(blocked == 1 ? "" : "s"). Nothing was activated."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func confirm(_ draft: PricedRouteCommerceClient.RateSheetDraft) async {
        confirmingDraftId = draft.draftPublicId
        errorMessage = nil
        statusMessage = nil
        defer { confirmingDraftId = nil }
        do {
            _ = try await client.confirmRateSheet(
                draft: draft,
                statement: reviewStatement(for: draft)
            )
            confirmationStatements[draft.draftPublicId] = nil
            statusMessage = "Exact draft confirmed. Pricing remains inactive until source rights and activation are authorized."
            await refresh()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            drafts = try await client.listRateSheets(mode: mode)
            errorMessage = nil
        } catch {
            if drafts.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    private var allowedContentTypes: [UTType] {
        [
            .pdf, .png, .jpeg, .webP, .commaSeparatedText, .plainText,
            .spreadsheet, .data,
        ]
    }

    private func mediaType(for url: URL) -> PricedRouteCommerceClient.RateSheetMediaType? {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "webp": return .webp
        case "csv": return .csv
        case "txt": return .plainText
        case "xls": return .xls
        case "xlsx": return .xlsx
        case "doc": return .doc
        case "docx": return .docx
        default: return nil
        }
    }

    private var modeIcon: String {
        switch mode {
        case .truck: return "truck.box.fill"
        case .rail: return "tram.fill"
        case .vessel: return "ferry.fill"
        }
    }

    private var modeTitle: String {
        switch mode {
        case .truck: return "Schedule A and contract evidence"
        case .rail: return "Tariffs, contracts, and interchange evidence"
        case .vessel: return "Freight, charter, bunker, port, and canal evidence"
        }
    }

    private var modeUploadLabel: String {
        switch mode {
        case .truck: return "Schedule A"
        case .rail: return "tariff or rail contract"
        case .vessel: return "freight or charter terms"
        }
    }

    private func shortHash(_ value: String) -> String {
        String(value.prefix(10)).uppercased()
    }
}

private extension PricedRouteRateSheetAuthorityPanel {
    enum PanelError: LocalizedError {
        case fileTooLarge
        case unsupportedDocument

        var errorDescription: String? {
            switch self {
            case .fileTooLarge:
                return "This original is too large for the immutable rate-sheet intake. Choose a file under 28 MB without altering its terms."
            case .unsupportedDocument:
                return "Use PDF, PNG, JPEG, WebP, CSV, TXT, XLS, XLSX, DOC, or DOCX."
            }
        }
    }
}
