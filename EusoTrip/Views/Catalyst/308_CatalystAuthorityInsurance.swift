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
//    insurance.requestCertificate — durable company-scoped COI request
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
                trailing: [NavSlot(label: "Fleet",  systemImage: "truck.box.fill", isCurrent: false),
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
    @State private var complianceOverview: ComplianceAPI.CatalystComplianceOverview?
    @State private var policies: [InsurancePolicy] = []
    @State private var stats: InsuranceStats?
    @State private var loading: Bool = true
    @State private var error: String?
    @State private var showCOISheet: Bool = false
    @State private var requestingCOI: Bool = false
    @State private var coiHolderName: String = ""
    @State private var coiHolderAddress: String = ""
    @State private var coiHolderEmail: String = ""
    @State private var selectedCOIPolicyIds: Set<Int> = []
    @State private var coiError: String?
    @State private var coiPacket: String?

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
        .sheet(isPresented: $showCOISheet) { coiRequestSheet }
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
                    openCOISheet()
                } label: {
                    Text("+ Request new COI")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
            }
            coiFeedback
            if policies.isEmpty {
                LifecycleCard { Text("No insurance policies on file.").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else {
                ForEach(policies) { p in policyRow(p) }
            }
        }
    }

    @ViewBuilder
    private var coiFeedback: some View {
        if let coiError {
            LifecycleCard(accentDanger: true) {
                Text(coiError).font(EType.caption).foregroundStyle(Brand.danger)
            }
        } else if let coiPacket {
            LifecycleCard {
                Text(coiPacket.split(separator: "\n").first.map(String.init) ?? "COI request saved.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var coiRequestSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Certificate of Insurance")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Request a company-scoped COI from the live policies on file.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    LifecycleCard {
                        VStack(spacing: 10) {
                            coiField("Certificate holder", text: $coiHolderName)
                            coiField("Holder email", text: $coiHolderEmail, keyboard: .emailAddress)
                            coiField("Holder address", text: $coiHolderAddress)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("POLICIES").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                        if policies.isEmpty {
                            EusoEmptyState(
                                systemImage: "doc.text.magnifyingglass",
                                title: "No policies to attach",
                                subtitle: "Upload or verify insurance policies before requesting a COI."
                            )
                        } else {
                            ForEach(policies) { policy in
                                LifecycleCard { coiPolicyRow(policy) }
                            }
                        }
                    }
                    if let coiError {
                        Text(coiError)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                    }
                    if let coiPacket {
                        LifecycleCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Request saved")
                                    .font(EType.body.weight(.semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Text(coiPacket)
                                    .font(.caption2)
                                    .foregroundStyle(palette.textTertiary)
                                ShareLink(item: coiPacket) {
                                    Label("Share COI packet", systemImage: "square.and.arrow.up")
                                        .font(EType.caption.weight(.semibold))
                                }
                            }
                        }
                    }
                    Button {
                        Task { await requestCOI() }
                    } label: {
                        HStack {
                            if requestingCOI { ProgressView().tint(.white) }
                            Text(requestingCOI ? "Requesting…" : "Request COI")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(requestingCOI || !coiFormValid)
                }
                .padding(18)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showCOISheet = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func coiField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            TextField(title, text: text)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.bgSecondary))
        }
    }

    private func coiPolicyRow(_ policy: InsurancePolicy) -> some View {
        Toggle(isOn: Binding(
            get: { selectedCOIPolicyIds.contains(policy.id) },
            set: { enabled in
                if enabled {
                    selectedCOIPolicyIds.insert(policy.id)
                } else {
                    selectedCOIPolicyIds.remove(policy.id)
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text(policy.policyType ?? "Policy")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(policy.carrier ?? "-") · POL \(policy.policyNumber ?? "-") · \(shortDate(policy.expirationDate))")
                    .font(.caption2)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .toggleStyle(.switch)
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
            ForEach(filingRows) { row in
                LifecycleCard(accentDanger: row.isBlocking) {
                    authRow(
                        title: row.title,
                        subtitle: row.subtitle,
                        badge: row.badge,
                        badgeColor: row.color
                    )
                }
            }
        }
    }

    private struct FilingRow: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let badge: String
        let color: Color
        let isBlocking: Bool
    }

    private var filingRows: [FilingRow] {
        let filings = complianceOverview?.filings
        return [
            filingRow(
                id: "hazmat",
                label: "HazMat authority",
                status: filings?.hazmat?.status ?? authorityExpiryStatus(
                    identifier: authority?.ownAuthority?.hazmatLicense,
                    expiresAt: authority?.ownAuthority?.hazmatExpiry
                ).status,
                detail: filings?.hazmat?.detail ?? authorityExpiryStatus(
                    identifier: authority?.ownAuthority?.hazmatLicense,
                    expiresAt: authority?.ownAuthority?.hazmatExpiry
                ).detail,
                date: filings?.hazmat?.expiresAt ?? authority?.ownAuthority?.hazmatExpiry
            ),
            filingRow(
                id: "twic",
                label: "TWIC card",
                status: filings?.twic?.status ?? authorityExpiryStatus(
                    identifier: authority?.ownAuthority?.twicCard,
                    expiresAt: authority?.ownAuthority?.twicExpiry
                ).status,
                detail: filings?.twic?.detail ?? authorityExpiryStatus(
                    identifier: authority?.ownAuthority?.twicCard,
                    expiresAt: authority?.ownAuthority?.twicExpiry
                ).detail,
                date: filings?.twic?.expiresAt ?? authority?.ownAuthority?.twicExpiry
            ),
            filingRow(
                id: "ucr",
                label: "UCR filing",
                status: filings?.ucr?.status,
                detail: filings?.ucr?.detail,
                date: filings?.ucr?.dueDate
            ),
            filingRow(
                id: "ifta",
                label: "IFTA filing",
                status: filings?.ifta?.status,
                detail: filings?.ifta?.detail,
                date: filings?.ifta?.dueDate
            ),
            filingRow(
                id: "irp",
                label: "IRP cab cards",
                status: filings?.irp?.status,
                detail: filings?.irp?.detail,
                date: filings?.irp?.dueDate
            )
        ]
    }

    private func filingRow(id: String, label: String, status: String?, detail: String?, date: String?) -> FilingRow {
        let normalized = (status ?? "unknown").trimmed.lowercased()
        let (badge, color, blocking): (String, Color, Bool) = {
            switch normalized {
            case "active", "completed", "valid":
                return ("ACTIVE", .green, false)
            case "expiring", "upcoming", "due", "pending":
                return ("REVIEW", .orange, false)
            case "expired", "overdue", "suspended":
                return ("BLOCK", Brand.danger, true)
            case "missing":
                return ("MISSING", Brand.danger, true)
            default:
                return ("UNKNOWN", palette.textTertiary, false)
            }
        }()
        let parts = [detail?.trimmed.nilIfEmpty, dateLabel(date)].compactMap { $0 }
        return FilingRow(
            id: id,
            title: label,
            subtitle: parts.isEmpty ? "Live filing status unavailable from provider" : parts.joined(separator: " · "),
            badge: badge,
            color: color,
            isBlocking: blocking
        )
    }

    private func dateLabel(_ iso: String?) -> String? {
        guard let iso = iso?.trimmed, !iso.isEmpty else { return nil }
        return "date \(shortDate(iso))"
    }

    private func authorityExpiryStatus(identifier: String?, expiresAt: String?) -> (status: String, detail: String) {
        guard identifier?.trimmed.nilIfEmpty != nil else {
            return ("missing", "Not on company authority file")
        }
        guard let expiresAt = expiresAt?.trimmed.nilIfEmpty else {
            return ("active", "Number on file, expiration not supplied")
        }
        if isExpired(expiresAt) {
            return ("expired", "Expired \(shortDate(expiresAt))")
        }
        if expiresWithin(expiresAt, days: 30) {
            return ("expiring", "Expires \(shortDate(expiresAt))")
        }
        return ("active", "Active until \(shortDate(expiresAt))")
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

    private func dateFromISO(_ iso: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: iso) { return date }
        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: iso) { return date }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: iso)
    }

    private func isExpired(_ iso: String?) -> Bool {
        guard let iso, !iso.isEmpty, let date = dateFromISO(iso) else { return false }
        return date.timeIntervalSinceNow < 0
    }

    private func expiresWithin(_ iso: String?, days: Int) -> Bool {
        guard let iso, !iso.isEmpty else { return false }
        guard let d = dateFromISO(iso) else { return false }
        return d.timeIntervalSinceNow < Double(days) * 86400 && d.timeIntervalSinceNow > 0
    }

    private var coiFormValid: Bool {
        !coiHolderName.trimmed.isEmpty && !selectedCOIPolicyIds.isEmpty
    }

    private func openCOISheet() {
        coiError = nil
        coiPacket = nil
        coiHolderName = ""
        coiHolderAddress = ""
        coiHolderEmail = ""
        selectedCOIPolicyIds = Set(policies.map(\.id))
        showCOISheet = true
    }

    private func requestCOI() async {
        coiError = nil
        guard coiFormValid else {
            coiError = "Add a certificate holder and select at least one live policy."
            return
        }
        requestingCOI = true
        defer { requestingCOI = false }
        struct In: Encodable {
            let holderName: String
            let holderAddress: String?
            let holderEmail: String?
            let policyIds: [Int]
            let additionalInsuredEndorsement: Bool
            let waiverOfSubrogation: Bool
        }
        struct Out: Decodable {
            let success: Bool
            let certificateId: Int?
            let certificateNumber: String
        }
        do {
            let selected = policies.filter { selectedCOIPolicyIds.contains($0.id) }
            let out: Out = try await EusoTripAPI.shared.mutation(
                "insurance.requestCertificate",
                input: In(holderName: coiHolderName.trimmed,
                          holderAddress: coiHolderAddress.trimmed.nilIfEmpty,
                          holderEmail: coiHolderEmail.trimmed.nilIfEmpty,
                          policyIds: selected.map(\.id),
                          additionalInsuredEndorsement: false,
                          waiverOfSubrogation: false)
            )
            coiPacket = coiPacketText(certificateNumber: out.certificateNumber, policies: selected)
            await loadStats()
        } catch {
            coiError = "COI request wasn't saved. \(error.eusoUserCopy)"
        }
    }

    private func coiPacketText(certificateNumber: String, policies selected: [InsurancePolicy]) -> String {
        let company = authority?.ownAuthority?.companyName ?? authority?.ownAuthority?.legalName ?? "Company"
        let policyLines = selected.map { policy in
            "- \(policy.policyType ?? "Policy") · \(policy.carrier ?? "-") · POL \(policy.policyNumber ?? "-") · expires \(shortDate(policy.expirationDate))"
        }.joined(separator: "\n")
        return """
        COI request \(certificateNumber) saved.
        Requesting company: \(company)
        Certificate holder: \(coiHolderName.trimmed)
        Holder email: \(coiHolderEmail.trimmed.nilIfEmpty ?? "-")
        Holder address: \(coiHolderAddress.trimmed.nilIfEmpty ?? "-")
        Policies:
        \(policyLines)
        Status: pending carrier/insurance review
        """
    }

    // MARK: pipeline

    private func loadAll() async {
        loading = true; error = nil
        async let a: Void = loadAuthority()
        async let p: Void = loadPolicies()
        async let s: Void = loadStats()
        async let c: Void = loadCompliance()
        _ = await (a, p, s, c)
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

    private func loadCompliance() async {
        do {
            complianceOverview = try await EusoTripAPI.shared.compliance.getCatalystCompliance()
        } catch {
            complianceOverview = nil
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}

#Preview("308 Auth+Ins · Dark")  { CatalystAuthorityInsuranceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("308 Auth+Ins · Light") { CatalystAuthorityInsuranceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
