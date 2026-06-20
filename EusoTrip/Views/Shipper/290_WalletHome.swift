//
//  290_WalletHome.swift
//  EusoTrip — Shipper · Wallet home (Arc G).
//
//  REDESIGNED to the Design Authority level (founder mandate #13): the
//  money surface is now a bespoke, alive, trustworthy wallet — a
//  volumetric hero "money card" with a gradient numeral + animated sheen,
//  the AVAILABLE / RESERVED / PENDING split as a drawn segmented allocation
//  bar, itemized escrow holds as bespoke vault tiles, lifetime activity as
//  a credit/debit ledger, and a hero cash-out CTA. Every glyph is a drawn
//  `WalletGlyph` Path — ZERO SF Symbols on this surface.
//
//  Real data, three real procs:
//    • `eusoWallet.getSnapshot`  → hero total + available/reserved/pending
//                                  (cents) + currency. (Same ledger the web
//                                  wallet binds to.)
//    • `wallet.getEscrowHolds`   → itemized holds (loadRef / route / amount).
//    • `wallet.getBalance`       → lifetime received / spent + MTD volume.
//  All bounded by the shared 22s session timeout; honest em-dash at nil/0;
//  last-good values stay on screen during a refresh.
//

import SwiftUI

struct WalletHomeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { WalletHomeBody() } nav: { shipperLifecycleNav() }
    }
}

// MARK: - eusoWallet.getSnapshot (cents-native, the canonical ledger)

private struct EusoWalletSnap: Decodable, Hashable {
    let walletId: Int?
    let availableCents: Int?
    let pendingCents: Int?
    let reservedCents: Int?
    let currency: String?

    private enum CodingKeys: String, CodingKey {
        case walletId, availableCents, pendingCents, reservedCents, currency
    }
    init(from decoder: Decoder) throws {
        // Defensive: every cents field may arrive as a number OR a numeric
        // String; a shape drift must never throw and blank the wallet.
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        func cents(_ k: CodingKeys) -> Int? {
            guard let c = c else { return nil }
            if let i = try? c.decodeIfPresent(Int.self, forKey: k) { return i }
            if let d = try? c.decodeIfPresent(Double.self, forKey: k) { return Int(d.rounded()) }
            if let s = try? c.decodeIfPresent(String.self, forKey: k), let d = Double(s) { return Int(d.rounded()) }
            return nil
        }
        walletId       = (try? c?.decodeIfPresent(Int.self, forKey: .walletId)) ?? nil
        availableCents = cents(.availableCents)
        pendingCents   = cents(.pendingCents)
        reservedCents  = cents(.reservedCents)
        currency       = (try? c?.decodeIfPresent(String.self, forKey: .currency)) ?? nil
    }
}

// MARK: - wallet.getEscrowHolds (bare array of itemized holds)

private struct EscrowHoldRow: Decodable, Identifiable, Hashable {
    let id: String
    let loadRef: String?
    let route: String?
    let driverName: String?
    let amount: Double?
    let status: String?
    let createdAt: String?
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Canonical ledger snapshot (cents) — drives the hero + composition.
    @State private var snap: EusoWalletSnap? = nil
    // Lifetime activity + MTD volume (the `wallet.getBalance` extras).
    @State private var balance: WalletBalance? = nil
    // Itemized escrow holds.
    @State private var holds: [EscrowHoldRow] = []

    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var showCashOut: Bool = false
    @State private var holdsExpanded: Bool = false

    private var isDark: Bool { palette.bgPage == Theme.dark.bgPage }

    /// Available dollars for the cash-out sheet — prefer the canonical
    /// snapshot (cents), fall back to the legacy balance.
    private var availableDollars: Double {
        if let c = snap?.availableCents { return Double(c) / 100.0 }
        return balance?.available ?? 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                header

                // ── HERO ──
                if let s = snap {
                    WalletBalanceHero(
                        availableCents: s.availableCents,
                        pendingCents: s.pendingCents,
                        reservedCents: s.reservedCents,
                        currency: s.currency ?? "USD"
                    )
                } else if loading {
                    heroSkeleton
                } else if let err = loadError {
                    errorCard(err)
                }

                // ── HERO CASH-OUT CTA ──
                cashOutAction

                // ── ESCROW HOLDS (itemized) ──
                if !holds.isEmpty {
                    holdsCard
                }

                // ── LIFETIME ACTIVITY (credit / debit ledger) ──
                if let b = balance {
                    activityCard(b)
                }

                // ── MANAGE ──
                manageSection

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCashOut) {
            ShipperCashOutSheet(
                available: availableDollars,
                onCompleted: { Task { await load() } }
            )
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                WalletEyebrow(glyph: .wallet, text: "SHIPPER · EUSOWALLET")
                Text("EusoWallet").font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            // Iridescent brand mark — drawn wallet glyph (no SF Symbol).
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 38, height: 38)
                WalletGlyph(kind: .wallet, size: 18, tint: AnyShapeStyle(Color.white), lineWidth: 1.6)
            }
            .shadow(color: Brand.magenta.opacity(isDark ? 0.45 : 0.22), radius: 10, x: 0, y: 4)
        }
    }

    // MARK: Loading / error

    private var heroSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            WalletShimmer(height: 14, radius: 6).frame(width: 130)
            WalletShimmer(height: 44, radius: 12)
            WalletShimmer(height: 9, radius: 5)
            HStack(spacing: 10) {
                WalletShimmer(height: 28, radius: 8)
                WalletShimmer(height: 28, radius: 8)
                WalletShimmer(height: 28, radius: 8)
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 8) {
                WalletGlyph(kind: .pulse, size: 14, tint: AnyShapeStyle(Brand.danger), lineWidth: 1.5)
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Escrow holds — itemized bespoke vault tiles

    private var holdsCard: some View {
        let shown = holdsExpanded ? holds : Array(holds.prefix(3))
        let heldTotal = holds.compactMap { $0.amount }.reduce(0, +)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                WalletEyebrow(glyph: .lock, text: "ESCROW HOLDS")
                Spacer(minLength: 0)
                Text(WalletMoney.usdDollarsPrecise(heldTotal > 0 ? heldTotal : nil))
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Brand.warning)
            }
            VStack(spacing: 8) {
                ForEach(shown) { h in
                    WalletHoldTile(loadRef: h.loadRef, route: h.route, status: h.status, amountDollars: h.amount)
                }
            }
            if holds.count > 3 {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
                        holdsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(holdsExpanded ? "Show fewer" : "Show all \(holds.count) holds")
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                        WalletGlyph(kind: .chevron, size: 10, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                            .rotationEffect(.degrees(holdsExpanded ? 90 : 0))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    // MARK: Lifetime activity — credit/debit ledger

    private func activityCard(_ b: WalletBalance) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WalletEyebrow(glyph: .pulse, text: "LIFETIME ACTIVITY")
            // received (credit) + spent (debit) drawn as ledger rows, plus
            // MTD volume as a third reference row. Honest em-dash at nil/0.
            VStack(spacing: 0) {
                WalletLedgerRow(title: "Received", memo: "All settled payouts", timestamp: nil,
                                amountDollars: b.totalReceived ?? 0, type: "earnings")
                WalletLedgerRow(title: "Spent", memo: "Fees, refunds, debits", timestamp: nil,
                                amountDollars: -(b.totalSpent ?? 0), type: "fee")
                volumeRow(b.monthVolume)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    /// MTD volume reference row — neutral (not a credit/debit), drawn pie
    /// glyph, no spark.
    private func volumeRow(_ v: Double?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                WalletGlyph(kind: .pie, size: 16, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Month-to-date volume").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("Gross moved this month").font(EType.micro).foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: Space.s2)
            Text(usd(v) == "-" ? "—" : usd(v))
                .font(.system(size: 15, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.vertical, 10)
    }

    // MARK: Manage section

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            WalletEyebrow(glyph: .pie, text: "MANAGE").padding(.leading, 2)
            VStack(spacing: 8) {
                link(glyph: .spark, title: "Wallet card style", subtitle: "Pick the look of your pickup pass", screenId: "WalletCardStyle")
                link(glyph: .pulse, title: "EusoWallet detail", subtitle: "Activity, holds, and pass", screenId: "291")
                link(glyph: .bank, title: "Settlements", subtitle: "Load payouts and invoices", screenId: "292")
                link(glyph: .bank, title: "Payment methods", subtitle: "Linked banks and cards", screenId: "295")
                link(glyph: .pulse, title: "Statements", subtitle: "Monthly account statements", screenId: "297")
                link(glyph: .spark, title: "Sustainability", subtitle: "Carbon spend and offsets", screenId: "298")
                link(glyph: .pie, title: "Reports", subtitle: "Spend and volume analytics", screenId: "299")
            }
        }
    }

    // Primary money action — opens the inline withdraw flow
    // (`wallet.requestPayout`). Full brand-gradient hero CTA with a drawn
    // arrow-down glyph so the cash-out reads as the headline action.
    private var cashOutAction: some View {
        Button {
            showCashOut = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(.white.opacity(0.18))
                    WalletGlyph(kind: .arrowDown, size: 22, tint: AnyShapeStyle(Color.white), lineWidth: 2)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cash out").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                    Text("Withdraw to a linked bank or card").font(EType.micro).foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                WalletGlyph(kind: .chevron, size: 14, tint: AnyShapeStyle(Color.white.opacity(0.9)), lineWidth: 2)
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

    private func link(glyph: WalletGlyph.Kind, title: String, subtitle: String, screenId: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screenId])
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    WalletGlyph(kind: glyph, size: 16, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(subtitle).font(EType.micro).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                WalletGlyph(kind: .chevron, size: 13, tint: AnyShapeStyle(palette.textTertiary), lineWidth: 1.5)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md, intensity: .whisper)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: Load — three real procs, bounded, last-good preserved
    //
    // The canonical snapshot is the gate (its failure surfaces the error
    // card); the holds + legacy balance are best-effort enrichments that
    // never blank the screen if they drift. On a refresh the prior values
    // stay on screen until the new ones land (no flash to empty).
    private func load() async {
        loading = true; loadError = nil
        do {
            async let snapTask: EusoWalletSnap = EusoTripAPI.shared.queryNoInput("eusoWallet.getSnapshot")
            async let holdsTask: [EscrowHoldRow] = EusoTripAPI.shared.queryNoInput("wallet.getEscrowHolds")
            async let balTask: WalletBalance = EusoTripAPI.shared.queryNoInput("wallet.getBalance")

            snap = try await snapTask
            holds = (try? await holdsTask) ?? holds
            balance = (try? await balTask) ?? balance
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
                WalletEyebrow(glyph: .arrowDown, text: "SHIPPER · CASH OUT")
                Text("Withdraw").font(.system(size: 24, weight: .heavy)).foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 34, height: 34)
                WalletGlyph(kind: .arrowDown, size: 16, tint: AnyShapeStyle(Color.white), lineWidth: 1.7)
            }
            .shadow(color: Brand.magenta.opacity(isDark ? 0.45 : 0.22), radius: 9, x: 0, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var availableRow: some View {
        HStack {
            HStack(spacing: 6) {
                WalletGlyph(kind: .wallet, size: 12, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.4)
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
                WalletGlyph(kind: .bank, size: 18, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.6)
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
                    WalletGlyph(kind: m.kind == "bank" ? .bank : .coins, size: 15, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.institution).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("••\(m.mask)\(m.isInstant ? " · instant" : "")").font(EType.micro).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                // Drawn selection indicator — filled gradient disc with a
                // check Path when chosen, hollow ring otherwise.
                ZStack {
                    Circle().strokeBorder(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary.opacity(0.6)), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if selected {
                        Circle().fill(LinearGradient.diagonal).frame(width: 18, height: 18)
                        Canvas { ctx, sz in
                            var p = Path()
                            let s = min(sz.width, sz.height)
                            p.move(to: CGPoint(x: 0.30 * s, y: 0.52 * s))
                            p.addLine(to: CGPoint(x: 0.44 * s, y: 0.66 * s))
                            p.addLine(to: CGPoint(x: 0.72 * s, y: 0.36 * s))
                            ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        }.frame(width: 18, height: 18)
                    }
                }
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
                WalletGlyph(kind: isInstant ? .bolt : .pulse, size: 14,
                            filled: isInstant && selected && !disabled,
                            tint: (selected && !disabled) ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary),
                            lineWidth: 1.6)
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
                WalletGlyph(kind: .pulse, size: 14, tint: AnyShapeStyle(Brand.danger), lineWidth: 1.5)
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
                else { WalletGlyph(kind: .arrowDown, size: 16, tint: AnyShapeStyle(Color.white), lineWidth: 1.8) }
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
                    // drawn checkmark Path (no SF Symbol)
                    Canvas { ctx, sz in
                        var p = Path()
                        let s = min(sz.width, sz.height)
                        p.move(to: CGPoint(x: 0.28 * s, y: 0.52 * s))
                        p.addLine(to: CGPoint(x: 0.44 * s, y: 0.68 * s))
                        p.addLine(to: CGPoint(x: 0.74 * s, y: 0.34 * s))
                        ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    }.frame(width: 40, height: 40)
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
