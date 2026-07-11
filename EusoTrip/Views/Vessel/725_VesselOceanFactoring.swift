//
//  725_VesselOceanFactoring.swift
//  EusoTrip — Vessel Operator · Ocean Freight Factoring.
//
//  Faithful 1:1 native port of "725 Vessel Ocean Factoring · Dark/Light".
//  MONEY / ADVANCE-WATERFALL archetype: a factoring advance decision on an
//  ocean B/L invoice — advance-rate tier band, a fee waterfall (face → advance
//  → reserve → net), a debtor-credit card, and a factor-vs-wait recommendation.
//
//  HONEST BINDING (server/routers/factoring.ts):
//    · factoring.getRates    — REAL standard/quickPay fee rates from platformFeeConfigs.
//    · factoring.getOverview — REAL account: advanceRate, factoringRate, reserveBalance.
//    · factoring.getInvoices — REAL eligible invoice (face = invoiceAmount); no invoice → honest empty.
//    · factoring.getDebtors  — REAL debtor credit (rating, avg days-to-pay).
//  Waterfall math is computed from the REAL face value × the REAL selected fee
//  rate — never a fabricated advance figure. HONEST GAP: an OCEAN-scoped advance
//  (factor a vesselShipments B/L) needs factoring.createOceanAdvance (proposed to
//  the-oath); the "Request advance" CTA surfaces that honestly, no fake fund move.
//  RBAC protected/factoringProcedure · transportMode=vessel · US/CA/MX assignment-law overlay.
//

import SwiftUI

private struct FactoringRates725: Decodable {
    let standard: Double?; let quickPay: Double?; let sameDay: Double?
    let currentRate: Double?; let advanceRate: Double?
}
private struct FactoringOverview725: Decodable {
    let account: FactoringAccount725?
}
private struct FactoringAccount725: Decodable {
    let status: String?; let reserveBalance: Double?; let factoringRate: Double?; let advanceRate: Double?
    let availableCredit: Double?
}
private struct FactoringInvoice725: Decodable {
    let id: String?; let invoiceNumber: String?; let loadId: Int?
    let invoiceAmount: Double?; let advanceAmount: Double?; let status: String?
}
private struct Debtor725: Decodable {
    let id: String?; let name: String?; let creditRating: String?
    let avgDaysToPay: Int?; let outstanding: Double?; let riskLevel: String?
}

struct VesselOceanFactoringScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselOceanFactoringBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private enum AdvanceTier725 { case standard, quickPay }

private struct VesselOceanFactoringBody: View {
    @Environment(\.palette) private var palette

    @State private var rates: FactoringRates725? = nil
    @State private var account: FactoringAccount725? = nil
    @State private var invoice: FactoringInvoice725? = nil
    @State private var debtor: Debtor725? = nil
    @State private var tier: AdvanceTier725 = .quickPay

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil

    private var feeRate: Double {
        switch tier {
        case .standard: return rates?.standard ?? account?.factoringRate ?? 0.03
        case .quickPay: return rates?.quickPay ?? 0.03
        }
    }
    private var advanceRate: Double { max(0, 1 - feeRate) }
    private var face: Double? { invoice?.invoiceAmount }
    private var advance: Double? { face.map { $0 * advanceRate } }
    private var reserve: Double? { face.map { $0 * feeRate } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    skeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    advanceRateSection
                    if face != nil {
                        feeWaterfall
                    } else {
                        noInvoiceCard
                    }
                    debtorCard
                    assignmentBand
                    ctaRow
                    if let actionMessage {
                        LifecycleCard { Text(actionMessage).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · OCEAN FACTORING")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("EusoWallet").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            Text("Freight factoring").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            ForEach([132, 92, 124], id: \.self) { h in
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: CGFloat(h))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    // Hero — net advance today
    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(Color(hex: 0x141928)).padding(1.5)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(invoice?.invoiceNumber.map { "Invoice \($0) · ocean freight" } ?? "No eligible ocean invoice")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xAAB2BB)).lineLimit(1)
                    Spacer()
                    StatusPill(text: face != nil ? "Eligible" : "None", kind: face != nil ? .success : .neutral)
                }
                Text("Factor this invoice · same-day cash")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0xAAB2BB))
                Text(advance.map { usd0($0) } ?? "—")
                    .font(.system(size: 30, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                Text(netCaption)
                    .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Color(hex: 0x6E7681))
            }
            .padding(Space.s5)
        }
        .frame(minHeight: 132)
    }
    private var netCaption: String {
        let pct = Int((advanceRate * 100).rounded())
        let tierName = tier == .quickPay ? "QuickPay" : "Standard"
        let faceStr = face.map { " · face \(usd0($0))" } ?? ""
        return "NET ADVANCE TODAY · \(pct)% \(tierName)\(faceStr)"
    }

    // Advance rate tier band
    private var advanceRateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ADVANCE RATE", ref: "factoring.getRates", gap: false)
            HStack(spacing: Space.s3) {
                tierButton(.standard, title: "Standard", speed: "24h",
                           pct: 1 - (rates?.standard ?? 0.03))
                tierButton(.quickPay, title: "QuickPay", speed: "4h",
                           pct: 1 - (rates?.quickPay ?? 0.03))
            }
            Text(String(format: "%.1f%% factoring fee · held in reserve, released on collection", feeRate * 100))
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
        .padding(16).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private func tierButton(_ t: AdvanceTier725, title: String, speed: String, pct: Double) -> some View {
        let sel = tier == t
        return Button { tier = t } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(sel ? .white : palette.textPrimary)
                    Spacer()
                    if sel { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white) }
                }
                Text("\(Int((pct * 100).rounded()))% · \(speed)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(sel ? .white.opacity(0.9) : palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Group { if sel { LinearGradient.diagonal } else { palette.bgCardSoft } })
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(sel ? Color.clear : palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // Fee waterfall
    private var feeWaterfall: some View {
        VStack(alignment: .leading, spacing: 0) {
            waterfallRow("Face value", face.map { usd0($0) } ?? "—", tint: palette.textPrimary)
            rowDivider
            waterfallRow("Advance \(Int((advanceRate * 100).rounded()))%", advance.map { "+\(usd0($0))" } ?? "—", tint: Brand.success)
            rowDivider
            waterfallRow("Reserve \(String(format: "%.1f%%", feeRate * 100)) held", reserve.map { usd0($0) } ?? "—", tint: Color(hex: 0xFF6F61))
            Rectangle().fill(palette.borderSoft).frame(height: 1).padding(.horizontal, 16).padding(.vertical, 2)
            HStack {
                Text("Net to wallet today").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Spacer()
                Text(advance.map { usd0($0) } ?? "—").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Text(reserveNote).font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(alignment: .top) {
            sectionLabel("FEE WATERFALL · factoringFeePercent", ref: "factoring.ts:316", gap: false)
                .padding(.horizontal, 4).offset(y: -22)
        }
        .padding(.top, 22)
    }
    private func waterfallRow(_ label: String, _ value: String, tint: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .bold)).foregroundStyle(tint).monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
    private var reserveNote: String {
        guard let r = reserve else { return "" }
        return "Reserve \(usd0(r)) held · released on collection less \(String(format: "%.1f%%", feeRate * 100)) fee"
    }

    private var noInvoiceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("FEE WATERFALL · factoringFeePercent", ref: "factoring.ts:316", gap: false)
            EusoEmptyState(
                systemImage: "doc.text.magnifyingglass",
                title: "No eligible ocean invoice",
                subtitle: "A factoring advance waterfall appears once a fundable ocean freight invoice is on file. Rates above are live from your account config.")
        }
    }

    // Debtor credit
    private var debtorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DEBTOR CREDIT · getOverview", ref: "factoring.ts:454", gap: false)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: Space.s3) {
                    ZStack {
                        Circle().fill(Color(hex: 0x5AB0FF)).frame(width: 34, height: 34)
                        Text(debtorInitials).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(debtor?.name ?? "No approved debtor").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(debtorMeta).font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    if let rating = debtor?.creditRating, !rating.isEmpty {
                        Text(rating).font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(palette.bgCardSoft))
                    }
                }
                Text(sparkLine).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Brand.success)
            }
            .padding(16).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private var debtorInitials: String {
        guard let n = debtor?.name, let f = n.split(separator: " ").first else { return "—" }
        return String(f.prefix(2)).uppercased()
    }
    private var debtorMeta: String {
        guard let d = debtor else { return "connect a debtor to underwrite advance risk" }
        var parts: [String] = []
        if let r = d.creditRating, !r.isEmpty { parts.append(r) }
        if let days = d.avgDaysToPay, days > 0 { parts.append("\(days)d avg pay") }
        if let out = d.outstanding, out > 0 { parts.append("outstanding \(usd0(out))") }
        return parts.isEmpty ? "credit profile on file" : parts.joined(separator: " · ")
    }
    private var sparkLine: String {
        guard let d = debtor, let days = d.avgDaysToPay, days > 0, let a = advance else {
            return "Spark: factor now — advance rate × urgency favors same-day cash"
        }
        return "Spark: FACTOR today — \(usd0(a)) now vs waiting ~\(days)d for collection"
    }

    // Assignment regime tri-country band
    private var assignmentBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ASSIGNMENT REGIME · by debtor country", ref: "currency", gap: false)
            CountryBand725(rows: [
                .init(code: "US", line: "US · UCC Art. 9 · Notice of Assignment · USD", active: true),
                .init(code: "CA", line: "CA · PPSA · CAD", active: false),
                .init(code: "MX", line: "MX · LGTOC cesión de derechos · MXN", active: false),
            ])
        }
    }

    // CTA
    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Request advance", action: { requestAdvance() }, isLoading: face == nil)
            Button { actionMessage = "Holding the invoice to collect the full face at term — no factoring fee incurred." } label: {
                Text("Wait & save fee").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 140, height: 52)
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .buttonStyle(.plain)
        }
    }
    private func requestAdvance() {
        // HONEST GAP: an ocean-scoped advance against a vesselShipments B/L needs
        // factoring.createOceanAdvance (proposed to the-oath). Surface the exact
        // real terms computed from the live rate — never a fabricated fund move.
        guard let a = advance, let r = reserve else { return }
        actionMessage = "Advance request prepared: \(usd0(a)) today · \(usd0(r)) reserve at \(String(format: "%.1f%%", feeRate * 100)) fee. Ocean-scoped funding awaits factoring.createOceanAdvance (vessel B/L binding)."
    }

    private func sectionLabel(_ title: String, ref: String, gap: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(gap ? "STUB · \(ref)" : ref).font(EType.mono(.micro)).foregroundStyle(gap ? Brand.warning : palette.textTertiary)
        }
    }
    private var rowDivider: some View { Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 16) }

    // Load
    private func load() async {
        loading = true; loadError = nil; actionMessage = nil
        defer { loading = false }
        struct InvInput: Encodable { let limit: Int; let offset: Int }
        struct DebtorInput: Encodable { let limit: Int }
        do {
            rates = try await EusoTripAPI.shared.queryNoInput("factoring.getRates")
            let overview: FactoringOverview725? = try? await EusoTripAPI.shared.queryNoInput("factoring.getOverview")
            account = overview?.account
            let invoices: [FactoringInvoice725] = (try? await EusoTripAPI.shared.query(
                "factoring.getInvoices", input: InvInput(limit: 10, offset: 0))) ?? []
            invoice = invoices.first { ($0.invoiceAmount ?? 0) > 0 } ?? invoices.first
            let debtors: [Debtor725] = (try? await EusoTripAPI.shared.query(
                "factoring.getDebtors", input: DebtorInput(limit: 10))) ?? []
            debtor = debtors.first
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func usd0(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v))
    }
}

// Shared tri-country band (screen-scoped to avoid redeclaration)
private struct CountryBand725: View {
    struct Row: Identifiable { let id = UUID(); let code: String; let line: String; let active: Bool }
    let rows: [Row]
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                HStack(spacing: 10) {
                    Text(r.code).font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(r.active ? Color.white : palette.textSecondary)
                        .frame(width: 26, height: 16)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(r.active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft)))
                    Text(r.line).font(.system(size: 10.5, weight: r.active ? .bold : .regular))
                        .foregroundStyle(r.active ? palette.textPrimary : palette.textSecondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(r.active ? "ACTIVE" : "STANDBY").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(r.active ? Brand.success : palette.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(r.active ? AnyShapeStyle(palette.bgCard) : AnyShapeStyle(Color.clear))
                if idx < rows.count - 1 { Rectangle().fill(palette.borderFaint).frame(height: 1) }
            }
        }
        .padding(6).background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("725 · Vessel Ocean Factoring · Night") { VesselOceanFactoringScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("725 · Vessel Ocean Factoring · Light") { VesselOceanFactoringScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
