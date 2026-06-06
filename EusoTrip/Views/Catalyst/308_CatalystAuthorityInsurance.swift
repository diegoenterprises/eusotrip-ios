//
//  308_CatalystAuthorityInsurance.swift
//  EusoTrip — Catalyst · Authority + Insurance (brick 308).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/308 Authority + Insurance.svg`.
//  Three stacked sections: Authority Health score + Operating Authority
//  rows + Insurance policy list + Endorsements/Filings strip.
//
//  Wire bindings (all real, no stubs):
//    authority.getMyAuthority  — AuthorityAPI.MyAuthority
//                                (ownAuthority {companyName, legalName,
//                                 mcNumber, dotNumber, insurancePolicy,
//                                 insuranceExpiry, complianceStatus,
//                                 isActive} + complianceScore).
//    insurance.getPolicies     — auto liability / motor cargo / general
//    insurance.getStats        — pool grade + renewals YTD
//
//  ZERO-FABRICATION NOTE — the server `authority.getMyAuthority`
//  (frontend/server/routers/authority.ts) returns ONLY ownAuthority +
//  leases + complianceScore. It carries NO USDOT-distinct-from-DOT,
//  NO surety bond, NO BMC-91X / BOC-3 flags, NO FMCSA SAFER / BASIC /
//  OOS counts, NO MCS-150 date, NO HazMat / TWIC / IRP / IFTA / UCR
//  filing state, NO operating-authority-type, NO grant date. Those are
//  a backend gap — they render as an honest "-" / "—" / EusoEmptyState,
//  never a fabricated literal or a green ACTIVE badge.
//
//  Bottom nav frozen per doctrine — content only.
//

import SwiftUI

// MARK: - Screen

struct CatalystAuthorityInsuranceScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { AuthInsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct AuthInsBody: View {
    @Environment(\.palette) private var palette

    // MARK: Wire models (insurance section — real insurancePolicies columns)

    private struct InsurancePolicy: Decodable, Hashable, Identifiable {
        let id: Int
        let policyType: String?
        let policyNumber: String?
        let carrier: String?
        let coverageAmount: String?
        let effectiveDate: String?
        let expirationDate: String?
        let status: String?

        enum CodingKeys: String, CodingKey {
            case id, policyType, policyNumber, effectiveDate, expirationDate, status
            case carrier = "providerName"          // server column
            case coverageAmount = "perOccurrenceLimit"  // server column
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id             = try c.decode(Int.self, forKey: .id)
            policyType     = try c.decodeIfPresent(String.self, forKey: .policyType)
            policyNumber   = try c.decodeIfPresent(String.self, forKey: .policyNumber)
            carrier        = try c.decodeIfPresent(String.self, forKey: .carrier)
            coverageAmount = try c.decodeIfPresent(String.self, forKey: .coverageAmount)
            effectiveDate  = try c.decodeIfPresent(String.self, forKey: .effectiveDate)
            expirationDate = try c.decodeIfPresent(String.self, forKey: .expirationDate)
            status         = try c.decodeIfPresent(String.self, forKey: .status)
        }
    }

    private struct InsuranceStats: Decodable, Hashable {
        let totalPolicies: Int?
        let activePolicies: Int?
        let expiringPolicies: Int?
        let renewalsYTD: Int?
        let poolGrade: String?

        enum CodingKeys: String, CodingKey {
            case totalPolicies
            case activePolicies = "active"
            case expiringPolicies = "expiring"
            case renewalsYTD
            case poolGrade
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.totalPolicies    = try c.decodeIfPresent(Int.self, forKey: .totalPolicies)
            self.activePolicies   = try c.decodeIfPresent(Int.self, forKey: .activePolicies)
            self.expiringPolicies = try c.decodeIfPresent(Int.self, forKey: .expiringPolicies)
            self.renewalsYTD      = try c.decodeIfPresent(Int.self, forKey: .renewalsYTD)
            self.poolGrade        = try c.decodeIfPresent(String.self, forKey: .poolGrade)
        }
    }

    // MARK: State

    @State private var authority: AuthorityAPI.MyAuthority?
    @State private var policies: [InsurancePolicy] = []
    @State private var stats: InsuranceStats?
    @State private var loading: Bool = true
    @State private var error: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && authority == nil {
                    LifecycleCard { Text("Loading authority…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = error {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    if let a = authority { authorityHealthCard(a) }
                    if let a = authority { operatingAuthoritySection(a) }
                    insuranceSection
                    endorsementsSection
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    // MARK: subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · AUTHORITY + INSURANCE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Authority + Insurance").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            // USDOT — server returns dotNumber only (no USDOT distinct from DOT).
            let dot = authority?.ownAuthority?.dotNumber ?? "-"
            Text("USDOT \(dot)").font(EType.caption).foregroundStyle(palette.textSecondary)
            // Active policies + renewals YTD — only render the YTD clause when
            // insurance.getStats actually shipped a renewal count.
            let active = stats?.activePolicies ?? policies.filter { ($0.status ?? "").lowercased() == "active" }.count
            if let renewals = stats?.renewalsYTD {
                Text("\(active) ACTIVE · \(renewals) RENEWAL\(renewals == 1 ? "" : "S") YTD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            } else {
                Text("\(active) ACTIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func authorityHealthCard(_ a: AuthorityAPI.MyAuthority) -> some View {
        let score = a.complianceScore
        let grade = stats?.poolGrade ?? gradeForScore(score)
        return LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 8) {
                LifecycleSection(label: "AUTHORITY HEALTH", icon: "checkmark.shield.fill")
                HStack(alignment: .firstTextBaseline) {
                    Text("\(score)")
                        .font(.system(size: 48, weight: .heavy).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("/ 100")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("POOL").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                        Text(grade)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(scoreColor(score))
                    }
                }
                // Honest source line — Part 376 lease compliance is what the
                // score is computed from server-side. No SAFER / BASIC / OOS /
                // MCS-150 data exists on this proc, so we don't claim it.
                Text("FMCSR Part 376 lease compliance · \(a.activeLeasesAsLessee.count + a.activeLeasesAsLessor.count) active lease\(a.activeLeasesAsLessee.count + a.activeLeasesAsLessor.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func operatingAuthoritySection(_ a: AuthorityAPI.MyAuthority) -> some View {
        let own = a.ownAuthority
        return VStack(alignment: .leading, spacing: 6) {
            Text("OPERATING AUTHORITY").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            if let own {
                let standing = (own.complianceStatus ?? "").lowercased()
                let standingLabel = (own.complianceStatus ?? "-").uppercased()
                let standingColor: Color = standing == "compliant" || standing == "active" ? .green
                                         : standing.isEmpty ? palette.textTertiary : .orange
                LifecycleCard {
                    authRow(title: "USDOT \(own.dotNumber ?? "-")",
                            subtitle: own.companyName ?? own.legalName ?? "-",
                            badge: standingLabel,
                            badgeColor: standingColor)
                }
                if let mc = own.mcNumber, !mc.isEmpty {
                    LifecycleCard {
                        authRow(title: "MC-\(mc)",
                                subtitle: "Operating authority\(own.insuranceExpiry.map { " · insurance expires \(shortDate($0))" } ?? "")",
                                badge: standingLabel,
                                badgeColor: standingColor)
                    }
                }
            } else {
                EusoEmptyState(
                    systemImage: "building.2",
                    title: "No company authority on file",
                    subtitle: "Your DOT / MC operating authority appears here once it's registered to your company."
                )
            }
        }
    }

    private func authRow(title: String, subtitle: String, badge: String, badgeColor: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(badge)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(badgeColor.opacity(0.18)))
                .foregroundStyle(badgeColor)
        }
    }

    private var insuranceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("INSURANCE · \(policies.count) \(policies.count == 1 ? "POLICY" : "POLICIES")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("eusoCatalystRequestCOI"), object: nil)
                } label: {
                    Text("+ Request new COI")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
            }
            if policies.isEmpty {
                LifecycleCard { Text("No insurance policies on file.").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else {
                ForEach(policies) { p in policyRow(p) }
            }
        }
    }

    private func policyRow(_ p: InsurancePolicy) -> some View {
        let renewing = expiresWithin(p.expirationDate, days: 60)
        let (badge, color): (String, Color) = renewing ? ("RENEW", .orange) : ("CURRENT", .green)
        return LifecycleCard(accentDanger: renewing) {
            authRow(title: "\(p.policyType ?? "Policy")\(p.coverageAmount.map { " · \($0)" } ?? "")",
                    subtitle: "\(p.carrier ?? "-") · POL \(p.policyNumber ?? "-") · expires \(shortDate(p.expirationDate))",
                    badge: badge,
                    badgeColor: color)
        }
    }

    private var endorsementsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ENDORSEMENTS & FILINGS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            // ZERO-FABRICATION — HazMat / TWIC / BOC-3 / IRP / IFTA / UCR
            // filing state has NO live source on authority.getMyAuthority
            // (or any wired proc this screen reads). We render an honest
            // empty state instead of fabricated green ACTIVE badges.
            EusoEmptyState(
                systemImage: "doc.text.magnifyingglass",
                title: "No filing data available",
                subtitle: "HazMat HNX · TWIC · BOC-3 · IRP · IFTA · UCR endorsement status isn't connected to this view yet."
            )
        }
    }

    // MARK: helpers

    private func gradeForScore(_ score: Int) -> String {
        switch score {
        case 95...100: return "A+"
        case 90..<95:  return "A"
        case 80..<90:  return "B"
        case 70..<80:  return "C"
        case 60..<70:  return "D"
        default:       return "F"
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return .green
        case 75..<90:  return .yellow
        case 60..<75:  return .orange
        default:       return .red
        }
    }

    private func shortDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "-" }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) {
            let out = DateFormatter(); out.dateFormat = "yyyy-MM-dd"
            return out.string(from: d)
        }
        // Tolerate a date-only or non-fractional ISO string by surfacing the
        // first 10 chars (yyyy-MM-dd) rather than the raw timestamp.
        return iso.count >= 10 ? String(iso.prefix(10)) : iso
    }

    private func expiresWithin(_ iso: String?, days: Int) -> Bool {
        guard let iso, !iso.isEmpty else { return false }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) else { return false }
        return d.timeIntervalSinceNow < Double(days) * 86400 && d.timeIntervalSinceNow > 0
    }

    // MARK: pipeline

    private func loadAll() async {
        loading = true; error = nil
        async let a: Void = loadAuthority()
        async let p: Void = loadPolicies()
        async let s: Void = loadStats()
        _ = await (a, p, s)
        loading = false
    }

    private func loadAuthority() async {
        do {
            authority = try await EusoTripAPI.shared.authority.getMyAuthority()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func loadPolicies() async {
        struct In: Encodable { let limit: Int }
        do {
            policies = try await EusoTripAPI.shared.query("insurance.getPolicies", input: In(limit: 20))
        } catch { /* */ }
    }

    private func loadStats() async {
        do { stats = try await EusoTripAPI.shared.queryNoInput("insurance.getStats") } catch { /* */ }
    }
}

#Preview("308 Auth+Ins · Dark")  { CatalystAuthorityInsuranceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("308 Auth+Ins · Light") { CatalystAuthorityInsuranceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
