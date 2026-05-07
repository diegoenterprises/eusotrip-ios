//
//  309_WalletPass.swift
//  EusoTrip — Shipper · Add to Apple Wallet (Arc H).
//

import SwiftUI
import PassKit

struct WalletPassScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { WalletPassBody(loadId: loadId) } nav: { shipperLifecycleNav() }
    }
}

private struct PassUrl: Decodable, Hashable {
    let url: String
    let expiresAt: String?
}

private struct WalletPassBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State private var pass: PassUrl? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Generating Wallet pass…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let p = pass { passCard(p) }
                else { LifecycleCard { Text("Wallet pass signing not yet on this deploy.").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wallet.pass.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · APPLE WALLET").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Add BOL to Wallet").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Generates a signed `.pkpass` for the BOL. Driver scans the QR code at the gate.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func passCard(_ p: PassUrl) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "PASS READY", icon: "checkmark.shield.fill")
            LifecycleRow(label: "Expires at", value: humanISO(p.expiresAt))
            Button {
                openPass(p.url)
            } label: {
                Text("Add to Wallet").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    private func openPass(_ url: String) {
        guard let u = URL(string: url) else { return }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: u),
               let pkPass = try? PKPass(data: data),
               let vc = PKAddPassesViewController(pass: pkPass) {
                await MainActor.run {
                    UIApplication.shared.connectedScenes
                        .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
                        .first?.present(vc, animated: true)
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let loadId: Int }
        let n = Int(loadId.replacingOccurrences(of: "load_", with: "")) ?? 0
        do {
            let p: PassUrl = try await EusoTripAPI.shared.query("documents.signWalletPass", input: In(loadId: n))
            pass = p
        } catch {
            // Pass signing requires the iOS Wallet pass-type ID and
            // certificates on the server. Surface clean state.
            pass = nil
        }
        loading = false
    }
}

#Preview("309 · Wallet pass · Night") {
    WalletPassScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("309 · Wallet pass · Afternoon") {
    WalletPassScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
