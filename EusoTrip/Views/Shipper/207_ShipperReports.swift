//
//  207_ShipperReports.swift
//  EusoTrip — Shipper · Reports (brick 207).
//
//  Parity-reconciled to `02 Shipper/Code/207_ShipperReports.swift` per
//  _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: TopBar (eyebrow + run/scheduled counter), Reports title
//  block (display + sub-line), IridescentHairline, QUICK EXPORTS
//  2×2 grid (4 tile cards with stroked glyphs + "Export · {fmt}"
//  gradient CTA), SAVED REPORTS card (4 rows with width-locked
//  RUN AGAIN / SCHEDULED / RUN status pills), CUSTOM REPORT BUILDER
//  card (metric chips + group-by chips + gradient Compose → CTA).
//
//  Real data preserved as a DASHBOARD EXTRA-OK section beneath the
//  wireframe recipe — `ShipperSpendingAnalyticsStore` (shippers.
//  getSpendingAnalytics) + `ShipperCatalystPerformanceStore` (shippers.
//  getCatalystPerformance) + period-chip propagation. Saved-report
//  row counts hydrate from live spend totals when available, fall
//  back to §11 canon while loading.
//
//  Persona canon (§11): Diego Usoro · Eusorone Technologies (companyId 1)
//  · MATRIX-50-2026-04-26. §11.2 hazmat tile UN trio: UN1203 gasoline,
//  UN1005 NH₃, UN1267 crude (matches §216 Compliance hazmat tile).
//  §214 sustainability scope-3: 42.6 t · GLEC v3.0.
//
//  Web peer: Reports.tsx (`/reports`) — flagged ⚠ shallow per trajectory.
//  Notification names: eusoShipperReportQuickExport,
//                      eusoShipperReportRow,
//                      eusoShipperReportComposeChip,
//                      eusoShipperReportCompose.
//
//  BottomNav: Me current — out of scope per parity mandate §1.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Visual taxonomy

private enum QuickExportKind: String {
    case spendByLane     = "spend_by_lane"
    case catalystPayable = "catalyst_payable"
    case hazmatAudit     = "hazmat_audit"
    case co2Statement    = "co2_statement"

    var format: String {
        switch self {
        case .spendByLane:     return "csv"
        case .catalystPayable: return "xlsx"
        case .hazmatAudit:     return "pdf"
        case .co2Statement:    return "pdf"
        }
    }
}

private enum ReportStatus {
    case runAgain   // gradient — top-of-list run-now
    case scheduled  // success-tint — already on cadence
    case run        // neutral-outlined — run-on-demand
}

private struct BuilderChip: Identifiable, Hashable {
    let id: String
    let label: String
    let width: CGFloat
}

// MARK: - Screen body

struct ShipperReports: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var spendStore = ShipperSpendingAnalyticsStore()
    @StateObject private var catalystStore = ShipperCatalystPerformanceStore()

    @State private var selectedPeriod: ShipperAPI.SpendingPeriod = .month
    @State private var activeMetricChips: Set<String> = ["spend"]
    @State private var activeGroupByChips: Set<String> = ["lane"]

    /// Real-export plumbing. `pendingShareItems` triggers the system
    /// `UIActivityViewController` so the user can save the CSV to
    /// Files / AirDrop / Mail. `exportError` surfaces server failures
    /// inline as a toast so taps never silently die. `isExporting`
    /// gates duplicate taps while the network is in flight.
    @State private var pendingShareItems: [URL]? = nil
    @State private var exportError: String? = nil
    @State private var isExporting: Bool = false

    private let metricChips: [BuilderChip] = [
        BuilderChip(id: "spend",  label: "Spend $",   width: 80),
        BuilderChip(id: "ontime", label: "On-time %", width: 86),
        BuilderChip(id: "miles",  label: "Miles",     width: 68),
        BuilderChip(id: "co2",    label: "CO₂",       width: 68),
    ]
    private let groupByChips: [BuilderChip] = [
        BuilderChip(id: "lane",      label: "Lane",      width: 68),
        BuilderChip(id: "equipment", label: "Equipment", width: 92),
        BuilderChip(id: "catalyst",  label: "Catalyst",  width: 80),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            titleBlock
                .padding(.top, Space.s3)
            IridescentHairline()
                .padding(.top, Space.s3)
                .padding(.horizontal, Space.s5)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    sectionLabel("QUICK EXPORTS")
                    quickExportGrid
                    sectionLabel("SAVED REPORTS")
                    savedReportsCard
                    customBuilderCard
                    dashboardSection
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .sheet(isPresented: Binding(
            get: { pendingShareItems != nil },
            set: { if !$0 { pendingShareItems = nil } }
        )) {
            if let urls = pendingShareItems {
                ReportShareSheet(items: urls)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) {
            if let err = exportError {
                Text(err)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.red.opacity(0.92), in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 3_500_000_000)
                            await MainActor.run { withAnimation { exportError = nil } }
                        }
                    }
            }
        }
        .overlay {
            if isExporting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    /// Shared writer + share-sheet trigger. Writes the export body to
    /// a fresh tmp file, sets `pendingShareItems` so the sheet binding
    /// presents `UIActivityViewController`. Errors land in
    /// `exportError` so the user gets a tap-acknowledgement either way.
    @MainActor
    private func presentExport(_ file: ReportsAPI.ExportFile) {
        do {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("eusotrip-reports", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(file.filename)
            try file.body.data(using: .utf8)?.write(to: url, options: .atomic)
            pendingShareItems = [url]
        } catch {
            exportError = "Couldn't prepare \(file.filename): \(error.localizedDescription)"
        }
    }

    /// Convenience wrapper around the export network call so every
    /// tap site is one line: spinner up, fetch, present share sheet
    /// or surface the error toast, spinner down.
    private func runExport(_ work: @escaping () async throws -> ReportsAPI.ExportFile) {
        guard !isExporting else { return }
        isExporting = true
        Task {
            do {
                let file = try await work()
                await MainActor.run {
                    isExporting = false
                    presentExport(file)
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    let msg = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
                    exportError = "Export failed: \(msg)"
                }
            }
        }
    }

    private func refreshAll() async {
        async let a: Void = spendStore.refresh()
        async let b: Void = catalystStore.refresh()
        _ = await (a, b)
    }

    private var liveSpend: ShipperAPI.SpendingAnalytics? {
        spendStore.state.value ?? nil
    }

    // MARK: - TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · REPORTS")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    private var counterEyebrow: String {
        // Saved-report taxonomy: 4 rows, 2 of them scheduled.
        let scheduled = 2
        let ranLifetime = (liveSpend?.loadCount ?? 12) // proxy for "runs" until reports.list ships
        return "\(ranLifetime) RUN · \(scheduled) SCHEDULED"
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reports")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Export MATRIX-50 metrics · CSV · XLSX · PDF · API")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - QUICK EXPORTS — 2×2 grid

    private var quickExportGrid: some View {
        let columns: [GridItem] = [
            GridItem(.flexible(), spacing: 12, alignment: .topLeading),
            GridItem(.flexible(), spacing: 12, alignment: .topLeading),
        ]
        return LazyVGrid(columns: columns, spacing: 12) {
            quickExportTile(
                kind: .spendByLane,
                title: "Spend by lane",
                sub:   spendByLaneSub,
                cta:   "Export · CSV"
            )
            quickExportTile(
                kind: .catalystPayable,
                title: "Catalyst payable",
                sub:   catalystPayableSub,
                cta:   "Export · XLSX"
            )
            quickExportTile(
                kind: .hazmatAudit,
                title: "Hazmat audit",
                sub:   "UN1203 · UN1005 · UN1267",
                cta:   "Export · PDF"
            )
            quickExportTile(
                kind: .co2Statement,
                title: "CO₂ statement",
                sub:   "42.6 t · GLEC v3.0",
                cta:   "Export · PDF"
            )
        }
    }

    private var spendByLaneSub: String {
        if let s = liveSpend, s.loadCount > 0 {
            return "\(s.loadCount) loads · \(currency(s.totalSpend)) · YTD"
        }
        return "22 lanes · 50 loads · YTD"
    }

    private var catalystPayableSub: String {
        if case .loaded(let rows) = catalystStore.state, !rows.isEmpty {
            return "\(rows.count) carriers · settlements"
        }
        return "5 carriers · settlements"
    }

    private func quickExportTile(kind: QuickExportKind, title: String, sub: String, cta: String) -> some View {
        Button {
            // Real in-app export — calls the matching tRPC procedure,
            // writes the rendered CSV body to a temp file, and
            // presents `UIActivityViewController` so the user can
            // Save to Files / AirDrop / Mail / Messages the file. No
            // Safari hand-off, no 404 web URL, no observability stub.
            // Telemetry post retained alongside the real action.
            NotificationCenter.default.post(
                name: .eusoShipperReportQuickExport, object: nil,
                userInfo: [
                    "source": "207_ShipperReports",
                    "shipperCompanyId": session.user?.companyId ?? "1",
                    "kind": kind.rawValue,
                    "format": kind.format,
                ]
            )
            switch kind {
            case .spendByLane:
                runExport { try await EusoTripAPI.shared.reports.exportSpendByLane() }
            case .catalystPayable:
                runExport { try await EusoTripAPI.shared.reports.exportCatalystPayable() }
            case .hazmatAudit:
                runExport { try await EusoTripAPI.shared.reports.exportHazmatAudit() }
            case .co2Statement:
                runExport { try await EusoTripAPI.shared.reports.exportCO2Statement() }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    glyph(for: kind)
                }
                .frame(width: 32, height: 36)
                .padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.78)
                    Text(cta)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LinearGradient.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 80)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(sub).")
        .accessibilityHint("Runs the export and downloads the file.")
    }

    @ViewBuilder
    private func glyph(for kind: QuickExportKind) -> some View {
        switch kind {
        case .spendByLane:     DocumentGlyph(stroke: palette.textPrimary)
        case .catalystPayable: SpreadsheetGlyph(stroke: palette.textPrimary)
        case .hazmatAudit:     HazmatDiamondGlyph(badgeCount: 3)
        case .co2Statement:    Co2MountainGlyph()
        }
    }

    // MARK: - SAVED REPORTS

    private var savedReportsCard: some View {
        VStack(spacing: 0) {
            ForEach(savedReports.indices, id: \.self) { idx in
                savedReportRow(savedReports[idx])
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                if idx < savedReports.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// 4 saved reports — Q1 spend rollup pulls live values when
    /// available; the other three are §11 canon-anchored cadences.
    private var savedReports: [(title: String, sub: String, status: ReportStatus, verb: String)] {
        let q1Sub: String
        if let s = liveSpend, s.loadCount > 0 {
            q1Sub = "\(s.loadCount) loads · \(currency(s.totalSpend)) · last run 2d ago"
        } else {
            q1Sub = "53 loads · $784,210 · last run 2d ago"
        }
        let catalystCount: Int = {
            if case .loaded(let rows) = catalystStore.state { return rows.count }
            return 12
        }()
        return [
            ("Q1 spend rollup",
             q1Sub,
             .runAgain, "runAgain"),
            ("Catalyst scorecard · 90d",
             "\(catalystCount) catalysts · letter grades · scheduled weekly Mon 06:00",
             .scheduled, "openSchedule"),
            ("Detention & accessorial",
             "$3,820 in detention · 4 claims · 90d window",
             .run, "run"),
            ("Hazmat exposure log",
             "UN1203 + UN1005 + UN1267 · scheduled monthly 1st 09:00",
             .scheduled, "openSchedule"),
        ]
    }

    private func savedReportRow(_ row: (title: String, sub: String, status: ReportStatus, verb: String)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Text(row.sub)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            statusPill(row.status, verb: row.verb, title: row.title)
                .frame(width: 80, height: 22)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title). \(row.sub).")
    }

    @ViewBuilder
    private func statusPill(_ status: ReportStatus, verb: String, title: String) -> some View {
        Button {
            // Real in-app run — `reports.runSavedReport` shapes the CSV
            // by title (Q1 spend rollup / catalyst scorecard / detention
            // & accessorial / hazmat exposure log) and the share sheet
            // ships the file. Telemetry post retained.
            NotificationCenter.default.post(
                name: .eusoShipperReportRow, object: nil,
                userInfo: [
                    "source": "207_ShipperReports",
                    "shipperCompanyId": session.user?.companyId ?? "1",
                    "verb": verb,
                    "title": title,
                ]
            )
            runExport {
                try await EusoTripAPI.shared.reports.runSavedReport(verb: verb, title: title)
            }
        } label: {
            ZStack {
                switch status {
                case .runAgain:
                    Capsule().fill(LinearGradient.primary)
                case .scheduled:
                    Capsule().fill(Brand.success.opacity(0.10))
                case .run:
                    Capsule().fill(palette.bgCard)
                    Capsule().stroke(palette.borderSoft, lineWidth: 1)
                }
                Text(label(for: status))
                    .font(.system(size: 10, weight: .bold)).tracking(0.4)
                    .foregroundStyle(textColor(for: status))
            }
        }
        .buttonStyle(.plain)
    }

    private func label(for status: ReportStatus) -> String {
        switch status {
        case .runAgain:  return "RUN AGAIN"
        case .scheduled: return "SCHEDULED"
        case .run:       return "RUN"
        }
    }
    private func textColor(for status: ReportStatus) -> Color {
        switch status {
        case .runAgain:  return .white
        case .scheduled: return Brand.success
        case .run:       return palette.textPrimary
        }
    }

    // MARK: - CUSTOM REPORT BUILDER

    private var customBuilderCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CUSTOM REPORT BUILDER")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 18)
                .padding(.leading, 20)
            Text("Compose your own report")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 12).padding(.leading, 20)
            Text("Pick metrics · group by · date window · format")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 4).padding(.leading, 20)

            HStack(spacing: 6) {
                ForEach(metricChips) { chip in
                    builderChip(chip, activeSet: activeMetricChips) {
                        toggle(chip, in: &activeMetricChips)
                    }
                }
            }
            .padding(.leading, 20).padding(.top, 14)

            HStack(spacing: 6) {
                ForEach(groupByChips) { chip in
                    builderChip(chip, activeSet: activeGroupByChips) {
                        toggle(chip, in: &activeGroupByChips)
                    }
                }
                Spacer(minLength: 8)
                composeChip
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func builderChip(_ chip: BuilderChip, activeSet: Set<String>, action: @escaping () -> Void) -> some View {
        let active = activeSet.contains(chip.id)
        return Button(action: action) {
            ZStack {
                if active {
                    Capsule().fill(LinearGradient.primary)
                } else {
                    Capsule().fill(palette.bgCardSoft)
                    Capsule().stroke(palette.borderSoft, lineWidth: 1)
                }
                Text(chip.label)
                    .font(.system(size: 11, weight: active ? .bold : .semibold))
                    .foregroundStyle(active ? Color.white : palette.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: chip.width, height: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chip.label) chip\(active ? ", active" : "")")
        .accessibilityHint("Toggles inclusion in the composed report.")
    }

    private func toggle(_ chip: BuilderChip, in set: inout Set<String>) {
        let wasActive = set.contains(chip.id)
        if wasActive { set.remove(chip.id) } else { set.insert(chip.id) }
        NotificationCenter.default.post(
            name: .eusoShipperReportComposeChip, object: nil,
            userInfo: [
                "source": "207_ShipperReports",
                "chipId": chip.id,
                "wasActive": wasActive,
            ]
        )
    }

    private var composeChip: some View {
        Button {
            // Real in-app custom-builder compose — server rolls the
            // user's load corpus by the selected metric + group-by
            // and returns a CSV. Server enum is single-valued for
            // each axis; iOS picks the first chip from each set.
            // Telemetry post retained.
            NotificationCenter.default.post(
                name: .eusoShipperReportCompose, object: nil,
                userInfo: [
                    "source": "207_ShipperReports",
                    "shipperCompanyId": session.user?.companyId ?? "1",
                    "metrics": Array(activeMetricChips),
                    "groupBy": Array(activeGroupByChips),
                ]
            )
            // Map the iOS chip taxonomy to the server's enum.
            // Server accepts: metric ∈ {spend, loads, miles}, groupBy ∈
            // {lane, equipment, catalyst}. iOS chip ids `ontime` and
            // `co2` are upper-funnel views that don't have a backing
            // metric column yet, so they fall through to `loads`.
            let rawMetric = activeMetricChips.first ?? "spend"
            let metric: String = {
                switch rawMetric {
                case "spend":  return "spend"
                case "miles":  return "miles"
                case "ontime", "co2", "loads": return "loads"
                default:       return "spend"
                }
            }()
            let rawGroupBy = activeGroupByChips.first ?? "lane"
            let groupBy: String = {
                switch rawGroupBy {
                case "lane", "equipment", "catalyst": return rawGroupBy
                default: return "lane"
                }
            }()
            runExport {
                try await EusoTripAPI.shared.reports.composeCustom(
                    metric: metric, groupBy: groupBy
                )
            }
        } label: {
            ZStack {
                Capsule().fill(LinearGradient.primary)
                Text("Compose →")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 100, height: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compose custom report")
    }

    // MARK: - DASHBOARD section (EXTRA-OK — kept beneath the wireframe)

    @ViewBuilder
    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                sectionLabel("LIVE DASHBOARD · \(periodLabel)")
                Spacer()
                periodChips
            }
            spendingSection
            catalystSection
        }
    }

    private var periodLabel: String {
        switch selectedPeriod {
        case .month:   return "MONTH"
        case .quarter: return "QUARTER"
        case .year:    return "YEAR"
        }
    }

    private var periodChips: some View {
        HStack(spacing: 6) {
            periodChip("M", .month)
            periodChip("Q", .quarter)
            periodChip("Y", .year)
        }
    }

    private func periodChip(_ label: String, _ value: ShipperAPI.SpendingPeriod) -> some View {
        let isOn = (value == selectedPeriod)
        return Button {
            guard !isOn else { return }
            selectedPeriod = value
            spendStore.setPeriod(value)
            catalystStore.setPeriod(value)
            Task { await refreshAll() }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textPrimary))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isOn ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                .overlay(Capsule().strokeBorder(isOn ? AnyShapeStyle(.clear) : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var spendingSection: some View {
        switch spendStore.state {
        case .loading:
            loadingTile(message: "Pulling your spend totals…")
        case .loaded(let optV):
            if let v = optV { spendKPIs(v) } else { spendEmpty }
        case .empty:
            spendEmpty
        case .error(let err):
            errorBanner(message: readableError(err)) { Task { await refreshAll() } }
        }
    }

    private var spendEmpty: some View {
        EusoEmptyState(
            systemImage: "chart.line.downtrend.xyaxis",
            title: "No spend in window",
            subtitle: "Once you post and settle a load in this period, the totals appear here."
        )
    }

    private func spendKPIs(_ v: ShipperAPI.SpendingAnalytics) -> some View {
        VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                metricTile(label: "TOTAL SPEND", value: currency(v.totalSpend), icon: "dollarsign.circle")
                metricTile(label: "LOADS",       value: "\(v.loadCount)",       icon: "shippingbox")
            }
            HStack(spacing: Space.s2) {
                metricTile(label: "AVG / LOAD", value: v.loadCount > 0 ? currency(v.avgPerLoad) : "—", icon: "chart.bar")
                metricTile(label: "AVG / MILE", value: v.avgPerMile > 0 ? currency(v.avgPerMile) : "—", icon: "speedometer")
            }
        }
    }

    private func metricTile(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private var catalystSection: some View {
        switch catalystStore.state {
        case .loading:
            loadingTile(message: "Ranking your catalysts…")
        case .loaded(let rows):
            if rows.isEmpty { catalystEmpty } else { catalystList(rows) }
        case .empty:
            catalystEmpty
        case .error(let err):
            errorBanner(message: readableError(err)) { Task { await refreshAll() } }
        }
    }

    private var catalystEmpty: some View {
        EusoEmptyState(
            systemImage: "person.crop.circle.badge.questionmark",
            title: "No catalyst loads in window",
            subtitle: "Once a catalyst hauls one of your posted loads, you'll see them ranked here by spend and on-time rate."
        )
    }

    private func catalystList(_ rows: [ShipperAPI.CatalystPerformance]) -> some View {
        let ranked = rows.sorted { l, r in
            if l.totalSpend != r.totalSpend { return l.totalSpend > r.totalSpend }
            return l.onTimeRate > r.onTimeRate
        }
        return VStack(spacing: 6) {
            ForEach(Array(ranked.enumerated()), id: \.element.id) { idx, row in
                catalystRow(rank: idx + 1, row: row)
            }
        }
    }

    private func catalystRow(rank: Int, row: ShipperAPI.CatalystPerformance) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            ZStack {
                Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                Text("\(rank)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 28, height: 28)
            .background(palette.bgCard)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name.isEmpty ? "—" : row.name)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(row.delivered)/\(row.totalLoads) delivered")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Text("·").font(EType.caption).foregroundStyle(palette.textTertiary)
                    Text(row.totalLoads > 0 ? "\(row.onTimeRate)% on-time" : "— on-time")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            Text(row.totalSpend > 0 ? currency(row.totalSpend) : "—")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func loadingTile(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("LOADING")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func errorBanner(message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button(action: retry) {
                Text("Retry")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Helpers

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }
}

// MARK: - SVG glyph shapes (lifted verbatim from wireframe Code/ port)

private struct DocumentGlyph: View {
    let stroke: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 28, geo.size.height / 32)
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: 22 * s, y: 0))
                    p.addLine(to: CGPoint(x: 28 * s, y: 6 * s))
                    p.addLine(to: CGPoint(x: 28 * s, y: 32 * s))
                    p.addLine(to: CGPoint(x: 0, y: 32 * s))
                    p.closeSubpath()
                }
                .stroke(stroke, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                Path { p in
                    p.move(to: CGPoint(x: 6 * s, y: 14 * s))
                    p.addLine(to: CGPoint(x: 22 * s, y: 14 * s))
                    p.move(to: CGPoint(x: 6 * s, y: 20 * s))
                    p.addLine(to: CGPoint(x: 22 * s, y: 20 * s))
                    p.move(to: CGPoint(x: 6 * s, y: 26 * s))
                    p.addLine(to: CGPoint(x: 16 * s, y: 26 * s))
                }
                .stroke(stroke, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
    }
}

private struct SpreadsheetGlyph: View {
    let stroke: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 28, geo.size.height / 32)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2 * s)
                    .stroke(stroke, lineWidth: 1.6)
                    .frame(width: 28 * s, height: 32 * s)
                Path { p in
                    p.move(to: CGPoint(x: 4 * s, y: 10 * s))
                    p.addLine(to: CGPoint(x: 24 * s, y: 10 * s))
                    p.move(to: CGPoint(x: 4 * s, y: 16 * s))
                    p.addLine(to: CGPoint(x: 24 * s, y: 16 * s))
                    p.move(to: CGPoint(x: 4 * s, y: 22 * s))
                    p.addLine(to: CGPoint(x: 24 * s, y: 22 * s))
                }
                .stroke(stroke, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
    }
}

private struct HazmatDiamondGlyph: View {
    let badgeCount: Int
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Rectangle()
                    .stroke(Brand.hazmat,
                            style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    .frame(width: size * 0.62, height: size * 0.62)
                    .rotationEffect(.degrees(45))
                Text("\(badgeCount)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.hazmat)
            }
            .frame(width: size, height: size, alignment: .center)
        }
    }
}

private struct Co2MountainGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 28, geo.size.height / 24)
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 24 * s))
                    p.addLine(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: 28 * s, y: 0))
                    p.addLine(to: CGPoint(x: 28 * s, y: 24 * s))
                    p.closeSubpath()
                }
                .stroke(Brand.success,
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 24 * s))
                    p.addLine(to: CGPoint(x: 7 * s, y: 18 * s))
                    p.addLine(to: CGPoint(x: 14 * s, y: 22 * s))
                    p.addLine(to: CGPoint(x: 21 * s, y: 14 * s))
                    p.addLine(to: CGPoint(x: 28 * s, y: 18 * s))
                    p.addLine(to: CGPoint(x: 28 * s, y: 24 * s))
                }
                .stroke(Brand.success,
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let eusoShipperReportQuickExport  = Notification.Name("eusoShipperReportQuickExport")
    static let eusoShipperReportRow          = Notification.Name("eusoShipperReportRow")
    static let eusoShipperReportComposeChip  = Notification.Name("eusoShipperReportComposeChip")
    static let eusoShipperReportCompose      = Notification.Name("eusoShipperReportCompose")
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct ShipperReportsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperReports()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_207(),
                trailing: shipperNavTrailing_207(),
                orbState: .idle
            )
        }
    }
}

// Out of scope per parity mandate §1 — reports live under Me.
private func shipperNavLeading_207() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",    isCurrent: false)]
}

private func shipperNavTrailing_207() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews

#Preview("207 · Shipper · Reports · Night") {
    ShipperReportsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("207 · Shipper · Reports · Afternoon") {
    ShipperReportsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

// MARK: - System share sheet wrapper

/// Bridge to `UIActivityViewController` so the reports screen can ship
/// the rendered CSV files via Save to Files / AirDrop / Mail / Messages
/// without ever leaving the app. Each tap on a quick-export tile or
/// saved-report row writes a temp file and pushes its URL into here.
private struct ReportShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
