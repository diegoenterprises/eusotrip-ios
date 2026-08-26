//
//  657_RailDisputeResolution.swift
//  EusoTrip — Rail · Rail Engineer · Dispute Resolution (brick 657).
//
//  Verbatim SwiftUI port of "05 Rail/657 Rail Dispute Resolution · Dark" at the
//  golden design-authority bar. CARRIER (Rail Engineer) vantage on the OPEN
//  BILLING-DISPUTE queue: a value-at-stake hero (in-dispute vs recovered + win
//  rate), a 3-cell KPI strip, an itemized disputes list with severity pills and
//  tabular amounts, an audit-match note, and a File-dispute / Run-audit CTA pair.
//
//  Nav: REAL Rail Engineer enum HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//  transportMode = rail · US/BNSF · 9-month overcharge statute. Persona Owen Trask.
//
//  WIRING (web parity /rail/disputes):
//    queue → freightClaims.getDisputeResolution EXISTS · freightClaims.ts:1763
//      ({status?,type?,limit,offset}) → { disputes[{disputeNumber,type,status,
//      amount,filedDate,invoiceNumber,resolvedAmount,offers[]}], total,
//      summary{active,resolved,totalDisputed,totalRecovered} }.
//    Run audit → freightClaims.runFreightAudit  EXISTS · freightClaims.ts:2525
//      ({auditType}) → persists company-scoped recovery findings.
//    File dispute → opens the file-dispute composer (eusoOpenFileDispute) — a blank
//      dispute needs an invoice+amount, so the queue routes to the composer rather
//      than firing freightClaims.fileDispute (freightClaims.ts:1929) with no target.
//  Avg age is an HONEST derivation from real filedDate. Party display names
//  (carrier/shipper) are a known STUB (getDisputeResolution returns "").
//  RBAC protectedProcedure (party-scoped; admin/dispatch see all).
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Data shapes (mirror freightClaims.getDisputeResolution)

private struct DisputeOffer657: Decodable { let by: String?; let amount: Double?; let at: String? }
private struct DisputeRow657: Decodable, Identifiable {
    let id: String
    let disputeNumber: String?
    let type: String?
    let status: String?
    let amount: Double?
    let resolvedAmount: Double?
    let filedDate: String?
    let description: String?
    let invoiceNumber: String?
    let carrier: String?
    let offers: [DisputeOffer657]?
}
private struct DisputeSummary657: Decodable {
    let active: Int?
    let resolved: Int?
    let totalDisputed: Double?
    let totalRecovered: Double?
}
private struct DisputeResolution657: Decodable {
    let disputes: [DisputeRow657]?
    let total: Int?
    let summary: DisputeSummary657?
}

// MARK: - Screen wrapper

struct RailDisputeResolutionScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailDisputeResolutionBody() } nav: {
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

// MARK: - Body

private struct RailDisputeResolutionBody: View {
    @Environment(\.palette) private var palette

    @State private var disputes: [DisputeRow657] = []
    @State private var summary: DisputeSummary657? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var auditing = false
    @State private var actionBanner: String? = nil
    @State private var actionIsError = false

    private func money(_ v: Double) -> String {
        if v >= 1000 { return "$" + String(format: "%.1fK", v / 1000) }
        return "$" + String(Int(v))
    }
    private func moneyFull(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    private var open: [DisputeRow657] { disputes.filter { !["resolved", "closed"].contains(($0.status ?? "").lowercased()) } }
    private var totalDisputed: Double { summary?.totalDisputed ?? open.reduce(0) { $0 + ($1.amount ?? 0) } }
    private var totalRecovered: Double { summary?.totalRecovered ?? disputes.reduce(0) { $0 + ($1.resolvedAmount ?? 0) } }
    private var resolvedCount: Int { summary?.resolved ?? disputes.filter { ($0.status ?? "").lowercased() == "resolved" }.count }
    private var activeCount: Int { summary?.active ?? open.count }
    private var winPct: Int {
        let denom = resolvedCount + activeCount
        return denom > 0 ? Int(Double(resolvedCount) / Double(denom) * 100) : 0
    }
    private var avgAgeDays: Int {
        let ages = open.compactMap { row -> Int? in
            guard let f = row.filedDate else { return nil }
            let d = ISO8601DateFormatter().date(from: f) ?? DateFormatter.iso(f)
            return d.map { Int(Date().timeIntervalSince($0) / 86400) }
        }
        guard !ages.isEmpty else { return 0 }
        return ages.reduce(0, +) / ages.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                titleRow
                IridescentHairline().padding(.top, Space.s3)

                if loading {
                    skeleton.padding(.top, Space.s4)
                } else if let err = loadError {
                    errorCard(err).padding(.top, Space.s4)
                } else {
                    valueHero.padding(.top, Space.s4)
                    kpiStrip.padding(.top, Space.s4)
                    disputesList.padding(.top, Space.s5)
                    auditMatch.padding(.top, Space.s4)
                    if let banner = actionBanner { actionBannerView(banner).padding(.top, Space.s3) }
                    ctaPair.padding(.top, Space.s4)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s5)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Top bar / title

    private var topBar: some View {
        HStack {
            EusoTripEyebrow(verbatim: "RAIL ENGINEER · DISPUTE RESOLUTION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("DSP · BILLING").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
        }
    }

    private var titleRow: some View {
        HStack {
            Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Text("Disputes").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(palette.textPrimary)
        }
        .padding(.top, Space.s3)
    }

    // MARK: Value hero (gradient-rim card)

    private var valueHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s2) {
                pillChip("billing"); pillChip("\(activeCount) open"); Spacer()
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(money(totalDisputed)).font(.system(size: 30, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("in dispute · across \(disputes.count) invoice\(disputes.count == 1 ? "" : "s")")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("RECOVERED").font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text(money(totalRecovered)).font(.system(size: 22, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text("win \(winPct)%").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.success)
                }
            }
            .padding(.top, Space.s3)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }
    private func pillChip(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).tracking(0.3).foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(Color.white.opacity(0.08)))
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s3) {
            kpiCell("OPEN", "\(activeCount)", "filed", highlight: true)
            kpiCell("AVG AGE", "\(avgAgeDays)d", "to resolve", highlight: false)
            kpiCell("WON YTD", "\(winPct)%", "recovery", highlight: false)
        }
    }
    private func kpiCell(_ label: String, _ value: String, _ sub: String, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(highlight ? .white.opacity(0.85) : palette.textTertiary)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(highlight ? .white : palette.textPrimary)
            Text(sub).font(.system(size: 10, weight: .regular)).foregroundStyle(highlight ? .white.opacity(0.8) : palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(highlight ? Color.clear : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Disputes list

    private var disputesList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("DISPUTES").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if disputes.isEmpty {
                EusoEmptyState(systemImage: "checkmark.seal", title: "No open disputes", subtitle: "Filed billing disputes appear here with the statute clock.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(disputes.prefix(5).enumerated()), id: \.element.id) { idx, d in
                        disputeRow(d)
                        if idx < min(disputes.count, 5) - 1 { Divider().overlay(palette.borderFaint).padding(.leading, Space.s4) }
                    }
                    HStack {
                        Text("9-month overcharge statute · disputes bind on carrier response")
                            .font(.system(size: 10, weight: .regular)).foregroundStyle(palette.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func disputeRow(_ d: DisputeRow657) -> some View {
        let kind = typeKind(d.type)
        let st = statusKind(d.status)
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(kind.color.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: kind.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(kind.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(typeLabel(d.type)).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text([d.invoiceNumber, d.carrier?.isEmpty == false ? d.carrier : d.disputeNumber].compactMap { $0 }.joined(separator: " · "))
                    .font(EType.mono(.caption)).tracking(0.3).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(st.label).font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(st.color)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(st.color.opacity(0.16)))
                Text(money(d.amount ?? 0)).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
    }

    private func typeKind(_ t: String?) -> (icon: String, color: Color) {
        switch (t ?? "").lowercased() {
        case "rate", "overcharge": return ("doc.text", Brand.info)
        case "detention", "accessorial", "demurrage": return ("clock", Brand.hazmat)
        case "duplicate", "damage": return ("doc.on.doc", Brand.escort)
        default: return ("exclamationmark.bubble", Brand.warning)
        }
    }
    private func typeLabel(_ t: String?) -> String {
        (t ?? "dispute").replacingOccurrences(of: "_", with: " ").capitalized
    }
    private func statusKind(_ s: String?) -> (label: String, color: Color) {
        switch (s ?? "").lowercased() {
        case "filed", "open":       return ("FILED", Brand.info)
        case "under_review", "responded": return ("REVIEW", Brand.hazmat)
        case "escalated":           return ("MEDIATION", Brand.escort)
        case "resolved":            return ("RESOLVED", Brand.success)
        case "closed":              return ("CLOSED", Brand.neutral)
        default:                    return ((s ?? "open").uppercased(), palette.textSecondary)
        }
    }

    // MARK: Audit match note

    private var auditMatch: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AUDIT MATCH").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text("Auto-flagged by the last invoice audit · manual disputes fill the rest")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("Each dispute binds on carrier response within the 9-month window")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
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
            CTAButton(title: "File dispute", action: openFileDispute)
            Button(action: { Task { await runAudit() } }) {
                Text(auditing ? "Auditing…" : "Run audit").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int; let offset: Int }
        do {
            let r: DisputeResolution657 = try await EusoTripAPI.shared.query("freightClaims.getDisputeResolution", input: In(limit: 20, offset: 0))
            self.disputes = r.disputes ?? []
            self.summary = r.summary
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func openFileDispute() {
        NotificationCenter.default.post(name: Notification.Name("eusoOpenFileDispute"), object: nil,
            userInfo: ["mode": "rail"])
        actionIsError = false
        actionBanner = "Opening the file-dispute composer"
    }

    private func runAudit() async {
        guard !auditing else { return }
        auditing = true; actionBanner = nil
        struct AuditIn: Encodable { let auditType: String }
        struct AuditOut: Decodable { let auditId: String?; let findingsCreated: Int?; let invoicesQueued: Int?; let totalVariance: Double? }
        do {
            let out: AuditOut = try await EusoTripAPI.shared.mutation("freightClaims.runFreightAudit", input: AuditIn(auditType: "full"))
            actionIsError = false
            let n = out.findingsCreated ?? 0
            actionBanner = n > 0
                ? "Audit \(out.auditId ?? "") flagged \(n) recovery finding\(n == 1 ? "" : "s") · \(moneyFull(out.totalVariance ?? 0))"
                : "Audit \(out.auditId ?? "") complete · no new overcharges found"
            await load()
        } catch {
            actionIsError = true
            actionBanner = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        auditing = false
    }

    // MARK: Scaffolds

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 116)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 72)
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

private extension DateFormatter {
    static func iso(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
}

// MARK: - Previews

#Preview("657 · Rail Dispute Resolution · Night") {
    RailDisputeResolutionScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("657 · Rail Dispute Resolution · Light") {
    RailDisputeResolutionScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
