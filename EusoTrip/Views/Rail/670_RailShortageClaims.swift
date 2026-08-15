//
//  670_RailShortageClaims.swift
//  EusoTrip — Rail Engineer · Shortage Claims (carrier-side cargo claims).
//
//  Bespoke port of "05 Rail/670 Rail Shortage Claims.svg" (Light + Dark).
//  Archetype = RECONCILIATION + EVIDENCE-DOSSIER CLAIMS LIST. Each claim row pairs a
//  BOL-vs-RECEIVED reconciliation bar (full track = BOL expected, blue fill = received,
//  red gap = the shortage) with a 4-pip EVIDENCE DOSSIER (BOL · WT · DR · PH; filled =
//  on file, hollow = missing) and a status word, so provability is legible at a glance.
//  Hero is a RECONCILIATION SUMMARY (open exposure $ left, expected-vs-received right).
//
//  Wired:
//    freightClaims.getShortageClaims (EXISTS freightClaims.ts:1082, protectedProcedure,
//      companyId-scoped) input {status?, limit, offset}
//      → { claims:[{id,claimNumber,loadNumber,commodity,expectedQty,receivedQty,
//                   shortageQty,shortageValue,status(reported|investigating|confirmed|
//                   resolved|denied),filedDate,reconciliation{bolQty,deliveryReceiptQty,
//                   variance,variancePercent}}],
//          total, summary{totalShortages,totalValue,avgShortagePercent,topCommodities} }
//      NOTE: server returns empty claims + zeroed summary (data layer is a stub today),
//      so the screen renders an honest empty/loading/error state at runtime; the seed
//      data lives ONLY in #Preview.
//
//  STUB (named gaps, to the-oath):
//    (1) No per-claim evidence inventory on the wire → the 4-pip dossier is derived
//        client-side from shortage severity. Propose claims[].evidence:{bol,wt,dr,ph}.
//    (2) No OT5/AAR statute deadline on the wire → the at-risk countdown is derived from
//        filedDate (+9mo per AAR Rule 102/123). Propose claims[].statuteDeadline.
//    (3) "File ready" CTA has no matching bulk mutation (fileClaim is per-load and needs
//        loadId/amount/description) → marked STUB; tapping re-runs load().
//
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//

import SwiftUI

// MARK: - Wire input (per-file; no module-level EmptyInput)

private struct ShortageClaimsInput670: Encodable {
    let limit: Int
    let offset: Int
}

// MARK: - Wire response (maps 1:1 to getShortageClaims)

private struct ShortageClaimsResp670: Decodable {
    let claims: [WireClaim670]
    let summary: WireSummary670?
}

private struct WireClaim670: Decodable, Identifiable {
    let id: String
    let claimNumber: String?
    let loadNumber: String?
    let commodity: String?
    let expectedQty: Int?
    let receivedQty: Int?
    let shortageQty: Int?
    let shortageValue: Double?
    let status: String?
    let filedDate: String?
    let reconciliation: WireReconciliation670?
}

private struct WireReconciliation670: Decodable {
    let bolQty: Int?
    let deliveryReceiptQty: Int?
    let variance: Int?
    let variancePercent: Double?
}

private struct WireSummary670: Decodable {
    let totalShortages: Int?
    let totalValue: Double?
    let avgShortagePercent: Double?
    let topCommodities: [String]?
}

// MARK: - View model

private enum ShortageStatus670 {
    case confirmed, investigating, atRisk

    var word: String {
        switch self {
        case .confirmed:     return "CONFIRMED"
        case .investigating: return "INVESTIGATING"
        case .atRisk:        return "AT RISK"
        }
    }
    var tint: Color {
        switch self {
        case .confirmed:     return Brand.success
        case .investigating: return Brand.warning
        case .atRisk:        return Brand.danger
        }
    }

    /// Map the wire status word (+ derived at-risk flag) to the bespoke 3-state posture.
    static func from(_ raw: String?, atRisk: Bool) -> ShortageStatus670 {
        if atRisk { return .atRisk }
        switch (raw ?? "").lowercased() {
        case "confirmed", "resolved": return .confirmed
        default:                      return .investigating
        }
    }
}

private struct EvidenceDossier670 {
    let bol, wt, dr, ph: Bool

    var note: (String, Color) {
        let missing = [bol, wt, dr, ph].filter { !$0 }.count
        if missing == 0 { return ("evidence complete", Brand.success) }
        if missing == 1 { return ("photos missing", Brand.warning) }
        return ("\(missing) docs missing", Brand.danger)
    }
}

private struct ClaimVM670: Identifiable {
    let id: String
    let commodity: String
    let claim: String
    let load: String
    let statute: String
    let expectedQty: Int
    let receivedQty: Int
    let shortVar: String
    let value: String
    let status: ShortageStatus670
    let evidence: EvidenceDossier670

    var receivedPct: CGFloat {
        guard expectedQty > 0 else { return 0 }
        return min(1, max(0, CGFloat(receivedQty) / CGFloat(expectedQty)))
    }
}

// MARK: - Wrapper (Shell + rail nav, COMPLIANCE inked)

struct RailShortageClaimsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailShortageClaimsBody670() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailShortageClaimsBody670: View {
    @Environment(\.palette) private var palette

    /// Preview-only seed. When non-nil, `load()` populates from this instead of the
    /// network so the bespoke layout is reviewable offline. Always nil at runtime.
    var previewSeed: ShortageClaimsResp670? = nil

    @State private var claims: [ClaimVM670] = []
    @State private var exposure: String = "$0"
    @State private var totalClaims: Int = 0
    @State private var expectedTotal: String = "-"
    @State private var receivedTotal: String = "-"
    @State private var loading = true
    @State private var loadError: String? = nil

    private let received = Color(red: 0.129, green: 0.588, blue: 0.953)
    private let short    = Color(red: 0.937, green: 0.325, blue: 0.314)

    // MARK: Derived posture

    private var readyCount: Int { claims.filter { $0.status == .confirmed }.count }
    private var investigatingCount: Int { claims.filter { $0.status == .investigating }.count }
    private var atRiskCount: Int { claims.filter { $0.status == .atRisk }.count }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if loading {
                    LifecycleCard {
                        Text("Loading shortage claims…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if claims.isEmpty {
                    EusoEmptyState(systemImage: "shippingbox",
                                   title: "No open shortage claims",
                                   subtitle: "BOL-vs-received reconciliation is clean for this carrier.")
                } else {
                    hero
                    claimsCard
                    esangRow
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    EusoTripBrandMark(size: 12)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · CARGO CLAIMS")
                        .font(.system(size: 9, weight: .heavy)).kerning(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("SHORTAGE")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Shortage claims")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("BNSF INTERMODAL")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textSecondary)
                    Text("BOL vs received")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            IridescentHairline()
        }
    }

    // MARK: Hero — reconciliation summary

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OPEN SHORTAGE EXPOSURE · \(totalClaims) CLAIM\(totalClaims == 1 ? "" : "S")")
                            .font(.system(size: 9, weight: .heavy)).kerning(1.0)
                            .foregroundStyle(palette.textSecondary)
                        Text(exposure)
                            .font(.system(size: 34, weight: .bold)).kerning(-0.6).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("EXPECTED · BOL")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(expectedTotal)
                            .font(.system(size: 15, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text("RECEIVED · DR")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textSecondary).padding(.top, 2)
                        Text(receivedTotal)
                            .font(.system(size: 15, weight: .bold)).monospacedDigit()
                            .foregroundStyle(received)
                    }
                }
                Spacer(minLength: 6)
                postureBar
            }.padding(20)
        }.frame(height: 130)
    }

    private var postureBar: some View {
        let total = max(1, claims.count)
        let readyFrac = CGFloat(readyCount) / CGFloat(total)
        let invFrac   = CGFloat(investigatingCount) / CGFloat(total)
        let riskFrac  = CGFloat(atRiskCount) / CGFloat(total)
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                let w = g.size.width
                HStack(spacing: 2) {
                    Capsule().fill(Brand.success).frame(width: w * readyFrac)
                    Rectangle().fill(Brand.warning).frame(width: w * invFrac)
                    Capsule().fill(short).frame(width: w * riskFrac)
                }
            }.frame(height: 10)
            HStack(spacing: 14) {
                legend(Brand.success, "\(readyCount)", "ready to file")
                legend(Brand.warning, "\(investigatingCount)", "investigating")
                legend(short, "\(atRiskCount)", "at risk")
                Spacer()
            }
        }
    }

    private func legend(_ c: Color, _ n: String, _ t: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(n).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(t).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Signature — reconciliation + evidence list

    private var claimsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CLAIMS · LEAST PROVABLE FLAGGED")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(claims.count) of \(totalClaims)")
                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(claims.enumerated()), id: \.element.id) { i, c in
                    claimRow(c)
                    if i < claims.count - 1 {
                        Divider().overlay(palette.borderFaint)
                    }
                }
            }
            .padding(.vertical, 6)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.borderFaint))
        }
    }

    private func claimRow(_ c: ClaimVM670) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(c.status.tint.opacity(0.14)).frame(width: 40, height: 40)
                .overlay(Image(systemName: "shippingbox").font(.system(size: 15)).foregroundStyle(c.status.tint))
            VStack(alignment: .leading, spacing: 6) {
                Text(c.commodity).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(c.claim) · \(c.load) · \(c.statute)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                // reconciliation bar
                HStack(spacing: 6) {
                    GeometryReader { g in
                        let w = g.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.textPrimary.opacity(0.06)).frame(height: 8)
                            HStack(spacing: 0) {
                                Capsule().fill(received).frame(width: w * c.receivedPct, height: 8)
                                Capsule().fill(short).frame(width: w * (1 - c.receivedPct), height: 8)
                            }
                        }
                    }.frame(width: 150, height: 8)
                    Text(c.shortVar)
                        .font(.system(size: 10, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Brand.danger)
                }
                evidencePips(c.evidence)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(c.value).font(.system(size: 15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text(c.status.word)
                    .font(.system(size: 9, weight: .heavy)).kerning(0.4)
                    .foregroundStyle(c.status.tint)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func evidencePips(_ e: EvidenceDossier670) -> some View {
        let pips: [(String, Bool)] = [("BOL", e.bol), ("WT", e.wt), ("DR", e.dr), ("PH", e.ph)]
        let note = e.note
        return HStack(spacing: 4) {
            ForEach(pips, id: \.0) { p in
                Text(p.0)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(p.1 ? Color.white : palette.textSecondary)
                    .frame(width: 26, height: 13)
                    .background(p.1 ? AnyView(RoundedRectangle(cornerRadius: 4).fill(Brand.blue))
                                    : AnyView(RoundedRectangle(cornerRadius: 4).stroke(palette.textSecondary, lineWidth: 1.2)))
            }
            Text(note.0).font(.system(size: 9, weight: .bold)).foregroundStyle(note.1).padding(.leading, 4)
        }
    }

    private var esangRow: some View {
        let flagged = claims.first(where: { $0.status == .atRisk }) ?? claims.first
        return HStack(spacing: 0) {
            ZStack {
                Circle().fill(Brand.magenta.opacity(0.18)).frame(width: 40, height: 40).blur(radius: 6)
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
            }.padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG AI")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                if let f = flagged {
                    Text("\(f.claim) is the least-provable claim.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("\(f.value) · its \(f.statute) statute window is closing.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                } else {
                    Text("All claims are fully documented.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.borderFaint))
    }

    private var ctaRow: some View {
        HStack(spacing: 8) {
            // STUB: no bulk file mutation on the wire (fileClaim is per-load); re-run load().
            CTAButton(title: "File ready · \(readyCount)", action: { Task { await load() } })
            Button {
                Task { await load() }
            } label: {
                Text("Reconcile")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load + mapping

    private func load() async {
        loading = true; loadError = nil
        if let seed = previewSeed {
            apply(seed)
            loading = false
            return
        }
        do {
            let resp: ShortageClaimsResp670 = try await EusoTripAPI.shared.query(
                "freightClaims.getShortageClaims",
                input: ShortageClaimsInput670(limit: 20, offset: 0)
            )
            apply(resp)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func apply(_ resp: ShortageClaimsResp670) {
        let mapped = resp.claims.map { Self.map($0) }
        // Least-provable first: most missing docs, then largest shortage value.
        claims = mapped.sorted { lhs, rhs in
            let lm = [lhs.evidence.bol, lhs.evidence.wt, lhs.evidence.dr, lhs.evidence.ph].filter { !$0 }.count
            let rm = [rhs.evidence.bol, rhs.evidence.wt, rhs.evidence.dr, rhs.evidence.ph].filter { !$0 }.count
            return lm == rm ? lhs.value > rhs.value : lm > rm
        }
        totalClaims = resp.summary?.totalShortages ?? resp.claims.count
        let totalValue = resp.summary?.totalValue ?? resp.claims.reduce(0) { $0 + ($1.shortageValue ?? 0) }
        exposure = Self.usd(totalValue)
        let expSum = resp.claims.reduce(0) { $0 + ($1.expectedQty ?? 0) }
        let recSum = resp.claims.reduce(0) { $0 + ($1.receivedQty ?? 0) }
        expectedTotal = expSum > 0 ? "\(expSum) units" : "-"
        receivedTotal = recSum > 0 ? "\(recSum) units" : "-"
    }

    // MARK: - Wire → VM mapping (pure)

    private static func map(_ w: WireClaim670) -> ClaimVM670 {
        let expected = w.expectedQty ?? w.reconciliation?.bolQty ?? 0
        let receivedQ = w.receivedQty ?? w.reconciliation?.deliveryReceiptQty ?? 0
        let shortQ = w.shortageQty ?? max(0, expected - receivedQ)
        let pct = w.reconciliation?.variancePercent ?? (expected > 0 ? Double(shortQ) / Double(expected) * 100 : 0)
        // Derived (STUB): evidence completeness inferred from severity; statute window from filedDate.
        let (evidence, daysLeft) = derive(status: w.status, variancePercent: pct, filedDate: w.filedDate)
        let atRisk = daysLeft <= 14
        let status = ShortageStatus670.from(w.status, atRisk: atRisk)
        return ClaimVM670(
            id: w.id,
            commodity: w.commodity ?? "Cargo shortage",
            claim: w.claimNumber ?? "CLM-\(w.id.prefix(4))",
            load: w.loadNumber ?? "-",
            statute: "OT5 \(daysLeft)d",
            expectedQty: expected,
            receivedQty: receivedQ,
            shortVar: shortVarLabel(shortQ: shortQ, pct: pct),
            value: usd(w.shortageValue ?? 0),
            status: status,
            evidence: evidence
        )
    }

    private static func shortVarLabel(shortQ: Int, pct: Double) -> String {
        "-\(shortQ) · \(String(format: "%.1f", pct))%"
    }

    /// STUB derivation: no per-claim evidence/statute on the wire yet.
    private static func derive(status: String?, variancePercent: Double, filedDate: String?) -> (EvidenceDossier670, Int) {
        let daysSinceFiled: Int
        if let filedDate, let d = ISO8601DateFormatter().date(from: filedDate) ?? plainDate(filedDate) {
            daysSinceFiled = max(0, Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0)
        } else {
            daysSinceFiled = 0
        }
        let daysLeft = max(0, 270 - daysSinceFiled) // AAR Rule 102/123: 9-month window.
        // More variance ⇒ more likely missing supporting docs.
        let evidence: EvidenceDossier670
        switch (status ?? "").lowercased() {
        case "confirmed", "resolved": evidence = .init(bol: true, wt: true, dr: true, ph: true)
        case "investigating":         evidence = .init(bol: true, wt: true, dr: true, ph: false)
        default:                      evidence = variancePercent >= 10
            ? .init(bol: true, wt: false, dr: false, ph: false)
            : .init(bol: true, wt: true, dr: false, ph: false)
        }
        return (evidence, daysLeft)
    }

    private static func plainDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    private static func usd(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Previews (seed data lives ONLY here)

/// Preview seed mirroring the canonical SVG sample (3 claims, mixed posture).
private let previewSeed670 = ShortageClaimsResp670(
    claims: [
        .init(id: "c1", claimNumber: "CLM-7741", loadNumber: "RAIL-260518-1A",
              commodity: "Canned goods · 40′ BNSF", expectedQty: 4820, receivedQty: 4700,
              shortageQty: 120, shortageValue: 4200, status: "confirmed", filedDate: "2026-05-26",
              reconciliation: .init(bolQty: 4820, deliveryReceiptQty: 4700, variance: 120, variancePercent: 2.5)),
        .init(id: "c2", claimNumber: "CLM-7738", loadNumber: "RAIL-260516-0C",
              commodity: "Bottled water · 53′ BNSF", expectedQty: 5200, receivedQty: 4890,
              shortageQty: 310, shortageValue: 6140, status: "investigating", filedDate: "2026-04-22",
              reconciliation: .init(bolQty: 5200, deliveryReceiptQty: 4890, variance: 310, variancePercent: 6.0)),
        .init(id: "c3", claimNumber: "CLM-7702", loadNumber: "RAIL-260408-2F",
              commodity: "Auto parts · 40′ BNSF", expectedQty: 4200, receivedQty: 3740,
              shortageQty: 460, shortageValue: 8200, status: "reported", filedDate: "2025-09-15",
              reconciliation: .init(bolQty: 4200, deliveryReceiptQty: 3740, variance: 460, variancePercent: 11.0))
    ],
    summary: .init(totalShortages: 6, totalValue: 18540, avgShortagePercent: 6.5, topCommodities: [])
)

@MainActor private func RailShortageClaimsPreview670(_ theme: Theme.Palette) -> some View {
    Shell(theme: theme) { RailShortageClaimsBody670(previewSeed: previewSeed670) } nav: {
        BottomNav(
            leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                      NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
            trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                       NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
            orbState: .idle
        )
    }
    .environmentObject(EusoTripSession())
}

#Preview("670 · Shortage claims · Light") {
    RailShortageClaimsPreview670(Theme.light).preferredColorScheme(.light)
}

#Preview("670 · Shortage claims · Night") {
    RailShortageClaimsPreview670(Theme.dark).preferredColorScheme(.dark)
}
