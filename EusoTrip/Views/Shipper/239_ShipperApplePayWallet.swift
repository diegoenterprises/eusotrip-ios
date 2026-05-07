//
//  239_ShipperApplePayWallet.swift
//  EusoTrip iOS — Shipper Apple Pay / PassKit / Wallet authoring
//                 (§35.3 Arc L)
//
//  iOS twin of:
//    /Users/diegousoro/Desktop/EusoTrip 2027 UI Wireframes/02 Shipper/Code/
//    239_ShipperApplePayWallet.swift
//
//  Surface: per-load Wallet pickup-credential pass + per-card Apple Pay
//  authoring. Ninth Arc L brick after 231→232→233→234→235→236→237→238.
//  Hero = active `.pkpass` for the MATRIX-50 row 1 pickup window
//  (LD-260427-A38FB12C7E · Houston→Dallas · MC-306 Gasoline UN1203 ·
//  $1,900). Tapping "Add to Wallet" fires PKAddPassesViewController.
//  Two cards below: passes-in-Wallet (3 rows mapping to MATRIX-50 rows
//  1/2/3) and Apple Pay methods (Visa default + Amex backup, both on
//  the Eusorone Technologies merchant account).
//
//  §11 Diego canon · §11.2/§11.4 MATRIX-50 lane canon all anchored.
//  Doctrine: §2 nav, §3 numbers-first, §4.3 single hairline, §7 breathe
//  density, §17.2 width-locked status grammar, §19.2 file-scoped helpers
//  (GradientPassHeader, GradientCapsuleCTA, DecorativeQRGrid,
//  TierLetterBadge, LDTile, WalletStatusPill, PassRow, PaymentCardRow), §20.4
//  no dead buttons, §22.2 counter eyebrow color encodes screen-status,
//  §35.3 Arc L iOS-platform integration surfaces.
//
//  Backend (server) endpoints owed (EUSO-2160):
//    wallet.listPaymentMethods           -> [PaymentMethod]
//    wallet.generatePassFor(loadId)      -> URL (signed .pkpass)
//    wallet.recordPaymentEvent(loadId, paymentMethodId, amount)
//    wallet.getPassReleaseQueue          -> [QueueEntry]
//
//  iOS API surface (consumed by LiveDataStore):
//    ShipperWalletAPI.currentPasses()           -> [WalletPass]
//    ShipperWalletAPI.generatePass(forLoadId:)  -> Result<URL, Error>
//    ShipperWalletAPI.addToWallet(passUrl:)      -> PKAddPassesViewController
//    ShipperWalletAPI.paymentMethods()           -> [PaymentMethod]
//    ShipperWalletAPI.setDefaultMethod(_:)
//
//  iOS framework binding:
//    PassKit (PKPass / PKPassLibrary / PKAddPassesViewController) +
//    Apple Pay (PKPaymentRequest / PKPaymentAuthorizationViewController).
//    Each .pkpass is signed against the Eusorone PassKit certificate
//    and carries: serialNumber = LD-id, primaryFields = lane,
//    secondaryFields = ETA, auxiliaryFields = carrier + escrow,
//    barcodes[0].message = "eusotrip://load/LD-..." for gate-scanner
//    verification.
//
//  Both #Preview blocks (Dark + Light) ship per §11.4 doctrine.
//

import SwiftUI

// MARK: - Screen

struct ShipperApplePayWallet: View {
    @Environment(\.palette) var palette
    @Environment(\.openURL) private var openURL

    /// Inline QR payload, set when `EusoWalletPassService` falls back
    /// to the no-pkpass branch. The hero pickup card swaps from the
    /// decorative grid to a live `EusoQRView` whenever this is non-nil.
    @State var inlineQrPayload: String? = nil
    /// 5-digit fallback code shown next to the QR for the "type-it"
    /// path when the gate scanner can't read the QR (camera issue,
    /// glare, rooted device with no camera permission).
    @State var inlineShortCode: String? = nil
    /// Inline banner — shown after every Add-to-Wallet attempt so the
    /// user always knows the result. Auto-clears after 4 s.
    @State var passBannerText: String? = nil
    @State var passBannerKind: WalletBannerKind = .info

    enum WalletBannerKind { case success, info, error }

    private let counterEyebrow = "3 PASSES · 1 ACTIVE"

    private let activePass = ActiveWalletPass(
        id:                "pass_LD-260427-A38FB12C7E",
        issuerLine:        "EUSORONE TECHNOLOGIES",
        title:             "Pickup Credential",
        loadId:            "LD-260427-A38FB12C7E",
        lane:              "Houston \u{2192} Dallas",
        eta:               "Apr 30 · in 4h 12m",
        equipment:         "MC-306 · UN1203 · Gas",
        carrierLine:       "Bulk Logistics · MC-1485",
        escrowLine:        "Escrow funded · $1,900",
        carrierTier:       "A",
        ctaLabel:          "Add to Wallet"
    )

    private let passes: [WalletPass] = [
        WalletPass(
            id:           "LD-260427-A38FB12C7E",
            tilePrefix:   "A3",
            lane:         "Houston \u{2192} Dallas",
            spec:         "MC-306 Gasoline UN1203 · 47k lb · $1,900",
            installedNote:"in Wallet",
            status:       .active
        ),
        WalletPass(
            id:           "LD-260427-7C3A09F18B",
            tilePrefix:   "7C",
            lane:         "Los Angeles \u{2192} Phoenix",
            spec:         "53' Reefer · fresh berries 33-38°F · $2,200",
            installedNote:"in Wallet",
            status:       .inTransit
        ),
        WalletPass(
            id:           "LD-260427-B41782FF02",
            tilePrefix:   "B4",
            lane:         "Kansas City \u{2192} Omaha",
            spec:         "MC-331 NH\u{2083} UN1005 · escort · $3,200",
            installedNote:"in Wallet",
            status:       .escort
        )
    ]

    private let activePassId: String = "LD-260427-A38FB12C7E"

    private let paymentMethods: [PaymentMethod] = [
        PaymentMethod(
            id:        "card_visa_4737",
            brand:     .visa,
            maskedPAN: "Visa \u{2022}\u{2022}\u{2022}\u{2022} 4737",
            spec:      "Eusorone Technologies · default · expires 09/28",
            tag:       .defaultMethod
        ),
        PaymentMethod(
            id:        "card_amex_7211",
            brand:     .amex,
            maskedPAN: "Amex \u{2022}\u{2022}\u{2022}\u{2022} 7211",
            spec:      "Eusorone Technologies · backup · expires 03/29",
            tag:       .backup
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, Space.s5)
            titleBlock
                .padding(.top, Space.s3)

            IridescentHairline()
                .padding(.top, Space.s3)

            sectionLabel("ACTIVE PASS · MATRIX-50 ROW 1")
                .padding(.top, Space.s5)
            heroPassCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            sectionLabel("PASSES · 3 IN WALLET")
                .padding(.top, Space.s5)
            passesCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            sectionLabel("APPLE PAY · 2 METHODS")
                .padding(.top, Space.s5)
            paymentMethodsCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            settingsPointerLink
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)

            footer
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s5)
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\u{2726} SHIPPER · WALLET")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel("Three Apple Wallet passes installed. One is currently the active pickup credential.")
        }
        .padding(.horizontal, Space.s5)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Wallet")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Apple Pay · Eusorone Technologies")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s5)
    }

    // MARK: - HERO PASS CARD (active Wallet pass)

    private var heroPassCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )

            VStack(alignment: .leading, spacing: 0) {
                GradientPassHeader(
                    issuerLine: activePass.issuerLine,
                    title:      activePass.title
                )

                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("LOAD ID")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, 12)

                        Text(activePass.loadId)
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(LinearGradient.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .padding(.top, 4)

                        Text("LANE")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, 12)

                        Text(activePass.lane)
                            .font(.system(size: 20, weight: .heavy))
                            .tracking(-0.3)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .padding(.top, 4)

                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ETA")
                                    .font(.system(size: 8, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(palette.textTertiary)
                                Text(activePass.eta)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                    .monospacedDigit()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("EQUIPMENT")
                                    .font(.system(size: 8, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(palette.textTertiary)
                                Text(activePass.equipment)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                            }
                        }
                        .padding(.top, 12)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Spacer()
                        // Real QR code via the shared EusoQR primitive.
                        // Encodes a role-aware deeplink to the load
                        // credential, plus the 5-digit fallback code
                        // visible underneath when `inlineShortCode`
                        // is populated. Founder mandate 2026-05-06 —
                        // every QR surface needs to actually work.
                        VStack(alignment: .trailing, spacing: 6) {
                            EusoQRView(
                                kind: .loadCredential(
                                    loadId: activePass.loadId,
                                    mode: .credential
                                ),
                                role: .shipper,
                                size: 92,
                                cornerRadius: 8
                            )
                            if let code = inlineShortCode {
                                Text(code)
                                    .font(EType.mono(.micro)).tracking(2.0)
                                    .foregroundStyle(palette.textPrimary)
                            }
                        }
                        .padding(.top, 12)
                        .padding(.trailing, 20)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                HStack(alignment: .center, spacing: 12) {
                    TierLetterBadge(letter: activePass.carrierTier)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activePass.carrierLine)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(activePass.escrowLine)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(LinearGradient.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer(minLength: 0)

                    Button(action: tapAddToWallet) {
                        GradientCapsuleCTA(label: activePass.ctaLabel, width: 140)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add the active pickup credential to Apple Wallet — installs a .pkpass bundle bound to LD-260427-A38FB12C7E.")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                .padding(.top, 56)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var passesCard: some View {
        VStack(spacing: 0) {
            ForEach(passes.indices, id: \.self) { idx in
                PassRow(
                    pass:        passes[idx],
                    isActive:    passes[idx].id == activePassId,
                    onRowTap:    { tapPassRow(passes[idx]) }
                )
                if idx < passes.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var paymentMethodsCard: some View {
        VStack(spacing: 0) {
            ForEach(paymentMethods.indices, id: \.self) { idx in
                PaymentCardRow(
                    method:    paymentMethods[idx],
                    onRowTap:  { tapPaymentMethod(paymentMethods[idx]) }
                )
                if idx < paymentMethods.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var settingsPointerLink: some View {
        Button(action: tapManageApplePay) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage Apple Pay integration")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Per-card · per-pass settings · 211 Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\u{2192}")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Manage Apple Pay integration. Per-card and per-pass settings live in 211 Settings.")
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Powered by Apple Pay · PassKit · Wallet")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
            Text("companyId 1 · Eusorone Technologies · MATRIX-50-2026-04-26")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, Space.s5)
    }

    // MARK: - Tap handlers (§20.4 no dead buttons)

    private func tapAddToWallet() {
        NotificationCenter.default.post(
            name: .eusoShipperWalletAddPass,
            object: nil,
            userInfo: [
                "source": "239_ShipperApplePayWallet",
                "passId": activePass.id,
                "loadId": activePass.loadId,
                "carrierMC": "MC-1485",
                "shipperCompanyId": 1
            ]
        )
        // Hand off to PassKit instead of openURL'ing Safari at a
        // dead web URL. The service handles the
        //   server credential mint → .pkpass fetch → PKPass parse →
        //   PKAddPassesViewController present
        // chain, plus a graceful fallback to the inline QR + 5-digit
        // shortCode card when the .pkpass signing pipeline is offline
        // (founder report 2026-05-06 — "clicking on passes opens up
        // web browser and error screen instead of connecting to the
        // apple wallet").
        let loadId = activePass.loadId
        Task {
            let result = await EusoWalletPassService.shared.addPass(forLoadId: loadId)
            await MainActor.run { applyPassResult(result) }
        }
    }

    private func tapPassRow(_ pass: WalletPass) {
        NotificationCenter.default.post(
            name: .eusoShipperWalletPassRow,
            object: nil,
            userInfo: [
                "source": "239_ShipperApplePayWallet",
                "passId": pass.id,
                "loadId": pass.id,
                "isActivePass": pass.id == activePassId,
                "shipperCompanyId": 1
            ]
        )
        // Tapping any pass row in the list also routes to the same
        // PassKit flow — every pass should add to Apple Wallet, not
        // open Safari.
        let loadId = pass.id
        Task {
            let result = await EusoWalletPassService.shared.addPass(forLoadId: loadId)
            await MainActor.run { applyPassResult(result) }
        }
    }

    /// Apply the result of `EusoWalletPassService.addPass` to local
    /// state. `presented` needs no UI work — the system Apple Wallet
    /// sheet is already up. The other two cases drive an inline
    /// banner so the user always knows what happened (no silent
    /// failures, per the no-dead-buttons doctrine).
    @MainActor
    private func applyPassResult(_ result: EusoWalletPassResult) {
        switch result {
        case .presented:
            passBannerKind = .success
            passBannerText = "Pass added to Apple Wallet"
        case .signingUnavailable(let qrPayload, let shortCode):
            passBannerKind = .info
            passBannerText = "Wallet signing offline — show the in-app QR + code \(shortCode) at the gate."
            inlineQrPayload = qrPayload
            inlineShortCode = shortCode
        case .failure(let message):
            passBannerKind = .error
            passBannerText = message
        }
        // Auto-clear after 4s so the banner doesn't linger.
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run { passBannerText = nil }
        }
    }

    private func tapPaymentMethod(_ method: PaymentMethod) {
        NotificationCenter.default.post(
            name: .eusoShipperWalletPaymentMethod,
            object: nil,
            userInfo: [
                "source": "239_ShipperApplePayWallet",
                "paymentMethodId": method.id,
                "brand": method.brand.rawValue,
                "isDefault": method.tag == .defaultMethod,
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/wallet/method/\(method.id)") {
            openURL(url)
        }
    }

    private func tapManageApplePay() {
        NotificationCenter.default.post(
            name: .eusoShipperWalletManage,
            object: nil,
            userInfo: [
                "source": "239_ShipperApplePayWallet",
                "targetScreen": "211 Settings",
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/settings/wallet") {
            openURL(url)
        }
    }
}

// MARK: - Domain models (file-scoped — wired by LiveDataStore from
//          ShipperWalletAPI.currentPasses() + wallet.listPaymentMethods)

private struct ActiveWalletPass {
    let id:          String
    let issuerLine:  String
    let title:       String
    let loadId:      String
    let lane:        String
    let eta:         String
    let equipment:   String
    let carrierLine: String
    let escrowLine:  String
    let carrierTier: String
    let ctaLabel:    String
}

private enum WalletPassStatus {
    case active
    case inTransit
    case escort

    var label: String {
        switch self {
        case .active:    return "ACTIVE"
        case .inTransit: return "IN TRANSIT"
        case .escort:    return "ESCORT"
        }
    }

    var pillWidth: CGFloat {
        switch self {
        case .active:    return 60
        case .inTransit: return 78
        case .escort:    return 60
        }
    }
}

private struct WalletPass: Identifiable {
    let id:            String
    let tilePrefix:    String
    let lane:          String
    let spec:          String
    let installedNote: String
    let status:        WalletPassStatus
}

private enum PaymentBrand: String {
    case visa = "VISA"
    case amex = "AMEX"
}

private enum PaymentTag: Equatable {
    case defaultMethod
    case backup

    var label: String {
        switch self {
        case .defaultMethod: return "DEFAULT"
        case .backup:        return "BACKUP"
        }
    }
}

private struct PaymentMethod: Identifiable {
    let id:        String
    let brand:     PaymentBrand
    let maskedPAN: String
    let spec:      String
    let tag:       PaymentTag
}

// MARK: - GradientPassHeader (40pt Apple Wallet pass-issuer header strip
//          — gradient diagonal fill, white issuer line + title + Apple
//          Pay "Pay" capsule on the right)

private struct GradientPassHeader: View {
    let issuerLine: String
    let title:      String

    var body: some View {
        ZStack(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius:     Radius.lg,
                bottomLeadingRadius:  0,
                bottomTrailingRadius: 0,
                topTrailingRadius:    Radius.lg,
                style: .continuous
            )
            .fill(LinearGradient.diagonal)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(issuerLine)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(Color.white.opacity(0.85))
                    Text(title)
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.3)
                        .foregroundStyle(.white)
                }
                Spacer()
                ZStack {
                    Capsule().fill(Color.white.opacity(0.18))
                    Text("Pay")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(issuerLine) — \(title) — Apple Pay")
    }
}

// MARK: - GradientCapsuleCTA (140×22 hero CTA — 234/235/236/237/238 recipe)

private struct GradientCapsuleCTA: View {
    let label: String
    let width: CGFloat

    var body: some View {
        ZStack {
            Capsule().fill(LinearGradient.primary)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 8)
        }
        .frame(width: width, height: 22)
    }
}

// MARK: - DecorativeQRGrid (90×90 pseudo-QR with 3 position markers +
//          module pattern. Decorative — production renders a real QR
//          via CIQRCodeGenerator from "eusotrip://load/LD-...")

private struct DecorativeQRGrid: View {
    @Environment(\.palette) var palette

    private let modules: [(CGFloat, CGFloat)] = [
        (32,6),(38,6),(44,6),(56,6),
        (32,12),(50,12),(56,12),
        (38,18),(44,18),(56,18),
        (32,24),(44,24),(50,24),
        (6,32),(18,32),(32,32),(44,32),(56,32),(68,32),(80,32),
        (12,38),(24,38),(38,38),(50,38),(62,38),(74,38),
        (6,44),(18,44),(32,44),(44,44),(56,44),(68,44),(80,44),
        (12,50),(24,50),(38,50),(50,50),(62,50),(74,50),
        (32,56),(44,56),(56,56),(68,56),(80,56),
        (38,64),(50,64),(62,64),(74,64),
        (32,70),(50,70),(56,70),(68,70),(80,70),
        (38,76),(44,76),(62,76),(74,76),
        (32,82),(44,82),(56,82),(68,82),(80,82)
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white)

            positionMarker(at: CGPoint(x: 6, y: 6))
            positionMarker(at: CGPoint(x: 64, y: 6))
            positionMarker(at: CGPoint(x: 6, y: 64))

            ForEach(modules.indices, id: \.self) { idx in
                let p = modules[idx]
                Rectangle()
                    .fill(Color(red: 0.05, green: 0.07, blue: 0.09))
                    .frame(width: 3, height: 3)
                    .offset(x: p.0, y: p.1)
            }
        }
        .frame(width: 90, height: 90)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func positionMarker(at p: CGPoint) -> some View {
        let mark = Color(red: 0.05, green: 0.07, blue: 0.09)
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(mark)
                .frame(width: 20, height: 20)
            Rectangle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .offset(x: 3, y: 3)
            Rectangle()
                .fill(mark)
                .frame(width: 8, height: 8)
                .offset(x: 6, y: 6)
        }
        .offset(x: p.x, y: p.y)
    }
}

// MARK: - TierLetterBadge (24×24 — 233 catalyst-grade recipe at
//          compact pass-band scale)

private struct TierLetterBadge: View {
    let letter: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient.primary)
            Text(letter)
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel("Catalyst tier \(letter)")
    }
}

// MARK: - LDTile (36×36 — 237/238 InitialsTile recipe, semantic pivot to
//          "active pass")

private struct LDTile: View {
    @Environment(\.palette) var palette
    let prefix: String
    let active: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(active
                      ? AnyShapeStyle(LinearGradient.primary)
                      : AnyShapeStyle(palette.textPrimary.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(active
                                      ? Color.clear
                                      : palette.borderFaint)
                )
            Text(prefix)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(active
                                 ? AnyShapeStyle(Color.white)
                                 : AnyShapeStyle(palette.textTertiary))
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

// MARK: - WalletStatusPill (60×18 gradient or 78×18 outlined — per-pass status)

private struct WalletStatusPill: View {
    @Environment(\.palette) var palette
    let status: WalletPassStatus

    var body: some View {
        ZStack {
            if status == .active {
                Capsule().fill(LinearGradient.primary)
            } else {
                Capsule()
                    .strokeBorder(palette.textPrimary.opacity(0.20),
                                  lineWidth: 1)
            }
            Text(status.label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(status == .active
                                 ? AnyShapeStyle(Color.white)
                                 : AnyShapeStyle(palette.textSecondary))
        }
        .frame(width: status.pillWidth, height: 18)
    }
}

// MARK: - PassRow (per-pass row — LD-tile + lane + italic spec + mono
//          LD-id + status pill; active variant gets gradient wash)

private struct PassRow: View {
    @Environment(\.palette) var palette
    let pass:        WalletPass
    let isActive:    Bool
    let onRowTap:    () -> Void

    var body: some View {
        Button(action: onRowTap) {
            ZStack(alignment: .leading) {
                if isActive {
                    LinearGradient.primary
                        .opacity(0.12)
                }

                HStack(alignment: .center, spacing: 12) {
                    if isActive {
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 6, height: 6)
                            .padding(.leading, 4)
                    } else {
                        Color.clear.frame(width: 10, height: 6)
                    }

                    LDTile(prefix: pass.tilePrefix, active: isActive)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pass.lane)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(isActive
                                             ? AnyShapeStyle(LinearGradient.primary)
                                             : AnyShapeStyle(palette.textPrimary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(pass.spec)
                            .font(.system(size: 10).italic())
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text("\(pass.id) · \(pass.installedNote)")
                            .font(EType.mono(.micro))
                            .tracking(0.3)
                            .foregroundStyle(isActive
                                             ? AnyShapeStyle(LinearGradient.primary)
                                             : AnyShapeStyle(palette.textTertiary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    WalletStatusPill(status: pass.status)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(pass.lane). \(pass.spec). \(pass.id), \(pass.installedNote). Status \(pass.status.label).\(isActive ? " Active pickup credential." : "")")
    }
}

// MARK: - PaymentCardRow (per-payment-method row · 32×20 card glyph +
//          masked PAN + textSecondary spec + status tag — mirrors 208's
//          larger PaymentMethod row recipe at compact-row scale)

private struct PaymentCardRow: View {
    @Environment(\.palette) var palette
    let method:    PaymentMethod
    let onRowTap:  () -> Void

    var body: some View {
        Button(action: onRowTap) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(red: 0.05, green: 0.07, blue: 0.09))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(palette.borderFaint, lineWidth: 1)
                        )
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.white.opacity(0.40))
                            .frame(height: 3)
                            .padding(.top, 5)
                        Spacer(minLength: 0)
                    }
                    Text(method.brand.rawValue)
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.top, 6)
                }
                .frame(width: 32, height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(method.maskedPAN)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(method.spec)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(method.tag.label)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(method.tag == .defaultMethod
                                     ? AnyShapeStyle(LinearGradient.primary)
                                     : AnyShapeStyle(palette.textTertiary))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(method.maskedPAN). \(method.spec). \(method.tag.label).")
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// "Add to Wallet" CTA — fires PKAddPassesViewController present
    /// sequence with a .pkpass bundle generated server-side via
    /// wallet.generatePassFor(loadId:). Payload: passId + loadId + carrierMC.
    static let eusoShipperWalletAddPass        = Notification.Name("eusoShipperWalletAddPass")

    /// Per-pass row tap — opens the per-pass edit sheet (lifecycle stage,
    /// pickup window, pass release queue position, scan-history audit).
    /// Tapping the active row re-opens the active pass in Apple Wallet
    /// via the passkit-pass: URL scheme.
    static let eusoShipperWalletPassRow        = Notification.Name("eusoShipperWalletPassRow")

    /// Per-payment-method row tap — opens the per-card edit sheet
    /// (default-card toggle, billing address, expiration, masked PAN
    /// re-tokenization). Default card opens PKPaymentAuthorizationViewController
    /// with the Eusorone merchant id pre-bound.
    static let eusoShipperWalletPaymentMethod  = Notification.Name("eusoShipperWalletPaymentMethod")

    /// "Manage Apple Pay integration" pointer link tap — routes into
    /// 211 Settings's Apple Pay card (source of truth for the per-card
    /// vector + global merchant id binding).
    static let eusoShipperWalletManage         = Notification.Name("eusoShipperWalletManage")
}

// MARK: - Shell wrapper + Shipper BottomNav (Me current)

private func shipperNavLeading() -> [NavSlot] {
    [
        NavSlot(label: "Home",  systemImage: "house.fill",   isCurrent: false),
        NavSlot(label: "Loads", systemImage: "shippingbox",  isCurrent: false),
    ]
}
private func shipperNavTrailing() -> [NavSlot] {
    [
        NavSlot(label: "Wallet", systemImage: "creditcard",   isCurrent: false),
        NavSlot(label: "Me",     systemImage: "person.fill",  isCurrent: true),
    ]
}

struct ShipperApplePayWalletScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ShipperApplePayWallet()
        } nav: {
            BottomNav(leading: shipperNavLeading(),
                      trailing: shipperNavTrailing(),
                      orbState: .idle)
        }
    }
}

// MARK: - Previews (Dark + Light per §11.4 doctrine)

#Preview("Shipper Apple Pay Wallet · Dark") {
    ShipperApplePayWalletScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
        .padding(24)
        .background(Theme.dark.bgPage)
}

#Preview("Shipper Apple Pay Wallet · Light") {
    ShipperApplePayWalletScreen(theme: Theme.light)
        .preferredColorScheme(.light)
        .padding(24)
        .background(Theme.light.bgPage)
}
