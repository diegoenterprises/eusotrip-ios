//
//  349_AccountExportDelete.swift
//  EusoTrip — Shipper · Account export + delete (Arc K).
//

import SwiftUI
import UIKit

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
    @State private var deleteRequested = false
    @State private var actionError: String? = nil
    @State private var confirmDelete: Bool = false
    @State private var confirmText: String = ""
    /// In-app share-sheet state for the "Download ZIP" action.
    /// Replaces the prior `UIApplication.shared.open(url)` Safari
    /// punt with authed-fetch + UIActivityViewController so the user
    /// can save the export ZIP straight into Files or AirDrop it.
    private struct ExportZipShareItem: Identifiable, Hashable {
        let id: UUID
        let url: URL
    }
    @State private var zipShareItem: ExportZipShareItem? = nil
    @State private var downloadingZip: Bool = false
    @State private var zipError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let url = exportUrl { exportReadyCard(url) }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                exportCard
                deleteCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .sheet(item: $zipShareItem) { item in
            ExportZipActivitySheet(url: item.url)
                .presentationDetents([.medium, .large])
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

    private var exportCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DATA EXPORT", icon: "square.and.arrow.up")
            Text("Receive a ZIP of your loads, settlements, contacts, and documents. Sent to your account email when ready.")
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

    private func exportReadyCard(_ url: String) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "EXPORT READY", icon: "checkmark.circle")
            Button { Task { await downloadExportZip(urlString: url) } } label: {
                HStack(spacing: 6) {
                    if downloadingZip {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 11, weight: .heavy))
                    }
                    Text(downloadingZip ? "Fetching…" : "Download ZIP")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(LinearGradient.diagonal).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(downloadingZip)
            if let zerr = zipError {
                Text(zerr).font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @MainActor
    private func downloadExportZip(urlString: String) async {
        guard !downloadingZip else { return }
        downloadingZip = true
        zipError = nil
        defer { downloadingZip = false }
        guard let url = URL(string: urlString) else {
            zipError = "Couldn't parse the export URL."
            return
        }
        do {
            let (data, _) = try await EusoTripAPI.shared.fetchAuthenticatedData(url)
            guard !data.isEmpty else {
                zipError = "Server returned an empty file."
                return
            }
            let suggested = url.lastPathComponent.isEmpty ? "eusotrip-export.zip" : url.lastPathComponent
            let safeName = suggested.lowercased().hasSuffix(".zip") ? suggested : "\(suggested).zip"
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(safeName)
            try data.write(to: tmp, options: .atomic)
            zipShareItem = ExportZipShareItem(id: UUID(), url: tmp)
        } catch let apiErr as EusoTripAPIError {
            zipError = apiErr.errorDescription ?? "Network error"
        } catch {
            zipError = error.localizedDescription
        }
    }

    private var deleteCard: some View {
        LifecycleCard(accentDanger: true) {
            LifecycleSection(label: "DELETE ACCOUNT", icon: "trash.fill")
            Text("Soft-delete your Eusorone account. 30-day window before purge. Active loads + settlements must be closed first.")
                .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            if deleteRequested {
                Text("DELETION REQUESTED · 30-day window started.").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Brand.danger).clipShape(Capsule())
            } else {
                Toggle("I understand this is permanent.", isOn: $confirmDelete).font(EType.caption)
                if confirmDelete {
                    TextField("Type 'DELETE' to confirm", text: $confirmText)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(palette.bgCard.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Brand.danger.opacity(0.5), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Button { Task { await requestDelete() } } label: {
                        HStack(spacing: 6) {
                            if deleting { ProgressView().tint(.white) }
                            Text(deleting ? "Deleting…" : "Delete account").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Brand.danger).clipShape(Capsule())
                    }.buttonStyle(.plain).disabled(deleting || confirmText != "DELETE")
                }
            }
        }
    }

    private func requestExport() async {
        exporting = true; actionError = nil
        struct Out: Decodable { let url: String? }
        do {
            let r: Out = try await EusoTripAPI.shared.queryNoInput("users.requestDataExport")
            exportUrl = r.url
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        exporting = false
    }

    private func requestDelete() async {
        deleting = true; actionError = nil
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("users.requestAccountDeletion", input: ["": ""] as [String: String])
            deleteRequested = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        deleting = false
    }
}

// MARK: - In-app share sheet for the export ZIP

private struct ExportZipActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview("349 · Export/Delete · Night") { AccountExportDeleteScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("349 · Export/Delete · Afternoon") { AccountExportDeleteScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
