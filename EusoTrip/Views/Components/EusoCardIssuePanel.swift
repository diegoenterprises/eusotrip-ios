//
//  EusoCardIssuePanel.swift
//  EusoTrip
//
//  Shared Stripe Treasury + Issuing surface. All role screens call the same
//  wallet.getEusoCardStatus / wallet.createEusoCard contract; server-side RBAC
//  decides who qualifies.
//

import SwiftUI

struct EusoCardIssuePanel: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    var title: String = "EusoCard"
    var subtitle: String = "Virtual card backed by EusoWallet"

    @State private var status: WalletAPI.EusoCardStatus?
    @State private var loading = true
    @State private var busy = false
    @State private var acceptedTerms = false
    @State private var actionError: String?
    @State private var issuanceIdempotencyKey = UUID().uuidString

    var body: some View {
        Group {
            if loading && status == nil {
                skeleton
            } else if let status, status.qualifying {
                panel(status)
            } else if let actionError {
                errorCard(actionError)
            } else {
                EmptyView()
            }
        }
        .task { await refresh() }
        .eusoRefreshHandler { await refresh() }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 6).fill(palette.tintNeutral.opacity(0.32)).frame(width: 120, height: 12)
            RoundedRectangle(cornerRadius: 10).fill(palette.tintNeutral.opacity(0.22)).frame(height: 54)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func panel(_ status: WalletAPI.EusoCardStatus) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient.diagonal)
                    Image(systemName: "creditcard.and.123")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                statusPill(status)
            }

            if let error = actionError ?? status.syncError {
                Text(error)
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if status.missingRequirements.isEmpty {
                cardSummary(status)
            } else {
                missingRequirements(status.missingRequirements)
            }

            recoveryControls(status)

            if status.canCreate {
                Toggle(isOn: $acceptedTerms) {
                    Text("I accept the Stripe Issuing authorized-user terms for this virtual EusoCard.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .toggleStyle(.switch)

                Link(destination: URL(string: "https://stripe.com/legal/issuing")!) {
                    Label("Review Stripe Issuing terms", systemImage: "arrow.up.right.square")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(Brand.blue)
                }

                Button {
                    Task { await createCard() }
                } label: {
                    HStack(spacing: Space.s2) {
                        if busy {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 15, weight: .heavy))
                        }
                        Text(status.setupState == "setup_required" ? "Start secure setup" : "Create EusoCard")
                            .font(EType.bodyStrong)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .foregroundStyle(Color.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busy || !acceptedTerms)
                .opacity(busy || !acceptedTerms ? 0.55 : 1)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func statusPill(_ status: WalletAPI.EusoCardStatus) -> some View {
        let label: String = {
            if let cardStatus = status.card?.status, !cardStatus.isEmpty { return cardStatus.uppercased() }
            switch status.setupState {
            case "setup_required": return "SETUP REQUIRED"
            case "ready_to_issue": return "READY TO ISSUE"
            case "onboarding_required": return "VERIFY IDENTITY"
            case "verification_pending": return "UNDER REVIEW"
            case "treasury_pending": return "ACTIVATING"
            case "needs_profile": return "PROFILE REQUIRED"
            case "not_qualified": return "UNAVAILABLE"
            case "refresh_required": return "REFRESH REQUIRED"
            default: return status.setupState.uppercased().replacingOccurrences(of: "_", with: " ")
            }
        }()
        return Text(label)
            .font(EType.micro)
            .tracking(0.6)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(LinearGradient.diagonal)
            .background(Capsule().fill(palette.bgCardSoft))
    }

    private func cardSummary(_ status: WalletAPI.EusoCardStatus) -> some View {
        VStack(spacing: 0) {
            summaryRow("Card", value: cardLabel(status.card))
            summaryRow("Treasury", value: treasuryLabel(status.treasury))
            summaryRow("Available", value: cents(status.treasury?.availableCents))
        }
        .overlay(alignment: .top) {
            Rectangle().fill(palette.iridescentHairline).frame(height: 1)
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack(spacing: Space.s3) {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: Space.s2)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.borderFaint).frame(height: 1)
        }
    }

    private func missingRequirements(_ rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Profile requirements")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                    Text(row)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
    }

    @ViewBuilder
    private func recoveryControls(_ status: WalletAPI.EusoCardStatus) -> some View {
        if status.onboardingRequired == true {
            setupCallout(
                title: "Secure setup required",
                message: "Stripe needs the account owner to finish identity and business verification before EusoCard can be issued.",
                buttonTitle: "Continue Stripe setup",
                icon: "arrow.up.right.square"
            ) {
                await resumeOnboarding()
            }
        } else if ["verification_pending", "treasury_pending", "refresh_required", "unavailable"].contains(status.setupState) {
            setupCallout(
                title: status.setupState == "treasury_pending"
                    ? "Treasury activation pending"
                    : status.setupState == "unavailable" ? "EusoCard status unavailable" : "Verification in progress",
                message: status.setupState == "treasury_pending"
                    ? "Stripe is activating the financial-account features required for card issuing."
                    : "Refresh after Stripe finishes reviewing the submitted account information.",
                buttonTitle: "Refresh status",
                icon: "arrow.clockwise"
            ) {
                await refresh()
            }
        } else if status.card?.status == "pending" || status.card?.status == "inactive" {
            setupCallout(
                title: "Card activation pending",
                message: "Stripe has the card record. Refresh to retrieve its current activation state.",
                buttonTitle: "Refresh status",
                icon: "arrow.clockwise"
            ) {
                await refresh()
            }
        }
    }

    private func setupCallout(
        title: String,
        message: String,
        buttonTitle: String,
        icon: String,
        action: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await action() }
            } label: {
                HStack(spacing: 7) {
                    if busy {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: icon)
                    }
                    Text(buttonTitle)
                        .font(EType.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(Color.white)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .opacity(busy ? 0.55 : 1)
        }
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
    }

    private func errorCard(_ error: String) -> some View {
        LifecycleCard(accentDanger: true) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s2) {
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .foregroundStyle(Brand.danger)
                    Text(error)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Retry EusoCard", systemImage: "arrow.clockwise")
                        .font(EType.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            status = try await EusoTripAPI.shared.wallet.getEusoCardStatus()
            actionError = nil
        } catch {
            actionError = friendly(error)
        }
    }

    private func createCard() async {
        guard acceptedTerms else { return }
        busy = true
        defer { busy = false }
        do {
            let fresh = try await EusoTripAPI.shared.wallet.createEusoCard(
                authorizedUserTermsAccepted: true,
                idempotencyKey: issuanceIdempotencyKey
            )
            status = fresh
            actionError = nil
            if let rawURL = fresh.onboardingUrl, let url = URL(string: rawURL) {
                openURL(url)
            }
            if fresh.card?.cardId != nil {
                acceptedTerms = false
                issuanceIdempotencyKey = UUID().uuidString
            }
        } catch {
            actionError = friendly(error)
        }
    }

    private func resumeOnboarding() async {
        busy = true
        defer { busy = false }
        do {
            let link = try await EusoTripAPI.shared.wallet.createEusoCardOnboardingLink()
            actionError = nil
            if let rawURL = link.onboardingUrl, let url = URL(string: rawURL) {
                openURL(url)
            } else {
                await refresh()
            }
        } catch {
            actionError = friendly(error)
        }
    }

    private func cardLabel(_ card: WalletAPI.EusoCardStatus.Card?) -> String {
        guard let card else { return "Not issued" }
        let brand = card.brand?.capitalized ?? "Virtual"
        if let last4 = card.last4, !last4.isEmpty {
            return "\(brand) \(String(repeating: "*", count: 4))\(last4)"
        }
        return card.status?.capitalized ?? "Pending"
    }

    private func treasuryLabel(_ treasury: WalletAPI.EusoCardStatus.Treasury?) -> String {
        guard let treasury else { return "Not opened" }
        if let bankLast4 = treasury.bankLast4, !bankLast4.isEmpty {
            return "Bank \(String(repeating: "*", count: 4))\(bankLast4)"
        }
        return treasury.status?.capitalized ?? treasury.financialAddressStatus?.capitalized ?? "Pending"
    }

    private func cents(_ cents: Int?) -> String {
        guard let cents else { return "Unavailable" }
        return (Double(cents) / 100).formatted(.currency(code: "USD"))
    }

    private func friendly(_ error: Error) -> String {
        let raw = (error as NSError).localizedDescription
        return raw.isEmpty ? "EusoCard is unavailable right now." : raw
    }
}
