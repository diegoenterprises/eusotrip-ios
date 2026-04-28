//
//  317_EsangAssistForecast.swift
//  EusoTrip — Shipper · ESang · Forecast (Arc I).
//

import SwiftUI

struct EsangAssistForecastScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ForecastBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ForecastEnvelope: Decodable, Hashable {
    let answer: String
    let recommendation: String?  // "tender_now" | "wait" | "split"
    let confidencePct: Int?
    let supportingPoints: [String]?
}

private struct ForecastBody: View {
    @Environment(\.palette) private var palette
    @State private var lane: String = ""
    @State private var env: ForecastEnvelope? = nil
    @State private var loading = false
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                inputCard
                if loading { LifecycleCard { Text("ESang forecasting…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let e = env { answerCard(e); pointsCard(e) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ESANG · FORECAST").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Should I tender now?").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var inputCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LANE", icon: "map")
            TextField("e.g. 'Houston to Dallas'", text: $lane)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onSubmit { Task { await ask() } }
            Button { Task { await ask() } } label: {
                Text("Ask").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(lane.isEmpty)
        }
    }

    private func answerCard(_ e: ForecastEnvelope) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "RECOMMENDATION", icon: "sparkles")
            Text(e.answer).font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            if let c = e.confidencePct {
                LifecycleRow(label: "Confidence", value: "\(c)%")
            }
            if let r = e.recommendation {
                LifecycleRow(label: "Action", value: r.uppercased())
            }
        }
    }

    private func pointsCard(_ e: ForecastEnvelope) -> some View {
        if let pts = e.supportingPoints, !pts.isEmpty {
            return AnyView(LifecycleCard {
                LifecycleSection(label: "SUPPORTING SIGNALS", icon: "list.bullet")
                ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(LinearGradient.diagonal).padding(.top, 6)
                        Text(p).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            })
        }
        return AnyView(EmptyView())
    }

    private func ask() async {
        loading = true; loadError = nil; env = nil
        struct In: Encodable { let lane: String }
        do {
            let r: ForecastEnvelope = try await EusoTripAPI.shared.api.query("esangAI.tenderForecast", input: In(lane: lane))
            env = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("317 · Forecast · Night") { EsangAssistForecastScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("317 · Forecast · Afternoon") { EsangAssistForecastScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
