//
//  660_RailClaimReport.swift
//  EusoTrip — Rail Engineer · Claim Report (Dark + Light · verbatim port of
//  "05 Rail / 660 Rail Claim Report.svg").
//
//  ARCHETYPE = EXPORT BUILDER: a settled-claim hero (claim value · paid · id ·
//  carrier), a FORMAT segmented control (PDF / CSV / XLSX), a SECTIONS toggle
//  card (Evidence / Timeline / Financials) with a purpose selector, a recent-
//  exports strip, a governing-law appendix strip, and a Generate / Preview CTA
//  pair. Turns a settled claim into an insurer/legal/regulator-ready export in
//  three taps. Distinct from the dossier twin (655) — this one BUILDS the file.
//
//  WIRING (grep-confirmed · frontend/server/routers/freightClaims.ts):
//    • claim hero        → freightClaims.getClaimById (query · :523)
//        input { id }; nullable dossier { claimNumber, amount, status, type,
//        carrier{name}, decision{amount} }.
//    • claim resolution  → freightClaims.getClaims (query · :438) — picks the
//        most recent claim id when none is passed in (this is a builder entry).
//    • Generate report   → freightClaims.generateClaimReport (mutation · :3269)
//        input { claimId, format, includeEvidence, includeTimeline,
//        includeFinancials, purpose }; returns { filename, content, ... }.
//    HONEST NOTE: the server currently emits CSV for every non-CSV format
//    (PDF/XLSX throw), and {jurisdiction}/governing-law-appendix is a proposed
//    field — the appendix strip is a presentation surface pending that arg
//    (handed to the-oath). "paid" reads decision.amount, null until decided.
//
//  RBAC: protectedProcedure. transportMode=rail · claim CLM/BNSF.
//  NAV (RailEngineerNavController): current = COMPLIANCE.
//

import SwiftUI

struct RailClaimReportScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailClaimReportBody() } nav: {
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

// MARK: - Decodables

private struct ClaimListRow660: Decodable { let id: Int; let claimNumber: String? }
private struct ClaimList660: Decodable { let claims: [ClaimListRow660]; let total: Int }

private struct ClaimDetail660: Decodable {
    struct Party: Decodable { let name: String? }
    struct Decision: Decodable { let amount: Double? }
    let id: String?
    let claimNumber: String?
    let type: String?
    let status: String?
    let amount: Double?
    let carrier: Party?
    let decision: Decision?
}

private struct GeneratedReport660: Decodable {
    let success: Bool?
    let filename: String?
    let format: String?
    let purpose: String?
}

private enum ReportFormat660: String, CaseIterable, Identifiable {
    case pdf = "PDF", csv = "CSV", xlsx = "XLSX"
    var id: String { rawValue }
    var wire: String { rawValue.lowercased() }
}

private enum ReportPurpose660: String, CaseIterable, Identifiable {
    case insurance, legal, `internal`, regulatory
    var id: String { rawValue }
    var label: String { self == .regulatory ? "reg." : rawValue }
    var wire: String { rawValue }
}

private struct ReportSection660: Identifiable {
    let id: String
    let title: String
    let sub: String
    let accent: Color
    let icon: String
}

// MARK: - Body

private struct RailClaimReportBody: View {
    @Environment(\.palette) private var palette

    @State private var claim: ClaimDetail660? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var format: ReportFormat660 = .pdf
    @State private var purpose: ReportPurpose660 = .insurance
    @State private var includeEvidence = true
    @State private var includeTimeline = true
    @State private var includeFinancials = true

    @State private var genBusy = false
    @State private var ack: String? = nil

    private let sections: [ReportSection660] = [
        .init(id: "evidence",  title: "Evidence pack", sub: "photos · inspection · BOL", accent: Brand.info,    icon: "doc.text"),
        .init(id: "timeline",  title: "Timeline",      sub: "filed → settled events",   accent: Brand.success, icon: "chart.line.uptrend.xyaxis"),
        .init(id: "financials",title: "Financials",    sub: "value · paid · recovery",  accent: Brand.escort,  icon: "dollarsign.circle")
    ]

    private func isOn(_ id: String) -> Bool {
        switch id {
        case "evidence":   return includeEvidence
        case "timeline":   return includeTimeline
        case "financials": return includeFinancials
        default:           return false
        }
    }
    private func toggle(_ id: String) {
        switch id {
        case "evidence":   includeEvidence.toggle()
        case "timeline":   includeTimeline.toggle()
        case "financials": includeFinancials.toggle()
        default: break
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                IridescentHairline()

                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else {
                    hero
                    formatPicker
                    sectionsCard
                    recentExports
                    governingLawStrip
                    if let ack {
                        Text(ack).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: Eyebrow + title

    private var eyebrow: some View {
        HStack {
            Text("✦ RAIL ENGINEER · CLAIM REPORT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("RPT · BUILDER")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Export report")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 6)
        }
    }

    // MARK: Hero

    private var hero: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    heroChip((claim?.status ?? "settled").lowercased())
                    heroChip((claim?.type ?? "damage").lowercased())
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: Space.s3) {
                    Text(compact(claim?.amount ?? 0))
                        .font(.system(size: 30, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("claim value")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(paidLine)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.top, 6)
                    Spacer(minLength: Space.s2)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("CLAIM")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(claim?.claimNumber ?? "—")
                            .font(EType.mono(.body))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(claim?.carrier?.name ?? "—")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var paidLine: String {
        if let paid = claim?.decision?.amount { return "paid \(compact(paid))" }
        return "paid pending decision"
    }

    private func heroChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).tracking(0.5)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Color.white.opacity(0.08)).clipShape(Capsule())
    }

    // MARK: Format segmented control

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("FORMAT").font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(ReportFormat660.allCases) { f in
                    let active = f == format
                    Button { format = f } label: {
                        Text(f.rawValue)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(active ? Color.white : palette.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(active ? Color.clear : palette.borderFaint))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Sections card

    private var sectionsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("SECTIONS").font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { idx, s in
                    sectionRow(s)
                    if idx < sections.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                            .padding(.vertical, Space.s3)
                    }
                }
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                    .padding(.vertical, Space.s3)
                purposeRow
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func sectionRow(_ s: ReportSection660) -> some View {
        let on = isOn(s.id)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(s.accent.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: s.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(s.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(s.sub).font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s2)
            Button { toggle(s.id) } label: {
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule()
                        .fill(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
                        .frame(width: 42, height: 24)
                        .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: on ? 0 : 1))
                    Circle().fill(.white).frame(width: 18, height: 18).padding(3)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var purposeRow: some View {
        HStack(spacing: Space.s2) {
            Text("Purpose").font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: Space.s2)
            ForEach(ReportPurpose660.allCases) { p in
                let active = p == purpose
                Button { purpose = p } label: {
                    Text(p.label)
                        .font(.system(size: 10, weight: active ? .bold : .regular))
                        .foregroundStyle(active ? Color.white : palette.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Color.clear))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Recent exports

    private var recentExports: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT EXPORTS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text("Report exports for this carrier appear here once generated.")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Governing-law appendix strip (tri-country)

    private var governingLawStrip: some View {
        HStack(spacing: 0) {
            lawColumn("US · 49 USC §11706", "Carmack · STB/FRA", active: true)
            divider
            lawColumn("CA · SOR/91-488", "CTA · Transport Canada", active: false)
            divider
            lawColumn("MX · LRSF Art.53", "ARTF · SICT", active: false)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 26)
    }

    private func lawColumn(_ title: String, _ sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5, weight: .heavy))
                .foregroundStyle(active ? Brand.info : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 8))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s2)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await generate() } } label: {
                Text(genBusy ? "Generating…" : "Generate report")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(genBusy ? 0.6 : 1).disabled(genBusy || claim?.id == nil)

            RailSecondaryActionButton(
                title: "Preview",
                sheetTitle: "Report preview",
                lines: previewLines,
                systemImage: "doc.text.magnifyingglass"
            )
        }
    }

    private var previewLines: [String] {
        [
            "Claim: \(claim?.claimNumber ?? "—")",
            "Carrier: \(claim?.carrier?.name ?? "—")",
            "Value: \(compact(claim?.amount ?? 0))",
            "Format: \(format.rawValue)",
            "Purpose: \(purpose.rawValue)",
            "Evidence pack: \(includeEvidence ? "included" : "excluded")",
            "Timeline: \(includeTimeline ? "included" : "excluded")",
            "Financials: \(includeFinancials ? "included" : "excluded")"
        ]
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 40)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 220)
        }
    }

    private func errorCard(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Formatting

    private func compact(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if a >= 1_000     { return String(format: "$%.1fK", v / 1_000) }
        return String(format: "$%.0f", v)
    }

    // MARK: Data

    private func reload() async {
        loading = true; loadError = nil
        do {
            // Builder entry — resolve the most recent claim to build a report for.
            struct ListInput: Encodable { let limit: Int; let offset: Int }
            let list: ClaimList660 = try await EusoTripAPI.shared.query(
                "freightClaims.getClaims", input: ListInput(limit: 1, offset: 0))
            guard let first = list.claims.first else {
                self.claim = nil; loading = false; return
            }
            struct IdInput: Encodable { let id: String }
            let detail: ClaimDetail660? = try await EusoTripAPI.shared.query(
                "freightClaims.getClaimById", input: IdInput(id: String(first.id)))
            self.claim = detail
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func generate() async {
        guard let id = claim?.id else {
            ack = "No claim resolved to build a report for yet."
            return
        }
        genBusy = true; ack = nil
        defer { genBusy = false }
        struct Input: Encodable {
            let claimId: String
            let format: String
            let includeEvidence: Bool
            let includeTimeline: Bool
            let includeFinancials: Bool
            let purpose: String
        }
        do {
            let res: GeneratedReport660 = try await EusoTripAPI.shared.mutation(
                "freightClaims.generateClaimReport",
                input: Input(claimId: id, format: format.wire,
                             includeEvidence: includeEvidence,
                             includeTimeline: includeTimeline,
                             includeFinancials: includeFinancials,
                             purpose: purpose.wire))
            if let name = res.filename {
                ack = "Report ready · \(name)"
            } else {
                ack = "Report generated for \(purpose.rawValue)."
            }
        } catch {
            // The server emits CSV only today; PDF/XLSX throw. Surface honestly.
            ack = "Export as \(format.rawValue) isn't available server-side yet — CSV is live. (\((error as? EusoTripAPIError)?.errorDescription ?? "try CSV"))"
        }
    }
}

#Preview("660 · Rail Claim Report · Night") {
    RailClaimReportScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("660 · Rail Claim Report · Light") {
    RailClaimReportScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
