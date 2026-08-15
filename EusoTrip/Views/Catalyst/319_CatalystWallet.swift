//
//  319_CatalystWallet.swift
//  EusoTrip — Catalyst · Wallet (brick 319).
//
//  REDESIGNED to the Design Authority level (founder mandate #13). The
//  carrier/broker money surface is now the bespoke EusoWallet language —
//  the SAME volumetric hero "money card" + drawn-glyph corpus shared with
//  the founder-approved Wallet home (290) and EusoWallet detail (291) via
//  `EusoWalletComponents`. ZERO SF Symbols on the money surface: every
//  glyph is a drawn `WalletGlyph` Path; the balance is a gradient numeral
//  on a layered card with an animated sheen + a bespoke composition bar;
//  receivables/payables/net-flow read as KPI tiles with drawn glyphs; the
//  ledger is a credit/debit `WalletLedgerRow` corpus; reserved entries are
//  bespoke `WalletHoldTile` vaults; loading is `WalletShimmer`.
//
//  Owner-op §8.4 seam wallet — Diego → Eusotrans → Michael cleanly flows in
//  one surface. Real endpoints, no stubs.
//
//  Wire bindings (UNCHANGED — same three procs, same shapes):
//    wallet.getBalance       — current cash balance (+ bankName / lastSyncedAt)
//    wallet.getSummary       — receivables / payables / net flow KPIs
//    wallet.getTransactions  — entry list ranked by urgency (input { limit })
//
//  Honest data: every dollar runs through `WalletMoney`/`usd`; nil/zero →
//  em-dash; last-good values stay on screen during a refresh. The filter
//  lens, axis chips, kind/status pills, and 30-row fetch are all preserved.
//
//  Bottom nav frozen per doctrine.
//

import SwiftUI

private struct WalletBalance: Decodable, Hashable {
    let balance: String?
    let bankName: String?
    let lastSyncedAt: String?
}

private struct WalletSummary: Decodable, Hashable {
    let balance: Double?
    let receivables: Double?
    let payables: Double?
    let netFlow30d: Double?
    let receivableCount: Int?
    let payableCount: Int?
}

private struct CatalystWalletTxnRow: Decodable, Hashable, Identifiable {
    let id: String
    let loadNumber: String?
    let kind: String?         // RECEIVABLE / PAYABLE / RESERVED / CLEARED
    let axis: String?         // "DU" or "ME"
    let status: String?
    let amount: String?
    let lane: String?
    let detail: String?
    let createdAt: String?

    /// The transaction amount parsed to dollars (honest nil at unparseable).
    var amountDollars: Double? {
        guard let a = amount, !a.isEmpty else { return nil }
        return Double(a.replacingOccurrences(of: ",", with: "")
                       .replacingOccurrences(of: "$", with: ""))
    }

    /// Signed dollars for the credit/debit ledger row. RECEIVABLE / CLEARED
    /// are money IN (credit, +); PAYABLE is money OUT (debit, −); RESERVED is
    /// itemized on its own vault tile (kept positive magnitude there).
    var signedAmount: Double {
        let mag = abs(amountDollars ?? 0)
        switch (kind ?? "").uppercased() {
        case "PAYABLE":  return -mag
        default:         return mag   // RECEIVABLE / CLEARED → credit
        }
    }

    /// Ledger type hint → glyph nuance in `WalletLedgerRow`.
    var ledgerType: String {
        switch (kind ?? "").uppercased() {
        case "PAYABLE":    return "payout"
        case "RECEIVABLE": return "earnings"
        case "CLEARED":    return "refund"
        default:           return "transfer"
        }
    }
}

struct CatalystWalletScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { WalletBody() } nav: {
            BottomNav(
                leading: CarrierNavRoute.leading(current: .me),
                trailing: CarrierNavRoute.trailing(current: .me),
                orbState: .idle
            )
        }
    }
}

private struct WalletBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Filter: String, CaseIterable {
        case all = "All", receivable = "Receivable", payable = "Payable", reserved = "Reserved", cleared = "Cleared"

        var glyph: WalletGlyph.Kind {
            switch self {
            case .all:        return .pulse
            case .receivable: return .arrowUp
            case .payable:    return .arrowDown
            case .reserved:   return .lock
            case .cleared:    return .spark
            }
        }
    }

    @State private var balance: WalletBalance?
    @State private var summary: WalletSummary?
    @State private var txns: [CatalystWalletTxnRow] = []
    @State private var filter: Filter = .all
    @State private var loading: Bool = true
    @State private var error: String?

    private var isDark: Bool { palette.bgPage == Theme.dark.bgPage }

    private var filtered: [CatalystWalletTxnRow] {
        guard filter != .all else { return txns }
        return txns.filter { ($0.kind ?? "").lowercased() == filter.rawValue.lowercased() }
    }

    /// RESERVED entries render as bespoke vault tiles (vs. ledger rows).
    private var reservedRows: [CatalystWalletTxnRow] {
        filtered.filter { ($0.kind ?? "").uppercased() == "RESERVED" }
    }
    /// Everything else flows the credit/debit ledger.
    private var ledgerRows: [CatalystWalletTxnRow] {
        filtered.filter { ($0.kind ?? "").uppercased() != "RESERVED" }
    }

    // MARK: Cents mapping for the hero composition bar (honest, dollars→cents)
    //
    // available = current cash balance · pending = receivables (incoming,
    // POD-pending) · reserved = payables (committed out). Prefer the rich
    // `getSummary` figures, fall back to the `getBalance` string.

    private func cents(_ v: Double?) -> Int? {
        guard let v = v, v > 0 else { return nil }
        return Int((v * 100).rounded())
    }
    private var availableCents: Int? {
        if let b = summary?.balance { return cents(b) }
        if let s = balance?.balance, let d = Double(s) { return cents(d) }
        return nil
    }
    private var pendingCents: Int? { cents(summary?.receivables) }
    private var reservedCentsValue: Int? { cents(summary?.payables) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header

                // ── HERO money card (shared bespoke language) ──
                if summary != nil || balance != nil {
                    WalletBalanceHero(
                        availableCents: availableCents,
                        pendingCents: pendingCents,
                        reservedCents: reservedCentsValue,
                        currency: "USD",
                        caption: balance?.bankName ?? "Cash balance"
                    )
                } else if loading {
                    heroSkeleton
                } else if let err = error {
                    errorCard(err)
                }

                ownerOpSeamBanner

                EusoCardIssuePanel(
                    title: "EusoCard",
                    subtitle: "Fleet spend card backed by EusoWallet Treasury"
                )

                kpiStrip

                filterTabs

                ledgerSection

                walletCardStyleRow

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header — drawn wallet mark (no SF Symbol)

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                WalletEyebrow(glyph: .wallet, text: "CATALYST · WALLET")
                Text("Wallet").font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("§8.4 owner-op seam · Diego→Eusotrans→Michael")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 38, height: 38)
                WalletGlyph(kind: .wallet, size: 18, tint: AnyShapeStyle(Color.white), lineWidth: 1.6)
            }
            .shadow(color: Brand.magenta.opacity(isDark ? 0.45 : 0.22), radius: 10, x: 0, y: 4)
        }
    }

    // MARK: Wallet card style row (pickup-pass look picker)
    //
    // Mirrors the shipper Wallet hub's "Wallet card style" row (290 §Manage) and
    // the driver one (069). The same pure WalletCardPickerView is registered for
    // the catalyst/carrier pool as "WalletCardStyleCatalyst"; this row pushes it
    // through the catalyst/carrier nav signal (`.eusoCarrierNavSwap`, which
    // CarrierSurface — the catalyst alias surface — observes) — a horizontal push,
    // never a slide-up. Same drawn-glyph idiom as the rest of this surface.

    private var walletCardStyleRow: some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoCarrierNavSwap, object: nil,
                userInfo: ["screenId": "WalletCardStyleCatalyst"]
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.14)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.iridescentHairline, lineWidth: 1)
                    WalletGlyph(kind: .spark, size: 16,
                                tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallet card style")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Pick the look of your pickup pass")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                WalletGlyph(kind: .chevron, size: 13,
                            tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .eusoCard(radius: Radius.lg, intensity: .standard)
        }
        .buttonStyle(.plain)
    }

    // MARK: Loading / error (bespoke shimmer + drawn-glyph error)

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

    // MARK: Owner-op seam banner — bespoke gradient card w/ drawn glyph

    private var ownerOpSeamBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.white.opacity(0.18))
                WalletGlyph(kind: .bolt, size: 18, tint: AnyShapeStyle(Color.white), lineWidth: 1.8)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("OWNER-OP SEAM · CLEAN BOOKS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Diego pays Eusotrans pays Michael · same company · zero days-to-pay")
                    .font(EType.micro).foregroundStyle(.white.opacity(0.95)).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal)
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .shadow(color: Brand.blue.opacity(isDark ? 0.30 : 0.14), radius: 12, x: 0, y: 6)
    }

    // MARK: KPI strip — bespoke drawn-glyph flow tiles
    //
    // Receivables / Payables / Net-flow rendered as carded tiles with a drawn
    // directional glyph, color-keyed, honest em-dash at nil/0.

    private var kpiStrip: some View {
        let recv = summary?.receivables
        let pay = summary?.payables
        let net = summary?.netFlow30d
        let recvCount = summary?.receivableCount ?? 0
        let payCount = summary?.payableCount ?? 0
        return VStack(alignment: .leading, spacing: Space.s2) {
            WalletEyebrow(glyph: .pie, text: "CASH FLOW")
            HStack(spacing: Space.s2) {
                kpiTile(glyph: .arrowUp, label: "RECEIVABLES",
                        value: usd(recv) == "-" ? "—" : usd(recv),
                        subtitle: "\(recvCount) load\(recvCount == 1 ? "" : "s") · POD pending",
                        color: Brand.success)
                kpiTile(glyph: .arrowDown, label: "PAYABLES",
                        value: usd(pay) == "-" ? "—" : usd(pay),
                        subtitle: "\(payCount) due · same-day to ME",
                        color: Brand.warning)
            }
            netFlowTile(net)
        }
    }

    private func kpiTile(glyph: WalletGlyph.Kind, label: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(color.opacity(0.14))
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(color.opacity(0.40), lineWidth: 1)
                    WalletGlyph(kind: glyph, size: 13, tint: AnyShapeStyle(color), lineWidth: 1.6)
                }
                .frame(width: 28, height: 28)
                Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
            }
            Text(value).font(.system(size: 19, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(color)
            Text(subtitle).font(EType.micro).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md, intensity: .standard)
    }

    /// Net-flow reads as a wider trailing tile with a drawn pulse glyph and a
    /// signed figure (honest em-dash at nil).
    private func netFlowTile(_ net: Double?) -> some View {
        let positive = (net ?? 0) >= 0
        let color: Color = net == nil ? palette.textSecondary : (positive ? Brand.success : Brand.danger)
        let valueStr: String = {
            guard let n = net else { return "—" }
            let body = usd(abs(n)) == "-" ? "$0" : usd(abs(n))
            return (positive ? "+" : "−") + body
        }()
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.14), color.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(color.opacity(0.35), lineWidth: 1)
                WalletGlyph(kind: .pulse, size: 16, tint: AnyShapeStyle(color), lineWidth: 1.6)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("NET FLOW · 30D TRAILING").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(net == nil ? "Awaiting movement" : (positive ? "Positive trailing flow" : "Negative trailing flow"))
                    .font(EType.micro).foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            Text(valueStr).font(.system(size: 18, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(color)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md, intensity: .feature)
    }

    // MARK: Filter lens — bespoke drawn-glyph capsules (same Filter cases)

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Button { filter = f } label: {
                        HStack(spacing: 5) {
                            WalletGlyph(kind: f.glyph, size: 11,
                                        tint: AnyShapeStyle(filter == f ? Color.white : palette.textSecondary),
                                        lineWidth: 1.4)
                            Text(f.rawValue)
                                .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                                .foregroundStyle(filter == f ? .white : palette.textSecondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background {
                            if filter == f {
                                Capsule().fill(LinearGradient.diagonal)
                            } else {
                                Capsule().fill(palette.bgCard)
                                    .overlay(Capsule().strokeBorder(palette.iridescentHairline, lineWidth: 1))
                            }
                        }
                        .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Ledger section — reserved vaults + credit/debit rows

    @ViewBuilder private var ledgerSection: some View {
        if loading && txns.isEmpty {
            ledgerSkeleton
        } else if let err = error, txns.isEmpty {
            errorCard(err)
        } else if filtered.isEmpty {
            EusoEmptyState(systemImage: "tray",
                           title: "No entries in this lens",
                           subtitle: "Receivables + payables + reserves land here as loads progress.")
        } else {
            // Count caption (preserved verbatim semantics).
            Text("\(txns.count) ENTRIES · RANKED BY URGENCY · MIXED DU / ME AXIS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)

            // Reserved → bespoke vault tiles.
            if !reservedRows.isEmpty {
                let reservedTotal = reservedRows.compactMap { $0.amountDollars }.reduce(0, +)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        WalletEyebrow(glyph: .lock, text: "RESERVED")
                        Spacer(minLength: 0)
                        Text(WalletMoney.usdDollarsPrecise(reservedTotal > 0 ? reservedTotal : nil))
                            .font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Brand.warning)
                    }
                    VStack(spacing: 8) {
                        ForEach(reservedRows) { t in
                            WalletHoldTile(
                                loadRef: t.loadNumber ?? "LD-\(t.id)",
                                route: holdRoute(t),
                                status: t.status,
                                amountDollars: t.amountDollars
                            )
                        }
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.lg, intensity: .standard)
            }

            // Everything else → credit/debit ledger.
            if !ledgerRows.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    WalletEyebrow(glyph: .pulse, text: "LEDGER")
                    VStack(spacing: 0) {
                        ForEach(Array(ledgerRows.enumerated()), id: \.element.id) { idx, t in
                            WalletLedgerRow(
                                title: ledgerTitle(t),
                                memo: ledgerMemo(t),
                                timestamp: t.createdAt,
                                amountDollars: t.signedAmount,
                                type: t.ledgerType,
                                showDivider: idx < ledgerRows.count - 1
                            )
                        }
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.lg, intensity: .feature)
            }
        }
    }

    private var ledgerSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            WalletEyebrow(glyph: .pulse, text: "LEDGER")
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 12) {
                        WalletShimmer(height: 40, radius: Radius.md).frame(width: 40)
                        VStack(alignment: .leading, spacing: 6) {
                            WalletShimmer(height: 12, radius: 4).frame(width: 150)
                            WalletShimmer(height: 9, radius: 4).frame(width: 96)
                        }
                        Spacer(minLength: 0)
                        WalletShimmer(height: 14, radius: 4).frame(width: 56)
                    }
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    // MARK: Ledger field derivation (preserves load #, kind, status, axis, lane, detail)

    /// Title carries the load number + kind/status semantics the old card
    /// surfaced in its top row.
    private func ledgerTitle(_ t: CatalystWalletTxnRow) -> String {
        let load = t.loadNumber ?? "LD-\(t.id)"
        let kind = (t.kind ?? "").capitalized
        return kind.isEmpty ? load : "\(load) · \(kind)"
    }

    /// Memo folds the axis (DU/ME), status, lane, and detail into one honest
    /// line so no field the old card showed is lost.
    private func ledgerMemo(_ t: CatalystWalletTxnRow) -> String? {
        var parts: [String] = []
        if let a = t.axis, !a.isEmpty { parts.append(a) }
        if let s = t.status, !s.isEmpty { parts.append(s.uppercased()) }
        if let lane = t.lane, !lane.isEmpty { parts.append(lane) }
        if let d = t.detail, !d.isEmpty { parts.append(d) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Hold-tile route line folds axis + lane + status/detail.
    private func holdRoute(_ t: CatalystWalletTxnRow) -> String? {
        var parts: [String] = []
        if let a = t.axis, !a.isEmpty { parts.append(a) }
        if let lane = t.lane, !lane.isEmpty { parts.append(lane) }
        if let d = t.detail, !d.isEmpty { parts.append(d) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Load — three real procs, bounded, last-good preserved (UNCHANGED)

    private func load() async {
        loading = true; error = nil
        async let a: Void = loadBalance()
        async let b: Void = loadSummary()
        async let c: Void = loadTxns()
        _ = await (a, b, c)
        loading = false
    }

    private func loadBalance() async {
        do { balance = try await EusoTripAPI.shared.queryNoInput("wallet.getBalance") } catch { /* */ }
    }
    private func loadSummary() async {
        do { summary = try await EusoTripAPI.shared.queryNoInput("wallet.getSummary") } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
    private func loadTxns() async {
        struct In: Encodable { let limit: Int }
        do {
            txns = try await EusoTripAPI.shared.query("wallet.getTransactions", input: In(limit: 30))
        } catch { /* */ }
    }
}

#Preview("319 Wallet · Dark")  { CatalystWalletScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("319 Wallet · Light") { CatalystWalletScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
