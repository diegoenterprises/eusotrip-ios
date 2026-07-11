//
//  010_RailFreightBillAudit.swift
//  EusoTrip — Rail · Shipper · Freight Bill Audit (brick 010).
//
//  Verbatim SwiftUI port of "05 Rail/010 Rail Freight Bill Audit · Dark" at the
//  golden design-authority bar. SHIPPER MONEY/ledger vantage: a three-way match
//  that runs itself — billed vs tariff-expected variance hero, an exceptions
//  ledger with severity pills, a recoverable total strip, an ESANG dispute-draft
//  advisory, a currency/tax regime band, and a Draft-dispute / Recent-audits CTA
//  pair. Distinct from carrier-side 599 (Rail Engineer vantage). Mirrors 227.
//
//  Nav: canonical Shipper enum HOME · LOADS · [orb] · WALLET(current) · ME.
//  transportMode = rail · US (BNSF Tariff 6004-C) · USD.
//
//  WIRING (web parity client/src/pages/shipper/FreightAudit.tsx):
//    audits + summary → freightClaims.getFreightAudit  EXISTS · freightClaims.ts:2416
//      ({limit,offset,status?}) → { audits[{invoiceNumber,carrier,invoiceAmount,
//      auditedAmount,variance,varianceType,status,auditDate,findings[]}], total,
//      summary{totalAudited,totalVariance,overcharges,undercharges,duplicates,
//      rateErrors,avgVariancePercent} } — the DB-backed freightAuditRecoveries
//      ledger. (railFreightAudit.recentAudits is a hardcoded-empty STUB — not used.)
//    Draft dispute → freightClaims.fileDispute         EXISTS · freightClaims.ts:1929
//      ({type,invoiceNumber,amount,description}) → DSP-YYYY-XXXXX + dispute_events.
//    Recent audits → reload / posts eusoFreightAuditHistory intent.
//  Per-finding deltas are extracted from the real finding strings where present
//  (honest); the aggregate variance drives the hero + recoverable strip. The
//  currency/tax regime band shows known regulatory constants. RBAC protectedProcedure
//  (company-scoped to DU/Eusorone).
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Data shapes (mirror freightClaims.getFreightAudit)

private struct FreightAuditRow010: Decodable, Identifiable {
    let id: String
    let invoiceNumber: String?
    let carrier: String?
    let invoiceAmount: Double?
    let auditedAmount: Double?
    let variance: Double?
    let varianceType: String?
    let status: String?
    let auditDate: String?
    let findings: [String]?
}
private struct FreightAuditSummary010: Decodable {
    let totalAudited: Double?
    let totalVariance: Double?
    let overcharges: Int?
    let undercharges: Int?
    let duplicates: Int?
    let rateErrors: Int?
    let avgVariancePercent: Double?
}
private struct FreightAuditResult010: Decodable {
    let audits: [FreightAuditRow010]?
    let total: Int?
    let summary: FreightAuditSummary010?
}

// MARK: - Screen wrapper

struct RailFreightBillAuditShipperScreen: View {
    let theme: Theme.Palette
    /// Optional invoice to focus; when nil the most recent audited invoice leads.
    var invoiceNumber: String? = nil

    var body: some View {
        Shell(theme: theme) { RailFreightBillAuditShipperBody(focusInvoice: invoiceNumber) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",      isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: true),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailFreightBillAuditShipperBody: View {
    @Environment(\.palette) private var palette
    let focusInvoice: String?

    @State private var audits: [FreightAuditRow010] = []
    @State private var summary: FreightAuditSummary010? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var actionBanner: String? = nil
    @State private var actionIsError = false
    @State private var drafting = false

    private let usd: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0; return f
    }()
    private func money(_ v: Double) -> String { usd.string(from: NSNumber(value: v)) ?? "$0" }

    private var lead: FreightAuditRow010? {
        if let f = focusInvoice { return audits.first { $0.invoiceNumber == f } ?? audits.first }
        return audits.max { abs($0.variance ?? 0) < abs($1.variance ?? 0) } ?? audits.first
    }
    private var billed: Double { lead?.invoiceAmount ?? 0 }
    private var expected: Double { lead?.auditedAmount ?? 0 }
    private var variance: Double { lead?.variance ?? (billed - expected) }
    private var findings: [String] { lead?.findings ?? [] }
    private var recoverable: Double { max(variance, 0) }

    private var auditFailed: Bool { abs(variance) > 0.5 || !findings.isEmpty }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                backRow
                heroTitle
                IridescentHairline().padding(.top, Space.s3)

                if loading {
                    skeleton.padding(.top, Space.s4)
                } else if let err = loadError {
                    errorCard(err).padding(.top, Space.s4)
                } else if lead == nil {
                    EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                                   title: "No audited invoices",
                                   subtitle: "Run a freight audit to surface overbills here.")
                        .padding(.top, Space.s5)
                    ctaPair.padding(.top, Space.s5)
                } else {
                    invoiceCard.padding(.top, Space.s4)
                    exceptionsCard.padding(.top, Space.s5)
                    recoverableStrip.padding(.top, Space.s4)
                    esangAdvisory.padding(.top, Space.s4)
                    regimeBand.padding(.top, Space.s5)
                    if let banner = actionBanner {
                        actionBannerView(banner).padding(.top, Space.s3)
                    }
                    ctaPair.padding(.top, Space.s5)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Top bar / title

    private var topBar: some View {
        HStack {
            Text("✦ SHIPPER · RAIL · FREIGHT AUDIT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(auditFailed ? "AUDIT FAILED" : "AUDIT CLEAN")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(auditFailed ? Brand.danger : Brand.success)
        }
    }

    private var backRow: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Text(lead?.carrier ?? "Freight bills").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
        }
        .padding(.top, Space.s3)
    }

    private var heroTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(money(billed)) billed")
                .font(.system(size: 32, weight: .bold)).tracking(-0.6).monospacedDigit()
                .foregroundStyle(LinearGradient.diagonal).lineLimit(1).minimumScaleFactor(0.6)
            Text([lead?.carrier, lead?.invoiceNumber].compactMap { $0 }.joined(separator: " · "))
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(.top, Space.s3)
    }

    // MARK: Hero invoice card

    private var invoiceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("INVOICE TOTAL · \(lead?.invoiceNumber ?? "—")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(exceptionBadge)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.danger)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.danger.opacity(0.16)))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(money(billed)).font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Tariff expected \(money(expected))").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Text("Variance \(variance >= 0 ? "+" : "")\(money(variance))")
                        .font(.system(size: 13, weight: .bold)).monospacedDigit()
                        .foregroundStyle(variance > 0 ? Brand.danger : Brand.success)
                }
            }
            .padding(.top, Space.s3)
            if let vt = lead?.varianceType, !vt.isEmpty {
                Text(vt.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
                    .padding(.top, Space.s3)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(alignment: .leading) { Rectangle().fill(auditFailed ? Brand.danger : Brand.success).frame(width: 3) }
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var exceptionBadge: String {
        let crit = summary?.duplicates ?? 0
        let n = findings.count
        return "\(n) EXCEPTION\(n == 1 ? "" : "S")\(crit > 0 ? " · \(crit) CRIT" : "")"
    }

    // MARK: Exceptions ledger

    private var exceptionsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("EXCEPTIONS · \(findings.count) FLAGGED")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if findings.isEmpty {
                EusoEmptyState(systemImage: "checkmark.seal",
                               title: "No exceptions",
                               subtitle: "This invoice matched the contracted tariff.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(findings.enumerated()), id: \.offset) { idx, f in
                        exceptionRow(f)
                        if idx < findings.count - 1 { Divider().overlay(palette.borderFaint).padding(.leading, Space.s4) }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func exceptionRow(_ finding: String) -> some View {
        let sev = severity(of: finding)
        let dollar = extractDollar(finding)
        return HStack(alignment: .top, spacing: Space.s3) {
            Circle().fill(sev.color).frame(width: 10, height: 10).padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(sev.label).font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(sev.color)
                Text(finding).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary).lineLimit(3)
            }
            Spacer(minLength: Space.s2)
            if let d = dollar {
                Text(d).font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(sev.color)
            } else {
                Text("review").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s4)
    }

    private func severity(of finding: String) -> (label: String, color: Color) {
        let f = finding.lowercased()
        if f.contains("duplicate") { return ("DUPLICATE · CRITICAL", Brand.danger) }
        if f.contains("overcharge") || f.contains("above") { return ("OVERCHARGE", Color(hex: 0xFF7A00)) }
        if f.contains("fuel") || f.contains("fsc") { return ("FUEL SURCHARGE", Brand.hazmat) }
        if f.contains("stale") || f.contains("superseded") { return ("STALE RATE · INFO", palette.textTertiary) }
        return ("FLAGGED", Brand.warning)
    }

    /// Extract the first "$1,234"-style token from a finding string (honest — no fabrication).
    private func extractDollar(_ s: String) -> String? {
        guard let range = s.range(of: #"\$[0-9][0-9,\.]*"#, options: .regularExpression) else { return nil }
        return String(s[range])
    }

    // MARK: Recoverable strip

    private var recoverableStrip: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("RECOVERABLE").font(.system(size: 10, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary)
                Text(recoverSub).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(money(recoverable)).font(.system(size: 20, weight: .bold)).monospacedDigit()
                .foregroundStyle(Brand.success)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .background(Brand.success.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
    private var recoverSub: String {
        let oc = summary?.overcharges ?? 0, dup = summary?.duplicates ?? 0
        return "\(oc) overcharge\(oc == 1 ? "" : "s") + \(dup) duplicate\(dup == 1 ? "" : "s") · 30-day window"
    }

    // MARK: ESang advisory

    private var esangAdvisory: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text("ESang: dispute draft built from \(findings.count) exception\(findings.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Recover \(money(recoverable)) · ready to file within the 30-day window")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Currency / tax regime band

    private var regimeBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CURRENCY · TAX REGIME").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s3) {
                regimeCell("US · USD", "no fed VAT", active: true)
                regimeCell("CA · CAD", "GST/HST", active: false)
                regimeCell("MX · MXN", "IVA 16%", active: false)
            }
        }
    }
    private func regimeCell(_ title: String, _ sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .heavy)).tracking(0.3).foregroundStyle(active ? .white : palette.textPrimary)
            Text(sub).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(active ? .white.opacity(0.9) : palette.textSecondary)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(active ? Color.clear : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Action banner + CTA

    private func actionBannerView(_ text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: actionIsError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(actionIsError ? Brand.danger : Brand.success)
            Text(text).font(EType.caption).foregroundStyle(actionIsError ? Brand.danger : palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background((actionIsError ? Brand.danger : Brand.success).opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder((actionIsError ? Brand.danger : Brand.success).opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: drafting ? "Drafting…" : "Draft dispute",
                      action: { Task { await draftDispute() } }, isLoading: drafting)
            Button(action: openRecent) {
                Text("Recent audits").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(width: 140, height: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct AuditIn: Encodable { let limit: Int; let offset: Int }
        do {
            let r: FreightAuditResult010 = try await EusoTripAPI.shared.query(
                "freightClaims.getFreightAudit", input: AuditIn(limit: 20, offset: 0))
            self.audits = r.audits ?? []
            self.summary = r.summary
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func draftDispute() async {
        guard !drafting, let l = lead, let inv = l.invoiceNumber else {
            actionIsError = true; actionBanner = "No audited invoice to dispute."; return
        }
        let amount = recoverable > 0 ? recoverable : abs(variance)
        guard amount > 0 else { actionIsError = true; actionBanner = "No recoverable variance to dispute."; return }
        drafting = true; actionBanner = nil
        struct FileIn: Encodable { let type: String; let invoiceNumber: String; let amount: Double; let description: String }
        struct FileOut: Decodable { let id: String?; let disputeNumber: String?; let status: String? }
        do {
            let out: FileOut = try await EusoTripAPI.shared.mutation(
                "freightClaims.fileDispute",
                input: FileIn(type: "rate", invoiceNumber: inv, amount: amount,
                              description: "Freight-bill audit variance on \(inv) (\(l.carrier ?? "carrier")): recover \(money(amount)) across \(findings.count) flagged exceptions within the 30-day window."))
            actionIsError = false
            actionBanner = out.disputeNumber.map { "Dispute \($0) drafted · \(money(amount))" } ?? "Dispute drafted · \(money(amount))"
            await load()
        } catch {
            actionIsError = true
            actionBanner = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        drafting = false
    }

    private func openRecent() {
        NotificationCenter.default.post(name: Notification.Name("eusoFreightAuditHistory"), object: nil,
            userInfo: ["total": audits.count])
        actionIsError = false
        actionBanner = "\(audits.count) audited invoice\(audits.count == 1 ? "" : "s") on file"
    }

    // MARK: Scaffolds

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 116)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
        }
    }
    private func errorCard(_ err: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Previews

#Preview("010 · Rail Freight Bill Audit · Night") {
    RailFreightBillAuditShipperScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("010 · Rail Freight Bill Audit · Light") {
    RailFreightBillAuditShipperScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
