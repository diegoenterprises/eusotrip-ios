//
//  WalletCardPickerView.swift
//  EusoTrip — the in-app "choose your Wallet card" screen. Binds to WalletCardStore.
//  Live preview at top, the 15 styles as a selectable grid, themed Add-to-Wallet.
//
//  TARGET: EusoTrip/Features/Wallet/WalletCardPickerView.swift
//  Logo asset: reuses the existing in-app flame brand mark — the
//  `EusoTripLogo` imageset in Assets.xcassets (the same blue→purple→magenta
//  flame the IntroSplash renders). It sits inside a white circle, matching the
//  Wallet-stack brand lockup.
//

import SwiftUI
import PassKit

struct WalletCardPickerView: View {
    @StateObject private var store = WalletCardStore()
    /// Pass the load the user is about to add a pass for (optional — omit for a pure style picker).
    var loadId: String? = nil

    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                WalletCardPreview(theme: store.selected, full: true)
                    .frame(width: 290, height: 384)
                    .padding(.top, 6)

                HStack {
                    Text("Choose your style").font(.headline)
                    Spacer()
                    Text("\(store.themes.count) styles").font(.subheadline).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(store.themes) { theme in
                        VStack(spacing: 5) {
                            WalletCardPreview(theme: theme, full: false)
                                .frame(width: 104, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13)
                                        .stroke(theme.id == store.selectedId ? Color.accentColor : .white.opacity(0.08),
                                                lineWidth: theme.id == store.selectedId ? 3 : 1)
                                )
                                .overlay(alignment: .topTrailing) {
                                    if theme.id == store.selectedId {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.white, Color.accentColor)
                                            .padding(6)
                                    }
                                }
                                .onTapGesture { store.select(theme.id) }   // ← the choose function
                            Text(theme.name).font(.caption2)
                                .foregroundStyle(theme.id == store.selectedId ? .primary : .secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(18)
        }
        .navigationTitle("Wallet card style")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let loadId {
                Button { Task { await store.addToWallet(loadId: loadId, present: present) } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wallet.pass.fill")
                        Text("Add to Apple Wallet").bold()
                    }
                    .frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.borderedProminent).tint(.black)
                .padding(.horizontal, 18).padding(.bottom, 10)
                .background(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .top) {
            if store.isSyncing { ProgressView().padding(8) }
        }
        .task { await store.load() }
        .alert("Heads up", isPresented: .constant(store.errorMessage != nil), actions: {
            Button("OK") { store.errorMessage = nil }
            Button("Retry") { store.retrySync() }
        }, message: { Text(store.errorMessage ?? "") })
    }

    // Present the PassKit sheet from the active window's root.
    private func present(_ vc: PKAddPassesViewController) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        (root.presentedViewController ?? root).present(vc, animated: true)
    }
}

// MARK: - The card preview (faithful to the HTML mockups). When the real card
//         art is bundled (WalletCardBackgrounds.xcassets, keyed on the theme id),
//         the preview renders the actual pass background so the picker shows the
//         TRUE look; otherwise it falls back to the solid color + an accent wash.
struct WalletCardPreview: View {
    let theme: WalletCardTheme
    let full: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Real bundled art when present (WalletCardBackgrounds.xcassets,
            // imageset name == theme.id), else the solid color + accent wash.
            if UIImage(named: theme.id) != nil {
                Color.clear.overlay { Image(theme.id).resizable().scaledToFill() }.clipped()
            } else {
                theme.bg
                // a hint of the art themes via an accent wash at the top
                if theme.isArt {
                    LinearGradient(colors: [theme.accent.opacity(0.35), .clear],
                                   startPoint: .topTrailing, endPoint: .center)
                }
            }
            VStack(alignment: .leading, spacing: full ? 10 : 4) {
                // HEADER — the identity that peeks in a Wallet stack
                HStack(alignment: .top) {
                    HStack(spacing: 6) {
                        Image("EusoTripLogo").resizable().scaledToFit()
                            .frame(width: full ? 22 : 14, height: full ? 22 : 14)
                            .padding(full ? 5 : 3).background(Circle().fill(.white))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("EUSOTRIP").font(.system(size: full ? 13 : 8, weight: .heavy)).kerning(1.2)
                            Text("PICKUP PASS").font(.system(size: full ? 8 : 5, weight: .bold))
                                .kerning(1.5).foregroundStyle(theme.accent)
                        }
                    }
                    Spacer()
                    if full {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("LOAD").font(.system(size: 7, weight: .bold)).opacity(0.6)
                            Text("SHP-MQESP8…").font(.system(size: 10, weight: .heavy))
                        }
                    }
                }
                Rectangle().frame(height: 2)
                    .foregroundStyle(theme.accent).opacity(0.9)
                if full {
                    HStack(alignment: .bottom) {
                        field("FROM", "Austin, TX"); Spacer()
                        Image(systemName: "arrow.right").foregroundStyle(theme.accent); Spacer()
                        field("TO", "San Antonio, TX", trailing: true)
                    }
                    Spacer()
                    HStack { field("EQUIPMENT", "HAZMAT"); Spacer(); field("GATE", "92602", trailing: true) }
                }
            }
            .foregroundStyle(theme.ink)
            .padding(full ? 14 : 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: full ? 18 : 13))
    }

    private func field(_ label: String, _ value: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            Text(label).font(.system(size: 7, weight: .bold)).opacity(0.6)
            Text(value).font(.system(size: 14, weight: .bold))
        }
    }
}

// MARK: - Registered host (ScreenRegistry / RoleSurfaceRouter)
//
// The shipper surface pushes screens by id through `.eusoShipperNavSwap`
// (RoleSurfaceRouter observes it + supplies the back chrome). This host wraps
// the pure style picker in the canonical `Shell` so it slots into the registry
// exactly like its wallet siblings (290 WalletHome / 291 EusoWalletDetail).
// Registered in ContentView; reached from the Wallet hub's "Wallet card style"
// row — a horizontal push, never a slide-up.
struct WalletCardStyleScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { WalletCardPickerView() } nav: { shipperLifecycleNav() }
    }
}
