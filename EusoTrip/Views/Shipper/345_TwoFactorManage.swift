//
//  345_TwoFactorManage.swift
//  EusoTrip — Shipper · 2FA manage (Arc K).
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

private struct TwoFactorBody: View {
    @Environment(\.palette) private var palette
    @State private var status: TfaStatus? = nil
    @State private var loading = true
    @State private var actionError: String? = nil
    @State private var working: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                if loading { LifecycleCard { Text("Loading 2FA status…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let s = status { statusCard(s); ctaRow(s); backupCodesCard(s) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "key.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · TWO-FACTOR AUTH").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Two-factor authentication").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func statusCard(_ s: TfaStatus) -> some View {
        LifecycleCard(accentWarning: !s.enabled, accentGradient: s.enabled) {
            LifecycleSection(label: "STATUS", icon: s.enabled ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
            LifecycleRow(label: "Enabled",  value: s.enabled ? "Yes" : "No")
            LifecycleRow(label: "Methods",  value: (s.methods ?? []).joined(separator: ", ").isEmpty ? "—" : (s.methods ?? []).joined(separator: ", "))
            LifecycleRow(label: "Last used", value: humanISO(s.lastUsed))
        }
    }

    private func ctaRow(_ s: TfaStatus) -> some View {
        Button { Task { s.enabled ? await disable() : await enable() } } label: {
            HStack(spacing: 6) {
                if working { ProgressView().tint(.white) }
                Text(working ? "Working…" : (s.enabled ? "Disable 2FA" : "Enable 2FA"))
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(s.enabled ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(LinearGradient.diagonal))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(working)
    }

    @ViewBuilder
    private func backupCodesCard(_ s: TfaStatus) -> some View {
        if s.enabled, let n = s.backupCodesRemaining {
            LifecycleCard {
                LifecycleSection(label: "BACKUP CODES", icon: "lock.rectangle.stack")
                LifecycleRow(label: "Remaining", value: "\(n)")
                Button {
                    Task { await regenerateCodes() }
                } label: {
                    Text("Regenerate codes").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; actionError = nil
        do {
            let s: TfaStatus = try await EusoTripAPI.shared.queryNoInput("auth.tfaStatus")
            status = s
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func enable() async {
        working = true; actionError = nil
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("auth.tfaEnable", input: ["": ""] as [String: String])
            await load()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        working = false
    }

    private func disable() async {
        working = true; actionError = nil
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("auth.tfaDisable", input: ["": ""] as [String: String])
            await load()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        working = false
    }

    private func regenerateCodes() async {
        working = true
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("auth.tfaRegenerateBackupCodes", input: ["": ""] as [String: String])
            await load()
        } catch { /* surface inline */ }
        working = false
    }
}

#Preview("345 · 2FA · Night") { TwoFactorManageScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("345 · 2FA · Afternoon") { TwoFactorManageScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
