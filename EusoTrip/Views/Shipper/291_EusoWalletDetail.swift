//
//  291_EusoWalletDetail.swift
//  EusoTrip — Shipper · EusoWallet detail (Arc G).
//
//  REDESIGNED to the Design Authority level (founder mandate #13). The
//  detail surface is now the bespoke wallet language: a volumetric hero
//  with the live balance composition, an itemized HOLDS section, and a
//  bespoke credit/debit transaction LEDGER — all drawn glyphs, ZERO SF
//  Symbols. Shares the `EusoWalletComponents` design system with 290.
//
//  Real data — the SAME canonical ledger the web wallet binds to:
//    • `eusoWallet.getSnapshot`      → available / pending / reserved (cents)
//                                      + currency. (Fixes the prior decode,
//                                      which read non-existent dollar fields
//                                      and silently blanked the snapshot.)
//    • `eusoWallet.listTransactions` → { items: [...], walletId }. (Fixes the
//                                      prior bare-array decode that always
//                                      yielded zero transactions.)
//    • `eusoWallet.listHolds`        → { items: [...] } active wallet holds,
//                                      itemized. Honest empty when none.
//  Bounded by the shared session timeout; honest em-dash at nil/0; the
//  ledger amounts decode decimals defensively (number OR numeric String).
//

import SwiftUI

struct EusoWalletDetailScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { EusoWalletDetailBody() } nav: { shipperLifecycleNav() }
    }
}

// MARK: - eusoWallet.getSnapshot (cents-native)

private struct DetailSnap: Decodable, Hashable {
    let availableCents: Int?
    let pendingCents: Int?
    let reservedCents: Int?
    let currency: String?

    private enum CodingKeys: String, CodingKey {
        case availableCents, pendingCents, reservedCents, currency
    }
    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        func cents(_ k: CodingKeys) -> Int? {
            guard let c = c else { return nil }
            if let i = try? c.decodeIfPresent(Int.self, forKey: k) { return i }
            if let d = try? c.decodeIfPresent(Double.self, forKey: k) { return Int(d.rounded()) }
            if let s = try? c.decodeIfPresent(String.self, forKey: k), let d = Double(s) { return Int(d.rounded()) }
            return nil
        }
        availableCents = cents(.availableCents)
        pendingCents   = cents(.pendingCents)
        reservedCents  = cents(.reservedCents)
        currency       = (try? c?.decodeIfPresent(String.self, forKey: .currency)) ?? nil
    }
}

// MARK: - eusoWallet.listTransactions ({ items, walletId } envelope)

/// One `wallet_transactions` row. `amount`/`fee`/`netAmount` are MySQL
/// decimals — drizzle/mysql2 hands them back as Strings, so decode each
/// defensively (number OR numeric String) to dollars. `description` is the
/// memo; `type`/`status` drive the glyph + tint.
private struct WalletTxnRow: Decodable, Identifiable, Hashable {
    let id: Int
    let type: String?
    let status: String?
    let amount: Double
    let fee: Double?
    let description: String?
    let loadNumber: String?
    let createdAt: String?
    let completedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, type, status, amount, fee, description, loadNumber, createdAt, completedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id can be Int or numeric String.
        if let i = try? c.decode(Int.self, forKey: .id) { id = i }
        else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) { id = i }
        else { id = Int.random(in: Int.min...(-1)) } // stable-enough fallback key
        type        = try? c.decodeIfPresent(String.self, forKey: .type)
        status      = try? c.decodeIfPresent(String.self, forKey: .status)
        amount      = Self.num(c, .amount) ?? 0
        fee         = Self.num(c, .fee)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        loadNumber  = try? c.decodeIfPresent(String.self, forKey: .loadNumber)
        createdAt   = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        completedAt = try? c.decodeIfPresent(String.self, forKey: .completedAt)
    }
    private static func num(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: k) { return d }
        if let s = try? c.decodeIfPresent(String.self, forKey: k) { return Double(s) }
        return nil
    }

    /// Signed dollars: credits positive, debits (payout/fee) negative.
    /// The ledger stores positive magnitudes + a `type`, so we derive the
    /// sign from the type semantics.
    var signedAmount: Double {
        let magnitude = abs(amount)
        switch (type ?? "").lowercased() {
        case "payout", "fee":  return -magnitude
        default:               return magnitude   // earnings/refund/bonus/deposit/adjustment/transfer → credit
        }
    }

    var memo: String? {
        if let d = description, !d.isEmpty { return d }
        if let ln = loadNumber, !ln.isEmpty { return "Load \(ln)" }
        return nil
    }
    var timestamp: String? { completedAt ?? createdAt }
}

private struct TxnEnvelope: Decodable {
    let items: [WalletTxnRow]
    let walletId: Int?
}

// MARK: - eusoWallet.listHolds ({ items } envelope)

private struct WalletHoldRow: Decodable, Identifiable, Hashable {
    let id: Int
    let amountCents: Int?
    let reason: String?
    let status: String?
    let loadNumber: String?
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, amountCents, reason, status, loadNumber, createdAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) { id = i }
        else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) { id = i }
        else { id = Int.random(in: Int.min...(-1)) }
        if let i = try? c.decodeIfPresent(Int.self, forKey: .amountCents) { amountCents = i }
        else if let s = try? c.decodeIfPresent(String.self, forKey: .amountCents), let d = Double(s) { amountCents = Int(d.rounded()) }
        else { amountCents = nil }
        reason     = try? c.decodeIfPresent(String.self, forKey: .reason)
        status     = try? c.decodeIfPresent(String.self, forKey: .status)
        loadNumber = try? c.decodeIfPresent(String.self, forKey: .loadNumber)
        createdAt  = try? c.decodeIfPresent(String.self, forKey: .createdAt)
    }
    var amountDollars: Double? { amountCents.map { Double($0) / 100.0 } }
    var loadRef: String? { loadNumber.map { "Load \($0)" } }
}

private struct HoldsEnvelope: Decodable {
    let items: [WalletHoldRow]
}

// MARK: - Body

private struct EusoWalletDetailBody: View {
    @Environment(\.palette) private var palette

    @State private var snap: DetailSnap? = nil
    @State private var txns: [WalletTxnRow] = []
    @State private var holds: [WalletHoldRow] = []
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var showAllTxns: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header

                if let s = snap {
                    WalletBalanceHero(
                        availableCents: s.availableCents,
                        pendingCents: s.pendingCents,
                        reservedCents: s.reservedCents,
                        currency: s.currency ?? "USD",
                        caption: "Spendable now"
                    )
                } else if loading {
                    snapSkeleton
                } else if let err = loadError {
                    errorCard(err)
                }

                if !holds.isEmpty { holdsCard }

                txnsCard

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            WalletEyebrow(glyph: .pulse, text: "SHIPPER · EUSOWALLET DETAIL")
            Text("Activity").font(.system(size: 24, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Loading / error

    private var snapSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            WalletShimmer(height: 14, radius: 6).frame(width: 120)
            WalletShimmer(height: 44, radius: 12)
            WalletShimmer(height: 9, radius: 5)
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

    // MARK: Holds (itemized)

    private var holdsCard: some View {
        let heldTotal = holds.compactMap { $0.amountDollars }.reduce(0, +)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                WalletEyebrow(glyph: .lock, text: "ACTIVE HOLDS")
                Spacer(minLength: 0)
                Text(WalletMoney.usdDollarsPrecise(heldTotal > 0 ? heldTotal : nil))
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Brand.warning)
            }
            VStack(spacing: 8) {
                ForEach(holds) { h in
                    WalletHoldTile(
                        loadRef: h.loadRef ?? (h.reason.map { $0.capitalized }),
                        route: h.reason?.replacingOccurrences(of: "_", with: " ").capitalized,
                        status: h.status,
                        amountDollars: h.amountDollars
                    )
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }

    // MARK: Transaction ledger

    private var txnsCard: some View {
        let shown = showAllTxns ? txns : Array(txns.prefix(8))
        return VStack(alignment: .leading, spacing: 12) {
            WalletEyebrow(glyph: .pulse, text: "TRANSACTIONS")

            if loading && txns.isEmpty {
                VStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in
                        HStack(spacing: 12) {
                            WalletShimmer(height: 40, radius: Radius.md).frame(width: 40)
                            VStack(alignment: .leading, spacing: 6) {
                                WalletShimmer(height: 12, radius: 4).frame(width: 140)
                                WalletShimmer(height: 9, radius: 4).frame(width: 90)
                            }
                            Spacer(minLength: 0)
                            WalletShimmer(height: 14, radius: 4).frame(width: 56)
                        }
                    }
                }
            } else if txns.isEmpty {
                emptyTxns
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { idx, t in
                        WalletLedgerRow(
                            title: titleFor(t),
                            memo: t.memo,
                            timestamp: t.timestamp,
                            amountDollars: t.signedAmount,
                            type: t.type,
                            showDivider: idx < shown.count - 1
                        )
                    }
                }
                if txns.count > 8 {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
                            showAllTxns.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(showAllTxns ? "Show fewer" : "Show all \(txns.count)")
                                .font(.system(size: 12, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                            WalletGlyph(kind: .chevron, size: 10, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                                .rotationEffect(.degrees(showAllTxns ? 90 : 0))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private var emptyTxns: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.blue.opacity(0.12), Brand.magenta.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                WalletGlyph(kind: .pulse, size: 18, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("No transactions yet").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("Payouts, fees, and escrow movements will appear here.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    /// Human title from the txn type (the memo carries the specifics).
    private func titleFor(_ t: WalletTxnRow) -> String {
        switch (t.type ?? "").lowercased() {
        case "earnings":   return "Load payout"
        case "payout":     return "Cash-out"
        case "fee":        return "Platform fee"
        case "refund":     return "Refund"
        case "bonus":      return "Bonus"
        case "adjustment": return "Adjustment"
        case "transfer":   return "Transfer"
        case "deposit":    return "Deposit"
        default:           return (t.type?.capitalized).flatMap { $0.isEmpty ? nil : $0 } ?? "Transaction"
        }
    }

    // MARK: Load — three real procs, bounded, last-good preserved

    private func load() async {
        loading = true; loadError = nil
        do {
            async let snapTask: DetailSnap = EusoTripAPI.shared.queryNoInput("eusoWallet.getSnapshot")
            async let txnsTask: TxnEnvelope = EusoTripAPI.shared.queryNoInput("eusoWallet.listTransactions")
            async let holdsTask: HoldsEnvelope = EusoTripAPI.shared.queryNoInput("eusoWallet.listHolds")

            snap = try await snapTask
            txns = (try? await txnsTask)?.items ?? txns
            holds = (try? await holdsTask)?.items ?? holds
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("291 · EusoWallet detail · Night") {
    EusoWalletDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("291 · EusoWallet detail · Afternoon") {
    EusoWalletDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
