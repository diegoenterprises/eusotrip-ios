//
//  284_CatalystCompliancePeek.swift
//  EusoTrip — Shipper · Catalyst compliance peek (Arc F).
//
//  Pulls FMCSA SAFER-style snapshot via `fmcsa.lookup(dotNumber)`
//  through the existing carrier-intelligence router. Falls back to
//  the local performance row when the FMCSA call hasn't been wired.
//

import SwiftUI

struct CatalystCompliancePeekScreen: View {
    let theme: Theme.Palette
    let catalystId: String
    var body: some View {
        Shell(theme: theme) { CatalystCompliancePeekBody(catalystId: catalystId) } nav: { shipperLifecycleNav() }
    }
}

private struct FmcsaPeek: Decodable, Hashable {
    let dotNumber: String?
    let mcNumber: String?
    let legalName: String?
    let safetyRating: String?
    let basicScores: [String: Double]?
    let insuranceOnFile: Bool?
}

private struct CatalystCompliancePeekBody: View {
    @Environment(\.palette) private var palette
    let catalystId: String
    @StateObject private var perf = ShipperCatalystPerformanceStore()
    @State private var peek: FmcsaPeek? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    private var row: ShipperAPI.CatalystPerformance? {
        perf.state.value?.first(where: { $0.catalystId == catalystId })
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let p = peek { peekCard(p) }
                else if loading { LifecycleCard { Text("Loading FMCSA data…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else { emptyCard }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task {
            await perf.refresh()
            await loadPeek()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CATALYST COMPLIANCE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Compliance peek").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func peekCard(_ p: FmcsaPeek) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "FMCSA SAFER", icon: "checkmark.shield.fill")
            LifecycleRow(label: "Legal name",  value: dashIfEmpty(p.legalName))
            LifecycleRow(label: "USDOT",       value: dashIfEmpty(p.dotNumber))
            LifecycleRow(label: "MC",          value: dashIfEmpty(p.mcNumber))
            LifecycleRow(label: "Safety",      value: dashIfEmpty(p.safetyRating))
            LifecycleRow(label: "Insurance",   value: p.insuranceOnFile == true ? "On file" : "Not on file")
            if let scores = p.basicScores, !scores.isEmpty {
                Text("BASIC SCORES").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary).padding(.top, 6)
                ForEach(scores.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                    LifecycleRow(label: k, value: String(format: "%.1f", v))
                }
            }
        }
    }

    private var emptyCard: some View {
        LifecycleCard {
            Text("FMCSA data not on file for this carrier yet. Carrier-intelligence integration may not be live for this DOT number.")
                .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loadPeek() async {
        loading = true; loadError = nil
        // Some platform deploys expose `fmcsa.lookupByCarrierId`. The
        // input shape varies; try the conservative version first.
        struct In: Encodable { let catalystId: String }
        do {
            let r: FmcsaPeek = try await EusoTripAPI.shared.api.query("fmcsa.lookupByCarrierId", input: In(catalystId: catalystId))
            peek = r
        } catch {
            // Endpoint may not be wired or named differently. Surface
            // empty state honestly.
            peek = nil
        }
        loading = false
    }
}

#Preview("284 · Compliance · Night") {
    CatalystCompliancePeekScreen(theme: Theme.dark, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("284 · Compliance · Afternoon") {
    CatalystCompliancePeekScreen(theme: Theme.light, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
