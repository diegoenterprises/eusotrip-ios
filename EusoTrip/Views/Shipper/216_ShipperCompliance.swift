//
//  216_ShipperCompliance.swift
//  EusoTrip 2027 UI — Shipper · Compliance (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/216_ShipperCompliance.swift. Persona: Diego
//  Usoro / Eusorone Technologies (companyId 1) per §11. The
//  primary surface is the FLEET-SCOPE compliance audit (catalyst
//  insurance / FMCSA SAFER / hazmat / claims posture) — the
//  shipper-self credit + insurance + document vault data shipped
//  by `compliance.getShipperCompliance` lives below as MY
//  DOCUMENTS supplemental cards.
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · COMPLIANCE / "{N} CATALYSTS · {V} VIOLATIONS"
//    2. Title block      Compliance / "Eusorone Technologies · last sync — · FMCSA SAFER"
//    3. IridescentHairline
//    4. Score hero card  148pt gradient rim · 48pt big score numeral · 80pt ring gauge
//    5. 2×2 compliance grid (INSURANCE · FMCSA SAFER · HAZMAT · CLAIMS YTD)
//    6. CATALYST COMPLIANCE section (3 rows · monogram + pills + 36pt grade badge)
//    7. Action ribbon (warn-wash · expiring doc reminder + Notify CTA)
//    8. MY DOCUMENTS supplemental — credit · insurance · document vault (real backend)
//
//  Real wiring preserved: `compliance.getShipperCompliance` +
//  `compliance.getShipperDocuments` via `ShipperComplianceStore`.
//  The score hero hydrates from `summary.score` and the ring gauge
//  trims to that value. Document vault + credit + insurance cards
//  preserved verbatim as supplemental.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2118 — `compliance.getFleetCompliance` / per-catalyst
//                compliance status not yet shipped. CATALYST
//                COMPLIANCE section paints a single placeholder card
//                ("Fleet-scope catalyst compliance pending") instead
//                of synthesising rows. 2×2 grid tiles paint "—" for
//                Insurance/FMCSA/Hazmat/Claims values.
//    EUSO-2119 — TopBar "{N} CATALYSTS · {V} VIOLATIONS" counter
//                paints "—" until fleet-scope endpoint lands.
//
//  Doctrine refs: §2 ME-tab nav (handled by ContentView); §3
//  numbers-first copy ("98.2 / 100"); §4.3 single iridescent
//  hairline; §7 breathe density; §11 / §11.4 / §13 Diego canon +
//  carrier mix; §16.2 action ribbon CTA pattern (warn-wash variant);
//  §17.2 2×2 credentials-grid recipe; §19.2 file-scoped glyphs +
//  warnWash gradient; §20.4 no dead buttons; §22.2 counter color.
//

import SwiftUI

// MARK: - Document categories (taxonomy mirrors web SHIPPER_DOCS)

private enum ComplianceCategory: String, CaseIterable, Identifiable {
    case all
    case business
    case credit
    case insurance
    case financial
    case facility

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       return "All"
        case .business:  return "Business"
        case .credit:    return "Credit"
        case .insurance: return "Insurance"
        case .financial: return "Financial"
        case .facility:  return "Facility"
        }
    }

    var icon: String {
        switch self {
        case .all:       return "square.grid.2x2"
        case .business:  return "building.2.fill"
        case .credit:    return "creditcard.fill"
        case .insurance: return "shield.fill"
        case .financial: return "dollarsign.circle.fill"
        case .facility:  return "building.fill"
        }
    }

    static func resolve(_ type: String?) -> ComplianceCategory {
        let t = (type ?? "").lowercased()
        if t.contains("license") || t.contains("ein") || t.contains("incorporation") || t.contains("duns") {
            return .business
        }
        if t.contains("credit") || t.contains("trade") || t.contains("bank_reference") {
            return .credit
        }
        if t.contains("insurance") || t.contains("liability") || t.contains("cargo") {
            return .insurance
        }
        if t.contains("w9") || t.contains("payment") || t.contains("ach") || t.contains("financial") {
            return .financial
        }
        if t.contains("facility") || t.contains("warehouse") || t.contains("food_safety") || t.contains("hazmat_permit") {
            return .facility
        }
        return .business
    }
}

private struct RequiredDoc: Hashable, Identifiable {
    let id: String
    let label: String
    let category: ComplianceCategory
    let required: Bool

    static let canonical: [RequiredDoc] = [
        RequiredDoc(id: "business_license",        label: "Business License",            category: .business,  required: true),
        RequiredDoc(id: "ein_letter",              label: "EIN Verification",            category: .business,  required: true),
        RequiredDoc(id: "articles_incorporation",  label: "Articles of Incorporation",   category: .business,  required: true),
        RequiredDoc(id: "duns_number",             label: "D-U-N-S Number",              category: .business,  required: false),
        RequiredDoc(id: "credit_application",      label: "Credit Application",          category: .credit,    required: true),
        RequiredDoc(id: "trade_references",        label: "Trade References (3+)",       category: .credit,    required: true),
        RequiredDoc(id: "bank_reference",          label: "Bank Reference Letter",       category: .credit,    required: false),
        RequiredDoc(id: "financial_statements",    label: "Financial Statements",        category: .credit,    required: false),
        RequiredDoc(id: "general_liability",       label: "General Liability Insurance", category: .insurance, required: true),
        RequiredDoc(id: "cargo_insurance",         label: "Cargo Insurance",             category: .insurance, required: false),
        RequiredDoc(id: "product_liability",       label: "Product Liability",           category: .insurance, required: false),
        RequiredDoc(id: "w9",                      label: "W-9 Form",                    category: .financial, required: true),
        RequiredDoc(id: "payment_terms",           label: "Payment Terms Agreement",     category: .financial, required: true),
        RequiredDoc(id: "ach_authorization",       label: "ACH Authorization",           category: .financial, required: false),
        RequiredDoc(id: "facility_insurance",      label: "Facility Insurance",          category: .facility,  required: false),
        RequiredDoc(id: "food_safety_cert",        label: "Food Safety Cert",            category: .facility,  required: false),
        RequiredDoc(id: "hazmat_permit",           label: "Hazmat Facility Permit",      category: .facility,  required: false),
    ]
}

// MARK: - Store (preserved verbatim)

@MainActor
final class ShipperComplianceStore: ObservableObject {
    enum LoadState {
        case loading
        case error(String)
        case loaded(
            summary: ShipperComplianceAPI.Summary,
            documents: [ShipperComplianceAPI.Document]
        )
    }

    @Published private(set) var state: LoadState = .loading

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        if case .loaded = state {} else { state = .loading }
        do {
            async let s = api.shipperCompliance.getShipperCompliance()
            async let d = api.shipperCompliance.getShipperDocuments()
            let (summary, documents) = try await (s, d)
            state = .loaded(summary: summary, documents: documents)
        } catch {
            state = .error("Couldn't reach compliance service.")
        }
    }
}

// MARK: - Screen root

struct ShipperCompliance: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = ShipperComplianceStore()
    @State private var category: ComplianceCategory = .all

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)

                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
            value: category
        )
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · COMPLIANCE")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            // EUSO-2119 — fleet-scope catalyst count + violations not on API surface yet.
            Text("— CATALYSTS · — VIOLATIONS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel("Fleet violation count, data pending")
        }
        .padding(.horizontal, Space.s5)
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Compliance")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · last sync — · FMCSA SAFER")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 80)
                }
            }
            .padding(.horizontal, Space.s5)
        case .error(let msg):
            errorBanner(msg)
                .padding(.horizontal, Space.s5)
        case .loaded(let summary, let documents):
            VStack(alignment: .leading, spacing: 0) {
                scoreHeroCard(summary)
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)
                complianceGrid
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)
                catalystSection
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)
                if let expiring = firstExpiring(documents) {
                    actionRibbon(for: expiring)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)
                }
                myDocumentsSection(summary: summary, documents: documents)
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)
            }
        }
    }

    private func firstExpiring(_ documents: [ShipperComplianceAPI.Document]) -> ShipperComplianceAPI.Document? {
        documents.first(where: { $0.status.lowercased() == "expiring" })
    }

    // MARK: Score hero card (gradient rim · 148pt · big numeral + ring gauge)

    private func scoreHeroCard(_ s: ShipperComplianceAPI.Summary) -> some View {
        let scoreString = "\(s.score)"
        let scopeBlurb: String = {
            if s.businessVerified { return "FMCSA SAFER · business verified" }
            return "FMCSA SAFER · scope: shipper company"
        }()
        let letter = letterFromScore(s.score)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("FLEET COMPLIANCE SCORE")
                        .font(EType.micro)
                        .tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, 28)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(scoreString)
                            .font(.system(size: 48, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("/ 100")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                    .padding(.top, 16)
                    Text(scopeBlurb)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, 8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.leading, 20)
                Spacer(minLength: 0)
                ringGauge(percent: CGFloat(min(100, max(0, s.score))) / 100, letter: letter)
                    .frame(width: 80, height: 80)
                    .padding(.top, 32)
                    .padding(.trailing, 20)
            }
        }
        .frame(height: 148)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Compliance score \(s.score) out of 100, \(scopeBlurb), grade \(letter)")
    }

    private func letterFromScore(_ score: Int) -> String {
        switch score {
        case 95...:     return "A+"
        case 90..<95:   return "A"
        case 85..<90:   return "A−"
        case 80..<85:   return "B+"
        case 75..<80:   return "B"
        default:         return "C"
        }
    }

    private func ringGauge(percent: CGFloat, letter: String) -> some View {
        ZStack {
            Circle()
                .stroke(palette.borderFaint, lineWidth: 6)
            Circle()
                .trim(from: 0, to: percent)
                .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("PASS")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Text(letter)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: 2×2 compliance grid

    private var complianceGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.s3, alignment: .leading),
                GridItem(.flexible(), spacing: Space.s3, alignment: .leading),
            ],
            spacing: Space.s3
        ) {
            // EUSO-2118 — fleet-scope tile values pending. Label + glyph
            // canon from §17.2 / §11.4; values paint "—".
            tile(kind: .insurance, label: "INSURANCE",   big: "—", sub: "fleet rollup pending", tone: .success)
            tile(kind: .fmcsa,     label: "FMCSA SAFER", big: "—", sub: "fleet rollup pending", tone: .success)
            tile(kind: .hazmat,    label: "HAZMAT · IMDG", big: "—", sub: "active hazmat lanes",   tone: .hazmat)
            tile(kind: .claims,    label: "CLAIMS YTD",   big: "—", sub: "open · closed",          tone: .info)
        }
    }

    private enum TileKind { case insurance, fmcsa, hazmat, claims }
    private enum TileTone { case success, hazmat, info }

    @ViewBuilder
    private func tile(kind: TileKind, label: String, big: String, sub: String, tone: TileTone) -> some View {
        HStack(alignment: .top, spacing: 0) {
            tileGlyph(kind, tone: tone)
                .frame(width: 28, height: 28)
                .padding(.top, 14)
                .padding(.leading, 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(EType.micro)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 18)
                Text(big)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 8)
                Text(sub)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 4)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            Spacer(minLength: 0)
        }
        .frame(height: 80)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(big), \(sub)")
    }

    @ViewBuilder
    private func tileGlyph(_ kind: TileKind, tone: TileTone) -> some View {
        let stroke: Color = {
            switch tone {
            case .success: return Brand.success
            case .hazmat:  return Brand.hazmat
            case .info:    return Brand.info
            }
        }()
        switch kind {
        case .insurance:
            ShieldCheckGlyph()
                .stroke(stroke, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        case .fmcsa:
            CircleCheckGlyph()
                .stroke(stroke, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        case .hazmat:
            HazmatDiamondGlyph()
                .stroke(stroke, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        case .claims:
            DocumentLinesGlyph()
                .stroke(stroke, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Catalyst compliance section

    private var catalystSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("CATALYST COMPLIANCE")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            // EUSO-2118 — fleet-scope catalyst compliance ledger
            // not yet shipped. Render an honest placeholder card
            // instead of synthesising rows.
            VStack(spacing: Space.s2) {
                HStack(spacing: Space.s3) {
                    Image(systemName: "person.2.crop.square.stack")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(palette.textTertiary)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Catalyst-scope compliance pending")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text("Per-catalyst INS / FMCSA / HAZMAT / DQ posture lands when `compliance.getFleetCompliance` ships (EUSO-2118).")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(Space.s4)
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
        }
    }

    // MARK: Action ribbon (warn-wash · expiring doc reminder)

    private func actionRibbon(for doc: ShipperComplianceAPI.Document) -> some View {
        let headline = "\(doc.name) · expiring"
        let sub = doc.expiresAt.isEmpty ? "request renewal certificate" : "expires \(doc.expiresAt) · request renewal certificate"
        return HStack(spacing: Space.s3) {
            WarningTriangleGlyph()
                .stroke(Brand.warning, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(sub)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            Button(action: { tapNotify(doc) }) {
                Text("Notify")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 60, height: 24)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notify renewal for \(doc.name)")
        }
        .padding(.horizontal, Space.s4)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient.warnWash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.30))
        )
    }

    // MARK: MY DOCUMENTS supplemental (real backend wiring · EXTRA-OK)

    private func myDocumentsSection(
        summary: ShipperComplianceAPI.Summary,
        documents: [ShipperComplianceAPI.Document]
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("MY DOCUMENTS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            statusStrip(summary, documents: documents)
            creditCard(summary)
            insuranceCard(summary)
            documentsCard(documents)
        }
    }

    private func statusStrip(_ s: ShipperComplianceAPI.Summary,
                             documents: [ShipperComplianceAPI.Document]) -> some View {
        let verified = documents.filter { $0.status == "active" || $0.status == "verified" }.count
        let pending  = documents.filter { $0.status == "pending" }.count
        let expiring = documents.filter { $0.status == "expiring" }.count
        let expired  = documents.filter { $0.status == "expired" }.count
        return HStack(spacing: Space.s2) {
            stripTile(value: "\(verified)", label: "VERIFIED", color: Brand.success)
            stripTile(value: "\(pending)",  label: "PENDING",  color: Brand.info)
            stripTile(value: "\(expiring)", label: "EXPIRING", color: Brand.warning)
            stripTile(value: "\(expired)",  label: "EXPIRED",  color: Brand.danger)
        }
    }

    private func stripTile(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func creditCard(_ s: ShipperComplianceAPI.Summary) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Brand.info)
                Text("CREDIT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(s.creditApproved ? "APPROVED" : "PENDING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(s.creditApproved ? Brand.success : Brand.warning)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill((s.creditApproved ? Brand.success : Brand.warning).opacity(0.18)))
            }
            HStack(spacing: Space.s3) {
                kpiCol(label: "RATING",     value: s.creditRating.isEmpty ? "—" : s.creditRating)
                kpiCol(label: "LIMIT",      value: formatMoney(s.creditLimit))
                kpiCol(label: "AVAILABLE",  value: formatMoney(s.availableCredit), accent: Brand.success)
                kpiCol(label: "TERMS",      value: s.paymentTerms.isEmpty ? "—" : s.paymentTerms)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func kpiCol(label: String, value: String, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(accent ?? palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func insuranceCard(_ s: ShipperComplianceAPI.Summary) -> some View {
        let lib = s.generalLiability
        let (chip, chipColor) = insuranceChipStyle(lib.status)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.purple)
                Text("INSURANCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(chip)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(chipColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(chipColor.opacity(0.18)))
            }
            HStack(spacing: Space.s3) {
                kpiCol(label: "GENERAL LIABILITY", value: formatMoney(lib.coverage))
                kpiCol(label: "EXPIRES", value: lib.expires.isEmpty ? "—" : lib.expires)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func insuranceChipStyle(_ status: String) -> (String, Color) {
        switch status.lowercased() {
        case "active":   return ("ACTIVE", Brand.success)
        case "expiring": return ("EXPIRING", Brand.warning)
        case "missing":  return ("MISSING", Brand.danger)
        case "expired":  return ("EXPIRED", Brand.danger)
        default:          return (status.uppercased().isEmpty ? "PENDING" : status.uppercased(), Brand.info)
        }
    }

    private func documentsCard(_ documents: [ShipperComplianceAPI.Document]) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("COMPLIANCE VAULT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(documents.count) on file")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ComplianceCategory.allCases) { c in
                        categoryChip(c)
                    }
                }
            }
            VStack(spacing: Space.s2) {
                ForEach(filteredRequiredDocs, id: \.id) { doc in
                    documentRow(doc, documents: documents)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text("Upload missing docs from eusotrip.com/shipper/compliance")
                    .font(EType.micro).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func categoryChip(_ c: ComplianceCategory) -> some View {
        let active = (category == c)
        return Button {
            category = c
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        } label: {
            HStack(spacing: 4) {
                Image(systemName: c.icon)
                    .font(.system(size: 10, weight: .heavy))
                Text(c.label)
                    .font(.system(size: 11, weight: .heavy))
                if c != .all {
                    let n = countFor(c)
                    Text("\(n)")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
            .background(
                Capsule().fill(active
                               ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                               : AnyShapeStyle(palette.bgCard))
            )
            .overlay(
                Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func countFor(_ c: ComplianceCategory) -> Int {
        RequiredDoc.canonical.filter { $0.category == c }.count
    }

    private var filteredRequiredDocs: [RequiredDoc] {
        if category == .all { return RequiredDoc.canonical }
        return RequiredDoc.canonical.filter { $0.category == category }
    }

    private func documentRow(_ doc: RequiredDoc, documents: [ShipperComplianceAPI.Document]) -> some View {
        let lookup = doc.id.lowercased()
        let match = documents.first { ($0.type?.lowercased() ?? "").contains(lookup) || $0.name.lowercased().contains(lookup.replacingOccurrences(of: "_", with: " ")) }
        let (chip, color) = docStatusChip(match?.status, required: doc.required)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.15))
                Image(systemName: doc.category.icon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(doc.label)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(doc.required ? "REQUIRED" : "OPTIONAL")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(doc.required ? Brand.warning : palette.textTertiary)
                    if let m = match, !m.expiresAt.isEmpty {
                        Text("· EXPIRES \(m.expiresAt)")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            Text(chip)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(color)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(color.opacity(0.15)))
                .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.75))
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, Space.s2)
    }

    private func docStatusChip(_ rawStatus: String?, required: Bool) -> (String, Color) {
        guard let s = rawStatus?.lowercased() else {
            return required ? ("MISSING", Brand.danger) : ("OPTIONAL", palette.textTertiary)
        }
        switch s {
        case "active", "verified":  return ("VERIFIED", Brand.success)
        case "pending":              return ("PENDING",  Brand.info)
        case "expiring":             return ("EXPIRING", Brand.warning)
        case "expired":              return ("EXPIRED",  Brand.danger)
        default:                      return (s.uppercased(), palette.textSecondary)
        }
    }

    // MARK: Notify post (§20.4)

    private func tapNotify(_ doc: ShipperComplianceAPI.Document) {
        // Real action: open the compliance team's mail composer
        // pre-filled with the document name + expiry so the renewal
        // request is one tap away. Replaces the prior openURL stub
        // to a 404 `/compliance/documents/{id}/notify` web route.
        // Telemetry post retained for observability.
        NotificationCenter.default.post(
            name: .eusoShipperComplianceNotify,
            object: nil,
            userInfo: [
                "source": "216_ShipperCompliance",
                "documentId": doc.id,
                "documentName": doc.name,
                "expiresAt": doc.expiresAt,
                "shipperCompanyId": 1
            ]
        )
        let subject = "Compliance renewal: \(doc.name)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Compliance%20renewal"
        let body = "Document: \(doc.name)\nID: \(doc.id)\nExpires: \(doc.expiresAt)\n\nPlease coordinate the renewal + re-upload."
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:compliance@eusotrip.com?subject=\(subject)&body=\(body)") {
            openURL(url)
        }
    }

    // MARK: Error banner

    private func errorBanner(_ msg: String) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Compliance offline")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
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
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func formatMoney(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 1_000_000 { return String(format: "$%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "$%.0fk", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n == 0          { return "—" }
        return "$\(n)"
    }
}

// MARK: - Glyph shapes (file-scoped per §19.2)

private struct ShieldCheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        var p = Path()
        p.move(to: CGPoint(x: 14 * s, y: 0 * s))
        p.addLine(to: CGPoint(x: 0 * s, y: 5 * s))
        p.addLine(to: CGPoint(x: 0 * s, y: 14 * s))
        p.addCurve(to: CGPoint(x: 14 * s, y: 28 * s),
                   control1: CGPoint(x: 0 * s, y: 22 * s),
                   control2: CGPoint(x: 14 * s, y: 28 * s))
        p.addCurve(to: CGPoint(x: 28 * s, y: 14 * s),
                   control1: CGPoint(x: 14 * s, y: 28 * s),
                   control2: CGPoint(x: 28 * s, y: 22 * s))
        p.addLine(to: CGPoint(x: 28 * s, y: 5 * s))
        p.closeSubpath()
        p.move(to: CGPoint(x: 9 * s, y: 14 * s))
        p.addLine(to: CGPoint(x: 13 * s, y: 18 * s))
        p.addLine(to: CGPoint(x: 20 * s, y: 11 * s))
        return p
    }
}

private struct CircleCheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        var p = Path()
        p.addEllipse(in: CGRect(x: 0, y: 0, width: 28 * s, height: 28 * s))
        p.move(to: CGPoint(x: 8 * s, y: 14 * s))
        p.addLine(to: CGPoint(x: 12 * s, y: 18 * s))
        p.addLine(to: CGPoint(x: 20 * s, y: 10 * s))
        return p
    }
}

private struct HazmatDiamondGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let half = min(rect.width, rect.height) / 2 * 0.95
        var p = Path()
        p.move(to:    CGPoint(x: center.x,        y: center.y - half))
        p.addLine(to: CGPoint(x: center.x + half, y: center.y))
        p.addLine(to: CGPoint(x: center.x,        y: center.y + half))
        p.addLine(to: CGPoint(x: center.x - half, y: center.y))
        p.closeSubpath()
        return p
    }
}

private struct DocumentLinesGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 22 * s, y: 0))
        p.addLine(to: CGPoint(x: 28 * s, y: 6 * s))
        p.addLine(to: CGPoint(x: 28 * s, y: 28 * s))
        p.addLine(to: CGPoint(x: 0, y: 28 * s))
        p.closeSubpath()
        p.move(to: CGPoint(x: 6 * s, y: 14 * s))
        p.addLine(to: CGPoint(x: 22 * s, y: 14 * s))
        p.move(to: CGPoint(x: 6 * s, y: 20 * s))
        p.addLine(to: CGPoint(x: 18 * s, y: 20 * s))
        return p
    }
}

private struct WarningTriangleGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var p = Path()
        p.move(to: CGPoint(x: 12 * s, y: 2 * s))
        p.addLine(to: CGPoint(x: 24 * s, y: 22 * s))
        p.addLine(to: CGPoint(x: 0 * s,  y: 22 * s))
        p.closeSubpath()
        p.move(to: CGPoint(x: 12 * s, y: 9 * s))
        p.addLine(to: CGPoint(x: 12 * s, y: 15 * s))
        p.move(to: CGPoint(x: 12 * s, y: 18.5 * s))
        p.addLine(to: CGPoint(x: 12 * s, y: 19 * s))
        return p
    }
}

// MARK: - Warn-wash gradient (§19.2 file-scoped)

private extension LinearGradient {
    static let warnWash = LinearGradient(
        colors: [Brand.warning.opacity(0.13), Brand.danger.opacity(0.13)],
        startPoint: .leading, endPoint: .trailing
    )
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Action ribbon "Notify" tap — sends a renewal reminder for an
    /// expiring document.
    static let eusoShipperComplianceNotify = Notification.Name("eusoShipperComplianceNotify")
}

// MARK: - Previews

#Preview("216 · Shipper Compliance · Dark") {
    ShipperCompliance()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("216 · Shipper Compliance · Light") {
    ShipperCompliance()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
