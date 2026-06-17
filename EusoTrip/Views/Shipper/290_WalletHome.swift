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
    // the remaining server fields — lastUpdated/stripeBalance/
    // paymentMethods — simply pass through untouched.)
    let totalReceived: Double?
    let totalSpent: Double?
    // Server always returns a `currency` String ("USD"); carry it so the
    // wallet can render in the account's real currency if it ever differs.
    let currency: String?

    private enum CodingKeys: String, CodingKey {
        case available, pending, reserved, escrow, total, monthVolume
        case totalReceived, totalSpent, currency
    }

    init(from decoder: Decoder) throws {
        // Defensive decode: every field is optional and tolerated as a
        // number OR a numeric String, so a server shape drift (e.g. a
        // decimal returned as a String) can never throw and blank the
        // whole wallet. Missing/null/unparseable → nil → honest em-dash.
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        func num(_ key: CodingKeys) -> Double? {
            guard let c = c else { return nil }
            if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
            if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
            return nil
        }
        available     = num(.available)
        pending       = num(.pending)
        reserved      = num(.reserved)
        escrow        = num(.escrow)
        total         = num(.total)
        monthVolume   = num(.monthVolume)
        totalReceived = num(.totalReceived)
        totalSpent    = num(.totalSpent)
        currency      = (try? c?.decodeIfPresent(String.self, forKey: .currency)) ?? nil
    }
}

private struct WalletHomeBody: View {
    @Environment(\.palette) private var palette
    @State private var balance: WalletBalance? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var showCashOut: Bool = false

    private var isDark: Bool { palette.bgPage == Theme.dark.bgPage }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                if let b = balance {
                    balanceHero(b)
                    breakdownCard(b)
                } else if loading {
                    balanceHeroSkeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.danger)
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            Spacer(minLength: 0)
                        }
                    }
                }
                quickActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCashOut) {
            ShipperCashOutSheet(
                available: balance?.available ?? 0,
                onCompleted: { Task { await load() } }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "wallet.pass.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · EUSOWALLET").font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(LinearGradient.diagonal)
                }
                Text("EusoWallet").font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            // Iridescent brand mark — the only ornament in the header,
            // echoing the house gradient so the screen signs itself.
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 36, height: 36)
                Image(systemName: "wallet.pass.fill").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
            }
            .shadow(color: Brand.magenta.opacity(isDark ? 0.45 : 0.22), radius: 10, x: 0, y: 4)
        }
    }

    // MARK: Balance hero — volumetric brand-gradient card with depth
    //
    // Elevated from a flat one-color gradient fill to a layered surface:
    // a diagonal brand base, a radial top-left glow, a soft sheen sweep,
    // a top-rim highlight hairline, and an iridescent drop shadow so the
    // card reads as a premium "money card" floating off the page. No data
    // changed — `usd(available)` and the two real stat chips below are the
    // exact same bindings, with the honest "$0"/em-dash behaviour intact.
    private func balanceHero(_ b: WalletBalance) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AVAILABLE BALANCE")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.4)
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 0)
                if let cur = b.currency, !cur.isEmpty {
                    Text(cur.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.16)).clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.75))
                }
            }
            Text(usd(b.available) == "-" ? "$0" : usd(b.available))
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
            HStack(spacing: 8) {
                heroStat(label: "MTD VOLUME", value: usd(b.monthVolume), icon: "chart.line.uptrend.xyaxis")
                heroStat(label: "IN ESCROW", value: usd(b.escrow), icon: "lock.shield.fill")
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient.diagonal
                // Radial bloom in the top-left so the gradient has a light
                // source instead of a flat two-stop wash.
                RadialGradient(
                    colors: [.white.opacity(0.28), .clear],
                    center: .topLeading, startRadius: 0, endRadius: 320
                )
                // Soft diagonal sheen sweep across the lower-right.
                LinearGradient(
                    colors: [.clear, .white.opacity(0.10), .clear],
                    startPoint: .top, endPoint: .bottomTrailing
                )
            }
        }
        .overlay(alignment: .top) {
            // Top-rim highlight — the catch-light that gives the card glass.
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
        }
        .clipShape(shape)
        .shadow(color: Brand.blue.opacity(isDark ? 0.40 : 0.18), radius: 18, x: 0, y: 10)
        .shadow(color: Brand.magenta.opacity(isDark ? 0.28 : 0.12), radius: 22, x: 0, y: 14)
    }

    private func heroStat(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white.opacity(0.8))
                Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.9).foregroundStyle(.white.opacity(0.8))
            }
            Text(value == "-" ? "—" : value)
                .font(.system(size: 14, weight: .heavy)).monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(.white.opacity(0.14))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.75))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var balanceHeroSkeleton: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            Text("AVAILABLE BALANCE").font(.system(size: 10, weight: .heavy)).tracking(1.4).foregroundStyle(.white.opacity(0.7))
            Text("Loading…").font(.system(size: 32, weight: .heavy)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal.opacity(0.85))
        .clipShape(shape)
    }

    // MARK: Breakdown — grouped, hairline-divided, tabular-numeric card
    //
    // Same six real rows as before, now organised into a "Balance
    // composition" group (pending / reserved / escrow / total) and a
    // "Lifetime activity" group (received / spent), separated by an
    // iridescent hairline. Sits on the signature eusoCard surface (the
    // brand gradient outline + glow) instead of a flat gray box, with
    // monospaced figures right-aligned for a ledger read. Em-dash honesty
    // preserved via `usd`.
    private func breakdownCard(_ b: WalletBalance) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(label: "BALANCE COMPOSITION", icon: "chart.pie.fill")
            VStack(spacing: 10) {
                ledgerRow(label: "Pending",  value: usd(b.pending),  emphasised: false)
                ledgerRow(label: "Reserved", value: usd(b.reserved), emphasised: false)
                ledgerRow(label: "Escrow",   value: usd(b.escrow),   emphasised: false)
                ledgerRow(label: "Total",    value: usd(b.total),    emphasised: true)
            }

            iridescentDivider

            sectionHeader(label: "LIFETIME ACTIVITY", icon: "clock.arrow.circlepath")
            VStack(spacing: 10) {
                // Surfaced only when real money has moved — `usd` renders an
                // honest em-dash at zero/nil, so a brand-new wallet shows "—".
                ledgerRow(label: "Received", value: usd(b.totalReceived), tint: Brand.success)
                ledgerRow(label: "Spent",    value: usd(b.totalSpent),    tint: Brand.warning)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private func sectionHeader(label: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(LinearGradient.diagonal)
        }
    }

    private func ledgerRow(label: String, value: String, emphasised: Bool = false, tint: Color? = nil) -> some View {
        let shown = (value == "-") ? "—" : value
        let valueColor: Color = (value == "-") ? palette.textTertiary : (tint ?? palette.textPrimary)
        return HStack {
            Text(label)
                .font(emphasised ? EType.bodyStrong : EType.caption)
                .foregroundStyle(emphasised ? palette.textPrimary : palette.textSecondary)
            Spacer(minLength: Space.s2)
            Text(shown)
                .font(.system(size: emphasised ? 17 : 14, weight: emphasised ? .heavy : .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
    }

    private var iridescentDivider: some View {
        Rectangle()
            .fill(palette.iridescentHairline)
            .frame(height: 1)
            .opacity(0.6)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            cashOutAction
            sectionHeader(label: "MANAGE", icon: "square.grid.2x2.fill")
                .padding(.leading, 2).padding(.top, 4)
            VStack(spacing: 8) {
                link(icon: "arrow.right.circle.fill", title: "EusoWallet detail", subtitle: "Activity, holds, and pass", screenId: "291")
                link(icon: "creditcard.fill", title: "Settlements", subtitle: "Load payouts and invoices", screenId: "292")
                link(icon: "creditcard.and.123", title: "Payment methods", subtitle: "Linked banks and cards", screenId: "295")
                link(icon: "doc.text.fill", title: "Statements", subtitle: "Monthly account statements", screenId: "297")
                link(icon: "leaf.fill", title: "Sustainability", subtitle: "Carbon spend and offsets", screenId: "298")
                link(icon: "chart.bar.fill", title: "Reports", subtitle: "Spend and volume analytics", screenId: "299")
            }
        }
    }

    // Primary money action — opens the inline withdraw flow
    // (`wallet.requestPayout`). Full brand-gradient hero CTA so the
    // cash-out reads as the headline action under the balance, not just
    // another list row.
    private var cashOutAction: some View {
        Button {
            showCashOut = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(.white.opacity(0.18))
                    Image(systemName: "arrow.down.to.line.circle.fill")
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cash out").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                    Text("Withdraw to a linked bank or card").font(EType.micro).foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, Space.s4).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .shadow(color: Brand.blue.opacity(isDark ? 0.35 : 0.16), radius: 14, x: 0, y: 8)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func link(icon: String, title: String, subtitle: String, screenId: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screenId])
        } label: {
            HStack(spacing: 12) {
                // Tinted gradient-outlined glyph tile — replaces the bare
                // SF Symbol so each row gets a real touch target and the
                // iridescent system language carries into the list.
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(LinearGradient.diagonal)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(subtitle).font(EType.micro).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md, intensity: .whisper)
            .contentShape(Rectangle())
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
        // Robust, locale-aware monetary parse. The old `.decimal`
        // NumberFormatter parse was buggy in two ways:
        //   1) it did a LENIENT prefix parse, so "5 cats", "1.2.3" or
        //      "1e3" yielded a number that silently passed validation
        //      while the field showed something else; and
        //   2) "1,234" is genuinely AMBIGUOUS — 1234 in the US, 1.234 in
        //      a comma-decimal locale — so accepting it could withdraw a
        //      wildly wrong amount.
        // We instead constrain the input to a single, unambiguous
        // monetary number for the user's locale and reject anything else
        // (empty, negative, multiple separators, stray characters,
        // ambiguous grouping) by returning nil.
        let cleaned = amountText
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // Sign is never valid for a withdrawal amount.
        if cleaned.contains("-") || cleaned.contains("+") { return nil }

        let decimalSep = Locale.current.decimalSeparator ?? "."
        let groupSep = Locale.current.groupingSeparator ?? ","

        // Allowed characters: digits, the locale decimal separator, and the
        // locale grouping separator. Anything else (letters, "e", a second
        // symbol, whitespace inside) is rejected outright — no prefix parse.
        var allowed = CharacterSet.decimalDigits
        allowed.insert(charactersIn: decimalSep)
        allowed.insert(charactersIn: groupSep)
        if cleaned.unicodeScalars.contains(where: { !allowed.contains($0) }) { return nil }

        // At most one decimal separator.
        let decimalCount = cleaned.components(separatedBy: decimalSep).count - 1
        if decimalCount > 1 { return nil }

        // Reject ambiguous grouping: a grouping separator is only honoured
        // when it unambiguously groups thousands (no decimal present means
        // "1,234" could be either 1234 or 1.234 — we refuse it). Once the
        // user types a decimal separator the grouping is unambiguous.
        if cleaned.contains(groupSep) {
            if decimalCount == 0 { return nil }
            // Decimal present → strip grouping and reparse on a fixed,
            // period-decimal basis so the value is deterministic.
        }

        // Normalise to a canonical "1234.56" form and parse with a strict
        // Double init (no lenient prefix behaviour).
        var canonical = cleaned.replacingOccurrences(of: groupSep, with: "")
        if decimalSep != "." {
            canonical = canonical.replacingOccurrences(of: decimalSep, with: ".")
        }
        guard let value = Double(canonical), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Full available balance as a string the locale-aware `parsedAmount`
    /// can round-trip: two fraction digits, the locale decimal separator,
    /// and NO grouping separator (grouping without a decimal is rejected as
    /// ambiguous, so we omit it entirely for a deterministic value).
    private var maxAmountText: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: available)) ?? String(format: "%.2f", available)
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

    private var isDark: Bool { palette.bgPage == Theme.dark.bgPage }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line.circle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · CASH OUT").font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(LinearGradient.diagonal)
                }
                Text("Withdraw").font(.system(size: 24, weight: .heavy)).foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 34, height: 34)
                Image(systemName: "arrow.down.to.line").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
            }
            .shadow(color: Brand.magenta.opacity(isDark ? 0.45 : 0.22), radius: 9, x: 0, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var availableRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "wallet.pass.fill").font(.system(size: 10, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("AVAILABLE").font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(usd(available) == "-" ? "$0" : usd(available))
                .font(.system(size: 20, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private var noMethodState: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                Image(systemName: "creditcard.trianglebadge.exclamationmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Add a payout method first").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("Link a bank account or debit card on Payment methods to cash out your balance.").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Button {
                dismiss()
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "295"])
            } label: {
                Text("Go to Payment methods")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).padding(.top, 2)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
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
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    Image(systemName: m.kind == "bank" ? "building.columns.fill" : "creditcard.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(LinearGradient.diagonal)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.institution).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("••\(m.mask)\(m.isInstant ? " · instant" : "")").font(EType.micro).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
            }
            .padding(.horizontal, Space.s3).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md, intensity: selected ? .feature : .whisper)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AMOUNT").font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                Text("$").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(palette.textSecondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Button {
                    amountText = maxAmountText
                } label: {
                    Text("MAX").font(.system(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(LinearGradient.diagonal)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(Capsule().strokeBorder(palette.iridescentHairline, lineWidth: 1))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg, intensity: .feature)
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
            HStack(spacing: 8) {
                Image(systemName: isInstant ? "bolt.fill" : "clock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle((selected && !disabled) ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(EType.bodyStrong).foregroundStyle(disabled ? palette.textTertiary : palette.textPrimary)
                    Text(subtitle).font(EType.micro).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md, intensity: (selected && !disabled) ? .feature : .whisper)
            .contentShape(Rectangle())
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
            .padding(.vertical, 14)
            .background(LinearGradient.diagonal)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .shadow(color: Brand.blue.opacity((isDark && canSubmit) ? 0.35 : 0), radius: 14, x: 0, y: 8)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 40, height: 40)
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                }
                .shadow(color: Brand.magenta.opacity(isDark ? 0.45 : 0.2), radius: 9, x: 0, y: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cash-out requested").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("On its way to your linked method").font(EType.micro).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            iridescentDivider
            VStack(spacing: 10) {
                ackRow(label: "Amount", value: moneyAck(ack.amount))
                if ack.fee > 0 { ackRow(label: "Instant fee", value: moneyAck(ack.fee)) }
                ackRow(label: "Net to you", value: moneyAck(ack.netAmount), emphasised: true)
                ackRow(label: "Status", value: ack.status.capitalized)
                if let eta = formatEta(ack.estimatedArrival) { ackRow(label: "Estimated arrival", value: eta) }
            }
            Button {
                onCompleted()
                dismiss()
            } label: {
                Text("Done").font(EType.bodyStrong).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(LinearGradient.diagonal)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).padding(.top, 2)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private var iridescentDivider: some View {
        Rectangle().fill(palette.iridescentHairline).frame(height: 1).opacity(0.6)
    }

    private func ackRow(label: String, value: String, emphasised: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasised ? EType.bodyStrong : EType.caption)
                .foregroundStyle(emphasised ? palette.textPrimary : palette.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: emphasised ? 16 : 14, weight: emphasised ? .heavy : .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
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
