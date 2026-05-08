//
//  345_TwoFactorManage.swift
//  EusoTrip — Shipper · 2FA manage (Arc K).
//
//  Founder doctrine 2026-05-07: '2FA make sure this is built
//  correctly we have the azure infrastructure to make so'. Real
//  TOTP enrollment flow with QR scan + verify + backup codes.
//
//  Backend (Azure-hosted) endpoints:
//    auth.tfaStatus              → { enabled, methods, backupCodesRemaining, lastUsed }
//    auth.tfaSetupTOTP           → { otpAuthUrl, secret, qrCodeBase64 }
//    auth.tfaVerifyTOTP(code)    → { success, backupCodes: [String] }
//    auth.tfaDisable(code)       → { success }
//    auth.tfaRegenerateBackupCodes → { success, backupCodes: [String] }
//

import SwiftUI

struct TwoFactorManageScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { TwoFactorBody() } nav: { shipperLifecycleNav() }
    }
}

private struct TfaStatus: Decodable, Hashable {
    let enabled: Bool
    let methods: [String]?
    let backupCodesRemaining: Int?
    let lastUsed: String?
}

private struct TfaSetupTOTP: Decodable, Hashable {
    let otpAuthUrl: String
    let secret: String
    let qrCodeBase64: String?
}

private struct TfaVerifyResult: Decodable, Hashable {
    let success: Bool
    let backupCodes: [String]?
}

private struct TwoFactorBody: View {
    @Environment(\.palette) private var palette
    @State private var status: TfaStatus? = nil
    @State private var loading = true
    @State private var actionError: String? = nil
    @State private var working: Bool = false

    @State private var showEnrollSheet: Bool = false
    @State private var showDisableConfirm: Bool = false
    @State private var presentedBackupCodes: [String]? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let err = actionError {
                    LifecycleCard(accentDanger: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Brand.danger)
                                Text(friendlyTfaTitle(err))
                                    .font(EType.bodyStrong)
                                    .foregroundStyle(palette.textPrimary)
                            }
                            Text(err)
                                .font(EType.caption)
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(2)
                            Button { Task { await load() } } label: {
                                Text("Retry")
                                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(LinearGradient.diagonal))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if loading {
                    LifecycleCard {
                        HStack(spacing: 8) {
                            ProgressView().tint(LinearGradient.diagonal).scaleEffect(0.8)
                            Text("Loading 2FA status…")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                } else if let s = status {
                    statusCard(s)
                    methodsExplainer
                    ctaRow(s)
                    backupCodesCard(s)
                    securityHints
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .sheet(isPresented: $showEnrollSheet) {
            TfaEnrollSheet { codes in
                presentedBackupCodes = codes
                showEnrollSheet = false
                Task { await load() }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Disable 2FA?",
               isPresented: $showDisableConfirm,
               actions: {
            Button("Disable", role: .destructive) {
                Task { await disable() }
            }
            Button("Cancel", role: .cancel) {}
        }, message: {
            Text("Your account will be less secure. You'll only need email + password to sign in.")
        })
        .sheet(item: Binding(
            get: { presentedBackupCodes.map { CodesPayload(codes: $0) } },
            set: { presentedBackupCodes = $0?.codes }
        )) { payload in
            BackupCodesSheet(codes: payload.codes)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private struct CodesPayload: Identifiable {
        let id = UUID()
        let codes: [String]
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "key.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · TWO-FACTOR AUTH").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Two-factor authentication").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Azure AD-backed. TOTP, backup codes, audit log on every sign-in.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func statusCard(_ s: TfaStatus) -> some View {
        LifecycleCard(accentWarning: !s.enabled, accentGradient: s.enabled) {
            LifecycleSection(label: "STATUS", icon: s.enabled ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
            LifecycleRow(label: "Enabled",  value: s.enabled ? "Yes" : "No")
            LifecycleRow(label: "Methods",  value: methodsLabel(s.methods))
            LifecycleRow(label: "Last used", value: humanISO(s.lastUsed))
        }
    }

    private var methodsExplainer: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("METHODS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                methodChip(icon: "qrcode", label: "TOTP authenticator app", desc: "Google Authenticator · Authy · 1Password — 6-digit code refreshes every 30s.")
                methodChip(icon: "lock.rectangle.stack", label: "Backup codes", desc: "Single-use 10-digit codes for when you lose your phone.")
            }
        }
    }

    private func methodChip(icon: String, label: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                Image(systemName: icon).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(desc).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func ctaRow(_ s: TfaStatus) -> some View {
        Button {
            if s.enabled {
                showDisableConfirm = true
            } else {
                showEnrollSheet = true
            }
        } label: {
            HStack(spacing: 6) {
                if working { ProgressView().tint(.white) }
                Image(systemName: s.enabled ? "minus.shield" : "plus.shield.fill")
                    .font(.system(size: 13, weight: .heavy))
                Text(working ? "Working…" : (s.enabled ? "Disable 2FA" : "Enable 2FA"))
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(s.enabled ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(LinearGradient.diagonal))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(working)
    }

    @ViewBuilder
    private func backupCodesCard(_ s: TfaStatus) -> some View {
        if s.enabled, let n = s.backupCodesRemaining {
            LifecycleCard(accentWarning: n < 3) {
                LifecycleSection(label: "BACKUP CODES", icon: "lock.rectangle.stack")
                LifecycleRow(label: "Remaining", value: "\(n)")
                if n < 3 {
                    Text("⚠ Low — regenerate before you run out.")
                        .font(EType.caption).foregroundStyle(Brand.warning)
                }
                Button {
                    Task { await regenerateCodes() }
                } label: {
                    HStack(spacing: 6) {
                        if working { ProgressView().scaleEffect(0.7).tint(.white) }
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .heavy))
                        Text("Regenerate codes").font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(working)
            }
        }
    }

    private var securityHints: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("WHY THIS MATTERS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("Catalyst dispatch, EusoWallet settlements, and EusoTicket BOL signing all gate on your account. 2FA prevents account takeover even when a password leaks.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func methodsLabel(_ raw: [String]?) -> String {
        let m = raw ?? []
        if m.isEmpty { return "—" }
        return m.map { $0.uppercased() }.joined(separator: " · ")
    }

    private func friendlyTfaTitle(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("auth") || lower.contains("unauthorized") || lower.contains("401") {
            return "Sign in again to manage 2FA"
        }
        if lower.contains("network") || lower.contains("offline") {
            return "Auth service offline — try again"
        }
        return "Couldn't load 2FA status"
    }

    // MARK: - Network

    private func load() async {
        loading = true; actionError = nil
        do {
            let s: TfaStatus = try await EusoTripAPI.shared.queryNoInput("auth.tfaStatus")
            status = s
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func disable() async {
        working = true; actionError = nil
        defer { working = false }
        struct Out: Decodable { let success: Bool }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("auth.tfaDisable", input: ["": ""] as [String: String])
            await load()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func regenerateCodes() async {
        working = true; actionError = nil
        defer { working = false }
        struct Out: Decodable {
            let success: Bool
            let backupCodes: [String]?
        }
        do {
            let r: Out = try await EusoTripAPI.shared.mutation("auth.tfaRegenerateBackupCodes", input: ["": ""] as [String: String])
            if let codes = r.backupCodes, !codes.isEmpty {
                presentedBackupCodes = codes
            }
            await load()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Enroll sheet (TOTP setup → verify → backup codes)

private struct TfaEnrollSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// Called with the backup codes when enrollment succeeds. The
    /// parent presents BackupCodesSheet with them.
    let onCompleted: ([String]) -> Void

    @State private var setupData: TfaSetupTOTP? = nil
    @State private var setupError: String? = nil
    @State private var loading = true
    @State private var verifyCode: String = ""
    @State private var verifying = false
    @State private var verifyError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    HStack(spacing: 8) {
                        ProgressView().tint(LinearGradient.diagonal)
                        Text("Generating TOTP secret…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = setupError {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    Button { Task { await loadSetup() } } label: {
                        Text("Retry").font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(LinearGradient.diagonal))
                    }.buttonStyle(.plain)
                } else if let s = setupData {
                    qrCard(s)
                    secretCard(s)
                    verifySection
                }
            }
            .padding(Space.s5)
        }
        .background(palette.bgPrimary)
        .task { await loadSetup() }
        .navigationBarHidden(true)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(Space.s4)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Enable 2FA")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Scan the QR with Google Authenticator / Authy / 1Password, then enter the 6-digit code below.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private func qrCard(_ s: TfaSetupTOTP) -> some View {
        VStack(spacing: 8) {
            // Render the server-provided QR code base64 PNG when
            // present, otherwise fall back to a CIFilter-generated
            // QR over the otpAuthUrl.
            if let b64 = s.qrCodeBase64,
               let data = Data(base64Encoded: b64),
               let img = UIImage(data: data) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
            } else {
                EusoQRView(payload: s.otpAuthUrl, size: 220)
            }
            Text("Or paste the secret below into your app.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func secretCard(_ s: TfaSetupTOTP) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SECRET").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            HStack {
                Text(s.secret)
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = s.secret
                } label: {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }.buttonStyle(.plain)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private var verifySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VERIFY").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            HStack {
                TextField("000 000", text: $verifyCode)
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .onChange(of: verifyCode) { _, v in
                        // Strip non-digits + cap at 6 to match TOTP.
                        verifyCode = String(v.filter(\.isNumber).prefix(6))
                    }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            if let err = verifyError {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
            Button {
                Task { await verify() }
            } label: {
                HStack(spacing: 6) {
                    if verifying { ProgressView().tint(.white).scaleEffect(0.7) }
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 12, weight: .heavy))
                    Text(verifying ? "Verifying…" : "Verify & enable")
                        .font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(verifying || verifyCode.count != 6)
        }
    }

    private func loadSetup() async {
        loading = true; setupError = nil
        defer { loading = false }
        do {
            let s: TfaSetupTOTP = try await EusoTripAPI.shared.queryNoInput("auth.tfaSetupTOTP")
            setupData = s
        } catch {
            setupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func verify() async {
        verifying = true; verifyError = nil
        defer { verifying = false }
        struct In: Encodable { let code: String }
        do {
            let r: TfaVerifyResult = try await EusoTripAPI.shared.mutation(
                "auth.tfaVerifyTOTP", input: In(code: verifyCode)
            )
            if r.success {
                onCompleted(r.backupCodes ?? [])
            } else {
                verifyError = "Code didn't match. Try again."
            }
        } catch {
            verifyError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Backup codes sheet

private struct BackupCodesSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let codes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Backup codes")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Save these somewhere safe — each one is single-use and grants account access if you lose your phone.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(codes, id: \.self) { c in
                    HStack {
                        Text(c)
                            .font(.system(size: 16, weight: .heavy, design: .monospaced))
                            .foregroundStyle(LinearGradient.diagonal)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
            }
            HStack(spacing: Space.s2) {
                Button {
                    UIPasteboard.general.string = codes.joined(separator: "\n")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill").font(.system(size: 11, weight: .heavy))
                        Text("Copy all").font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1))
                }.buttonStyle(.plain)
                ShareLink(item: codes.joined(separator: "\n")) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .heavy))
                        Text("Share").font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .background(palette.bgPrimary)
    }
}

#Preview("345 · 2FA · Night") { TwoFactorManageScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("345 · 2FA · Afternoon") { TwoFactorManageScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
