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

struct WalletCardPickerView: View {
    /// What KIND of pass this picker mints when the bottom CTA fires.
    /// `.pickup` is the original load pickup pass; `.staffAccess` mints the
    /// themed STAFF ACCESS CARD against the caller's real `staffAccessTokens`.
    enum Mode: Equatable { case pickup, staffAccess }

    @StateObject private var store = WalletCardStore()
    /// Pass the load the user is about to add a pass for (optional — omit for a pure style picker).
    var loadId: String? = nil
    /// Which pass kind the bottom CTA mints. Defaults to the pickup pass so the
    /// shipper/driver/catalyst call sites (`WalletCardPickerView(loadId:)`) are
    /// unchanged — only the access surface passes `.staffAccess`.
    var mode: Mode = .pickup

    /// Real server-issued QR/code shown when PassKit signing is not configured.
    /// This is the same credential the pass would carry, never a local token.
    @State private var inlineFallback: WalletInlineFallback? = nil

    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    /// The eyebrow label the preview header shows ("PICKUP PASS" vs "ACCESS PASS").
    private var previewKindLabel: String {
        mode == .staffAccess ? "ACCESS PASS" : "PICKUP PASS"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                WalletCardPreview(
                    theme: store.selected,
                    full: true,
                    kindLabel: previewKindLabel,
                    load: store.previewLoad
                )
                    .frame(maxWidth: 360)
                    .aspectRatio(375.0 / 220.0, contentMode: .fit)
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
                                .frame(width: 104)
                                .aspectRatio(375.0 / 220.0, contentMode: .fit)
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
                                    } else if theme.id == store.pendingThemeId {
                                        ProgressView()
                                            .tint(.white)
                                            .padding(6)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { store.select(theme.id) }
                            Text(theme.name).font(.caption2)
                                .foregroundStyle(theme.id == store.selectedId ? .primary : .secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(18)
        }
        .navigationTitle(mode == .staffAccess ? "Access card style" : "Wallet card style")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            // The bottom CTA mints whichever pass the picker is in. Pickup mode
            // needs a load; access mode mints against the caller's real
            // staffAccessTokens (no load).
            if mode == .staffAccess {
                addCTA(title: "Add access card to Wallet") {
                    Task { await store.addAccessCardToWallet() }
                }
            } else if let loadId {
                addCTA(title: "Add to Apple Wallet") {
                    Task { await store.addToWallet(loadId: loadId) }
                }
            }
        }
        .overlay(alignment: .top) {
            if store.isSyncing { ProgressView().padding(8) }
        }
        .eusoRefreshTask { await store.load(loadId: mode == .pickup ? loadId : nil) }
        .onReceive(NotificationCenter.default.publisher(for: .eusoAccessFallbackToInlineQR)) { note in
            guard mode == .staffAccess else { return }
            let code = note.userInfo?["accessCode"] as? String ?? ""
            let qr   = note.userInfo?["qrPayload"]  as? String ?? ""
            let exp  = note.userInfo?["expiresAt"]  as? String
            inlineFallback = WalletInlineFallback(
                kind: .staffAccess,
                code: code,
                qrPayload: qr,
                expiresAt: exp
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoFallbackToInlineQR)) { note in
            guard mode == .pickup else { return }
            let code = note.userInfo?["shortCode"] as? String ?? ""
            let qr   = note.userInfo?["qrPayload"] as? String ?? ""
            let exp  = note.userInfo?["expiresAt"] as? String
            inlineFallback = WalletInlineFallback(
                kind: .pickup,
                code: code,
                qrPayload: qr,
                expiresAt: exp
            )
        }
        .sheet(item: $inlineFallback) { fallback in
            NavigationStack { WalletInlineFallbackView(fallback: fallback) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Heads up", isPresented: .constant(store.errorMessage != nil), actions: {
            Button("OK") { store.errorMessage = nil }
            if store.canRetryThemeSync {
                Button("Retry") { store.retrySync() }
            }
        }, message: { Text(store.errorMessage ?? "") })
    }

    /// Shared bottom Add-to-Wallet button — same chrome for both pass kinds.
    private func addCTA(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "wallet.pass.fill")
                Text(title).bold()
            }
            .frame(maxWidth: .infinity).frame(height: 50)
        }
        .buttonStyle(.borderedProminent).tint(.black)
        .disabled(!store.canMintSelectedTheme)
        .padding(.horizontal, 18).padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - The card preview (faithful to the HTML mockups). When the real card
//         art is bundled (WalletCardBackgrounds.xcassets, keyed on the theme id),
//         the preview renders the actual pass background so the picker shows the
//         TRUE look; otherwise it falls back to the solid color + an accent wash.
struct WalletCardPreview: View {
    let theme: WalletCardTheme
    let full: Bool
    /// The eyebrow under "EUSOTRIP" — "PICKUP PASS" by default so existing
    /// callers (the load pickup pass) are unchanged; the access surface passes
    /// "ACCESS PASS".
    var kindLabel: String = "PICKUP PASS"
    var load: WalletCardStore.PreviewLoad? = nil

    /// True when this preview is for the staff access card (drives the body
    /// fields: identity + clearance rather than a lane).
    private var isAccess: Bool { kindLabel == "ACCESS PASS" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.bg
            if let previewImage = theme.previewImage {
                switch theme.normalizedArtSlot {
                case "background":
                    Color.clear.overlay {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFill()
                            .scaleEffect(full ? 1.08 : 1.02)
                            .blur(radius: full ? 6 : 1.5)
                    }
                    .clipped()
                case "strip":
                    VStack(spacing: 0) {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: full ? 118 : 35)
                            .clipped()
                        Spacer(minLength: 0)
                    }
                case "thumbnail":
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: full ? 74 : 26, height: full ? 74 : 26)
                        .clipShape(RoundedRectangle(cornerRadius: full ? 10 : 4))
                        .padding(full ? 14 : 8)
                default:
                    EmptyView()
                }
            }
            VStack(alignment: .leading, spacing: full ? 10 : 4) {
                HStack(alignment: .top) {
                    HStack(spacing: 6) {
                        Group {
                            if let logoImage = theme.logoImage {
                                Image(uiImage: logoImage).resizable().scaledToFit()
                            } else {
                                Image("EusoTripLogo").resizable().scaledToFit()
                            }
                        }
                            .frame(width: full ? 22 : 14, height: full ? 22 : 14)
                            .padding(full ? 5 : 3).background(Circle().fill(.white))
                        Text(isAccess ? "EusoTrip · Access" : "EusoTrip · Pickup")
                            .font(.system(size: full ? 13 : 8, weight: .bold))
                    }
                    Spacer()
                    if full {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(isAccess ? "STAFF" : "LOAD").font(.system(size: 7, weight: .bold)).opacity(0.6)
                            Text(isAccess ? "—" : (load?.loadNumber ?? "—"))
                                .font(.system(size: 10, weight: .heavy))
                        }
                    }
                }
                if full {
                    if isAccess {
                        HStack(alignment: .bottom) {
                            field("STAFF", "—"); Spacer()
                            field("ROLE", "—", trailing: true)
                        }
                        Spacer()
                        HStack { field("FACILITY", "—"); Spacer(); field("GATE CODE", "—", trailing: true) }
                    } else {
                        if theme.passStyle == "eventTicket" {
                            field(
                                "LANE",
                                "\(load?.origin ?? "—") → \(load?.destination ?? "—")"
                            )
                        } else {
                            HStack(alignment: .bottom) {
                                field("FROM", load?.origin ?? "—")
                                Spacer()
                                Image(systemName: "arrow.right").foregroundStyle(theme.accent)
                                Spacer()
                                field("TO", load?.destination ?? "—", trailing: true)
                            }
                        }
                        Spacer()
                        HStack {
                            field("ETA", load?.eta ?? "—")
                            Spacer()
                            field("GATE CODE", "—", trailing: true)
                        }
                        HStack {
                            field("EQUIPMENT", load?.equipment ?? "—")
                            Spacer()
                            field("CARRIER", load?.carrier ?? "—", trailing: true)
                        }
                    }
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
                .lineLimit(2)
                .minimumScaleFactor(0.72)
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

// MARK: - Driver host (ScreenRegistry, role:.driver)
//
// Same pure `WalletCardPickerView` (role-agnostic — it just talks to the
// wallet theme procs), wrapped in the DRIVER Me-detail chrome rather than the
// shipper one. The driver Me surface pushes screens by id through
// `.eusoDriverMeNavSwap` (the host owns the back stack), so this host only
// supplies the canonical driver Me bottom bar — the same four-tab BottomNav
// with "Me" current that `driverMeHubNav()` (067A) renders for every Me leaf,
// and that 069's `MeWalletScreen` uses. `driverMeHubNav()` is file-private to
// 067A, so the chrome is mirrored here exactly (identical to how 069 keeps its
// own local nav helpers). Registered in ContentView as "WalletCardStyleDriver";
// reached from the driver Wallet hub's "Wallet card style" row — a horizontal
// push, never a slide-up.
struct DriverWalletCardStyleScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { WalletCardPickerView() } nav: { driverMeDetailNav_walletCard() }
    }
}

/// Canonical driver Me-detail bottom bar — the same four tabs the rest of the
/// driver app uses, with "Me" current. Mirrors `driverMeHubNav()` in
/// 067A_DriverMeHubs.swift (which is file-private there).
private func driverMeDetailNav_walletCard() -> BottomNav {
    BottomNav(
        leading: [
            NavSlot(label: "Home",  systemImage: "house.fill",       isCurrent: false),
            NavSlot(label: "Trips", systemImage: "shippingbox.fill", isCurrent: false),
        ],
        trailing: [
            NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
            NavSlot(label: "Me",       systemImage: "person.fill",      isCurrent: true),
        ],
        orbState: .idle
    )
}

// MARK: - Catalyst / Carrier host (ScreenRegistry, role:.catalyst)
//
// Same role-agnostic `WalletCardPickerView` (it just talks to the wallet theme
// procs), wrapped in the CATALYST chrome rather than the shipper one. Catalyst
// is aliased to the carrier surface (`RoleSurfaceRouter` renders `.catalyst`
// through `CarrierSurface`, which resolves screens out of the concatenated
// `.carrier` + `.catalyst` pool and pushes by id through `.eusoCarrierNavSwap`).
// The host therefore only supplies the canonical catalyst Wallet bottom bar —
// the SAME four-tab BottomNav (Home / Dispatch / Wallet / Me) that
// `CatalystWalletScreen` (319) renders, with "Wallet" current since this is a
// Wallet leaf. Registered in ContentView as "WalletCardStyleCatalyst"; reached
// from the catalyst Wallet hub (319) AND the carrier Earnings hub (312)
// "Wallet card style" row — a horizontal push, never a slide-up. One registered
// screen serves BOTH the catalyst and carrier surfaces (shared pool).
struct CatalystWalletCardStyleScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { WalletCardPickerView() } nav: { catalystWalletNav_walletCard() }
    }
}

/// Canonical catalyst Wallet bottom bar — the same four tabs `CatalystWalletScreen`
/// (319) uses, with "Wallet" current. Inlined here exactly (319's nav is built
/// inline in its `Shell`), matching the catalyst/carrier nav idiom.
private func catalystWalletNav_walletCard() -> BottomNav {
    BottomNav(
        leading: [
            NavSlot(label: "Home",     systemImage: "house",                  isCurrent: false),
            NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: false),
        ],
        trailing: [
            NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: true),
            NavSlot(label: "Me",     systemImage: "person",          isCurrent: false),
        ],
        orbState: .idle
    )
}

// MARK: - Real inline credential when PassKit signing is not configured

struct WalletInlineFallback: Identifiable, Equatable {
    enum Kind: String, Equatable { case pickup, staffAccess }

    let kind: Kind
    let code: String
    let qrPayload: String
    let expiresAt: String?
    var id: String { kind.rawValue + "|" + code + "|" + qrPayload }
}

struct WalletInlineFallbackView: View {
    let fallback: WalletInlineFallback
    @Environment(\.dismiss) private var dismiss

    private var isAccess: Bool { fallback.kind == .staffAccess }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(isAccess ? "Access card ready" : "Pickup credential ready")
                        .font(.headline)
                    Text(isAccess
                         ? "Show this active code or QR at the gate. It is the same verified temporary access grant."
                         : "Show this active QR or code at pickup. It is the server-issued credential for this load.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(.top, 8)

                if !fallback.qrPayload.isEmpty {
                    EusoQRView(
                        kind: .raw(text: fallback.qrPayload),
                        role: isAccess ? .terminal : .shipper,
                        size: 220
                    )
                }

                if !fallback.code.isEmpty {
                    VStack(spacing: 4) {
                        Text(isAccess ? "6-DIGIT CODE" : "GATE CODE")
                            .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                            .foregroundStyle(.secondary)
                        Text(spacedCode(fallback.code))
                            .font(.system(size: 34, weight: .heavy, design: .monospaced))
                            .tracking(4)
                    }
                }

                if let exp = fallback.expiresAt, !exp.isEmpty {
                    Text("Expires \(exp)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
        .navigationTitle(isAccess ? "Access card" : "Pickup credential")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    /// Group a 6-digit access code as "123 456"; other server code formats
    /// remain byte-for-byte intact.
    private func spacedCode(_ c: String) -> String {
        let digits = c.filter(\.isNumber)
        guard digits.count == 6 else { return c }
        let i = digits.index(digits.startIndex, offsetBy: 3)
        return "\(digits[..<i]) \(digits[i...])"
    }
}
