//
//  299_Reports.swift
//  EusoTrip — Shipper · Reports (Arc G).
//  Quick re-runs over `reports.list` + `reports.runById`.
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

private struct ReportsBody: View {
    @Environment(\.palette) private var palette
    @State private var reports: [SavedReport] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var rerunning: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                quickExports
                content
                composeOnWebCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · REPORTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Reports").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Saved reports run with one tap. Custom report builder lives on web.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var quickExports: some View {
        LifecycleCard {
            LifecycleSection(label: "QUICK EXPORTS", icon: "square.and.arrow.up")
            ForEach(["Loads (last 30d) — CSV", "Spend by lane (MTD) — CSV", "Carrier scorecards — CSV"], id: \.self) { label in
                HStack {
                    Image(systemName: "doc").foregroundStyle(LinearGradient.diagonal)
                    Text(label).font(EType.body).foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Text("Run").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }
                .padding(.vertical, 4)
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
                Text("No saved reports yet. Build one on the web shipper page; it'll show up here for one-tap re-runs.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            LifecycleCard {
                LifecycleSection(label: "SAVED REPORTS", icon: "tray.full")
                ForEach(reports) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text(dashIfEmpty(r.kind?.uppercased())).font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Button { Task { await rerun(r.id) } } label: {
                            if rerunning == r.id {
                                ProgressView().tint(.white).frame(width: 60, height: 30).background(LinearGradient.diagonal).clipShape(Capsule())
                            } else {
                                Text("Run").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(LinearGradient.diagonal).clipShape(Capsule())
                            }
                        }.buttonStyle(.plain).disabled(rerunning != nil)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var composeOnWebCard: some View {
        LifecycleCard {
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer").foregroundStyle(LinearGradient.diagonal)
                Text("Custom report builder is on web. iOS handles re-runs and exports.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [SavedReport] = try await EusoTripAPI.shared.api.queryNoInput("reports.list")
            reports = r
        } catch {
            // No reports endpoint on iOS yet — surface clean state.
            reports = []
        }
        loading = false
    }

    private func rerun(_ id: String) async {
        rerunning = id
        struct In: Encodable { let id: String }
        struct Out: Decodable { let url: String? }
        do {
            let r: Out = try await EusoTripAPI.shared.api.mutation("reports.runById", input: In(id: id))
            if let url = r.url, let u = URL(string: url) { UIApplication.shared.open(u) }
        } catch { /* surface inline if needed */ }
        rerunning = nil
    }
}

#Preview("299 · Reports · Night") {
    ReportsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("299 · Reports · Afternoon") {
    ReportsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
