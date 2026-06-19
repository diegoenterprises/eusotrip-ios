//
//  EusoWalletComponents.swift
//  EusoTrip — the bespoke EusoWallet design system (Views/Components).
//
//  The money surface. Built to the Design Authority level the founder
//  insists on (#13): NOT an "AI-coded basic" balance + list, but a
//  volumetric, alive, trustworthy wallet language shared by the Wallet
//  home (290) and the EusoWallet detail (291).
//
//  Doctrine honored verbatim:
//    • ZERO SF Symbols. Every glyph is a drawn `Shape`/`Path` (see
//      `WalletGlyph`) — wallet, up/down arrows, lock, coin, pulse, all
//      hand-drawn in the brand idiom. Nothing here is `Image(systemName:)`.
//    • Palette + LinearGradient.diagonal + brand gradients; the hero is a
//      large gradient-numeral balance on a layered "money card" (aurora
//      bloom + sheen sweep + top-rim catch-light + iridescent glow), not a
//      plain number on a flat fill.
//    • AVAILABLE vs HOLD / RESERVE is a bespoke drawn segmented allocation
//      bar (`WalletCompositionBar`) with a drawn-glyph legend — never a
//      plain list.
//    • The ledger is a bespoke credit/debit row (`WalletLedgerRow`) with a
//      drawn directional glyph + a micro "intention" spark and tabular
//      figures, color-keyed to credit/debit.
//    • Honest data: every dollar runs through `usd`/the cents helpers and
//      em-dashes at nil/zero. Mockup numbers are never shipped.
//    • Motion is tasteful and Reduce-Motion respected (the hero sheen and
//      the bar fill freeze when the system asks).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Money helpers (cents-native, honest)

enum WalletMoney {
    /// Cents → "$1,234" (whole-dollar, grouped). Honest: nil/≤0 → em-dash.
    static func usdCents(_ cents: Int?) -> String {
        guard let c = cents, c > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: Double(c) / 100.0)) ?? "$\(c / 100)"
    }

    /// Full-precision cents → "$1,234.56". Used for ledger amounts where a
    /// sub-dollar fee/refund must not be rounded away. Honest at zero only
    /// when `hideZero` (nil always em-dashes).
    static func usdCentsPrecise(_ cents: Int?, hideZero: Bool = false) -> String {
        guard let c = cents else { return "—" }
        if hideZero && c == 0 { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: Double(c) / 100.0)) ?? "$\(Double(c) / 100.0)"
    }

    /// Dollars (Double) → full-precision currency string. Honest at nil.
    static func usdDollarsPrecise(_ v: Double?, hideZero: Bool = false) -> String {
        guard let v = v else { return "—" }
        if hideZero && v == 0 { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - WalletGlyph — the drawn glyph corpus (ZERO SF Symbols)

/// Every wallet glyph drawn as a `Path`. Replaces the SF Symbols the old
/// screens used (`wallet.pass.fill`, `arrow.down.to.line`, `lock.shield`,
/// `chart.pie`, `chevron.right`, …) so the money surface is 100% bespoke.
/// Sized to a unit box and stroked/filled in the caller's style.
struct WalletGlyph: View {
    enum Kind {
        case wallet        // the EusoWallet mark
        case arrowDown     // cash-out / debit out
        case arrowUp       // credit in
        case lock          // hold / escrow
        case coins         // reserve
        case pulse         // activity / ledger
        case chevron       // disclosure
        case pie           // composition
        case bolt          // instant
        case bank          // payout method
        case spark         // intention mark
    }

    let kind: Kind
    var size: CGFloat = 16
    /// When true the glyph is filled with `tint`; otherwise stroked.
    var filled: Bool = false
    var tint: AnyShapeStyle = AnyShapeStyle(Color.white)
    var lineWidth: CGFloat = 1.6

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let path = Self.path(for: kind, side: s)
            if filled {
                ctx.fill(path, with: .style(tint))
            } else {
                ctx.stroke(path, with: .style(tint),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Authored in a unit box (0…1) then scaled to `side`.
    static func path(for kind: Kind, side s: CGFloat) -> Path {
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var p = Path()
        switch kind {
        case .wallet:
            // A billfold with a rounded pocket + a button.
            let body = CGRect(x: 0.12 * s, y: 0.26 * s, width: 0.76 * s, height: 0.50 * s)
            p.addRoundedRect(in: body, cornerSize: CGSize(width: 0.12 * s, height: 0.12 * s))
            // flap
            p.move(to: P(0.12, 0.40))
            p.addLine(to: P(0.62, 0.40))
            p.addLine(to: P(0.62, 0.26))
            // clasp dot
            p.addEllipse(in: CGRect(x: 0.70 * s, y: 0.46 * s, width: 0.10 * s, height: 0.10 * s))
        case .arrowDown:
            p.move(to: P(0.5, 0.16))
            p.addLine(to: P(0.5, 0.72))
            p.move(to: P(0.28, 0.50))
            p.addLine(to: P(0.5, 0.74))
            p.addLine(to: P(0.72, 0.50))
            // landing line
            p.move(to: P(0.26, 0.86))
            p.addLine(to: P(0.74, 0.86))
        case .arrowUp:
            p.move(to: P(0.5, 0.84))
            p.addLine(to: P(0.5, 0.28))
            p.move(to: P(0.28, 0.50))
            p.addLine(to: P(0.5, 0.26))
            p.addLine(to: P(0.72, 0.50))
        case .lock:
            // shackle
            p.addArc(center: P(0.5, 0.42), radius: 0.18 * s,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.move(to: P(0.32, 0.42))
            p.addLine(to: P(0.32, 0.50))
            p.move(to: P(0.68, 0.42))
            p.addLine(to: P(0.68, 0.50))
            // body
            let lockBody = CGRect(x: 0.26 * s, y: 0.50 * s, width: 0.48 * s, height: 0.34 * s)
            p.addRoundedRect(in: lockBody, cornerSize: CGSize(width: 0.08 * s, height: 0.08 * s))
        case .coins:
            p.addEllipse(in: CGRect(x: 0.20 * s, y: 0.30 * s, width: 0.44 * s, height: 0.20 * s))
            p.move(to: P(0.20, 0.40)); p.addLine(to: P(0.20, 0.56))
            p.addArc(center: P(0.42, 0.56), radius: 0.22 * s,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.move(to: P(0.64, 0.40)); p.addLine(to: P(0.64, 0.56))
            // second coin
            p.addEllipse(in: CGRect(x: 0.40 * s, y: 0.48 * s, width: 0.44 * s, height: 0.20 * s))
        case .pulse:
            p.move(to: P(0.08, 0.50))
            p.addLine(to: P(0.30, 0.50))
            p.addLine(to: P(0.40, 0.26))
            p.addLine(to: P(0.54, 0.74))
            p.addLine(to: P(0.66, 0.42))
            p.addLine(to: P(0.74, 0.50))
            p.addLine(to: P(0.92, 0.50))
        case .chevron:
            p.move(to: P(0.40, 0.28))
            p.addLine(to: P(0.62, 0.50))
            p.addLine(to: P(0.40, 0.72))
        case .pie:
            p.addEllipse(in: CGRect(x: 0.16 * s, y: 0.16 * s, width: 0.68 * s, height: 0.68 * s))
            p.move(to: P(0.5, 0.5)); p.addLine(to: P(0.5, 0.16))
            p.move(to: P(0.5, 0.5)); p.addLine(to: P(0.82, 0.62))
        case .bolt:
            p.move(to: P(0.56, 0.12))
            p.addLine(to: P(0.30, 0.54))
            p.addLine(to: P(0.48, 0.54))
            p.addLine(to: P(0.42, 0.88))
            p.addLine(to: P(0.70, 0.44))
            p.addLine(to: P(0.50, 0.44))
            p.closeSubpath()
        case .bank:
            p.move(to: P(0.50, 0.16)); p.addLine(to: P(0.14, 0.36)); p.addLine(to: P(0.86, 0.36)); p.closeSubpath()
            for cx: CGFloat in [0.24, 0.42, 0.58, 0.76] {
                p.move(to: P(cx, 0.40)); p.addLine(to: P(cx, 0.74))
            }
            p.move(to: P(0.14, 0.80)); p.addLine(to: P(0.86, 0.80))
        case .spark:
            p.move(to: P(0.5, 0.14)); p.addLine(to: P(0.58, 0.42)); p.addLine(to: P(0.86, 0.5))
            p.addLine(to: P(0.58, 0.58)); p.addLine(to: P(0.5, 0.86)); p.addLine(to: P(0.42, 0.58))
            p.addLine(to: P(0.14, 0.5)); p.addLine(to: P(0.42, 0.42)); p.closeSubpath()
        }
        return p
    }
}

// MARK: - WalletEyebrow — drawn-glyph section eyebrow

/// The iridescent small-caps eyebrow used across the wallet, with a DRAWN
/// glyph (not an SF Symbol). Shared by both screens for one voice.
struct WalletEyebrow: View {
    let glyph: WalletGlyph.Kind
    let text: String
    var size: CGFloat = 9

    var body: some View {
        HStack(spacing: 6) {
            WalletGlyph(kind: glyph, size: size + 2, tint: AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.4)
            Text(text)
                .font(.system(size: size, weight: .heavy)).tracking(1.2)
                .foregroundStyle(LinearGradient.diagonal)
        }
    }
}

// MARK: - WalletBalanceHero — the HERO "money card"

/// The headline balance. A layered volumetric card: brand-diagonal base,
/// a radial aurora bloom, a slow animated sheen sweep, a top-rim
/// catch-light, and a dual iridescent glow so it reads as a premium money
/// card floating off obsidian. The TOTAL renders as a large gradient-aware
/// white numeral with a moving sheen highlight (Reduce-Motion freezes it).
/// Beneath sits the bespoke `WalletCompositionBar`.
///
/// All inputs are cents from `eusoWallet.getSnapshot`; honest em-dash at
/// nil/zero via `WalletMoney`.
struct WalletBalanceHero: View {
    let availableCents: Int?
    let pendingCents: Int?
    let reservedCents: Int?
    /// Currency code from the snapshot ("USD"). Rendered as a small chip.
    var currency: String? = "USD"
    /// Optional caption under the available figure ("Spendable now").
    var caption: String? = "Available to spend"

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheen: CGFloat = -0.4
    @State private var barProgress: CGFloat = 0

    private var isDark: Bool { palette.bgPage == Theme.dark.bgPage }

    private var totalCents: Int {
        (availableCents ?? 0) + (pendingCents ?? 0) + (reservedCents ?? 0)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        VStack(alignment: .leading, spacing: 16) {
            // ── eyebrow + currency chip ──
            HStack {
                HStack(spacing: 6) {
                    WalletGlyph(kind: .wallet, size: 13, tint: AnyShapeStyle(Color.white.opacity(0.9)), lineWidth: 1.4)
                    Text("TOTAL BALANCE")
                        .font(.system(size: 10, weight: .heavy)).tracking(1.4)
                        .foregroundStyle(.white.opacity(0.82))
                }
                Spacer(minLength: 0)
                if let cur = currency, !cur.isEmpty {
                    Text(cur.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.16)).clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.75))
                }
            }

            // ── the hero numeral with a moving sheen highlight ──
            heroNumeral

            // ── available callout (the actually-spendable figure) ──
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(WalletMoney.usdCents(availableCents))
                    .font(.system(size: 19, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(.white)
                Text(caption ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 0)
            }

            // ── bespoke composition bar (available / reserved / pending) ──
            WalletCompositionBar(
                availableCents: availableCents,
                reservedCents: reservedCents,
                pendingCents: pendingCents,
                progress: barProgress,
                onGradient: true
            )
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient.diagonal
                RadialGradient(colors: [.white.opacity(0.30), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 340)
                LinearGradient(colors: [.clear, .white.opacity(0.10), .clear],
                               startPoint: .top, endPoint: .bottomTrailing)
            }
        }
        .overlay(alignment: .top) {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        }
        .clipShape(shape)
        .shadow(color: Brand.blue.opacity(isDark ? 0.42 : 0.18), radius: 20, x: 0, y: 10)
        .shadow(color: Brand.magenta.opacity(isDark ? 0.30 : 0.12), radius: 24, x: 0, y: 14)
        .onAppear {
            if reduceMotion {
                barProgress = 1
            } else {
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: false)) {
                    sheen = 1.4
                }
                withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.15)) {
                    barProgress = 1
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Total balance \(WalletMoney.usdCents(totalCents > 0 ? totalCents : nil)), available \(WalletMoney.usdCents(availableCents))")
    }

    /// The big number. White heavy numeral with a diagonal white sheen band
    /// masked to the glyphs (so the highlight sweeps across the digits) —
    /// reads "alive" without compromising legibility. Honest em-dash at zero.
    private var heroNumeral: some View {
        let shown = WalletMoney.usdCents(totalCents > 0 ? totalCents : nil)
        return Text(shown)
            .font(.system(size: 46, weight: .heavy))
            .monospacedDigit()
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.85), .clear],
                            startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: geo.size.width * sheen)
                        .blendMode(.plusLighter)
                    }
                    .mask(
                        Text(shown)
                            .font(.system(size: 46, weight: .heavy))
                            .monospacedDigit()
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                    )
                    .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - WalletCompositionBar — the AVAILABLE / RESERVE / PENDING showpiece

/// The breakdown drawn as a single proportional segmented allocation bar
/// (capsule) with a drawn-glyph legend underneath — the bespoke
/// alternative to a plain "Available / Reserved / Pending" list. Each
/// segment's width is proportional to its share of the total; segments
/// animate in via `progress` (0→1). When everything is zero the bar shows
/// an honest hairline "no funds yet" track rather than a fake fill.
///
/// `onGradient` flips the palette for use ON the hero gradient card (light
/// inks) vs. on a normal page card (brand inks).
struct WalletCompositionBar: View {
    let availableCents: Int?
    let reservedCents: Int?
    let pendingCents: Int?
    /// 0→1 reveal driver owned by the parent (so the hero can spring it).
    var progress: CGFloat = 1
    var onGradient: Bool = false

    @Environment(\.palette) private var palette

    private var available: CGFloat { CGFloat(max(0, availableCents ?? 0)) }
    private var reserved: CGFloat { CGFloat(max(0, reservedCents ?? 0)) }
    private var pending: CGFloat { CGFloat(max(0, pendingCents ?? 0)) }
    private var total: CGFloat { available + reserved + pending }

    // Segment colors. On the gradient card we use bright translucent inks;
    // on a page card we use the brand semantic palette.
    private var availColor: Color { onGradient ? .white : Brand.success }
    private var reserveColor: Color { onGradient ? .white.opacity(0.55) : Brand.warning }
    private var pendingColor: Color { onGradient ? .white.opacity(0.32) : Brand.info }
    private var trackColor: Color { onGradient ? .white.opacity(0.18) : palette.borderSoft }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bar
            legend
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let availW = total > 0 ? (available / total) * w * progress : 0
            let resW = total > 0 ? (reserved / total) * w * progress : 0
            let pendW = total > 0 ? (pending / total) * w * progress : 0
            ZStack(alignment: .leading) {
                // track
                Capsule().fill(trackColor)
                if total > 0 {
                    HStack(spacing: 2) {
                        if availW > 0 {
                            Capsule().fill(availColor).frame(width: max(3, availW - 2))
                        }
                        if resW > 0 {
                            Capsule().fill(reserveColor).frame(width: max(3, resW - 2))
                        }
                        if pendW > 0 {
                            Capsule().fill(pendingColor).frame(width: max(3, pendW - 2))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(height: 9)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: availColor, glyph: .arrowUp, label: "Available", cents: availableCents)
            legendItem(color: reserveColor, glyph: .lock, label: "Reserved", cents: reservedCents)
            legendItem(color: pendingColor, glyph: .coins, label: "Pending", cents: pendingCents)
            Spacer(minLength: 0)
        }
    }

    private func legendItem(color: Color, glyph: WalletGlyph.Kind, label: String, cents: Int?) -> some View {
        let inkPrimary: Color = onGradient ? .white : palette.textPrimary
        let inkSecondary: Color = onGradient ? .white.opacity(0.7) : palette.textTertiary
        return HStack(spacing: 5) {
            // drawn dot + glyph
            ZStack {
                Circle().fill(color.opacity(onGradient ? 0.9 : 0.16)).frame(width: 16, height: 16)
                WalletGlyph(kind: glyph, size: 10,
                            tint: AnyShapeStyle(onGradient ? Color(white: 0.12) : color), lineWidth: 1.3)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(inkSecondary)
                Text(WalletMoney.usdCents(cents))
                    .font(.system(size: 11, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(inkPrimary)
            }
        }
    }
}

// MARK: - WalletLedgerRow — the bespoke credit / debit ledger entry

/// One transaction, drawn with intention: a directional glyph tile
/// (up = credit / green, down = debit / red) whose ring is the credit/debit
/// color, the title + memo + timestamp stacked, a micro "spark" intention
/// mark, and the signed amount in tabular figures color-keyed to direction.
/// Sits as a row inside a carded ledger. Amounts are dollars (the server's
/// `wallet_transactions.amount` decimal) routed through honest formatting.
struct WalletLedgerRow: View {
    let title: String
    let memo: String?
    let timestamp: String?
    /// Signed dollars: positive = credit (in), negative = debit (out).
    let amountDollars: Double
    /// Transaction type for the glyph/label nuance (earnings/payout/fee/…).
    var type: String? = nil
    var showDivider: Bool = true

    @Environment(\.palette) private var palette

    private var isCredit: Bool { amountDollars >= 0 }
    private var directionColor: Color { isCredit ? Brand.success : Brand.danger }
    private var glyph: WalletGlyph.Kind {
        switch (type ?? "").lowercased() {
        case "fee":     return .arrowDown
        case "payout":  return .arrowDown
        case "bonus":   return .spark
        case "refund":  return .arrowUp
        default:        return isCredit ? .arrowUp : .arrowDown
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // direction tile — drawn glyph, color-rimmed
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(directionColor.opacity(0.12))
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(directionColor.opacity(0.45), lineWidth: 1)
                    WalletGlyph(kind: glyph, size: 16, tint: AnyShapeStyle(directionColor), lineWidth: 1.7)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let memo = memo, !memo.isEmpty {
                            Text(memo)
                                .font(EType.micro)
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1)
                        }
                        if let ts = timestamp, !ts.isEmpty {
                            if memo?.isEmpty == false {
                                Circle().fill(palette.textTertiary.opacity(0.5)).frame(width: 2.5, height: 2.5)
                            }
                            Text(humanISO(ts))
                                .font(EType.mono(.micro)).tracking(0.3)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: Space.s2)

                VStack(alignment: .trailing, spacing: 3) {
                    Text((isCredit ? "+" : "−") + WalletMoney.usdDollarsPrecise(abs(amountDollars)))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(directionColor)
                    // micro intention spark — a 3-pip directional cue
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule()
                                .fill(directionColor.opacity(0.85 - Double(i) * 0.28))
                                .frame(width: 5, height: 2.5)
                        }
                    }
                    .scaleEffect(x: isCredit ? 1 : -1, anchor: .center)
                }
            }
            .padding(.vertical, 10)

            if showDivider {
                Rectangle()
                    .fill(palette.iridescentHairline)
                    .frame(height: 1)
                    .opacity(0.4)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - WalletHoldTile — bespoke escrow / hold card

/// An itemized escrow hold rendered as a bespoke tile: a drawn lock glyph
/// in a warning-tinted vault, the load reference + route, a status pill,
/// and the held amount. Beautiful itemization of the hold/reserve breakdown
/// (vs. a plain list). Honest: amount em-dashes at nil.
struct WalletHoldTile: View {
    let loadRef: String?
    let route: String?
    let status: String?
    let amountDollars: Double?

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.warning.opacity(0.12))
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.warning.opacity(0.40), lineWidth: 1)
                WalletGlyph(kind: .lock, size: 18, tint: AnyShapeStyle(Brand.warning), lineWidth: 1.7)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(dashIfEmpty(loadRef))
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(dashIfEmpty(route))
                    .font(EType.micro).foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(WalletMoney.usdDollarsPrecise(amountDollars))
                    .font(.system(size: 15, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                if let st = status, !st.isEmpty {
                    Text(st.uppercased())
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Brand.warning.opacity(0.14)))
                }
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md, intensity: .whisper)
    }
}

// MARK: - WalletShimmer — bespoke loading skeleton

/// A bounded, brand-tinted shimmer used while the wallet loads. A diagonal
/// highlight sweeps across a rounded block. Reduce-Motion shows a static
/// soft block. Always paired with a caller-side timeout so it never lingers.
struct WalletShimmer: View {
    var height: CGFloat = 16
    var radius: CGFloat = 8

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(palette.bgCardSoft)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, Brand.blue.opacity(0.18), Brand.magenta.opacity(0.18), .clear],
                            startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: geo.size.width * phase)
                    }
                    .clipShape(shape)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Wallet components — Night") {
    ScrollView {
        VStack(spacing: 16) {
            WalletBalanceHero(availableCents: 482_350, pendingCents: 64_000, reservedCents: 128_900)
            WalletLedgerRow(title: "Load payout", memo: "Load DAL-8842", timestamp: nil, amountDollars: 2_450.00, type: "earnings")
            WalletLedgerRow(title: "Platform fee", memo: "Brokerage", timestamp: nil, amountDollars: -36.75, type: "fee", showDivider: false)
            WalletHoldTile(loadRef: "LOAD-8842", route: "Dallas → Laredo", status: "held", amountDollars: 1_289.00)
            WalletShimmer(height: 120, radius: 20)
        }
        .padding(14)
    }
    .background(Theme.dark.bgPage)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("Wallet components — Afternoon") {
    ScrollView {
        VStack(spacing: 16) {
            WalletBalanceHero(availableCents: 482_350, pendingCents: 64_000, reservedCents: 128_900)
            WalletLedgerRow(title: "Load payout", memo: "Load DAL-8842", timestamp: nil, amountDollars: 2_450.00, type: "earnings")
            WalletHoldTile(loadRef: "LOAD-8842", route: "Dallas → Laredo", status: "held", amountDollars: 1_289.00)
        }
        .padding(14)
    }
    .background(Theme.light.bgPage)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
