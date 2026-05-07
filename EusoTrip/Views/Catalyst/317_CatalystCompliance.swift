//
//  317_CatalystCompliance.swift
//  EusoTrip — Catalyst · Compliance (carrier-level overview).
//
//  Pixel-faithful port of the 317 Catalyst Compliance Figma —
//  carrier-level federal compliance dashboard. Pairs with the
//  per-driver 326 surface I shipped in build 217:
//
//    • 317 = carrier-level (MC, DOT, insurance, FMCSA SAFER, CSA
//      basic scores) — THIS file.
//    • 326 = per-driver scanline (CSA · §395 HOS · MCSAP · §391.41
//      Medical · §382 Drug pool).
//
//  Closes the empty state I left on 326 ("Not yet wired · check 317
//  carrier compliance home") — when the catalyst opens 317, the SAFER
//  rating + score-out-of-100 + insurance expiry + safety rating all
//  light up from real data; 326 then surfaces "see 317 for the
//  carrier-level view" on the CSA BASIC row.
//
//  Server wiring (real, no stubs):
//    • `compliance.getCatalystCompliance` (compliance.ts:2456) — the
//       carrier-level envelope: score / mcAuthority / dotNumber /
//       liabilityInsurance / cargoInsurance / safetyRating / csaScore.
//    • `fmcsa.lookupSelf` (fmcsa.ts:298) — live FMCSA SAFER record
//       for the catalyst's own DOT (cached via Redis + MySQL, falls
//       through to the live QCMobile call). Returns either
//       `{available: true, dotNumber, mcNumber, legalName,
//       safetyRating, oosViolations, lastInspection}` or
//       `{available: false, reason: ...}` — the canvas paints honest
//       em-dash when not available.
//    • `compliance.getDriverComplianceList` — for the per-driver
//       roster strip at the bottom (count of compliant / expiring /
//       expired / out-of-compliance drivers).
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystComplianceScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystCompliance()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_317(),
                trailing: catalystNavTrailing_317(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_317() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_317() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Body

private struct CatalystCompliance: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    @State private var overview: ComplianceAPI.CatalystComplianceOverview? = nil
    @State private var safer: FMCSASelfLookup? = nil
    @State private var driverRoster: [ComplianceAPI.DriverComplianceRow] = []
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    // MARK: Action ribbon sheet routing
    @State private var showFleetDrivers: Bool = false
    @State private var showShareInsuranceLink: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                iridescentHairline

                if loading {
                    skeletonBody
                } else if let err = loadError {
                    errorBanner(err)
                } else {
                    saferBanner
                    scoreHeroCard
                    authorityRow
                    insuranceCards
                    driverRosterStrip
                    actionRibbon
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
        // RealtimeService → driver / load / dispatch events all
        // can change the carrier's compliance posture (a violation
        // pushes the score down, a renewed insurance bumps it back up).
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
        }
        .sheet(isPresented: $showFleetDrivers) {
            CatalystFleetDriversScreen(theme: palette)
                .environmentObject(EusoTripSession())
        }
        .sheet(isPresented: $showShareInsuranceLink) {
            insuranceShareSheet
                .environment(\.palette, palette)
        }
    }

    @ViewBuilder
    private var insuranceShareSheet: some View {
        let liability = overview?.liabilityInsurance
        let body = """
        Renewal request — Eusotrans LLC carrier insurance
        DOT \(safer?.dotNumber ?? "—") · MC \(safer?.mcNumber ?? "—")
        Liability current expiry: \(liability?.expires ?? "—") · status: \(liability?.status ?? "—")
        Coverage: $\(Int(liability?.coverage ?? 0))
        Please send a renewal quote at your earliest convenience.
        """
        let mailto = "mailto:?subject=Insurance%20renewal%20request&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Renew liability insurance")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("EusoTrip doesn't write policies in-app. Tap below to email your insurance broker with the renewal payload prepopulated, or copy the details to your clipboard.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if let url = URL(string: mailto) {
                    ShareLink(item: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.fill").font(.system(size: 13, weight: .heavy))
                            Text("Email broker").font(.system(size: 14, weight: .heavy))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                        .padding(.horizontal, 20)
                    }
                }
                ScrollView {
                    Text(body)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(palette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 20)
                }
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Insurance renewal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showShareInsuranceLink = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - TopBar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · COMPLIANCE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(scoreHeader)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var scoreHeader: String {
        if let s = overview?.score { return "SCORE \(s) / 100" }
        return "—"
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Compliance")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text(subtitleLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var subtitleLine: String {
        let legal = safer?.legalName ?? "Carrier"
        return "\(legal) · MC + DOT · Insurance · FMCSA SAFER · 49 CFR §385"
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: - SAFER banner (live or unavailable)

    private var saferBanner: some View {
        let available = safer?.available == true
        let icon = available ? "shield.lefthalf.filled" : "shield.slash"
        let title = available ? "FMCSA SAFER · \(safer?.safetyRating ?? "NOT RATED")" : "FMCSA SAFER · UNAVAILABLE"
        let reason = available
            ? "DOT \(safer?.dotNumber ?? "—") · \(safer?.oosViolations ?? 0) out-of-service violations"
            : (safer?.reason ?? "No DOT number on file")

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(available ? Brand.success : Brand.warning)
                .frame(width: 36, height: 36)
                .background((available ? Brand.success : Brand.warning).opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(palette.textPrimary)
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if available, let last = safer?.lastInspection, !last.isEmpty {
                Text(formatDate(last))
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Score hero card

    private var scoreHeroCard: some View {
        let score = overview?.score ?? 0
        let safetyRating = overview?.safetyRating ?? safer?.safetyRating ?? "—"

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OVERALL SCORE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("\(score) / 100")
                    .font(.system(size: 28, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text(scoreTagLine(score))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text("SAFETY RATING")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(safetyRating)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(safetyRatingTint(safetyRating))
                Text("49 CFR §385")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue, Brand.magenta],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func scoreTagLine(_ score: Int) -> String {
        if score >= 90 { return "Excellent · ready for any tender" }
        if score >= 70 { return "Compliant · review pending items" }
        if score >= 40 { return "Action required · clear gaps" }
        return "Critical · blocks new tenders"
    }

    private func safetyRatingTint(_ rating: String) -> Color {
        switch rating.uppercased() {
        case "SATISFACTORY": return Brand.success
        case "CONDITIONAL":  return Brand.warning
        case "UNSATISFACTORY": return Brand.danger
        default: return palette.textPrimary
        }
    }

    // MARK: - Authority row (MC / DOT / UCR / IRP / IFTA)

    private var authorityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AUTHORITY")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                authorityTile(label: "MC",  value: overview?.mcAuthority ?? "")
                authorityTile(label: "DOT", value: overview?.dotNumber ?? "")
            }
            HStack(spacing: 8) {
                authorityTile(label: "UCR",  value: overview?.ucr ?? "")
                authorityTile(label: "IRP",  value: overview?.irp ?? "")
                authorityTile(label: "IFTA", value: overview?.ifta ?? "")
            }
        }
    }

    private func authorityTile(label: String, value: String) -> some View {
        let display = value.isEmpty ? "—" : value
        let tint: Color = value.isEmpty ? palette.textTertiary : Brand.success
        return VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(display)
                .font(.system(size: 13, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Insurance cards (Liability + Cargo)

    private var insuranceCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INSURANCE")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if let liability = overview?.liabilityInsurance {
                insuranceCard(title: "Liability", policy: liability)
            }
            if let cargo = overview?.cargoInsurance {
                insuranceCard(title: "Cargo", policy: cargo)
            }
        }
    }

    private func insuranceCard(title: String, policy: ComplianceAPI.CatalystComplianceInsurance) -> some View {
        let (statusLabel, statusTint) = insuranceStatus(policy.status)
        return HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(statusTint)
                .frame(width: 36, height: 36)
                .background(statusTint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(coverageLine(policy))
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Text(statusLabel)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(statusTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusTint.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func insuranceStatus(_ raw: String) -> (String, Color) {
        switch raw.lowercased() {
        case "active":   return ("ACTIVE",   Brand.success)
        case "expiring": return ("EXPIRING", Brand.warning)
        case "expired":  return ("EXPIRED",  Brand.danger)
        case "missing":  return ("MISSING",  Brand.danger)
        default:          return (raw.uppercased().isEmpty ? "—" : raw.uppercased(), palette.textTertiary)
        }
    }

    private func coverageLine(_ policy: ComplianceAPI.CatalystComplianceInsurance) -> String {
        let coverage = formatCurrency(policy.coverage)
        let exp = policy.expires.isEmpty ? "—" : "exp \(policy.expires)"
        return "\(coverage) · \(exp)"
    }

    private func formatCurrency(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    // MARK: - Driver roster strip

    private var driverRosterStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FLEET DRIVER COMPLIANCE")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                driverCountTile(eyebrow: "COMPLIANT", count: complianceCount("compliant"), tint: Brand.success)
                driverCountTile(eyebrow: "EXPIRING",  count: complianceCount("expiring"),  tint: Brand.warning)
                driverCountTile(eyebrow: "EXPIRED",   count: complianceCount("expired"),   tint: Brand.danger)
            }
        }
    }

    private func complianceCount(_ statusFilter: String) -> Int {
        driverRoster.filter { $0.status == statusFilter }.count
    }

    private func driverCountTile(eyebrow: String, count: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text("\(String(count))")
                .font(.system(size: 22, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(count > 0 ? tint : palette.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(count > 0 ? tint.opacity(0.4) : palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Action ribbon

    private var actionRibbon: some View {
        let action = nextAction()
        return Button {
            // Real navigation by axis. Each axis routes to the surface
            // where the catalyst can resolve it:
            //   • drivers   → 304 Fleet Drivers (per-driver list with
            //                 onboarding/DQ alerts feed)
            //   • insurance → ShareLink to mailto: insurance broker
            //                 (real-world action; the catalyst doesn't
            //                 renew policies in-app, they email their
            //                 broker / underwriter)
            //   • safety / authority / report → Fleet Drivers as well
            //                 (the per-driver scanlines drive most
            //                 remediation; carrier-level filings are
            //                 done off-app via FMCSA Portal)
            switch action.axis {
            case "drivers", "safety", "authority", "report":
                showFleetDrivers = true
            case "insurance":
                showShareInsuranceLink = true
            default:
                showFleetDrivers = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.icon)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(action.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private struct ActionDescriptor {
        let icon: String
        let title: String
        let subtitle: String
        let axis: String
    }

    private func nextAction() -> ActionDescriptor {
        // Prioritize what's broken: insurance → safety rating → MC/DOT
        // → driver-roster issues. When everything's clean, surface the
        // quarterly-report CTA.
        if let liability = overview?.liabilityInsurance, liability.status == "expired" || liability.status == "missing" {
            return ActionDescriptor(
                icon: "exclamationmark.shield.fill",
                title: "Renew liability insurance",
                subtitle: "Required for any active tender · 49 CFR §387",
                axis: "insurance"
            )
        }
        if let liability = overview?.liabilityInsurance, liability.status == "expiring" {
            return ActionDescriptor(
                icon: "clock.badge.exclamationmark.fill",
                title: "Schedule liability insurance renewal",
                subtitle: "Expires \(liability.expires) · 49 CFR §387",
                axis: "insurance"
            )
        }
        let rating = (overview?.safetyRating ?? safer?.safetyRating ?? "").uppercased()
        if rating == "UNSATISFACTORY" || rating == "CONDITIONAL" {
            return ActionDescriptor(
                icon: "shield.lefthalf.filled.slash",
                title: "Open FMCSA SAFER remediation",
                subtitle: "Safety rating: \(rating) · 49 CFR §385",
                axis: "safety"
            )
        }
        if (overview?.mcAuthority ?? "").isEmpty {
            return ActionDescriptor(
                icon: "doc.text.fill",
                title: "File MC authority",
                subtitle: "Required for for-hire interstate · FMCSA OP-1",
                axis: "authority"
            )
        }
        if complianceCount("expired") > 0 {
            return ActionDescriptor(
                icon: "person.crop.circle.badge.exclamationmark",
                title: "Resolve \(complianceCount("expired")) driver compliance gaps",
                subtitle: "Open 326 driver compliance for the per-driver scanline",
                axis: "drivers"
            )
        }
        return ActionDescriptor(
            icon: "checkmark.shield.fill",
            title: "All federal axes clean",
            subtitle: "File the quarterly compliance report · 49 CFR §385",
            axis: "report"
        )
    }

    // MARK: - Empty / loading / error

    private var skeletonBody: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 60)
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCard).frame(height: 110)
            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.bgCard).frame(height: 60) }
            }
            ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 60) }
        }
        .redacted(reason: .placeholder)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(msg)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Button { Task { await loadAll() } } label: {
                    Text("Retry")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Brand.danger.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func formatDate(_ raw: String) -> String {
        if raw.count >= 10 { return String(raw.prefix(10)) }
        return raw
    }

    // MARK: - Network

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            async let overviewTask: ComplianceAPI.CatalystComplianceOverview? = {
                try? await EusoTripAPI.shared.compliance.getCatalystCompliance()
            }()
            async let saferTask: FMCSASelfLookup? = {
                try? await EusoTripAPI.shared.fmcsa.lookupSelf()
            }()
            async let rosterTask: [ComplianceAPI.DriverComplianceRow] = {
                ((try? await EusoTripAPI.shared.compliance.getDriverComplianceList(limit: 100))?.drivers) ?? []
            }()
            let (o, s, r) = await (overviewTask, saferTask, rosterTask)
            self.overview = o
            self.safer = s
            self.driverRoster = r
        }
    }
}

// MARK: - Previews

#Preview("317 · Catalyst · Compliance · Night") {
    CatalystComplianceScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("317 · Catalyst · Compliance · Afternoon") {
    CatalystComplianceScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
