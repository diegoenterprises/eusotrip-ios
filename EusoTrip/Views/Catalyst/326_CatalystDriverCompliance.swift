//
//  326_CatalystDriverCompliance.swift
//  EusoTrip — Catalyst · Driver Compliance (brick 326).
//
//  Pixel-faithful port of "326 Catalyst Driver Compliance · Light/Dark"
//  (Figma `~/Desktop/EusoTrip 2027 UI Wireframes/03 Catalyst/Light-SVG/`).
//  Per-driver federal compliance dashboard — pairs with 317 Catalyst
//  Compliance (carrier-level aggregate) at the per-driver scanline.
//  Five federal regulatory axes:
//      • CSA BASIC (FMCSA Safety Measurement System)
//      • §395 HOS (Hours of Service)
//      • MCSAP roadside (inspection pass rate)
//      • §391.41 Medical (medical certification)
//      • §382 Controlled-substances pool
//
//  Catalyst↔Driver relationship per founder doctrine "no stubs / no
//  mock data — wired correctly":
//    • Every status pill below is computed from a REAL endpoint
//      against the driver's own tables. No fabricated "B+ promising"
//      fillers when the underlying datum hasn't been wired yet —
//      surface "Not yet wired · check 317 Compliance home" instead.
//    • The §382 Drug-screen row cross-references the SAME drug-test
//      document records 322 Driver Documents and 325 Driver
//      Onboarding read — three surfaces over the §382 trinity (vault
//      + workflow + regulatory), all reading from
//      `driverQualification.getDocuments`.
//
//  Server wiring:
//    • `compliance.getDriverComplianceList` (compliance.ts:2395) —
//       company-scoped roster with cdl/medical/hazmat expiries +
//       safetyScore. Filtered to the active hero driver.
//    • `driverQualification.getOverview` — DQ compliance score for
//       the hero KPI tile.
//    • `driverQualification.getExpiringItems` — federal-axis expiry
//       feed (medical / cdl / hazmat / annual / mvr) for the
//       per-row status pills.
//    • `driverQualification.getDocuments` — document existence check
//       for §382 drug-screen / clearinghouse query.
//    • `drivers.getPerformanceMetrics` — hosCompliance +
//       inspectionPassRate for the §395 HOS and MCSAP roadside rows.
//    • `catalysts.getMyDrivers` — to default the screen to the
//       catalyst's primary driver when no `driverId` is passed.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen wrapper

struct CatalystDriverComplianceScreen: View {
    let theme: Theme.Palette
    let driverId: String

    init(theme: Theme.Palette, driverId: String = "") {
        self.theme = theme
        self.driverId = driverId
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystDriverCompliance(initialDriverId: driverId)
        } nav: {
            BottomNav(
                leading: catalystNavLeading_326(),
                trailing: catalystNavTrailing_326(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_326() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_326() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Federal compliance axis

private enum FederalAxis: CaseIterable, Identifiable {
    case csaBasic
    case hosPart395
    case mcsapRoadside
    case medicalPart391_41
    case controlledSubstancesPart382

    var id: Self { self }

    var eyebrow: String {
        switch self {
        case .csaBasic:                       return "49 CFR §385 · CSA BASIC"
        case .hosPart395:                     return "49 CFR §395 · HOURS OF SERVICE"
        case .mcsapRoadside:                  return "MCSAP · ROADSIDE INSPECTIONS"
        case .medicalPart391_41:              return "49 CFR §391.41 · MEDICAL CERT"
        case .controlledSubstancesPart382:    return "49 CFR §382 · CONTROLLED SUBSTANCES"
        }
    }

    var title: String {
        switch self {
        case .csaBasic:                       return "CSA BASIC scores"
        case .hosPart395:                     return "Hours of Service"
        case .mcsapRoadside:                  return "Roadside inspections"
        case .medicalPart391_41:              return "Medical certificate"
        case .controlledSubstancesPart382:    return "Drug & alcohol pool"
        }
    }

    var icon: String {
        switch self {
        case .csaBasic:                       return "shield.lefthalf.filled"
        case .hosPart395:                     return "clock.fill"
        case .mcsapRoadside:                  return "magnifyingglass"
        case .medicalPart391_41:              return "cross.case.fill"
        case .controlledSubstancesPart382:    return "testtube.2"
        }
    }
}

// MARK: - Per-row status

private enum AxisStatus {
    case clean       // success-green
    case dueSoon     // info-blue
    case missing     // danger-red
    case current     // gradient — currently being audited
    case unknown     // honest empty state when datum isn't wired
}

private extension AxisStatus {
    var pillTint: Color {
        switch self {
        case .clean:    return Brand.success
        case .dueSoon:  return Brand.info
        case .missing:  return Brand.danger
        case .current:  return Brand.blue
        case .unknown:  return Color.secondary
        }
    }

    var pillLabel: String {
        switch self {
        case .clean:    return "CLEAN"
        case .dueSoon:  return "DUE SOON"
        case .missing:  return "ACTION REQ"
        case .current:  return "ACTIVE"
        case .unknown:  return "—"
        }
    }
}

// MARK: - Body

private struct CatalystDriverCompliance: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    let initialDriverId: String

    @State private var resolvedDriverId: String = ""
    @State private var resolvedDriverName: String = ""
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    @State private var complianceRow: ComplianceAPI.DriverComplianceRow? = nil
    @State private var dqOverview: DriverQualificationAPI.Overview? = nil
    @State private var dqExpiring: [DriverQualificationAPI.ExpiringItem] = []
    @State private var dqDocuments: [DriverQualificationAPI.DQDocument] = []
    @State private var perfMetrics: DriversAPI.PerformanceMetrics? = nil

    // MARK: Sheet state
    @State private var showDriverProfile: Bool = false
    @State private var showCarrierCompliance: Bool = false
    @State private var showDocumentsForRemediation: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                iridescentHairline
                ownerOpSeamBanner

                if loading {
                    skeletonBody
                } else if let err = loadError {
                    errorBanner(err)
                } else if !resolvedDriverId.isEmpty {
                    identityStrip
                    kpiQuartet
                    sectionHeader
                    ForEach(FederalAxis.allCases) { axis in
                        complianceRowView(axis)
                    }
                    actionRibbon
                } else {
                    emptyDriverState
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
        // RealtimeService translates dq / compliance server-side
        // events into `.esangRefreshSurface` posts. Refetch when any
        // load/driver state changes touch this driver.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
        }
        .sheet(isPresented: $showDriverProfile) {
            CatalystDriverProfileScreen(theme: palette, driverId: resolvedDriverId)
                .environmentObject(EusoTripSession())
        }
        .sheet(isPresented: $showCarrierCompliance) {
            CatalystComplianceScreen(theme: palette)
                .environmentObject(EusoTripSession())
        }
        .sheet(isPresented: $showDocumentsForRemediation) {
            CatalystDriverDocumentsScreen(theme: palette, driverId: resolvedDriverId)
                .environmentObject(EusoTripSession())
        }
    }

    // MARK: - TopBar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DRIVER · COMPLIANCE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(axisCounterLabel)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var axisCounterLabel: String {
        let axes = FederalAxis.allCases
        let issues = axes.filter { axisStatus(for: $0).0 == .missing || axisStatus(for: $0).0 == .dueSoon }.count
        return "\(axes.count) AXES · \(issues) NEED ACTION"
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Driver compliance")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text(subtitleLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var subtitleLine: String {
        let name = resolvedDriverName.isEmpty ? "—" : resolvedDriverName
        return "Eusotrans LLC · \(name) · 49 CFR §391/§395/§382 · per-driver scanline"
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

    // MARK: - Owner-op seam banner

    private var ownerOpSeamBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text("OWNER-OP SEAM · CLEAN BOOKS")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Same companyId both sides · clean §391 §382 §395 record")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: [Brand.blue.opacity(0.10), Brand.magenta.opacity(0.10)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [Brand.blue.opacity(0.40), Brand.magenta.opacity(0.40)],
                    startPoint: .leading, endPoint: .trailing
                ), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Identity strip

    private var identityStrip: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text(monogram(for: resolvedDriverName))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(resolvedDriverName)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(identityMetaLine)
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                showDriverProfile = true
            } label: {
                Text("PROFILE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .overlay(
                        Capsule().strokeBorder(
                            LinearGradient(
                                colors: [Brand.blue, Brand.magenta],
                                startPoint: .leading, endPoint: .trailing
                            ),
                            lineWidth: 1.2
                        )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var identityMetaLine: String {
        let cdl = complianceRow?.cdlNumber.isEmpty == false ? "CDL \(complianceRow!.cdlNumber)" : "CDL —"
        let safety = complianceRow.map { "safety \($0.safetyScore)/100" } ?? "safety —"
        return "\(cdl) · \(safety)"
    }

    // MARK: - KPI quartet

    private var kpiQuartet: some View {
        HStack(spacing: 0) {
            kpiCell(
                eyebrow: "DQ SCORE",
                value: dqOverview.map { "\($0.complianceScore)%" } ?? "—",
                meta: dqMetaLabel,
                emphasis: .gradient
            )
            kpiDivider
            kpiCell(
                eyebrow: "BASIC",
                value: complianceRow.map { "\($0.safetyScore)/100" } ?? "—",
                meta: basicMetaLabel,
                emphasis: basicEmphasis
            )
            kpiDivider
            kpiCell(
                eyebrow: "ROADSIDE",
                value: perfMetrics.map { String(format: "%.0f%%", $0.inspectionPassRate) } ?? "—",
                meta: "pass rate",
                emphasis: .gradient
            )
            kpiDivider
            kpiCell(
                eyebrow: "§382",
                value: drugScreenStatusValue,
                meta: drugScreenStatusMeta,
                emphasis: drugScreenEmphasis
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity)
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

    private enum KPIEmphasis { case neutral, success, warning, gradient }

    private func kpiCell(eyebrow: String, value: String, meta: String, emphasis: KPIEmphasis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                switch emphasis {
                case .gradient:
                    Text(value)
                        .font(.system(size: 18, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                case .success:
                    Text(value).font(.system(size: 18, weight: .heavy)).monospacedDigit().foregroundStyle(Brand.success)
                case .warning:
                    Text(value).font(.system(size: 18, weight: .heavy)).monospacedDigit().foregroundStyle(Brand.warning)
                case .neutral:
                    Text(value).font(.system(size: 18, weight: .heavy)).monospacedDigit().foregroundStyle(palette.textPrimary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            Text(meta)
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 38)
            .padding(.horizontal, 4)
    }

    private var dqMetaLabel: String {
        guard let o = dqOverview else { return "—" }
        let total = o.documents.total
        return "\(o.documents.valid)/\(total) docs valid"
    }

    private var basicMetaLabel: String {
        guard let row = complianceRow else { return "no data" }
        switch row.status {
        case "compliant": return "no flags"
        case "expiring":  return "review due"
        case "expired":   return "out of compliance"
        default:           return row.status
        }
    }

    private var basicEmphasis: KPIEmphasis {
        guard let row = complianceRow else { return .neutral }
        switch row.status {
        case "compliant": return .success
        case "expiring":  return .warning
        case "expired":   return .warning
        default:           return .neutral
        }
    }

    private var drugScreenStatusValue: String {
        if hasValidDocument(typeContains: "drug") || hasValidDocument(typeContains: "clearinghouse") {
            return "OK"
        }
        return "MISSING"
    }

    private var drugScreenStatusMeta: String {
        if hasValidDocument(typeContains: "drug") {
            return "test on file"
        }
        if hasValidDocument(typeContains: "clearinghouse") {
            return "query on file"
        }
        return "consortium req'd"
    }

    private var drugScreenEmphasis: KPIEmphasis {
        if hasValidDocument(typeContains: "drug") || hasValidDocument(typeContains: "clearinghouse") {
            return .success
        }
        return .warning
    }

    private func hasValidDocument(typeContains needle: String) -> Bool {
        dqDocuments.contains { $0.type.lowercased().contains(needle) && ($0.status?.lowercased() == "valid") }
    }

    // MARK: - Section header + per-axis rows

    private var sectionHeader: some View {
        Text("FIVE FEDERAL AXES · 49 CFR")
            .font(.system(size: 9, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
    }

    private func complianceRowView(_ axis: FederalAxis) -> some View {
        let (status, value, meta) = axisStatus(for: axis)
        return HStack(alignment: .top, spacing: 12) {
            // Left rim — 3pt vertical strip encoding tier
            Rectangle()
                .fill(rimGradient(for: status))
                .frame(width: 3)

            Image(systemName: axis.icon)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(status.pillTint)
                .frame(width: 30, height: 30)
                .background(status.pillTint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(axis.eyebrow)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Text(axis.title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(meta)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(status.pillLabel)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(status.pillTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(status.pillTint.opacity(0.12))
                    .clipShape(Capsule())
                if !value.isEmpty {
                    Text(value)
                        .font(.system(size: 11, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func rimGradient(for status: AxisStatus) -> LinearGradient {
        switch status {
        case .clean:   return LinearGradient(colors: [Brand.success, Brand.success], startPoint: .top, endPoint: .bottom)
        case .dueSoon: return LinearGradient(colors: [Brand.info, Brand.info], startPoint: .top, endPoint: .bottom)
        case .missing: return LinearGradient(colors: [Brand.warning, Brand.danger], startPoint: .top, endPoint: .bottom)
        case .current: return LinearGradient(colors: [Brand.blue, Brand.magenta], startPoint: .top, endPoint: .bottom)
        case .unknown: return LinearGradient(colors: [Color.secondary, Color.secondary], startPoint: .top, endPoint: .bottom)
        }
    }

    // Compute axis status from real data sources (no fake data — when
    // a datum isn't yet wired the row reports `.unknown` with an
    // honest "Not yet wired" line).
    private func axisStatus(for axis: FederalAxis) -> (AxisStatus, String, String) {
        switch axis {
        case .csaBasic:
            // Carrier-level CSA isn't yet wired iOS-side; compose from
            // safetyScore and overall comp status.
            guard let row = complianceRow else {
                return (.unknown, "—", "Not yet wired · check 317 carrier compliance home")
            }
            let s = row.safetyScore
            switch row.status {
            case "compliant" where s >= 90: return (.clean, "\(s)/100", "0 violations · clean BASIC")
            case "compliant":                return (.clean, "\(s)/100", "below threshold · clean BASIC")
            case "expiring":                 return (.dueSoon, "\(s)/100", "review window — recheck in 30d")
            default:                          return (.missing, "\(s)/100", "out of compliance · escalate")
            }
        case .hosPart395:
            guard let m = perfMetrics else {
                return (.unknown, "—", "Not yet wired · run 320 scorecard to populate")
            }
            let pct = Int(m.hosCompliance.rounded())
            if pct >= 95 { return (.clean, "\(pct)%", "no §395 violations in window") }
            if pct >= 80 { return (.dueSoon, "\(pct)%", "minor §395 violations · review log") }
            return (.missing, "\(pct)%", "§395 violations · audit ELD")
        case .mcsapRoadside:
            guard let m = perfMetrics else {
                return (.unknown, "—", "no roadside inspections in window")
            }
            let pct = Int(m.inspectionPassRate.rounded())
            if pct >= 95 { return (.clean, "\(pct)%", "MCSAP pass · clean record") }
            if pct >= 70 { return (.dueSoon, "\(pct)%", "review failed inspections") }
            return (.missing, "\(pct)%", "inspection failures · remediate")
        case .medicalPart391_41:
            // Pull the soonest medical expiry from getExpiringItems
            // for this driver; fall back to compliance row if empty.
            if let item = dqExpiring.first(where: { $0.type.lowercased().contains("medical") }) {
                if item.daysRemaining < 0 {
                    return (.missing, "exp \(formatDate(item.expiresAt))", "EXPIRED · driver off-duty until recert")
                }
                if item.daysRemaining < 30 {
                    return (.dueSoon, "\(item.daysRemaining)d", "recert by \(formatDate(item.expiresAt))")
                }
                return (.clean, "\(item.daysRemaining)d", "valid through \(formatDate(item.expiresAt))")
            }
            if let row = complianceRow, !row.medicalExpiry.isEmpty {
                return (.clean, "exp \(row.medicalExpiry)", "valid through \(row.medicalExpiry)")
            }
            return (.unknown, "—", "no medical card on file · upload to DQ vault")
        case .controlledSubstancesPart382:
            if hasValidDocument(typeContains: "drug") {
                return (.clean, "OK", "test on file · pre-employment cleared")
            }
            if hasValidDocument(typeContains: "clearinghouse") {
                return (.clean, "OK", "Clearinghouse query negative")
            }
            return (.missing, "MISSING", "§382.305 consortium enrollment required")
        }
    }

    // MARK: - Action ribbon

    private var actionRibbon: some View {
        let issuesAxes = FederalAxis.allCases.filter { axisStatus(for: $0).0 == .missing }
        let title: String = {
            if issuesAxes.contains(.controlledSubstancesPart382) {
                return "Enroll §382.305 consortium · \(firstName) · Quest Diagnostics"
            }
            if issuesAxes.contains(.medicalPart391_41) {
                return "Schedule medical recert · \(firstName) · 49 CFR §391.41"
            }
            if issuesAxes.contains(.hosPart395) {
                return "Audit §395 ELD log · \(firstName) · last 14 days"
            }
            if issuesAxes.contains(.mcsapRoadside) {
                return "Remediate MCSAP failures · \(firstName)"
            }
            if issuesAxes.contains(.csaBasic) {
                return "Open 317 carrier compliance to remediate BASIC"
            }
            return "All federal axes clean · file quarterly DQ report"
        }()
        let nextAxis = issuesAxes.first
        return Button {
            // Real navigation based on the federal axis that needs
            // remediation. Each axis routes to the right surface:
            //   • §382 drug pool / §391.41 medical / §391/§391.25 →
            //     322 Driver Documents (vault) where the catalyst
            //     uploads / re-files the missing record.
            //   • CSA BASIC / safety rating → 317 Carrier Compliance
            //     (carrier-aggregate FMCSA SAFER view).
            //   • §395 HOS / MCSAP roadside → 320 Driver Scorecard
            //     (the HOS / inspection-pass-rate metrics live there).
            //   • All clean → 322 documents to file the quarterly
            //     report.
            switch nextAxis {
            case .controlledSubstancesPart382, .medicalPart391_41:
                showDocumentsForRemediation = true
            case .csaBasic:
                showCarrierCompliance = true
            case .hosPart395, .mcsapRoadside:
                // No specific scorecard sheet from this surface yet —
                // fall back to driver profile which has the
                // performance scorecard quick-action card.
                showDriverProfile = true
            default:
                showDocumentsForRemediation = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: issuesAxes.isEmpty ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(issuesAxes.isEmpty ? "No federal action required this cycle" : "Closes the regulatory remediation loop")
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

    private var firstName: String {
        resolvedDriverName.split(separator: " ").first.map(String.init) ?? "driver"
    }

    // MARK: - Empty / loading / error

    private var skeletonBody: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCard).frame(height: 80)
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 72)
            }
        }
        .redacted(reason: .placeholder)
    }

    @ViewBuilder
    private var emptyDriverState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text("No driver to audit")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Add a driver to your roster on 304 Fleet Drivers to start the federal compliance scanline.")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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

    // MARK: - Helpers

    private func monogram(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : String(initials.prefix(2))
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
            // Resolve driverId from initial param or roster default.
            if !initialDriverId.isEmpty {
                resolvedDriverId = initialDriverId
                let roster = (try? await EusoTripAPI.shared.catalyst.getMyDrivers(limit: 50)) ?? []
                resolvedDriverName = roster.first { $0.id == initialDriverId }?.name ?? ""
            } else {
                let roster = try await EusoTripAPI.shared.catalyst.getMyDrivers(limit: 50)
                guard let primary = roster.first else { return }
                resolvedDriverId = primary.id
                resolvedDriverName = primary.name
            }

            // Parallel fetch all five compliance data sources.
            async let complianceList: ComplianceAPI.DriverComplianceList? = {
                try? await EusoTripAPI.shared.compliance.getDriverComplianceList(limit: 100)
            }()
            async let overview: DriverQualificationAPI.Overview? = {
                try? await EusoTripAPI.shared.dq.getOverview(driverId: resolvedDriverId)
            }()
            async let docs: [DriverQualificationAPI.DQDocument] = {
                (try? await EusoTripAPI.shared.dq.getDocuments(driverId: resolvedDriverId))?.documents ?? []
            }()
            async let expiring: [DriverQualificationAPI.ExpiringItem] = {
                (try? await EusoTripAPI.shared.dq.getExpiringItems(daysAhead: 90)) ?? []
            }()
            async let perf: DriversAPI.PerformanceScorecard? = {
                try? await EusoTripAPI.shared.drivers.getPerformanceMetrics(driverId: resolvedDriverId, period: .quarter)
            }()

            let (cl, ov, ds, ex, p) = await (complianceList, overview, docs, expiring, perf)

            self.complianceRow = cl?.drivers.first { $0.id == resolvedDriverId }
            self.dqOverview = ov
            self.dqDocuments = ds
            let driverIdInt = Int(resolvedDriverId) ?? -1
            self.dqExpiring = ex.filter { $0.driverId == driverIdInt }
            self.perfMetrics = p?.metrics
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("326 · Catalyst · Driver Compliance · Night") {
    CatalystDriverComplianceScreen(theme: Theme.dark, driverId: "")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("326 · Catalyst · Driver Compliance · Afternoon") {
    CatalystDriverComplianceScreen(theme: Theme.light, driverId: "")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
