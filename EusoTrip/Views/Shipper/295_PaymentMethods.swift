//
//  295_PaymentMethods.swift
//  EusoTrip — Shipper · Wallet payment methods.
//

import SwiftUI

struct PaymentMethodsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            PaymentMethodsBody()
        } nav: {
            shipperLifecycleNav()
        }
    }
}

private struct PaymentMethodsBody: View {
    @Environment(\.palette) private var palette

    @State private var methods: [WalletPaymentMethod] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var actionMessage: String?
    @State private var actionKind: ActionKind = .info
    @State private var addingApplePay = false
    @State private var settingDefaultId: String?

    private enum ActionKind { case success, info, error }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                applePayCard
                if let actionMessage {
                    messageCard(actionMessage, kind: actionKind)
                }
                methodSection
                secureSetupButton
                disclosure
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                WalletEyebrow(glyph: .bank, text: "SHIPPER · PAYMENT RAILS")
                Text("Payment methods")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("Cards and bank rails used for EusoWallet cash-out, escrow funding, and settlement movement.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 38, height: 38)
                WalletGlyph(kind: .bank, size: 18, tint: AnyShapeStyle(Color.white), lineWidth: 1.6)
            }
        }
    }

    private var applePayCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    WalletGlyph(kind: .wallet, size: 18, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.7)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Pay")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Adds a real card through PassKit and Stripe SetupIntent. EusoTrip never stores card numbers.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button {
                Task { await addWithApplePay() }
            } label: {
                HStack(spacing: Space.s2) {
                    if addingApplePay {
                        ProgressView().tint(.white)
                    } else {
                        WalletGlyph(kind: .wallet, size: 16, tint: AnyShapeStyle(Color.white), lineWidth: 1.8)
                    }
                    Text(addingApplePay ? "Opening Apple Pay..." : "Add via Apple Pay")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(addingApplePay)
            .opacity(addingApplePay ? 0.7 : 1)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            WalletEyebrow(glyph: .pie, text: "LINKED RAILS · \(methods.count)")
            if loading {
                WalletShimmer(height: 132, radius: Radius.lg)
            } else if let loadError {
                messageCard(loadError, kind: .error)
            } else if methods.isEmpty {
                EusoEmptyState(
                    systemImage: "creditcard",
                    title: "No payment rails linked",
                    subtitle: "Add a card with Apple Pay or open the secure Stripe setup flow."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(methods.indices, id: \.self) { idx in
                        methodRow(methods[idx])
                        if idx < methods.count - 1 {
                            Rectangle()
                                .fill(palette.borderFaint)
                                .frame(height: 1)
                                .padding(.horizontal, Space.s3)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func methodRow(_ method: WalletPaymentMethod) -> some View {
        Button {
            Task { await setDefault(method) }
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    WalletGlyph(kind: method.kind == "bank" ? .bank : .coins, size: 17, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.6)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(method.institution)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text("\(method.kind.capitalized) · ••\(method.mask)\(method.isInstant ? " · instant" : "")")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 0)
                if settingDefaultId == method.id {
                    ProgressView().controlSize(.small)
                } else {
                    Text(method.isDefault ? "DEFAULT" : "SET")
                        .font(EType.micro)
                        .tracking(0.8)
                        .foregroundStyle(method.isDefault ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(method.isDefault || settingDefaultId != nil)
        .accessibilityLabel("\(method.institution), ending \(method.mask), \(method.isDefault ? "default" : "not default")")
    }

    private var secureSetupButton: some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "296"])
        } label: {
            HStack(spacing: Space.s3) {
                WalletGlyph(kind: .bank, size: 17, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.6)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open secure setup")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Stripe-hosted card and ACH setup")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                WalletGlyph(kind: .chevron, size: 12, tint: AnyShapeStyle(palette.textTertiary), lineWidth: 1.5)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md, intensity: .standard)
        }
        .buttonStyle(.plain)
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Security")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("Apple Pay tokens go to Stripe; bank credentials stay with Plaid or Stripe. EusoTrip stores only verified method references and masked display fields.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .whisper)
    }

    private func messageCard(_ text: String, kind: ActionKind) -> some View {
        let color: Color = kind == .success ? Brand.success : kind == .error ? Brand.danger : palette.textSecondary
        return HStack(alignment: .top, spacing: Space.s2) {
            WalletGlyph(kind: .pulse, size: 14, tint: AnyShapeStyle(color), lineWidth: 1.5)
                .padding(.top, 2)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(kind == .error ? Brand.danger : palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md, intensity: .standard)
    }

    @MainActor
    private func addWithApplePay() async {
        guard !addingApplePay else { return }
        addingApplePay = true
        actionMessage = nil
        let outcome = await EusoWalletApplePayProvider.shared.addCard()
        switch outcome {
        case .added(_, let brand, let last4):
            actionKind = .success
            actionMessage = "Apple Pay card added\(brand.map { " · \($0.capitalized)" } ?? "")\(last4.map { " ••\($0)" } ?? "")."
            await load()
        case .cancelled:
            actionKind = .info
            actionMessage = "Apple Pay was cancelled. No card was added."
        case .failed(let error):
            actionKind = .error
            actionMessage = error
        }
        addingApplePay = false
    }

    @MainActor
    private func setDefault(_ method: WalletPaymentMethod) async {
        guard !method.isDefault, settingDefaultId == nil else { return }
        settingDefaultId = method.id
        actionMessage = nil
        struct Ack: Decodable { let success: Bool; let payoutMethodId: String; let updatedAt: String? }
        struct In: Encodable { let payoutMethodId: String }
        do {
            let _: Ack = try await EusoTripAPI.shared.mutation("wallet.setDefaultPayoutMethod", input: In(payoutMethodId: method.id))
            methods = methods.map {
                WalletPaymentMethod(
                    id: $0.id,
                    kind: $0.kind,
                    institution: $0.institution,
                    mask: $0.mask,
                    isDefault: $0.id == method.id,
                    isInstant: $0.isInstant,
                    addedAt: $0.addedAt
                )
            }
            actionKind = .success
            actionMessage = "\(method.institution) is now the default rail."
            await load()
        } catch {
            actionKind = .error
            actionMessage = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        settingDefaultId = nil
    }

    @MainActor
    private func load() async {
        loading = true
        loadError = nil
        do {
            let response = try await EusoTripAPI.shared.walletExtras.listPaymentMethods()
            methods = response.items
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("295 · Payment methods · Night") {
    PaymentMethodsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}

#Preview("295 · Payment methods · Afternoon") {
    PaymentMethodsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
