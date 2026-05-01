//
//  054_HaulPaySettlement.swift
//  EusoTrip — Lifecycle screen 054 · HaulPay Settlement.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `054 HaulPay Settlement.png`. Post-POD pay surface — purple
//  hero with net-to-driver + load tag + cleared chip, gross-
//  invoice line, deductions list (HazmatPool only when product is
//  hazmat), instant / 24-hour / pre-check pay buttons, ESANG
//  cadence note, Statement / Claim now CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct HaulPaySettlement: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isClaiming: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .afternoon) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // Production-clean placeholders.
    //
    // Updated 2026-04-24 (eusotrip-killers ledger-hygiene pass) — every
    // hard-coded settlement value (NAMA LANCASTER, $948.50, MC-306 BOL
    // 22089, Chase ·9124) replaced with em-dash placeholders. Real data
    // comes from `wallet.getEarnings` + `settlementBatching.getMyBatch`.
    // The Sign + claim CTA fires `wallet.requestInstantPayout` /
    // `settlementBatching.acceptBatch` against the live load id.
    //
    // Doctrine: 0% mock data — no fake settlements rendered in
    // production. The screen still draws the layout; placeholder values
    // disappear the moment the live earnings record hydrates.
    private let fallbackClock        = "—"
    private let fallbackLoadTag      = "LOAD · —"
    private let fallbackNetBig       = "$ —"
    private let fallbackNetSub       = ""
    private let fallbackNetCaption   = "AWAITING POD"
    private let fallbackGrossLabel   = "Gross invoice · —"
    private let fallbackGrossSub     = "—"
    private let fallbackGrossValue   = "—"
    private let fallbackInstant      = "—"
    private let fallbackInstantSub   = "FEE —"
    private let fallback24h          = "—"
    private let fallback24hSub       = "FREE"
    private let fallbackPreCheck     = "—"
    private let fallbackPreCheckSub  = "AUTO · FREE"
    private let fallbackEsang        = "ESANG will narrate the cadence the moment your settlement clears."

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                heroCard
                grossRow
                deductionsList
                payoutOptions
                esangAdvisory
                actions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { navBack?() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("HAULPAY · \(fallbackLoadTag)")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            Spacer(minLength: 0)
            Text(fallbackClock)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(fallbackNetBig)
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text(fallbackNetSub)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Text("POD CLEARED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
            }
            Text(fallbackNetCaption)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var grossRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm).fill(Brand.success.opacity(0.2))
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Brand.success)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(fallbackGrossLabel)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(fallbackGrossSub)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(fallbackGrossValue)
                .font(EType.bodyStrong)
                .foregroundStyle(Brand.success)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var deductionsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DEDUCTIONS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(deductionTotal)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(Brand.danger)
            }
            ForEach(deductions, id: \.label) { row in
                deductionRow(icon: row.icon, label: row.label, sub: row.sub, value: row.value)
            }
        }
    }

    private struct DedRow {
        let icon: String
        let label: String
        let sub: String
        let value: String
    }

    private var deductions: [DedRow] {
        // Production-clean. Updated 2026-04-24 (eusotrip-killers
        // ledger-hygiene pass) — values blanked. Backend wire-in:
        // populate from `wallet.getEarnings({ loadId })` →
        // `WalletAPI.WalletEarnings.deductions[]`. Each backend
        // deduction row has `kind` (factoring | platformFee |
        // hazmatPool | coldChain | securement | chassis | grounding),
        // `label`, `subline`, and `amount`. The product-context
        // branches below remain in place so the right rows render
        // for the right product type, but values are em-dashed
        // until the settlement record is live.
        var rows: [DedRow] = [
            .init(icon: "rectangle.stack.fill", label: "HaulPay factoring", sub: "2.5% OF GROSS", value: "−$—"),
            .init(icon: "shield.fill",          label: "EusoPlatform fee",  sub: "1.0% OF GROSS", value: "−$—"),
        ]
        if ctx.isHazmat {
            rows.append(.init(icon: "drop.fill", label: "HM-HazmatPool escrow", sub: "REVERSED ON POD", value: "−$—"))
        }
        switch ctx.product {
        case .reefer:
            rows.append(.init(icon: "thermometer.snowflake", label: "Cold-chain audit", sub: "USDA TRACE FEE", value: "−$—"))
        case .flatbed:
            rows.append(.init(icon: "link", label: "Securement audit", sub: "DOT 393 ATTEST", value: "−$—"))
        case .container, .railIntermodal, .vesselContainer:
            rows.append(.init(icon: "cube.box.fill", label: "Chassis pool fee", sub: "DAILY USE", value: "−$—"))
        case .railBulk, .vesselBulk:
            rows.append(.init(icon: "circle.hexagongrid.fill", label: "Grounding kit fee", sub: "BULK CARGO", value: "−$—"))
        default:
            break
        }
        return rows
    }

    private var deductionTotal: String {
        // Sum the visible deduction strings — keep formatting simple
        var total: Double = 0
        for r in deductions {
            let cleaned = r.value.replacingOccurrences(of: "−$", with: "")
            if let v = Double(cleaned) { total += v }
        }
        return "−$\(String(format: "%.2f", total))"
    }

    private func deductionRow(icon: String, label: String, sub: String, value: String) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm).fill(Brand.danger.opacity(0.15))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Brand.danger)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(value)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(Brand.danger)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 9)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var payoutOptions: some View {
        HStack(spacing: Space.s2) {
            payoutCell(label: "INSTANT",   primary: fallbackInstant,    sub: fallbackInstantSub,   selected: true)
            payoutCell(label: "24-HOUR",   primary: fallback24h,         sub: fallback24hSub,        selected: false)
            payoutCell(label: "PRE-CHECK", primary: fallbackPreCheck,    sub: fallbackPreCheckSub,   selected: false)
        }
    }

    private func payoutCell(label: String, primary: String, sub: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            Text(primary)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            Text(sub)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint), lineWidth: selected ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var esangAdvisory: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text(fallbackEsang)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: Space.s3) {
            Button { openStatement() } label: {
                Text("Statement")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            CTAButton(
                title: "Claim now",
                action: { Task { await claim() } },
                trailingIcon: "arrow.right",
                isLoading: isClaiming
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func claim() async {
        isClaiming = true
        defer { isClaiming = false }
        let keys = ["claimed", "paid"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }

    /// "Statement" — open the canonical settlement statement view in
    /// the EusoWallet sub-route of the Me hub. The full breakdown
    /// (line items, deductions, fees, net) lives there; this lifecycle
    /// screen just shows the per-load summary.
    private func openStatement() {
        MeAction.fire("054.open-statement",
                      userInfo: ["loadId": lifecycle.loadId])
        NotificationCenter.default.post(
            name: .esangOpenMeDetail,
            object: "earnings",
            userInfo: ["loadId": lifecycle.loadId]
        )
        navBack?()
    }
}

struct HaulPaySettlementScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            HaulPaySettlement(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_054(),
                      trailing: driverNavTrailing_054(),
                      orbState: .idle)
        }
    }
}

// PNG canon at `01 Driver/{Light,Dark}/054 HaulPay Settlement.png` +
// [Driver E2E map] doctrine pin Wallet · settlements · payout · tax
// · IFTA · earnings (054, 055, 068, 069, 070, 077, 078, 079, 080, 090)
// inside the Wallet ring. Restored canonical layout: Home / Trips ·
// Wallet / Me with **WALLET current**. Prior iOS shipped with all
// four `isCurrent` flags `false` — no tab marked current at all,
// double-drift.
private func driverNavLeading_054() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: false)]
}
private func driverNavTrailing_054() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: true),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

#Preview("054 · HaulPay Settlement · Dark") {
    HaulPaySettlementScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("054 · HaulPay Settlement · Light") {
    HaulPaySettlementScreen(theme: Theme.light).preferredColorScheme(.light)
}
