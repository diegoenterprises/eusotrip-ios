//
//  299_Reports.swift
//  EusoTrip — Shipper · Reports (Arc G).
//
//  Real in-app exports across the full grid:
//    • QUICK EXPORTS — 4 tiles (Spend by lane / Catalyst payable /
//      Hazmat audit / CO₂ statement) call `reports.export*` and
//      present `UIActivityViewController` so the file lands in
//      Files / AirDrop / Mail / Messages.
//    • SAVED REPORTS — `reports.list` populated cells, each Run
//      pill calls `reports.runSavedReport` (verb + title) and
//      shares the rendered CSV.
//    • COMPOSE — single CTA jumps to 207 ShipperReports' custom
//      builder, no more "builder lives on web" stub.
//
//  Replaces the prior `reports.runById` (procedure that did not
//  exist) and the on-web stub copy. Founder no-stubs doctrine
//  2026-05-05: every visible button performs a real action.
//

import SwiftUI

struct ReportsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ReportsBody() } nav: { shipperLifecycleNav() }
    }
}

private struct SavedReport: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String?
    let lastRunAt: String?
    let savedAt: String?
}

/// Quick-export tile descriptor — maps a human label to the matching
/// `ReportsAPI` method so the row can be tap-driven without a
/// switch-statement at every call site.
private enum QuickExportTile: String, CaseIterable, Identifiable {
    case spendByLane     = "Spend by lane — CSV"
    case catalystPayable = "Catalyst payable — CSV"
    case hazmatAudit     = "Hazmat audit — CSV"
    case co2             = "CO₂ statement (GLEC v3.0) — CSV"

    var id: String { rawValue }

    func run() async throws -> ReportsAPI.ExportFile {
        switch self {
        case .spendByLane:     return try await EusoTripAPI.shared.reports.exportSpendByLane()
        case .catalystPayable: return try await EusoTripAPI.shared.reports.exportCatalystPayable()
        case .hazmatAudit:     return try await EusoTripAPI.shared.reports.exportHazmatAudit()
        case .co2:             return try await EusoTripAPI.shared.reports.exportCO2Statement()
        }
    }
}

private struct ReportsBody: View {
    @Environment(\.palette) private var palette
    @State private var reports: [SavedReport] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var rerunning: String? = nil
    @State private var pendingShareItems: [URL]? = nil
    @State private var exportError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                quickExports
                content
                composeCTA
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .sheet(isPresented: Binding(
            get: { pendingShareItems != nil },
            set: { if !$0 { pendingShareItems = nil } }
        )) {
            if let urls = pendingShareItems {
                ReportsArcGShareSheet(items: urls)
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
                    .padding(.top, 56)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 3_500_000_000)
                            await MainActor.run { withAnimation { exportError = nil } }
                        }
                    }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · REPORTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Reports").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Quick-export and re-run saved reports. Every tap returns a real CSV.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var quickExports: some View {
        LifecycleCard {
            LifecycleSection(label: "QUICK EXPORTS", icon: "square.and.arrow.up")
            ForEach(QuickExportTile.allCases) { tile in
                Button {
                    runExport { try await tile.run() }
                } label: {
                    HStack {
                        Image(systemName: "doc").foregroundStyle(LinearGradient.diagonal)
                        Text(tile.rawValue).font(EType.body).foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                        Text("Run").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(LinearGradient.diagonal).clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard { Text("Loading reports…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
        } else if reports.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "SAVED REPORTS", icon: "tray")
                Text("No saved reports yet. The four canon cadences (Q1 spend rollup, catalyst scorecard, detention & accessorial, hazmat exposure) live on 207.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            LifecycleCard {
                LifecycleSection(label: "SAVED REPORTS", icon: "tray.full")
                ForEach(reports) { r in
                    Button {
                        Task { await rerun(r) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                                Text(dashIfEmpty(r.kind?.uppercased())).font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                            if rerunning == r.id {
                                ProgressView().tint(.white).frame(width: 60, height: 30).background(LinearGradient.diagonal).clipShape(Capsule())
                            } else {
                                Text("Run").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(LinearGradient.diagonal).clipShape(Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(rerunning != nil)
                }
            }
        }
    }

    /// CTA into 207 ShipperReports — that screen owns the metric +
    /// group-by chip selector and the Compose mutation. Replaces the
    /// prior "builder lives on web" stub.
    private var composeCTA: some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap, object: nil,
                userInfo: ["screenId": "207"]
            )
        } label: {
            LifecycleCard {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open custom report builder")
                            .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Text("Pick metric + group-by, then export. (Opens 207.)")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [SavedReport] = try await EusoTripAPI.shared.queryNoInput("reports.list")
            reports = r
        } catch {
            reports = []
        }
        loading = false
    }

    /// Run a saved report by mapping its name → the same verb/title
    /// taxonomy 207 uses. The server's `runSavedReport` keys off the
    /// title so the rollup matches whichever cadence the user saved.
    private func rerun(_ r: SavedReport) async {
        guard rerunning == nil else { return }
        rerunning = r.id
        defer { rerunning = nil }
        do {
            let file = try await EusoTripAPI.shared.reports.runSavedReport(
                verb: "run", title: r.name
            )
            await MainActor.run { presentExport(file) }
        } catch {
            let msg = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            await MainActor.run { exportError = "Run failed: \(msg)" }
        }
    }

    /// Quick-export tile pipeline — same shape as 207's `runExport`
    /// helper. Spinner state lives on the tile itself when needed; the
    /// CSV body is written to a temp file and the share sheet pops.
    private func runExport(_ work: @escaping () async throws -> ReportsAPI.ExportFile) {
        Task {
            do {
                let file = try await work()
                await MainActor.run { presentExport(file) }
            } catch {
                let msg = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { exportError = "Export failed: \(msg)" }
            }
        }
    }

    @MainActor
    private func presentExport(_ file: ReportsAPI.ExportFile) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("eusotrip-reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(file.filename)
        do {
            try file.body.data(using: .utf8)?.write(to: url, options: .atomic)
            pendingShareItems = [url]
        } catch {
            exportError = "Couldn't prepare \(file.filename): \(error.localizedDescription)"
        }
    }
}

/// Local share-sheet wrapper — same shape as 207 ShipperReports'
/// `ReportShareSheet`. Kept private to this file to avoid namespace
/// collision; can be promoted to a shared component once a third
/// surface needs it.
private struct ReportsArcGShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview("299 · Reports · Night") {
    ReportsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("299 · Reports · Afternoon") {
    ReportsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
