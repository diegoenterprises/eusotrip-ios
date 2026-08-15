//
//  349_AccountExportDelete.swift
//  EusoTrip — Shipper · Account export + delete + migrate (Arc K).
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AccountExportDeleteScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ExportDeleteBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ExportDeleteBody: View {
    @Environment(\.palette) private var palette
    @State private var exporting = false
    @State private var deleting = false
    @State private var exportUrl: String? = nil
    @State private var exportFilename: String? = nil
    @State private var deletionLifecycleStatus: UsersAPI.AccountDeletionStatus.Status = .none
    @State private var deleteScheduledFor: String? = nil
    @State private var deletionBlockedReason: String? = nil
    @State private var loadingDeletionStatus = true
    @State private var deletionStatusError: String? = nil
    @State private var cancellingDelete = false
    @State private var deleteCancelled = false
    @State private var actionError: String? = nil
    @State private var confirmDelete: Bool = false
    @State private var confirmText: String = ""
    @State private var deletionPassword: String = ""
    /// In-app share-sheet state for the "Download archive" action.
    /// Authed fetch + UIActivityViewController so the user can save the
    /// signed JSON export straight into Files or AirDrop it — never a
    /// Safari punt.
    private struct ExportArchiveShareItem: Identifiable, Hashable {
        let id: UUID
        let url: URL
    }
    @State private var archiveShareItem: ExportArchiveShareItem? = nil
    @State private var downloadingArchive: Bool = false
    @State private var archiveError: String? = nil
    // ── Import / migrate state ──
    @State private var importPickerPresented = false
    @State private var importing = false
    @State private var importAck: UsersAPI.ImportRequestAck? = nil
    @State private var importError: String? = nil
    // ── Approvals state (users.pendingDataImports) ──
    @State private var transfers: UsersAPI.ImportTransferList? = nil
    @State private var transfersLoading = true
    @State private var transfersError: String? = nil
    @State private var decidingImportId: String? = nil
    @State private var importDecisionPasswords: [String: String] = [:]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let url = exportUrl { exportReadyCard(url) }
                if deleteCancelled { deleteCancelledCard }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                exportCard
                importCard
                approvalsCard
                if !deleteCancelled { deleteCard }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .sheet(item: $archiveShareItem) { item in
            ExportArchiveActivitySheet(url: item.url)
                .presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $importPickerPresented, allowedContentTypes: [.json, .plainText]) { result in
            switch result {
            case .success(let url): Task { await submitImport(from: url) }
            case .failure(let err): importError = err.localizedDescription
            }
        }
        .eusoRefreshTask {
            await loadDeletionStatus()
            await loadTransfers()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "trash.circle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.danger)
                Text("SHIPPER · ACCOUNT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(Brand.danger)
            }
            Text("Export or delete account").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: - Export

    private var exportCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DATA EXPORT", icon: "square.and.arrow.up")
            Text("Download a signed archive of your profile, loads, settlements, contacts, documents, wallet history and messages. A copy of the download link is also emailed to your account email.")
                .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            Button { Task { await requestExport() } } label: {
                HStack(spacing: 6) {
                    if exporting { ProgressView().tint(.white) }
                    Text(exporting ? "Requesting…" : "Request export").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(exporting)
        }
    }

    private var deleteCancelledCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "DELETION CANCELLED", icon: "checkmark.circle")
            Text("Your account deletion was cancelled. Nothing will be purged.")
                .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func exportReadyCard(_ url: String) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "EXPORT READY", icon: "checkmark.circle")
            Text("Your archive is ready. Save it to Files, then pick it under Import / Migrate on a new account to move your contacts and eligible personal documents over.")
                .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            Button { Task { await downloadExportArchive(urlString: url) } } label: {
                HStack(spacing: 6) {
                    if downloadingArchive {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 11, weight: .heavy))
                    }
                    Text(downloadingArchive ? "Fetching…" : "Download archive")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(LinearGradient.diagonal).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(downloadingArchive)
            if let aerr = archiveError {
                Text(aerr).font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @MainActor
    private func downloadExportArchive(urlString: String) async {
        guard !downloadingArchive else { return }
        downloadingArchive = true
        archiveError = nil
        defer { downloadingArchive = false }
        guard let url = URL(string: urlString) else {
            archiveError = "Couldn't parse the export URL."
            return
        }
        do {
            let (data, _) = try await EusoTripAPI.shared.fetchAuthenticatedData(url)
            guard !data.isEmpty else {
                archiveError = "Your export downloaded as zero bytes — nothing was saved to this device. Request the export again."
                return
            }
            let fallback = url.lastPathComponent.isEmpty ? "eusotrip-export.json" : url.lastPathComponent
            let suggested = exportFilename ?? fallback
            let lowered = suggested.lowercased()
            let safeName = (lowered.hasSuffix(".json") || lowered.hasSuffix(".zip")) ? suggested : "\(suggested).json"
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(safeName)
            try data.write(to: tmp, options: .atomic)
            archiveShareItem = ExportArchiveShareItem(id: UUID(), url: tmp)
        } catch let apiErr as EusoTripAPIError {
            archiveError = apiErrorMessage(apiErr)
        } catch {
            archiveError = "The export could not be saved to this device. Try the download again."
        }
    }

    // MARK: - Import / migrate

    private var importCard: some View {
        LifecycleCard {
            LifecycleSection(label: "IMPORT / MIGRATE", icon: "square.and.arrow.down.on.square")
            Text("Moving to a new account? Pick the signed export archive you downloaded from the old account. After the source owner approves, contacts and personal documents not bound to a load, shipment, agreement, compliance case or other operational record move here. Operational records, loads, settlements and wallet history stay on the source account for their retention periods.")
                .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            if let ack = importAck {
                Text("PENDING APPROVAL · sent to account #\(ack.sourceUserId)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
                Text("The source account owner has been notified. The request appears under Migration approvals below once it's decided.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Button { importPickerPresented = true } label: {
                    HStack(spacing: 6) {
                        if importing { ProgressView().tint(.white) }
                        Text(importing ? "Verifying…" : "Pick export archive").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(importing)
            }
            if let err = importError {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @MainActor
    private func submitImport(from fileURL: URL) async {
        importing = true; importError = nil
        defer { importing = false }
        let secured = fileURL.startAccessingSecurityScopedResource()
        defer { if secured { fileURL.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: fileURL)
            struct Archive: Decodable { let manifest: UsersAPI.ExportManifest? }
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            guard let manifest = archive.manifest, let signature = manifest.signature, !signature.isEmpty else {
                importError = "That file has no signed manifest. Download a fresh export archive from the source account and try again."
                return
            }
            let required = Set(UsersAPI.ExportManifest.requiredSections)
            guard manifest.schemaName == UsersAPI.ExportManifest.schemaName,
                  manifest.schemaVersion == UsersAPI.ExportManifest.schemaVersion,
                  manifest.complete,
                  Set(manifest.requiredSections) == required,
                  required.allSatisfy({ manifest.entityCounts[$0] != nil }) else {
                importError = "That archive is incomplete or uses an unsupported EusoTrip export schema. Download a fresh export from the source account."
                return
            }
            importAck = try await EusoTripAPI.shared.users.requestDataImport(manifest: manifest, signature: signature)
            await loadTransfers()
        } catch let apiErr as EusoTripAPIError {
            importError = apiErrorMessage(apiErr)
        } catch let decodeErr as DecodingError {
            _ = decodeErr
            importError = "That file isn't an EusoTrip export archive."
        } catch {
            importError = "That archive could not be read. Choose the original downloaded export and try again."
        }
    }

    // MARK: - Migration approvals (source-owner decisions + own requests)

    @ViewBuilder
    private var approvalsCard: some View {
        if transfersLoading && transfers == nil {
            LifecycleCard {
                LifecycleSection(label: "MIGRATION APPROVALS", icon: "person.2.badge.gearshape")
                HStack(spacing: 8) {
                    ProgressView().tint(palette.textSecondary)
                    Text("Loading migration status…")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
        if let err = transfersError {
            LifecycleCard(accentDanger: true) {
                LifecycleSection(label: "MIGRATION STATUS UNAVAILABLE", icon: "exclamationmark.triangle")
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Button { Task { await loadTransfers() } } label: {
                    Text("Retry").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(transfersLoading)
            }
        }
        if let t = transfers, !(t.incoming.isEmpty && t.outgoing.isEmpty) {
            LifecycleCard {
                LifecycleSection(label: "MIGRATION APPROVALS", icon: "person.2.badge.gearshape")
                if !t.incoming.isEmpty {
                    Text("Requests to move data OUT of this account. Approval re-keys contacts and eligible personal documents that are not bound to operational records. Loads, shipments, agreements, compliance records, settlements and wallet history remain here.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(t.incoming) { row in incomingRow(row) }
                }
                if !t.outgoing.isEmpty {
                    Text("Requests you filed from an archive.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(t.outgoing) { row in outgoingRow(row) }
                }
            }
        }
    }

    private func incomingRow(_ row: UsersAPI.ImportTransferRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("→ account #\(row.targetUserId ?? 0)")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                statusBadge(row.status)
            }
            if let email = row.targetEmail, !email.isEmpty {
                Text(email).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            if row.status.lowercased() == "pending" {
                SecureField("Source-account password", text: importPasswordBinding(row.importId))
                    .textContentType(.password)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.stroke, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                HStack(spacing: 8) {
                    Button { Task { await decide(row.importId, approve: true) } } label: {
                        HStack(spacing: 4) {
                            if decidingImportId == row.importId { ProgressView().scaleEffect(0.6).tint(.white) }
                            Text("Approve").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                    }.buttonStyle(.plain).disabled(decidingImportId != nil || importDecisionPasswords[row.importId, default: ""].isEmpty)
                    Button { Task { await decide(row.importId, approve: false) } } label: {
                        Text("Reject").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Brand.danger).clipShape(Capsule())
                    }.buttonStyle(.plain).disabled(decidingImportId != nil || importDecisionPasswords[row.importId, default: ""].isEmpty)
                }
            } else if let ex = row.executed {
                Text("\(ex.contactsMoved ?? 0) contacts · \(ex.documentsMoved ?? 0) eligible personal documents moved")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func outgoingRow(_ row: UsersAPI.ImportTransferRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("← account #\(row.sourceUserId ?? 0)")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                statusBadge(row.status)
            }
            if let ex = row.executed, row.status.lowercased() == "approved" {
                Text("\(ex.contactsMoved ?? 0) contacts · \(ex.documentsMoved ?? 0) eligible personal documents now in this account")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: String) -> some View {
        let lowered = status.lowercased()
        let color: Color = lowered == "approved" ? Brand.success : (lowered == "rejected" ? Brand.danger : Brand.warning)
        return Text(status.uppercased())
            .font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color).clipShape(Capsule())
    }

    @MainActor
    private func loadTransfers() async {
        transfersLoading = true
        transfersError = nil
        defer { transfersLoading = false }
        do {
            transfers = try await EusoTripAPI.shared.users.pendingDataImports()
        } catch {
            transfersError = apiErrorMessage(error)
        }
    }

    @MainActor
    private func decide(_ importId: String, approve: Bool) async {
        let password = importDecisionPasswords[importId, default: ""]
        guard !password.isEmpty else {
            transfersError = "Enter the source-account password to approve or reject this migration."
            return
        }
        decidingImportId = importId
        transfersError = nil
        defer { decidingImportId = nil }
        do {
            if approve { _ = try await EusoTripAPI.shared.users.approveDataImport(importId: importId, password: password) }
            else { _ = try await EusoTripAPI.shared.users.rejectDataImport(importId: importId, password: password) }
            importDecisionPasswords[importId] = nil
            await loadTransfers()
        } catch {
            transfersError = apiErrorMessage(error)
        }
    }

    // MARK: - Delete

    private var deleteCard: some View {
        LifecycleCard(accentDanger: true) {
            LifecycleSection(label: "DELETE ACCOUNT", icon: "trash.fill")
            Text("Schedule account deletion with a 30-day cancellation window. Active truck, rail, and vessel work; settlements; wallet balances or transfers; and legal or regulatory holds must be cleared first.")
                .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            if loadingDeletionStatus {
                HStack(spacing: 8) {
                    ProgressView().tint(palette.textSecondary)
                    Text("Checking account status…")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else if let err = deletionStatusError {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Button { Task { await loadDeletionStatus() } } label: {
                    Text("Retry").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(loadingDeletionStatus)
            } else if deletionLifecycleStatus == .purging {
                Text("PURGE IN PROGRESS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Brand.danger).clipShape(Capsule())
                Text("The 30-day cancellation window has closed and your account data is being erased now. This is not a new 30-day request, and it can no longer be cancelled from this screen.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            } else if deletionLifecycleStatus == .executed {
                Text("DELETION EXECUTED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Brand.danger).clipShape(Capsule())
                Text("Account deletion has completed. Nothing further is pending on this account.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            } else if deletionLifecycleStatus == .blocked {
                Text("DELETION BLOCKED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Brand.warning).clipShape(Capsule())
                Text(deletionBlockMessage)
                    .font(EType.caption).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true)
                Button { Task { await loadDeletionStatus() } } label: {
                    Text("Check again").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(loadingDeletionStatus)
            } else if deletionLifecycleStatus == .pending {
                Text("DELETION REQUESTED · 30-day window started.").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Brand.danger).clipShape(Capsule())
                if let purge = scheduledPurgeLabel {
                    Text("Scheduled purge · \(purge)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
                }
                Text("Change your mind any time before the window closes and your account stays active.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                Button { Task { await cancelDelete() } } label: {
                    HStack(spacing: 6) {
                        if cancellingDelete { ProgressView().tint(.white) }
                        Text(cancellingDelete ? "Cancelling…" : "Cancel deletion").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(cancellingDelete)
            } else {
                Toggle("I understand this is permanent.", isOn: $confirmDelete).font(EType.caption)
                if confirmDelete {
                    TextField("Type 'DELETE' to confirm", text: $confirmText)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(palette.bgCard.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Brand.danger.opacity(0.5), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    SecureField("Re-enter account password", text: $deletionPassword)
                        .textContentType(.password)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(palette.bgCard.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Brand.danger.opacity(0.5), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Button { Task { await requestDelete() } } label: {
                        HStack(spacing: 6) {
                            if deleting { ProgressView().tint(.white) }
                            Text(deleting ? "Scheduling…" : "Schedule deletion").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Brand.danger).clipShape(Capsule())
                    }.buttonStyle(.plain).disabled(deleting || confirmText != "DELETE" || deletionPassword.isEmpty)
                }
            }
        }
    }

    private func requestExport() async {
        exporting = true; actionError = nil
        do {
            let pkg = try await EusoTripAPI.shared.users.requestDataExport()
            guard let url = pkg.url, !url.isEmpty else {
                actionError = "A complete export archive was not issued. No export was recorded as ready."
                return
            }
            exportUrl = url
            exportFilename = pkg.filename
        } catch {
            actionError = apiErrorMessage(error)
        }
        exporting = false
    }

    private func requestDelete() async {
        deleting = true; actionError = nil
        defer { deleting = false }
        do {
            let r = try await EusoTripAPI.shared.users.requestAccountDeletion(
                password: deletionPassword,
                reason: "user_requested"
            )
            guard r.success else {
                actionError = "Your deletion request was not confirmed. Your account remains active and nothing is scheduled — submit the request again."
                return
            }
            deleteScheduledFor = r.scheduledFor
            deletionLifecycleStatus = .pending
            deletionBlockedReason = nil
            deleteCancelled = false
            deletionPassword = ""
        } catch {
            actionError = friendlyDeletionError(error)
        }
    }

    private func cancelDelete() async {
        cancellingDelete = true; actionError = nil
        defer { cancellingDelete = false }
        do {
            let response = try await EusoTripAPI.shared.users.cancelAccountDeletion()
            guard response.success else {
                actionError = "The cancellation was not confirmed. Your deletion request may still be scheduled — retry, and check the date above before it runs."
                return
            }
            deletionLifecycleStatus = .cancelled
            deleteScheduledFor = nil
            deletionBlockedReason = nil
            confirmDelete = false
            confirmText = ""
            deletionPassword = ""
            deleteCancelled = true
        } catch {
            actionError = apiErrorMessage(error)
        }
    }

    @MainActor
    private func loadDeletionStatus() async {
        loadingDeletionStatus = true
        deletionStatusError = nil
        defer { loadingDeletionStatus = false }
        do {
            let persisted = try await EusoTripAPI.shared.users.getAccountDeletionStatus()
            deletionLifecycleStatus = persisted.status
            deleteScheduledFor = persisted.status == .pending ? persisted.scheduledFor : nil
            deletionBlockedReason = persisted.status == .blocked ? persisted.blockedReason : nil
            if persisted.status != .cancelled { deleteCancelled = false }
        } catch {
            deletionStatusError = apiErrorMessage(error)
        }
    }

    private var deletionBlockMessage: String {
        let reason = deletionBlockedReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reason.isEmpty
            ? "This deletion is blocked, but no reason is available. Check again or contact support before retrying."
            : reason
    }

    private func apiErrorMessage(_ error: Error) -> String {
        guard let apiError = error as? EusoTripAPIError else {
            return "The account request could not be completed. Try again."
        }
        switch apiError {
        case .unauthenticated:
            return "Sign in again to continue this account request."
        case .forbidden:
            return "This account is not permitted to complete that request."
        case .httpStatus(let code, _):
            return code == 401 || code == 403
                ? "Sign in again or confirm that this is your account."
                : "The account request could not be completed (error \(code)). Try again."
        case .decodingFailed, .empty:
            return "The result could not be verified. Refresh before trying again."
        case .queuedForOfflineReplay:
            return "This account request needs an internet connection. Reconnect and try again."
        case .notConfigured, .badURL, .trpcError:
            return "The account request could not be completed. Try again."
        }
    }

    private func importPasswordBinding(_ importId: String) -> Binding<String> {
        Binding(
            get: { importDecisionPasswords[importId, default: ""] },
            set: { importDecisionPasswords[importId] = $0 }
        )
    }

    /// Maps the active-loads rejection to a plain-language inline message.
    private func friendlyDeletionError(_ error: Error) -> String {
        let internalReason: String
        if case EusoTripAPIError.trpcError(let message) = error {
            internalReason = message
        } else if case EusoTripAPIError.forbidden(let message) = error {
            internalReason = message
        } else {
            internalReason = ""
        }
        let lowered = internalReason.lowercased()
        if lowered.contains("active load") || lowered.contains("active loads") {
            return "You can't delete your account while you have active loads. Close or cancel them first."
        }
        return apiErrorMessage(error)
    }

    /// Human-readable purge date from the server's `scheduledFor` ISO string,
    /// or nil when the server didn't return one (then we show no date).
    private var scheduledPurgeLabel: String? {
        guard let raw = deleteScheduledFor, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return nil }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .none
        return out.string(from: date)
    }
}

// MARK: - In-app share sheet for the export archive

private struct ExportArchiveActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview("349 · Export/Delete · Night") { AccountExportDeleteScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("349 · Export/Delete · Afternoon") { AccountExportDeleteScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
