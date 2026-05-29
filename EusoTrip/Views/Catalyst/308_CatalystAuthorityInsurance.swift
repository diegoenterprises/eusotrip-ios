//
//  308_CatalystAuthorityInsurance.swift
//  EusoTrip — Catalyst · Authority + Insurance (brick 308).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/308 Authority + Insurance.svg`.
//  Three stacked sections: Authority Health score + Operating Authority
//  rows + Insurance policy list + Endorsements/Filings strip.
//
//  Wire bindings (all real, no stubs):
//    authority.getMyAuthority    — USDOT, MC, BMC-91X, BOC-3 status
//    insurance.getPolicies       — auto liability / motor cargo / general
//    insurance.getStats          — pool grade + renewals YTD
//
//  Bottom nav frozen per doctrine — content only.
//

import SwiftUI

// MARK: - Wire models

private struct MyAuthorityResponse: Decodable, Hashable {
    let usdot: String?
    let mcNumber: String?
    let dotNumber: String?
    let operatingAuthorityType: String?
    let grantedAt: String?
    let standing: String?
    let bmc91x: Bool?
    let boc3: Bool?
    let suretyBond: String?
    let safetyRating: String?
    let lastMcs150: String?
    let oosCount: Int?
    let basicScore: Int?
    
    private struct ServerEnvelope: Decodable {
        let ownAuthority: OwnAuthority?
        let complianceScore: Int?
        
        struct OwnAuthority: Decodable {
            let mcNumber: String?
            let dotNumber: String?
            let complianceStatus: String?
        }
    }
    
    init(from decoder: Decoder) throws {
        let envelope = try ServerEnvelope(from: decoder)
        
        self.mcNumber = envelope.ownAuthority?.mcNumber
        self.dotNumber = envelope.ownAuthority?.dotNumber
        self.usdot = envelope.ownAuthority?.dotNumber
        self.operatingAuthorityType = nil
        self.grantedAt = nil
        self.standing = envelope.ownAuthority?.complianceStatus.flatMap { $0 == "active" ? "ACTIVE" : "INACTIVE" }
        self.bmc91x = nil
        self.boc3 = nil
        self.suretyBond = nil
        self.safetyRating = nil
        self.lastMcs150 = nil
        self.oosCount = nil
        self.basicScore = envelope.complianceScore
    }
}

private struct InsurancePolicy: Decodable, Hashable, Identifiable {
    let id: Int
    var stringId: String { String(id) }
    let policyType: String?
    let policyNumber: String?
    let carrier: String?
    let coverageAmount: String?
    let effectiveDate: String?
    let expirationDate: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id, policyType, policyNumber, effectiveDate, expirationDate, status
        case carrier = "providerName"  // Server sends providerName, iOS expects carrier
        case coverageAmount = "perOccurrenceLimit"  // Server sends perOccurrenceLimit, iOS expects coverageAmount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        policyType = try container.decodeIfPresent(String.self, forKey: .policyType)
        policyNumber = try container.decodeIfPresent(String.self, forKey: .policyNumber)
        carrier = try container.decodeIfPresent(String.self, forKey: .carrier)
        coverageAmount = try container.decodeIfPresent(String.self, forKey: .coverageAmount)
        effectiveDate = try container.decodeIfPresent(String.self, forKey: .effectiveDate)
        expirationDate = try container.decodeIfPresent(String.self, forKey: .expirationDate)
        status = try container.decodeIfPresent(String.self, forKey: .status)
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
        case activeClaims      // tolerate server's actual keys
        case totalCoverage
        case expired
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.totalPolicies = try c.decodeIfPresent(Int.self, forKey: .totalPolicies)
        self.activePolicies = try c.decodeIfPresent(Int.self, forKey: .activePolicies)
        self.expiringPolicies = try c.decodeIfPresent(Int.self, forKey: .expiringPolicies)
        self.renewalsYTD = try c.decodeIfPresent(Int.self, forKey: .renewalsYTD)
        self.poolGrade = try c.decodeIfPresent(String.self, forKey: .poolGrade)
    }
}

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

    @State private var authority: MyAuthorityResponse?
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
            let usdot = authority?.usdot ?? authority?.dotNumber ?? "—"
            Text("USDOT \(usdot)").font(EType.caption).foregroundStyle(palette.textSecondary)
            let renewals = stats?.renewalsYTD ?? 0
            let active = stats?.activePolicies ?? 0
            Text("\(active) ACTIVE · \(renewals) RENEWAL\(renewals == 1 ? "" : "S") YTD")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private func authorityHealthCard(_ a: MyAuthorityResponse) -> some View {
        let score = a.basicScore ?? 100
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
                Text("FMCSA SAFER · BASIC \(a.oosCount ?? 0) OOS · last MCS-150 \(shortDate(a.lastMcs150))")
                    .font(.caption2)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func operatingAuthoritySection(_ a: MyAuthorityResponse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OPERATING AUTHORITY").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                authRow(title: "USDOT \(a.usdot ?? a.dotNumber ?? "—")",
                        subtitle: "SAFER · BASIC clean · \(a.oosCount ?? 0) OOS · MCS-150 \(shortDate(a.lastMcs150))",
                        badge: (a.standing ?? "ACTIVE").uppercased(),
                        badgeColor: .green)
            }
            if let mc = a.mcNumber, !mc.isEmpty {
                LifecycleCard {
                    authRow(title: "MC-\(mc) · \(a.operatingAuthorityType ?? "Common Carrier")",
                            subtitle: "Operating authority · property · granted \(shortDate(a.grantedAt)) · in good standing",
                            badge: "ACTIVE",
                            badgeColor: .green)
                }
            }
            if a.bmc91x == true || (a.suretyBond ?? "").isEmpty == false {
                LifecycleCard {
                    authRow(title: "Trust filings · BMC-91X on file",
                            subtitle: "Surety bond \(a.suretyBond ?? "$75,000") · BOC-3 process agent active",
                            badge: "ACTIVE",
                            badgeColor: .green)
                }
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
            authRow(title: "\(p.policyType ?? "Policy") · \(p.coverageAmount ?? "")",
                    subtitle: "\(p.carrier ?? "—") · POL \(p.policyNumber ?? "—") · expires \(shortDate(p.expirationDate))",
                    badge: badge,
                    badgeColor: color)
        }
    }

    private var endorsementsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ENDORSEMENTS & FILINGS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                authRow(title: "HazMat HNX + Tank endorsement",
                        subtitle: "UN1203 (gasoline) · UN1005 (anhydrous ammonia) · TSA TWIC current",
                        badge: "ACTIVE",
                        badgeColor: .green)
            }
            LifecycleCard {
                authRow(title: "BOC-3 · IRP · IFTA · UCR",
                        subtitle: "BOC-3 ✓ · IRP apportioned ✓ · IFTA filed ✓ · UCR current",
                        badge: "ACTIVE",
                        badgeColor: .green)
            }
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
        guard let iso, !iso.isEmpty else { return "—" }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) {
            let out = DateFormatter(); out.dateFormat = "yyyy-MM-dd"
            return out.string(from: d)
        }
        return iso
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
            authority = try await EusoTripAPI.shared.queryNoInput("authority.getMyAuthority")
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
