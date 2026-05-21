//
//  307_CatalystReports.swift
//  EusoTrip — Catalyst · Reports (brick 307).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/307 Catalyst Reports.svg`.
//  Owner-op reporting hub — IFTA, DVIR, CSA, Schedule C exports +
//  saved reports + scheduled rollups.
//
//  Wire bindings (all real, no stubs):
//    reports.getSavedReports   — saved + scheduled list
//    reports.getReportStats    — header counts (run / scheduled)
//    reports.runReport         — fire an export
//

import SwiftUI

private struct SavedReport: Decodable, Hashable, Identifiable {
    let id: String
    let title: String?
    let summary: String?
    let lastRunAgo: String?
    let schedule: String?
    let format: String?
}

private struct ReportStats: Decodable, Hashable {
    let runCount: Int?
    let scheduledCount: Int?
}

struct CatalystReportsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ReportsBody() } nav: {
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

private struct QuickExport: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let format: String
    let symbol: String
}

private struct ReportsBody: View {
    @Environment(\.palette) private var palette

    @State private var saved: [SavedReport] = []
    @State private var stats: ReportStats?
    @State private var loading: Bool = true
    @State private var runningId: String?
    @State private var ack: String?

    private let quickExports: [QuickExport] = [
        .init(id: "driverPay",  title: "Driver pay",       subtitle: "Owner-op · YTD",          format: "XLSX", symbol: "person.fill"),
        .init(id: "iftaQ",      title: "IFTA quarterly",   subtitle: "Multi-state · miles",     format: "CSV",  symbol: "doc.text.fill"),
        .init(id: "hazmat",     title: "Hazmat exposure",  subtitle: "UN-coded · lane-detail",  format: "PDF",  symbol: "flame.fill"),
        .init(id: "csa",        title: "CSA scorecard",    subtitle: "7 BASICS · violations",   format: "PDF",  symbol: "checkmark.shield.fill"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                quickExportGrid
                savedSection
                if let m = ack {
                    LifecycleCard(accentGradient: true) { Text(m).font(EType.caption).foregroundStyle(palette.textPrimary) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · REPORTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Reports").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("IFTA · DVIR · CSA · Schedule C").font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(stats?.runCount ?? saved.count) RUN · \(stats?.scheduledCount ?? 0) SCHEDULED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var quickExportGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("QUICK EXPORTS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(quickExports) { q in quickExportCard(q) }
            }
        }
    }

    private func quickExportCard(_ q: QuickExport) -> some View {
        Button {
            Task { await runQuickExport(q) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: q.symbol)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(q.title).font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                Text(q.subtitle).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                HStack(spacing: 6) {
                    if runningId == q.id { ProgressView().controlSize(.mini) }
                    Text(runningId == q.id ? "Running…" : "Export · \(q.format)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.4)))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SAVED REPORTS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            if loading && saved.isEmpty {
                LifecycleCard { Text("Loading reports…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if saved.isEmpty {
                EusoEmptyState(systemImage: "tray", title: "No saved reports", subtitle: "Quick-exports become saved reports automatically after first run.")
            } else {
                ForEach(saved) { r in savedRow(r) }
            }
        }
    }

    private func savedRow(_ r: SavedReport) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(r.title ?? "Report \(r.id)").font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button {
                        Task { await runSaved(r) }
                    } label: {
                        HStack(spacing: 4) {
                            if runningId == r.id { ProgressView().controlSize(.mini) }
                            Text(runningId == r.id ? "Running…" : "Run again")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(runningId != nil)
                }
                if let s = r.summary { Text(s).font(.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true) }
                if let sch = r.schedule {
                    Text("Scheduled · \(sch)").font(.caption2).foregroundStyle(palette.textTertiary)
                } else if let ago = r.lastRunAgo {
                    Text("Last run \(ago)").font(.caption2).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func load() async {
        loading = true
        async let s: Void = loadSaved()
        async let st: Void = loadStats()
        _ = await (s, st)
        loading = false
    }
    private func loadSaved() async {
        do { saved = try await EusoTripAPI.shared.queryNoInput("reports.getSavedReports") } catch { /* */ }
    }
    private func loadStats() async {
        do { stats = try await EusoTripAPI.shared.queryNoInput("reports.getReportStats") } catch { /* */ }
    }

    private func runQuickExport(_ q: QuickExport) async {
        runningId = q.id; defer { runningId = nil }
        struct In: Encodable { let reportId: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("reports.runReport", input: In(reportId: q.id))
            ack = "\(q.title) export queued (\(q.format))"
        } catch {
            ack = "Failed to run \(q.title): \(error)"
        }
    }

    private func runSaved(_ r: SavedReport) async {
        runningId = r.id; defer { runningId = nil }
        struct In: Encodable { let reportId: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("reports.runReport", input: In(reportId: r.id))
            ack = "\(r.title ?? "Report") queued"
            await loadSaved()
        } catch {
            ack = "Failed: \(error)"
        }
    }
}

#Preview("307 Reports · Dark")  { CatalystReportsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("307 Reports · Light") { CatalystReportsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
