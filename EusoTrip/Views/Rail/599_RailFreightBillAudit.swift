//
//  599_RailFreightBillAudit.swift
//  EusoTrip — Rail Engineer · Freight Bill Audit.
//
//  Verbatim port of "599 Rail Freight Bill Audit · Dark".
//  CARRIER-SIDE (RAIL_ENGINEER vantage). A variance-reconciliation surface:
//  recoverable hero figure + billed-vs-expected bar + AUDIT FINDINGS exceptions
//  ledger with severity pills + RECONCILIATION strip + AUDIT TRAIL timeline.
//  Audit a rail freight invoice line-by-line against the contracted tariff,
//  surface overbills/duplicates as flagged findings, and file recovery.
//
//  WIRING (web parity client/src/pages/rail/FreightBillAudit.tsx,
//  /rail/freight-audit/:invoiceId · server/routers/railFreightAudit.ts):
//    findings + variance → railFreightAudit.auditInvoice  EXISTS (:27)
//                          ({invoiceId}->{billed,expected,findings[]})
//    audit-trail timeline → railFreightAudit.recentAudits EXISTS (:103)
//    Tariff button        → STUB · named-gap rail.tariffLookup
//                           (propose railTariff.lookup({lane,equipment}))
//    Flag for recovery    → STUB · named-gap railFreightAudit.fileRecovery
//                           (propose fileRecovery({invoiceId,findingIds[]}))
//  RBAC railProcedure (RAIL_ENGINEER|CATALYST). transportMode=rail · US (USD).
//

import SwiftUI

struct RailFreightBillAuditScreen: View {
    let theme: Theme.Palette
    /// Invoice under audit. Defaults to the canonical wireframe sample so
    /// the screen renders standalone; real call-sites inject the route's
    /// :invoiceId.
    var invoiceId: String = "FB-RAIL-2241"

    var body: some View {
        Shell(theme: theme) { RailFreightBillAuditBody(invoiceId: invoiceId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",  isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror railFreightAudit.ts return shapes)

/// railFreightAudit.auditInvoice → { billed, expected, findings[] }
private struct RailAuditResult: Decodable {
    let invoiceId: String?
    let invoiceNumber: String?
    let carrier: String?
    let billed: Double?
    let expected: Double?
    let linesChecked: Int?
    let findings: [RailAuditFinding]?
}

private struct RailAuditFinding: Decodable, Identifiable {
    let id: String?
    let lineId: String?
    let title: String?
    let detail: String?
    /// "overbill" | "duplicate" | "ok" | "undercharge" | "missing"
    let kind: String?
    /// "variance" | "critical" | "ok" — drives the severity pill.
    let severity: String?
    /// Signed dollar variance for this line, when applicable.
    let variance: Double?
    /// Display amount on the right rail ("+$150", "$0 dup", "$640").
    let amount: Double?

    var rowId: String { id ?? lineId ?? title ?? UUID().uuidString }
}

/// railFreightAudit.recentAudits → audit-trail timeline rows.
private struct RailAuditTrailEntry: Decodable, Identifiable {
    let id: String?
    let title: String?
    /// "variance" | "critical" | "info" | "ok" — drives the dot color.
    let kind: String?
    let timeAgo: String?

    var rowId: String { id ?? title ?? UUID().uuidString }
}

// MARK: - Body

private struct RailFreightBillAuditBody: View {
    @Environment(\.palette) private var palette
    let invoiceId: String

    @State private var audit: RailAuditResult? = nil
    @State private var trail: [RailAuditTrailEntry] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // Action state
    @State private var filing = false
    @State private var actionBanner: String? = nil
    @State private var actionIsError = false

    private let usd: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()
    private let usd2: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    private func money(_ v: Double) -> String {
        usd.string(from: NSNumber(value: abs(v))) ?? "$0"
    }
    private func money2(_ v: Double) -> String {
        usd2.string(from: NSNumber(value: abs(v))) ?? "$0.00"
    }

    private var billed: Double   { audit?.billed ?? 0 }
    private var expected: Double { audit?.expected ?? 0 }
    private var variance: Double { billed - expected }
    private var findings: [RailAuditFinding] { audit?.findings ?? [] }
    private var exceptionCount: Int {
        findings.filter { ($0.severity ?? "").lowercased() != "ok" }.count
    }
    private var linesChecked: Int { audit?.linesChecked ?? findings.count }
    private var netRecoverable: Double {
        // Net recoverable = sum of recoverable variances on flagged lines.
        findings.reduce(into: 0.0) { acc, f in
            if (f.severity ?? "").lowercased() != "ok" { acc += (f.variance ?? 0) }
        }
    }
    private var carrier: String { audit?.carrier ?? "BNSF" }
    private var invoiceNumber: String { audit?.invoiceNumber ?? invoiceId }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                backRow
                hero
                IridescentHairline()
                    .padding(.top, Space.s3)

                if loading {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .fill(palette.bgCardSoft).frame(height: 90)
                                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                    .strokeBorder(palette.borderFaint))
                        }
                    }
                    .padding(.top, Space.s3)
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.top, Space.s3)
                } else {
                    reconciliationCard
                        .padding(.top, Space.s3)
                    findingsSection
                        .padding(.top, Space.s5)
                    netRecoverableStrip
                        .padding(.top, Space.s4)
                    auditTrailSection
                        .padding(.top, Space.s5)
                    if let banner = actionBanner {
                        actionBannerView(banner)
                            .padding(.top, Space.s3)
                    }
                    ctaPair
                        .padding(.top, Space.s5)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + invoice id)

    private var topBar: some View {
        HStack {
            Text("✦ RAIL ENGINEER · BILL AUDIT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(invoiceNumber)
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Back chevron + breadcrumb

    private var backRow: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Freight bills")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, Space.s3)
    }

    // MARK: - Hero figure + subline

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(varianceHero)
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text("\(carrier) invoice \(invoiceNumber) · billed \(money(billed)) vs expected \(money(expected))")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.top, Space.s4)
    }

    private var varianceHero: String {
        let mag = money(netRecoverable == 0 ? variance : netRecoverable)
        return "+\(mag) recoverable"
    }

    // MARK: - Reconciliation hero card

    private var reconciliationCard: some View {
        // billed-vs-expected bar fractions
        let total = max(billed, expected, 0.0001)
        let expectedFrac = min(max(expected / total, 0), 1)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("INVOICE RECONCILIATION")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(exceptionCount) EXCEPTIONS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(Brand.danger)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.danger.opacity(0.14)))
            }

            // billed vs expected bar
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgPage)
                        .frame(width: w, height: 10)
                    Capsule().fill(LinearGradient.primary)
                        .frame(width: w * expectedFrac, height: 10)
                    Capsule().fill(Brand.danger)
                        .frame(width: max(w * (1 - expectedFrac), 8), height: 10)
                        .offset(x: w * expectedFrac - max(w * (1 - expectedFrac), 8))
                }
            }
            .frame(height: 10)
            .padding(.top, Space.s3)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Billed").font(EType.micro).foregroundStyle(palette.textSecondary)
                    Text(money(billed))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expected (tariff)").font(EType.micro).foregroundStyle(palette.textSecondary)
                    Text(money(expected))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Variance").font(EType.micro).foregroundStyle(palette.textSecondary)
                    Text("+\(money(variance))")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Brand.danger).monospacedDigit()
                }
            }
            .padding(.top, Space.s4)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(alignment: .leading) {
            Rectangle().fill(Brand.danger).frame(width: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Audit findings ledger

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("AUDIT FINDINGS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(linesChecked) lines checked")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }

            if findings.isEmpty {
                EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                               title: "No findings",
                               subtitle: "Line-by-line audit results will appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(findings.enumerated()), id: \.element.rowId) { idx, f in
                        findingRow(f)
                        if idx < findings.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.leading, Space.s4)
                        }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func findingRow(_ f: RailAuditFinding) -> some View {
        let kind = (f.kind ?? "").lowercased()
        let sev  = (f.severity ?? "").lowercased()

        // Glyph + accent per finding kind / severity.
        let accent: Color
        let glyph: String
        switch sev {
        case "ok":       accent = Brand.success; glyph = "checkmark"
        case "critical": accent = Brand.danger;  glyph = "doc.on.doc"
        default:         accent = Brand.warning; glyph = "exclamationmark.triangle"
        }
        // duplicate → doc.on.doc, overbill → triangle, ok → checkmark
        let icon: String = {
            if kind == "duplicate" { return "doc.on.doc" }
            if sev == "ok"         { return "checkmark" }
            return glyph
        }()

        // Severity pill label.
        let pill: String = {
            if sev == "ok"       { return "OK" }
            if sev == "critical" { return "CRITICAL" }
            return "VARIANCE"
        }()

        // Right-rail amount — verbatim semantics:
        //   variance line  → "+$150" in accent
        //   duplicate line → "$0 dup" in secondary
        //   ok line        → "$640" in primary
        let amountText: String
        let amountColor: Color
        if kind == "duplicate" {
            amountText = "\(money(f.amount ?? 0)) dup"
            amountColor = palette.textSecondary
        } else if sev == "ok" {
            amountText = money(f.amount ?? 0)
            amountColor = palette.textPrimary
        } else {
            amountText = "+\(money(f.variance ?? f.amount ?? 0))"
            amountColor = accent
        }

        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(f.title ?? "Finding")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                if let detail = f.detail {
                    Text(detail)
                        .font(EType.mono(.caption)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(pill)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.16)))
                Text(amountText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(amountColor).monospacedDigit()
            }
        }
        .padding(Space.s4)
    }

    // MARK: - Reconciliation total strip

    private var netRecoverableStrip: some View {
        HStack {
            Text("NET RECOVERABLE")
                .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("+\(money2(netRecoverable == 0 ? variance : netRecoverable))")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
        }
        .padding(.horizontal, Space.s4)
        .frame(height: 38)
        .background(palette.textPrimary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Audit trail timeline

    private var auditTrailSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("AUDIT TRAIL · LAST 2 HRS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            if trail.isEmpty {
                Text("No recent audit activity.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(trail.enumerated()), id: \.element.rowId) { idx, e in
                        trailRow(e, isFirst: idx == 0, isLast: idx == trail.count - 1)
                    }
                }
            }
        }
    }

    private func trailRow(_ e: RailAuditTrailEntry, isFirst: Bool, isLast: Bool) -> some View {
        let dotColor: Color = {
            switch (e.kind ?? "").lowercased() {
            case "variance": return Brand.blue          // gradient lead dot reads blue→magenta; first entry uses diagonal below
            case "critical": return Brand.danger
            case "info":     return Brand.info
            case "ok":       return Brand.success
            default:         return palette.textSecondary
            }
        }()
        let dotSize: CGFloat = isFirst ? 8 : 6

        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(spacing: 0) {
                Group {
                    if isFirst {
                        Circle().fill(LinearGradient.diagonal)
                    } else {
                        Circle().fill(dotColor)
                    }
                }
                .frame(width: dotSize, height: dotSize)
                .padding(.top, isFirst ? 3 : 4)
                if !isLast {
                    Rectangle().fill(palette.textPrimary.opacity(0.10))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 11)

            HStack(alignment: .top) {
                Text(e.title ?? "")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Text(e.timeAgo ?? "")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s3)
        }
    }

    // MARK: - Action banner

    private func actionBannerView(_ text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: actionIsError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(actionIsError ? Brand.danger : Brand.success)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(actionIsError ? Brand.danger : palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((actionIsError ? Brand.danger : Brand.success).opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder((actionIsError ? Brand.danger : Brand.success).opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: filing ? "Filing…" : "Flag for recovery",
                action: { Task { await fileRecovery() } },
                isLoading: filing
            )
            Button {
                Task { await lookupTariff() }
            } label: {
                Text("Tariff")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 120, height: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct InvoiceIn: Encodable { let invoiceId: String }
        struct TrailIn: Encodable { let invoiceId: String; let limit: Int }
        do {
            // findings + variance → railFreightAudit.auditInvoice EXISTS (:27)
            async let a: RailAuditResult = EusoTripAPI.shared.query(
                "railFreightAudit.auditInvoice", input: InvoiceIn(invoiceId: invoiceId))
            // audit-trail timeline → railFreightAudit.recentAudits EXISTS (:103)
            async let t: [RailAuditTrailEntry] = EusoTripAPI.shared.query(
                "railFreightAudit.recentAudits", input: TrailIn(invoiceId: invoiceId, limit: 8))
            let (result, trailRows) = try await (a, t)
            self.audit = result
            self.trail = trailRows
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Actions

    private func fileRecovery() async {
        guard !filing else { return }
        filing = true; actionBanner = nil
        // PORT-GAP: railFreightAudit.fileRecovery (named-gap STUB) —
        // propose fileRecovery({invoiceId,findingIds[]})->{disputeId};
        // writes dispute row + blockchainAuditTrail; broadcast
        // WS_CHANNELS.SETTLEMENT / WS_EVENTS.DISPUTE_OPENED.
        struct RecoveryIn: Encodable { let invoiceId: String; let findingIds: [String] }
        struct RecoveryOut: Decodable { let disputeId: String? }
        let ids = findings
            .filter { ($0.severity ?? "").lowercased() != "ok" }
            .compactMap { $0.id ?? $0.lineId }
        do {
            let out: RecoveryOut = try await EusoTripAPI.shared.mutation(
                "railFreightAudit.fileRecovery",
                input: RecoveryIn(invoiceId: invoiceId, findingIds: ids))
            actionIsError = false
            if let dispute = out.disputeId {
                actionBanner = "Recovery filed · dispute \(dispute)"
            } else {
                actionBanner = "Recovery filed for \(invoiceNumber)"
            }
        } catch {
            actionIsError = true
            actionBanner = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        filing = false
    }

    private func lookupTariff() async {
        actionBanner = nil
        // PORT-GAP: rail.tariffLookup (named-gap STUB) — propose
        // railTariff.lookup({lane,equipment})->{baseRate,fscBasis}.
        struct TariffIn: Encodable { let invoiceId: String }
        struct TariffOut: Decodable { let baseRate: Double?; let fscBasis: String? }
        do {
            let out: TariffOut = try await EusoTripAPI.shared.query(
                "railTariff.lookup", input: TariffIn(invoiceId: invoiceId))
            actionIsError = false
            if let rate = out.baseRate {
                actionBanner = "Tariff base \(money(rate))" + (out.fscBasis.map { " · FSC \($0)" } ?? "")
            } else {
                actionBanner = "Tariff lookup returned no rate."
            }
        } catch {
            actionIsError = true
            actionBanner = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("599 · Rail Freight Bill Audit · Night") {
    RailFreightBillAuditScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("599 · Rail Freight Bill Audit · Light") {
    RailFreightBillAuditScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
