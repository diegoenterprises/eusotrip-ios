//
//  290_WalletHome.swift
//  EusoTrip — Shipper · Wallet home (Arc G).
//  Backed by `wallet.getBalance` (existing) + `eusoWallet.getSnapshot`
//  + `wallet.getEscrowHolds`. Em-dash sentinels everywhere.
//

import SwiftUI

struct WalletHomeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { WalletHomeBody() } nav: { shipperLifecycleNav() }
    }
}

private struct WalletBalance: Decodable, Hashable {
    let available: Double?
    let pending: Double?
    let reserved: Double?
    let escrow: Double?
    let total: Double?
    let monthVolume: Double?
    // `wallet.getBalance` also returns lifetime in/out totals; decode
    // them so the breakdown surfaces real activity when a wallet has
    // moved money. (tRPC decode ignores any field we don't list, so
    // the remaining server fields — currency/lastUpdated/stripeBalance/
    // paymentMethods — simply pass through untouched.)
    let totalReceived: Double?
    let totalSpent: Double?
}

private struct WalletHomeBody: View {
    @Environment(\.palette) private var palette
    @State private var balance: WalletBalance? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var showCashOut: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let b = balance { balanceHero(b); breakdownCard(b) }
                else if loading { LifecycleCard { Text("Loading wallet…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                quickActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .sheet(isPresented: $showCashOut) {
            ShipperCashOutSheet(
                available: balance?.available ?? 0,
                onCompleted: { Task { await load() } }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wallet.pass.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · EUSOWALLET").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("EusoWallet").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func balanceHero(_ b: WalletBalance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AVAILABLE BALANCE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(.white.opacity(0.85))
            Text(usd(b.available) == "-" ? "$0" : usd(b.available)).font(.system(size: 32, weight: .heavy)).foregroundStyle(.white).monospacedDigit()
            HStack(spacing: 8) {
                Text("MTD VOLUME \(usd(b.monthVolume))").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func breakdownCard(_ b: WalletBalance) -> some View {
        LifecycleCard {
            LifecycleSection(label: "BREAKDOWN", icon: "list.bullet")
            LifecycleRow(label: "Pending",   value: usd(b.pending))
            LifecycleRow(label: "Reserved",  value: usd(b.reserved))
            LifecycleRow(label: "Escrow",    value: usd(b.escrow))
            LifecycleRow(label: "Total",     value: usd(b.total))
            // Lifetime activity — surfaced only when real money has
            // moved. `usd` renders an honest em-dash at zero/nil, so a
            // brand-new wallet shows "-" rather than a fabricated value.
            LifecycleRow(label: "Received",  value: usd(b.totalReceived))
            LifecycleRow(label: "Spent",     value: usd(b.totalSpent))
        }
    }

    private var quickActions: some View {
        VStack(spacing: 8) {
            cashOutAction
            link(icon: "arrow.right.circle", title: "EusoWallet detail", screenId: "291")
            link(icon: "creditcard", title: "Settlements", screenId: "292")
            link(icon: "creditcard.and.123", title: "Payment methods", screenId: "295")
            link(icon: "doc.text", title: "Statements", screenId: "297")
            link(icon: "leaf", title: "Sustainability", screenId: "298")
            link(icon: "chart.bar", title: "Reports", screenId: "299")
        }
    }

    // Primary money action — opens the inline withdraw flow
    // (`wallet.requestPayout`). Gradient-accented card so the cash-out
    // entry reads as the hero action in the quick-actions stack.
    private var cashOutAction: some View {
        Button {
            showCashOut = true
        } label: {
            LifecycleCard(accentGradient: true) {
                HStack {
                    Image(systemName: "arrow.down.to.line.circle.fill").foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cash out").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Text("Withdraw to a linked bank or card").font(EType.micro).foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
        }.buttonStyle(.plain)
    }

    private func link(icon: String, title: String, screenId: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screenId])
        } label: {
            LifecycleCard {
                HStack {
                    Image(systemName: icon).foregroundStyle(LinearGradient.diagonal)
                    Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
        }.buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let b: WalletBalance = try await EusoTripAPI.shared.queryNoInput("wallet.getBalance")
            balance = b
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Cash-out sheet (inline)
//
// Real withdraw flow backed by `wallet.requestPayout`
// (EusoTripAPI.shared.walletExtras.requestPayout). Loads the shipper's
// linked payout methods via `wallet.getPayoutMethods`; if none are
// linked it shows an honest "add a payout method first" state (the
// shipper adds methods on screen 295). Amount is validated against the
// live available balance (server min $1.00). Stripe Connect only debits
// AFTER it confirms, so a thrown error means the balance is untouched —
// the server message is surfaced verbatim. On success the parent
// reloads the balance.

private struct ShipperCashOutSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let available: Double
    let onCompleted: () -> Void

    @State private var methods: [WalletPaymentMethod] = []
    @State private var methodsLoading: Bool = true
    @State private var methodsError: String? = nil
    @State private var selectedMethodId: String? = nil

    @State private var amountText: String = ""
    @State private var instant: Bool = false
    @State private var submitting: Bool = false
    @State private var errorText: String? = nil
    @State private var ack: WalletExtrasAPI.RequestPayoutAck? = nil

    private var parsedAmount: Double? {
        let cleaned = amountText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    private var selectedMethod: WalletPaymentMethod? {
        methods.first { $0.id == selectedMethodId }
    }

    private var instantAvailable: Bool { selectedMethod?.isInstant ?? false }

    private var validationError: String? {
        guard let amt = parsedAmount else { return nil }
        if amt < 1 { return "Minimum cash-out is $1." }
        if amt > available { return "Amount exceeds your available balance." }
        return nil
    }

    private var canSubmit: Bool {
        !submitting
            && selectedMethodId != nil
            && parsedAmount != nil
            && (parsedAmount ?? 0) >= 1
            && (parsedAmount ?? 0) <= available
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let ack = ack {
                    successCard(ack)
                } else if methodsLoading {
                    LifecycleCard { Text("Loading payout methods…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let me = methodsError {
                    LifecycleCard(accentDanger: true) { Text(me).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if methods.isEmpty {
                    noMethodState
                } else {
                    availableRow
                    methodPicker
                    amountField
                    speedPicker
                    if let v = validationError { inlineError(v) }
                    if let e = errorText { inlineError(e) }
                    submitButton
                }
            }
            .padding(.horizontal, 14).padding(.top, 24).padding(.bottom, 48)
        }
        .task { await loadMethods() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.to.line.circle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CASH OUT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Withdraw").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var availableRow: some View {
        LifecycleCard {
            HStack {
                Text("AVAILABLE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(usd(available) == "-" ? "$0" : usd(available)).font(EType.bodyStrong).monospacedDigit().foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var noMethodState: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Add a payout method first").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("Link a bank account or debit card on Payment methods to cash out your balance.").font(EType.caption).foregroundStyle(palette.textSecondary)
                Button {
                    dismiss()
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "295"])
                } label: {
                    Text("Go to Payment methods")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TO").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 8) {
                ForEach(methods) { m in methodOption(m) }
            }
        }
    }

    private func methodOption(_ m: WalletPaymentMethod) -> some View {
        let selected = m.id == selectedMethodId
        return Button {
            selectedMethodId = m.id
            if !m.isInstant { instant = false }
        } label: {
            LifecycleCard(accentGradient: selected) {
                HStack(spacing: 10) {
                    Image(systemName: m.kind == "bank" ? "building.columns.fill" : "creditcard.fill").foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.institution).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Text("••\(m.mask)\(m.isInstant ? " · instant" : "")").font(EType.micro).foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }.buttonStyle(.plain)
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AMOUNT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                HStack(spacing: 8) {
                    Text("$").font(.system(size: 20, weight: .heavy)).foregroundStyle(palette.textSecondary)
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 20, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button {
                        amountText = String(format: "%.2f", available)
                    } label: {
                        Text("MAX").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(LinearGradient.diagonal)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var speedPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SPEED").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                speedOption(title: "Standard", subtitle: "1–2 business days", isInstant: false)
                speedOption(title: "Instant", subtitle: instantAvailable ? "Fee applies · minutes" : "Not on this method", isInstant: true)
            }
        }
    }

    private func speedOption(title: String, subtitle: String, isInstant: Bool) -> some View {
        let selected = instant == isInstant
        let disabled = isInstant && !instantAvailable
        return Button {
            guard !disabled else { return }
            instant = isInstant
        } label: {
            LifecycleCard(accentGradient: selected && !disabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(EType.bodyStrong).foregroundStyle(disabled ? palette.textTertiary : palette.textPrimary)
                    Text(subtitle).font(EType.micro).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private func inlineError(_ text: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.danger)
                Text(text).font(EType.caption).foregroundStyle(Brand.danger)
                Spacer(minLength: 0)
            }
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if submitting { ProgressView().tint(.white) }
                else { Image(systemName: "arrow.down.to.line.circle.fill").foregroundStyle(.white) }
                Text(submitTitle).font(EType.bodyStrong).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .opacity(canSubmit ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var submitTitle: String {
        if submitting { return "Requesting…" }
        if let amt = parsedAmount, amt >= 1 { return "Cash out \(usd(amt))" }
        return "Cash out"
    }

    private func successCard(_ ack: WalletExtrasAPI.RequestPayoutAck) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(LinearGradient.diagonal)
                    Text("Cash-out requested").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Spacer()
                }
                ackRow(label: "Amount", value: moneyAck(ack.amount))
                if ack.fee > 0 { ackRow(label: "Instant fee", value: moneyAck(ack.fee)) }
                ackRow(label: "Net to you", value: moneyAck(ack.netAmount))
                ackRow(label: "Status", value: ack.status.capitalized)
                if let eta = formatEta(ack.estimatedArrival) { ackRow(label: "Estimated arrival", value: eta) }
                Button {
                    onCompleted()
                    dismiss()
                } label: {
                    Text("Done").font(EType.bodyStrong).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain).padding(.top, 2)
            }
        }
    }

    private func ackRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).font(EType.bodyStrong).monospacedDigit().foregroundStyle(palette.textPrimary)
        }
    }

    private func loadMethods() async {
        methodsLoading = true; methodsError = nil
        do {
            let response = try await EusoTripAPI.shared.walletExtras.listPaymentMethods()
            methods = response.items
            selectedMethodId = methods.first(where: { $0.isDefault })?.id ?? methods.first?.id
        } catch {
            methodsError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        methodsLoading = false
    }

    private func submit() async {
        guard canSubmit, let amt = parsedAmount, let methodId = selectedMethodId else { return }
        submitting = true; errorText = nil
        do {
            let result = try await EusoTripAPI.shared.walletExtras.requestPayout(
                amount: amt,
                payoutMethodId: methodId,
                instant: instant
            )
            ack = result
        } catch {
            // Server message verbatim — tells the shipper exactly why
            // (insufficient balance, payouts not enabled, etc.). The
            // wallet is untouched on failure.
            errorText = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
    }

    /// Full-precision money for the payout ack (`usd` rounds to whole
    /// dollars and em-dashes at zero, which would hide a sub-dollar fee).
    private func moneyAck(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }

    private func formatEta(_ iso: String?) -> String? {
        guard let iso = iso, !iso.isEmpty else { return nil }
        let iso8601 = ISO8601DateFormatter()
        if let date = iso8601.date(from: iso) {
            let out = DateFormatter(); out.dateFormat = "MMM d"
            return out.string(from: date)
        }
        let inFmt = DateFormatter(); inFmt.dateFormat = "yyyy-MM-dd"
        if let date = inFmt.date(from: String(iso.prefix(10))) {
            let out = DateFormatter(); out.dateFormat = "MMM d"
            return out.string(from: date)
        }
        return nil
    }
}

#Preview("290 · Wallet · Night") {
    WalletHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("290 · Wallet · Afternoon") {
    WalletHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
