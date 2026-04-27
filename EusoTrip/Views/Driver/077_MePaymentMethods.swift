//
//  077_MePaymentMethods.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · payment methods)
//
//  Screen 077 · Me · Payment Methods — the driver's EusoWallet payout
//  + card-on-file management surface. Two buckets (cards / banks) in
//  one scrollable list, per-row default badge, tap to set default,
//  long-press / trailing trash to unlink. An "Add method" CTA opens
//  the existing AddPaymentAccountSheet (Plaid + Stripe side-by-side).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Every row comes from the live `payments.getPaymentMethods`
//      tRPC procedure — MCP-verified at
//      `frontend/server/routers/payments.ts:323`. Server reads the
//      driver's Stripe Customer, pulls both `card` and
//      `us_bank_account` payment methods, and stamps `isDefault`
//      against whichever is wired as the invoice default.
//
//    • Mutations (`setDefault`, `unlink`) round-trip through real
//      Stripe via `payments.setDefaultMethod` + `deletePaymentMethod`.
//      Optimistic updates reconcile against server truth on failure
//      — no fire-and-forget silent drops.
//
//    • Empty state is server-confirmed. A driver with no Stripe
//      Customer yet (brand-new account, hasn't linked a bank or
//      attached a card) gets the "Add a payout method" hero — which
//      CTAs into AddPaymentAccountSheet where Plaid + Stripe flows
//      already live.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on default chips + the "Add method"
//         CTA. Brand.warning on destructive (unlink) confirmation.
//    §4   Tokenized spacing, radii, type. No magic numbers.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in AnyShapeStyle.
//    §10  Previews compile — store lands in `.error` under the no-
//         baseURL runtime. No fixtures.
//

import SwiftUI

// MARK: - Screen root

struct MePaymentMethods: View {
    @Environment(\.palette) var palette
    @StateObject private var store = PaymentMethodsStore()
    @State private var showAddSheet: Bool = false
    @State private var pendingUnlink: PaymentsAPI.PaymentMethod?
    @State private var lastToast: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                switch store.state {
                case .loading:
                    skeleton
                case .empty:
                    emptyHero
                case .error(let e):
                    errorBanner(e)
                case .loaded(let rows):
                    if let defaultRow = rows.first(where: \.isDefault) {
                        defaultBanner(defaultRow)
                    }
                    cardsSection(rows.filter { $0.type == "card" })
                    banksSection(rows.filter { $0.type == "bank" })
                }
                addMethodCTA
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $showAddSheet, onDismiss: {
            // Coming back from Add-Account — re-fetch so the new
            // method lands in the list without a pull-to-refresh.
            Task { await store.refresh() }
        }) {
            AddPaymentAccountSheet(onLinked: {
                showAddSheet = false
                Task { await store.refresh() }
            })
            .eusoSheetX()
        }
        .alert(
            pendingUnlink.map { $0.type == "card" ? "Unlink card?" : "Unlink bank?" } ?? "Unlink?",
            isPresented: Binding(
                get: { pendingUnlink != nil },
                set: { if !$0 { pendingUnlink = nil } }
            ),
            presenting: pendingUnlink
        ) { row in
            Button("Unlink", role: .destructive) {
                Task {
                    await store.unlink(id: row.id)
                    flashToast("Method unlinked")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { row in
            if row.type == "card" {
                Text("This removes \(row.brand ?? "the card") ••\(row.last4). Payouts will fall back to your default bank.")
            } else {
                Text("This removes \(row.bankName ?? "the bank") ••\(row.last4). Payouts will pause until you pick another default.")
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = lastToast {
                toastView(toast)
                    .padding(.bottom, Space.s6)
                    .padding(.horizontal, Space.s4)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Payment Methods")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Cards · bank accounts · payout default")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.4))
                .frame(height: 84)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 72)
            }
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "creditcard",
            title: "No payment methods yet",
            subtitle: "Link a bank through Plaid for ACH payouts, or attach a card via Stripe. Your credentials never touch EusoTrip's servers."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load payment methods")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Default banner

    private func defaultBanner(_ row: PaymentsAPI.PaymentMethod) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: row.type == "card" ? "creditcard.fill" : "building.columns.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(LinearGradient.diagonal)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("PAYOUTS DEFAULT")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                Text(rowTitle(row))
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(rowSubtitle(row))
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Sections

    @ViewBuilder
    private func cardsSection(_ rows: [PaymentsAPI.PaymentMethod]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("CARDS")
                        .font(EType.micro).tracking(1.4)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(rows.count)")
                        .font(EType.micro).tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(spacing: Space.s2) {
                    ForEach(rows) { row in
                        methodRow(row)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func banksSection(_ rows: [PaymentsAPI.PaymentMethod]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("BANKS")
                        .font(EType.micro).tracking(1.4)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(rows.count)")
                        .font(EType.micro).tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(spacing: Space.s2) {
                    ForEach(rows) { row in
                        methodRow(row)
                    }
                }
            }
        }
    }

    private func methodRow(_ row: PaymentsAPI.PaymentMethod) -> some View {
        let isMutating = store.mutatingId == row.id
        return HStack(spacing: Space.s3) {
            Image(systemName: row.type == "card" ? "creditcard" : "building.columns")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(row.isDefault ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textSecondary))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(palette.bgCard.opacity(0.8))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(row))
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(rowSubtitle(row))
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            if isMutating {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else if row.isDefault {
                Text("DEFAULT")
                    .font(EType.micro).tracking(1.1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            } else {
                Menu {
                    Button {
                        Task {
                            await store.setDefault(id: row.id)
                            flashToast("Default payout method updated")
                        }
                    } label: {
                        Label("Set as default", systemImage: "star")
                    }
                    Button(role: .destructive) {
                        pendingUnlink = row
                    } label: {
                        Label("Unlink", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(palette.bgCard.opacity(0.8))
                        )
                }
                .menuStyle(.button)
                .accessibilityLabel("Manage \(rowTitle(row))")
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(row.isDefault ? Color.white.opacity(0.25) : palette.borderFaint, lineWidth: 1)
        )
    }

    // MARK: Add CTA

    private var addMethodCTA: some View {
        Button {
            showAddSheet = true
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add a method")
                    .font(EType.bodyStrong)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Plaid / Stripe linking sheet")
    }

    // MARK: Disclosure

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("Processed by Stripe + Plaid")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("EusoTrip never stores your bank or card credentials — they live at Stripe and Plaid, both independently certified. The default method receives settlement payouts on the cadence set in Eusowallet.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Toast

    private func toastView(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LinearGradient.diagonal)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 16, y: 8)
    }

    private func flashToast(_ text: String) {
        withAnimation { lastToast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation { lastToast = nil }
            }
        }
    }

    // MARK: Row formatters

    private func rowTitle(_ row: PaymentsAPI.PaymentMethod) -> String {
        if row.type == "card" {
            let brand = row.brand?.capitalized ?? "Card"
            return "\(brand) ••\(row.last4)"
        } else {
            return "\(row.bankName ?? "Bank") ••\(row.last4)"
        }
    }

    private func rowSubtitle(_ row: PaymentsAPI.PaymentMethod) -> String {
        if row.type == "card" {
            if let exp = row.expiryDate { return "Expires \(exp)" }
            return "Card on file"
        }
        return "ACH bank · eligible for payouts"
    }
}

// MARK: - Screen wrapper

struct MePaymentMethodsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MePaymentMethods()
        } nav: {
            BottomNav(
                leading: driverNavLeading_077(),
                trailing: driverNavTrailing_077(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_077() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_077() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: true),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Previews

#Preview("077 · Me Payment Methods · Night") {
    MePaymentMethodsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("077 · Me Payment Methods · Afternoon") {
    MePaymentMethodsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
