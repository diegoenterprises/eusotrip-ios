//
//  216_ShipperCompliance.swift
//  EusoTrip 2027 UI — brick 216 (shipper · compliance dashboard)
//
//  Business verification · credit standing · insurance status ·
//  compliance document vault. Mirrors web `/shipper/compliance`
//  (`ShipperCompliance.tsx`) backed by the shipper-scope subset of
//  `complianceRouter` (`getShipperCompliance`, `getShipperDocuments`,
//  `uploadDocument`).
//
//  Cohort B day-1 — fully dynamic. No fixtures.
//
//    • Compliance score hero  → `compliance.getShipperCompliance`
//    • Credit + insurance row → same envelope
//    • Document vault         → `compliance.getShipperDocuments`
//
//  Doctrine refs:
//    §1   Score hero is gradient-blue→magenta. Credit "Approved"
//         pill in success tint. Insurance status pill keys color
//         off active/expiring/missing.
//    §2   `.easeOut(0.12)` press scale on every CTA. Success haptic
//         on a verified status.
//    §4   Tokenized Space/Radius/EType.
//    §5   Palette semantic. Brand.success / .warning / .danger for
//         status keying.
//    §10  Dark + Light previews under the empty-envelope path.
//
//  Powered by ESANG AI™.
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

    /// Heuristic mapping from a server-emitted `type` string back
    /// to one of the 5 canonical categories. Matches the web
    /// constant `SHIPPER_DOCS` taxonomy.
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

// MARK: - Required-document fixture (mirrors web SHIPPER_DOCS)
//
// The server's `getShipperDocuments` returns only the docs that have
// actually been uploaded. The web peer overlays a static list of
// REQUIRED docs so the shipper sees what's still missing. We do the
// same here so the iOS surface stays parity.

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

// MARK: - Store

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = ShipperComplianceStore()
    @State private var category: ComplianceCategory = .all

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
            value: category
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.checkerboard")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · COMPLIANCE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Verification & vault")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("Business verified · credit standing · insurance · compliance vault — every doc carriers will check before they accept your loads.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 80)
                }
            }
        case .error(let msg):
            errorBanner(msg)
        case .loaded(let summary, let documents):
            scoreHero(summary)
            statusStrip(summary, documents: documents)
            creditCard(summary)
            insuranceCard(summary)
            documentsCard(documents)
        }
    }

    // MARK: Score hero

    private func scoreHero(_ s: ShipperComplianceAPI.Summary) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("COMPLIANCE SCORE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if s.businessVerified {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9, weight: .heavy))
                        Text("BUSINESS VERIFIED")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    }
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Brand.success.opacity(0.18)))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(s.score)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("/ 100")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
            }
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 5)
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * CGFloat(min(100, max(0, s.score))) / 100, height: 5)
                }
            }
            .frame(height: 5)
            Text(scoreCommentary(s.score))
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func scoreCommentary(_ score: Int) -> String {
        switch score {
        case 90...:    return "Top-tier — every required document on file. Carriers can accept your loads with one tap."
        case 75..<90:  return "Solid standing — a few optional docs would push you to top-tier."
        case 60..<75:  return "Acceptable — required docs are mostly in place. Address the missing items above."
        default:        return "Action needed — required documents are missing. Carriers may pause acceptance."
        }
    }

    // MARK: Status strip (4 quick counts)

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

    // MARK: Credit card

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

    // MARK: Insurance card

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

    // MARK: Documents card

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
            // Category filter chips
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

            // Doctrine note: server upload mutation is currently a
            // stub. iOS surfaces an honest "upload from web" disclosure
            // until the S3/Blob path lands server-side, instead of
            // hiding the upload affordance.
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
        // Try to find a matching uploaded document by type prefix
        // match. Server emits free-form `type` strings so a strict
        // equality check would miss most uploads.
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

    // MARK: Helpers

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

// MARK: - Previews

#Preview("216 · Shipper Compliance · Night") {
    ShipperCompliance()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("216 · Shipper Compliance · Afternoon") {
    ShipperCompliance()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
