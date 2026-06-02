//
//  PasskeysManagementView.swift
//  EusoTrip — Settings → Passkeys management.
//
//  Drop-in sheet that lists every passkey bound to the signed-in
//  account, surfaces an "Add a passkey" action that drives the
//  Face-ID registration flow on this device, and lets the user
//  revoke a credential they no longer trust.
//
//  Server contract:
//    • auth.passkeyList     — protected, returns active credentials
//    • auth.passkeyRegister* — protected, two-step WebAuthn create
//    • auth.passkeyRevoke   — protected, soft-deletes by id
//

import SwiftUI

struct PasskeysManagementView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: EusoTripSession

    @State private var phase: Phase = .loading
    @State private var passkeys: [AuthAPI.PasskeyListRow] = []
    @State private var registering: Bool = false
    @State private var revokingId: Int? = nil
    @State private var error: String? = nil
    @State private var toast: String? = nil
    @State private var showLabelPrompt: Bool = false
    @State private var newLabel: String = ""

    enum Phase { case loading, loaded, empty }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    hero
                    if let e = error { errorBanner(e) }
                    if let t = toast { toastBanner(t) }
                    switch phase {
                    case .loading: loadingState
                    case .empty:   emptyState
                    case .loaded:  list
                    }
                    addCard
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(palette.bgPage)
            .navigationTitle("Passkeys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .task { await load() }
            .alert("Name this passkey", isPresented: $showLabelPrompt) {
                TextField("e.g. Diego's iPhone 16 Pro", text: $newLabel)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) { newLabel = "" }
                Button("Add") {
                    Task { await register(label: newLabel) }
                }
            } message: {
                Text("Use a name that makes it easy to recognize this device later.")
            }
        }
    }

    // MARK: — Hero / banners

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "key.viewfinder")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("FACE ID · WEBAUTHN").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Sign in with this device — no password.")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Passkeys are stored in the Secure Enclave and sync across your Apple devices via iCloud Keychain. We never see the private key.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Dismiss") { error = nil }
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(10)
        .background(Brand.danger.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.45))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func toastBanner(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Brand.success)
            Text(msg).font(EType.caption).foregroundStyle(Brand.success)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Brand.success.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.45))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: — States

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView().scaleEffect(0.9).tint(palette.textPrimary)
            Text("Loading your passkeys…")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "key.slash")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No passkeys yet")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Add this device's Face ID as a passkey to skip the password on every sign-in. You can add a passkey per device, and each one is independently revocable.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REGISTERED · \(passkeys.count)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            ForEach(passkeys) { row in
                passkeyRow(row)
            }
        }
    }

    private func passkeyRow(_ row: AuthAPI.PasskeyListRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal.opacity(0.15))
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.label ?? "Unnamed passkey")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                HStack(spacing: 6) {
                    Text(row.rpId)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                    if let created = row.createdAt.flatMap(formatDate) {
                        Text("· added \(created)")
                            .font(EType.caption).foregroundStyle(palette.textTertiary)
                    }
                }
                if let last = row.lastUsedAt.flatMap(formatDate) {
                    Text("Last used \(last)")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                } else {
                    Text("Not used yet")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 0)

            Button {
                Task { await revoke(row) }
            } label: {
                if revokingId == row.id {
                    ProgressView().scaleEffect(0.55).tint(Brand.danger)
                } else {
                    Text("Revoke")
                        .font(.system(size: 11, weight: .heavy))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(Brand.danger)
                        .background(Capsule().fill(Brand.danger.opacity(0.1)))
                        .overlay(Capsule().strokeBorder(Brand.danger.opacity(0.4)))
                }
            }
            .buttonStyle(.plain)
            .disabled(revokingId != nil)
        }
        .padding(12)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: — Add card

    private var addCard: some View {
        Button {
            error = nil
            toast = nil
            newLabel = defaultDeviceLabel()
            showLabelPrompt = true
        } label: {
            HStack(spacing: 8) {
                if registering {
                    ProgressView().scaleEffect(0.6).tint(.white)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .heavy))
                }
                Text(registering ? "Registering…" : "Add a passkey on this device")
                    .font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .foregroundStyle(.white)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(registering)
    }

    // MARK: — Behavior

    @MainActor
    private func load() async {
        phase = .loading
        do {
            let rows = try await EusoTripAPI.shared.auth.passkeyList()
            passkeys = rows
            phase = rows.isEmpty ? .empty : .loaded
        } catch {
            self.error = "Couldn't load passkeys: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            phase = .empty
        }
    }

    @MainActor
    private func register(label: String) async {
        guard !registering else { return }
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        let finalLabel = trimmed.isEmpty ? defaultDeviceLabel() : trimmed
        registering = true
        defer { registering = false }
        error = nil
        toast = nil
        do {
            try await session.registerPasskey(label: finalLabel)
            toast = "Passkey added · \(finalLabel)"
            newLabel = ""
            await load()
        } catch let e as EusoAuthError where e == .userCanceled {
            // No-op — user dismissed the Face ID sheet.
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func revoke(_ row: AuthAPI.PasskeyListRow) async {
        guard revokingId == nil else { return }
        revokingId = row.id
        defer { revokingId = nil }
        error = nil
        toast = nil
        do {
            _ = try await EusoTripAPI.shared.auth.passkeyRevoke(id: row.id)
            toast = "Revoked · \(row.label ?? "passkey")"
            await load()
        } catch {
            self.error = "Couldn't revoke: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    // MARK: — Helpers

    /// Compose a sensible default label so the user can hit "Add"
    /// without typing — e.g. "Diego's iPhone 16 Pro".
    private func defaultDeviceLabel() -> String {
        let device = UIDevice.current.name        // "Diego's iPhone"
        let model = UIDevice.current.localizedModel
        return device.contains(model) ? device : "\(device) · \(model)"
    }

    private func formatDate(_ iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? {
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: iso)
        }()
        guard let date else { return nil }
        let style = RelativeDateTimeFormatter()
        style.unitsStyle = .short
        return style.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Previews

#Preview("Passkeys · Dark") {
    PasskeysManagementView()
        .environment(\.palette, Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("Passkeys · Light") {
    PasskeysManagementView()
        .environment(\.palette, Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
