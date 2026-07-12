//
//  803_VesselFreightAudit.swift
//  EusoTrip — Vessel Operator · Freight Audit (MONEY-DETAIL variance archetype).
//
//  Faithful port of "803 Vessel Freight Audit.svg" (Dark + Light). Turns a passive
//  bill-pay queue into an active recovery worklist: a gradient net-variance headline,
//  a variance-breakdown card (over / duplicate / rate-error composition + audited /
//  count stats), and a per-invoice findings ledger (audit chip + mono invoice id +
//  carrier · lane · finding + OVER/DUP/RATE/CLEAR pill + variance) — catching the
//  overcharge and duplicate invoices before they are paid.
//
//  Nav: Shell + BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME), COMPLIANCE inked.
//
//  REAL WIRING (tRPC · server/routers/freightClaims.ts):
//    · freightClaims.getFreightAudit  {startDate?, endDate?, status?, limit, offset}
//        -> { audits:[{id, invoiceNumber, carrier, invoiceAmount, auditedAmount,
//              variance, varianceType, status, auditDate, findings:[]}], total,
//              summary:{totalAudited, totalVariance, overcharges, undercharges,
//              duplicates, rateErrors, avgVariancePercent} }  (:2416) — companyId-scoped
//        off freightAuditRecoveries. NOTE (honest): the recovery table can be empty
//        (no findings recorded yet) — the ledger renders the honest empty state, never
//        fabricated invoices.
//    · freightClaims.runFreightAudit  {invoiceIds?, dateRange?, auditType} -> { auditId,
//        findingsCreated, totalVariance }  (:2525 · mutation · scans payments vs
//        settlements, saves overcharge findings for recovery). The "Run freight audit"
//        verb; reloads getFreightAudit after.
//    · "Export" composes a findings CSV from the LIVE audits and opens the native share
//        sheet (server exportFreightAuditLedger is a NAMED GAP · honest interim).
//
//  RBAC: getFreightAudit / runFreightAudit protectedProcedure. transportMode=vessel ·
//  country US (USD). COUNTRY-DONE: an audit-authority folder tab re-bases the freight-tax
//  basis by jurisdiction — US FMC 46 CFR 514 (ocean freight not taxed · USD) active /
//  CA CBSA CTA (GST/HST · CAD) · MX SAT (IVA 16% · MXN) standby. NAMED GAP for the-oath:
//  vessel.getFreightAuditRegime({country}) -> {auditAuthority, freightTaxBasis, taxRate,
//  currency}. NO mock data — every finding, count and dollar is a live row.
//

import SwiftUI
import UIKit

struct VesselFreightAuditScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselFreightAuditBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct FreightAuditResult803: Decodable {
    let audits: [FreightAuditRow803]
    let total: Int?
    let summary: FreightAuditSummary803?
}

private struct FreightAuditSummary803: Decodable {
    let totalAudited: Double?
    let totalVariance: Double?
    let overcharges: Double?
    let undercharges: Double?
    let duplicates: Int?
    let rateErrors: Int?
    let avgVariancePercent: Double?
}

private struct FreightAuditRow803: Decodable, Identifiable {
    let id: String
    let invoiceNumber: String
    let carrier: String
    let invoiceAmount: Double?
    let auditedAmount: Double?
    let variance: Double?
    let varianceType: String?
    let status: String?
    let auditDate: String?
    let findings: [String]?
}

private struct RunAuditResult803: Decodable {
    let auditId: String?
    let findingsCreated: Int?
    let totalVariance: Double?
}

private enum AuditJurisdiction803: String, CaseIterable {
    case us = "US", ca = "CA", mx = "MX"
    var authority: String { self == .us ? "FMC 46 CFR 514" : self == .ca ? "CBSA · CTA" : "SAT" }
    var basis: String { self == .us ? "ocean freight not taxed · USD" : self == .ca ? "GST/HST · CAD" : "IVA 16% · MXN" }
    var active: Bool { self == .us }
}

// MARK: - Body

private struct VesselFreightAuditBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.vesselOperatorNavHandler) private var navHandler

    @State private var audits: [FreightAuditRow803] = []
    @State private var summary: FreightAuditSummary803? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var running = false
    @State private var runAck: String? = nil
    @State private var runError: String? = nil
    @State private var jurisdiction: AuditJurisdiction803 = .us
    @State private var exportDoc: ShareDoc803? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                IridescentHairline().padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        errorCard(err)
                    } else {
                        breakdownCard
                        findingsSection
                        if let ack = runAck { banner(ack, danger: false) }
                        if let err = runError { banner(err, danger: true) }
                        ctaRow
                        authorityCard
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.top, Space.s5)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $exportDoc) { doc in ActivityShareSheet803(items: [doc.url]) }
    }

    // MARK: Header (eyebrow + breadcrumb + net-variance hero)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("VESSEL OPERATOR · FREIGHT AUDIT")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("RECOVERY").font(EType.mono(.micro)).tracking(0.8).foregroundStyle(palette.textTertiary)
            }
            Button { navHandler?("Compliance") } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text("Compliance").font(.system(size: 13, weight: .semibold))
                }.foregroundStyle(palette.textSecondary)
            }.buttonStyle(.plain).padding(.top, Space.s2)

            Text(money(netVariance))
                .font(.system(size: 34, weight: .bold, design: .monospaced)).tracking(-0.6)
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.top, Space.s3)
            Text(heroSub).font(EType.caption).foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7).padding(.top, 2)
        }
    }

    // MARK: Variance breakdown card (gradient-rim · composition bar + stats)

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("VARIANCE BREAKDOWN")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(pct(summary?.avgVariancePercent ?? 0))
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(breakdownSegments.enumerated()), id: \.offset) { _, seg in
                        RoundedRectangle(cornerRadius: 6).fill(seg.color)
                            .frame(width: max(4, geo.size.width * CGFloat(seg.share)))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 12)
            HStack(alignment: .top, spacing: Space.s5) {
                statCol(label: "AUDITED", value: money(summary?.totalAudited ?? 0, compact: true), tone: palette.textPrimary)
                statCol(label: "OVER", value: "\(overCount)", tone: Brand.warning)
                statCol(label: "DUP·RATE", value: "\(dupRateCount)", tone: palette.textPrimary)
                Spacer(minLength: 0)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
    }

    private func statCol(label: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textSecondary)
            Text(value).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(tone)
        }
    }

    // MARK: Findings ledger

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("AUDIT FINDINGS · BY INVOICE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if audits.isEmpty {
                EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                               title: "No findings recorded",
                               subtitle: "Run a freight audit to scan paid invoices against settlements — overcharges and duplicates land here for recovery.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(audits.prefix(12).enumerated()), id: \.element.id) { idx, a in
                        findingRow(a)
                        if idx < min(audits.count, 12) - 1 {
                            Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            }
        }
    }

    private func findingRow(_ a: FreightAuditRow803) -> some View {
        let (accent, tag) = typeStyle(a.varianceType, variance: a.variance ?? 0)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(a.invoiceNumber)
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(findingSub(a)).font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(tag).font(.system(size: 9, weight: .heavy)).tracking(0.3).foregroundStyle(accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(accent.opacity(0.16)))
                Text(varianceText(a.variance ?? 0))
                    .font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
    }

    // MARK: CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await runAudit() } } label: {
                HStack(spacing: 6) {
                    if running { ProgressView().tint(.white).scaleEffect(0.8) }
                    Text(running ? "Auditing…" : "Run freight audit")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(running).opacity(running ? 0.7 : 1.0)

            Button { exportFindings() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 12, weight: .bold))
                    Text("Export").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(palette.textPrimary)
                .frame(minWidth: 116, minHeight: 48).padding(.horizontal, Space.s3)
                .background(palette.bgCard).overlay(Capsule().strokeBorder(palette.borderFaint)).clipShape(Capsule())
            }
            .buttonStyle(.plain).disabled(audits.isEmpty).opacity(audits.isEmpty ? 0.6 : 1.0)
        }
    }

    // MARK: Audit-authority folder tab

    private var authorityCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                ForEach(AuditJurisdiction803.allCases, id: \.self) { j in
                    Button { withAnimation(.easeOut(duration: 0.15)) { jurisdiction = j } } label: {
                        Text(j == .us ? "US · FMC AUDIT" : "\(j.rawValue) · \(j.authority)")
                            .font(.system(size: 9.5, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(jurisdiction == j ? Brand.info : palette.textSecondary)
                            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                            .frame(maxWidth: .infinity)
                            .background(jurisdiction == j ? Brand.info.opacity(0.16) : palette.bgCard)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(jurisdiction == j ? Brand.info.opacity(0.55) : palette.borderFaint))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("AUDIT AUTHORITY · FREIGHT-TAX BASIS")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Text("\(jurisdiction.authority) · \(jurisdiction.basis)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textPrimary)
                if !jurisdiction.active {
                    Text("Standby — activates on the first \(jurisdiction.rawValue) audit.")
                        .font(.system(size: 8.5)).foregroundStyle(palette.textTertiary)
                } else {
                    Text("CA CBSA · GST/HST · MX SAT · IVA 16% — activate on first non-US audit")
                        .font(.system(size: 8.5)).foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Loading / error / banners

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 118)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 240)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    private func errorCard(_ err: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func banner(_ msg: String, danger: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: danger ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(danger ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(LinearGradient.diagonal))
            Text(msg).font(EType.caption).foregroundStyle(danger ? Brand.danger : palette.textPrimary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background((danger ? Brand.danger : Brand.success).opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder((danger ? Brand.danger : Brand.success).opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Derived

    private var netVariance: Double {
        if let v = summary?.totalVariance { return v }
        return audits.reduce(0) { $0 + ($1.variance ?? 0) }
    }
    private var heroSub: String {
        let audited = money(summary?.totalAudited ?? 0, compact: true)
        return "net variance · \(audited) audited · \(overCount) over · \(dupCount) dup · \(rateCount) rate · \(pct(summary?.avgVariancePercent ?? 0)) avg"
    }
    private var overCount: Int {
        let fromRows = audits.filter { isType($0.varianceType, "overcharge") || (($0.variance ?? 0) > 0 && ($0.varianceType == nil)) }.count
        return fromRows
    }
    private var dupCount: Int { summary?.duplicates ?? audits.filter { isType($0.varianceType, "duplicate") }.count }
    private var rateCount: Int { summary?.rateErrors ?? audits.filter { isType($0.varianceType, "rate") }.count }
    private var dupRateCount: Int { dupCount + rateCount }

    private struct BreakSeg803 { let color: Color; let share: Double }
    private var breakdownSegments: [BreakSeg803] {
        // Composition from the live findings, grouped by |variance| per type.
        var byType: [String: Double] = [:]
        for a in audits { byType[typeKey(a.varianceType), default: 0] += abs(a.variance ?? 0) }
        let total = max(byType.values.reduce(0, +), 0.001)
        let order: [(String, Color)] = [("overcharge", Brand.danger), ("duplicate", Brand.warning),
                                        ("rate", Brand.info), ("other", Brand.neutral)]
        return order.compactMap { key, color in
            let amt = byType[key] ?? 0
            return amt > 0 ? BreakSeg803(color: color, share: amt / total) : nil
        }
    }

    private func typeKey(_ t: String?) -> String {
        let s = (t ?? "").lowercased()
        if s.contains("over") { return "overcharge" }
        if s.contains("dup") { return "duplicate" }
        if s.contains("rate") { return "rate" }
        return "other"
    }
    private func isType(_ t: String?, _ needle: String) -> Bool { (t ?? "").lowercased().contains(needle) }

    private func typeStyle(_ t: String?, variance: Double) -> (Color, String) {
        switch typeKey(t) {
        case "overcharge": return (Brand.danger, "OVER")
        case "duplicate":  return (Brand.warning, "DUP")
        case "rate":       return (Brand.info, "RATE")
        default:           return variance == 0 ? (Brand.success, "CLEAR") : (Brand.neutral, "FLAG")
        }
    }

    private func findingSub(_ a: FreightAuditRow803) -> String {
        var parts: [String] = []
        if !a.carrier.isEmpty { parts.append(a.carrier) }
        if let f = a.findings?.first, !f.isEmpty { parts.append(f) }
        else if let t = a.varianceType, !t.isEmpty { parts.append(t.replacingOccurrences(of: "_", with: " ")) }
        return parts.isEmpty ? "audited" : parts.joined(separator: " · ")
    }

    private func varianceText(_ v: Double) -> String {
        if v == 0 { return "$0" }
        let sign = v > 0 ? "+" : "−"
        return "\(sign)\(money(abs(v)))"
    }
    private func pct(_ v: Double) -> String { "\(String(format: "%.1f", v))%" }
    private func money(_ v: Double, compact: Bool = false) -> String {
        if compact {
            if abs(v) >= 1_000_000 { return "$\(String(format: "%.2fM", v / 1_000_000))" }
            if abs(v) >= 1000 { return "$\(String(format: "%.1fK", v / 1000))" }
        }
        if v == v.rounded() { return "$\(Int(v).formatted(.number.grouping(.automatic)))" }
        return "$\(String(format: "%.2f", v))"
    }

    // MARK: - Actions

    private func load() async {
        loading = true; loadError = nil
        struct AuditIn: Encodable { let limit: Int; let offset: Int }
        do {
            let res: FreightAuditResult803 = try await EusoTripAPI.shared.query(
                "freightClaims.getFreightAudit", input: AuditIn(limit: 50, offset: 0))
            self.audits = res.audits
            self.summary = res.summary
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func runAudit() async {
        running = true; runAck = nil; runError = nil
        struct RunIn: Encodable { let auditType: String }
        do {
            let res: RunAuditResult803 = try await EusoTripAPI.shared.mutation(
                "freightClaims.runFreightAudit", input: RunIn(auditType: "full"))
            let found = res.findingsCreated ?? 0
            runAck = found > 0
                ? "\(found) finding\(found == 1 ? "" : "s") saved for recovery · \(money(res.totalVariance ?? 0))."
                : "Audit complete · no new variances found."
            await load()
        } catch {
            runError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        running = false
    }

    private func exportFindings() {
        guard !audits.isEmpty else { return }
        var csv = "invoice,carrier,invoice_amount,audited_amount,variance,type,status,date\n"
        for a in audits {
            let carrier = a.carrier.replacingOccurrences(of: ",", with: " ")
            csv += "\(a.invoiceNumber),\(carrier),\(String(format: "%.2f", a.invoiceAmount ?? 0)),"
            csv += "\(String(format: "%.2f", a.auditedAmount ?? 0)),\(String(format: "%.2f", a.variance ?? 0)),"
            csv += "\(a.varianceType ?? ""),\(a.status ?? ""),\(a.auditDate ?? "")\n"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("freight-audit-\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.data(using: .utf8)?.write(to: url)
            exportDoc = ShareDoc803(url: url)
        } catch {
            loadError = "Couldn't compose the audit ledger."
        }
    }
}

// MARK: - Share plumbing

private struct ShareDoc803: Identifiable { let id = UUID(); let url: URL }

private struct ActivityShareSheet803: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview("803 · Vessel Freight Audit · Night") {
    VesselFreightAuditScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("803 · Vessel Freight Audit · Light") {
    VesselFreightAuditScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
