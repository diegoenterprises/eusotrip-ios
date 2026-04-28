//
//  326_FmcsaSaferMirror.swift
//  EusoTrip — Shipper · FMCSA SAFER mirror (Arc J).
//

import SwiftUI

struct FmcsaSaferMirrorScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { FmcsaBody() } nav: { shipperLifecycleNav() }
    }
}

private struct FmcsaSelf: Decodable, Hashable {
    let dotNumber: String?
    let mcNumber: String?
    let legalName: String?
    let safetyRating: String?
    let oosViolations: Int?
    let basicScores: [String: Double]?
    let lastInspection: String?
}

private struct FmcsaBody: View {
    @Environment(\.palette) private var palette
    @State private var data: FmcsaSelf? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Pulling FMCSA data…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let d = data { authorityCard(d); basicCard(d); inspectionCard(d) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · FMCSA SAFER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("FMCSA SAFER mirror").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func authorityCard(_ d: FmcsaSelf) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "AUTHORITY", icon: "doc.text")
            LifecycleRow(label: "Legal name",  value: dashIfEmpty(d.legalName))
            LifecycleRow(label: "USDOT",       value: dashIfEmpty(d.dotNumber))
            LifecycleRow(label: "MC",          value: dashIfEmpty(d.mcNumber))
            LifecycleRow(label: "Safety",      value: dashIfEmpty(d.safetyRating))
            LifecycleRow(label: "OOS violations", value: d.oosViolations.map { "\($0)" } ?? "—")
        }
    }

    @ViewBuilder
    private func basicCard(_ d: FmcsaSelf) -> some View {
        if let scores = d.basicScores, !scores.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "BASIC SCORES", icon: "chart.bar")
                ForEach(scores.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                    LifecycleRow(label: k, value: String(format: "%.1f", v))
                }
            }
        }
    }

    private func inspectionCard(_ d: FmcsaSelf) -> some View {
        LifecycleCard {
            LifecycleSection(label: "INSPECTIONS", icon: "calendar")
            LifecycleRow(label: "Last inspection", value: humanISO(d.lastInspection, format: "MMM d, yyyy"))
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: FmcsaSelf = try await EusoTripAPI.shared.api.queryNoInput("fmcsa.lookupSelf")
            data = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("326 · FMCSA · Night") { FmcsaSaferMirrorScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("326 · FMCSA · Afternoon") { FmcsaSaferMirrorScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
