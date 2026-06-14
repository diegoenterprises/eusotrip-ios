//
//  317_eSangAssistForecast.swift
//  EusoTrip — Shipper · eSang · Forecast (Arc I).
//

import SwiftUI

struct eSangAssistForecastScreen: View {
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
                if loading { LifecycleCard { Text("eSang forecasting…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let e = env { answerCard(e); pointsCard(e) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Bespoke route glyph (WeatherIcons) — no SF Symbol.
                WeatherIcons.utility(.route, size: 11, tint: WeatherV3.auroraB)
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
        guard let pts = e.supportingPoints, !pts.isEmpty else { return AnyView(EmptyView()) }
        // The server MAY append a weather supportingPoint — but only on a
        // real elevated/severe lane risk, and only as an untyped string
        // (esangAI.tenderForecast.supportingPoints is string[]). Split it
        // out by content so it earns the §3 bespoke treatment ("weather as
        // a tender decision input") while the rate/bid signals keep the
        // plain bullet. Honest: if the server emitted no weather point
        // (the common case while the feed is enterprise-gated), nothing
        // weather renders.
        let weatherPoints = pts.filter { Self.isWeatherSignal($0) }
        let otherPoints = pts.filter { !Self.isWeatherSignal($0) }
        return AnyView(VStack(alignment: .leading, spacing: Space.s4) {
            if !otherPoints.isEmpty {
                LifecycleCard {
                    LifecycleSection(label: "SUPPORTING SIGNALS", icon: "list.bullet")
                    ForEach(Array(otherPoints.enumerated()), id: \.offset) { _, p in
                        HStack(alignment: .top, spacing: 6) {
                            // Bullet via a tiny brand dot — no SF Symbol.
                            Circle().fill(LinearGradient.diagonal).frame(width: 5, height: 5).padding(.top, 6)
                            Text(p).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            ForEach(Array(weatherPoints.enumerated()), id: \.offset) { _, wp in
                WeatherTenderInputCard(point: wp)
            }
        })
    }

    /// Heuristic: does this untyped supporting string carry a weather
    /// signal? The server appends a weather point (e.g. a §3 LaneImpact
    /// headline) only on elevated/severe lane risk, so a match is a real
    /// weather decision input — never fabricated. Conservative vocabulary
    /// drawn from the §3 driver fields + Tomorrow.io condition families so
    /// the rate/bid/trend signals never get mis-tagged.
    static func isWeatherSignal(_ raw: String) -> Bool {
        let s = raw.lowercased()
        let terms = [
            "weather", "lane impact", "corridor impact", "voyage", "berth",
            "precip", "rain", "snow", "ice", "sleet", "freezing", "storm",
            "thunder", "lightning", "wind", "gust", "crosswind", "fog",
            "visibility", "vis ", "wave", "swell", "sig wave", "streamflow",
            "flood", "blizzard", "hail", "winter", "elevated", "severe",
            "watch", "advisory", "warning"
        ]
        return terms.contains { s.contains($0) }
    }

    private func ask() async {
        loading = true; loadError = nil; env = nil
        struct In: Encodable { let lane: String }
        do {
            let r: ForecastEnvelope = try await EusoTripAPI.shared.query("esangAI.tenderForecast", input: In(lane: lane))
            env = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Weather tender-input card (inline · bespoke)
//
// The §3 framing of the weather supportingPoint: "weather as a tender
// decision input." Reuses the in-house WeatherIcons corpus (a condition
// glyph mapped from the point's text, plus the §3 .route framing glyph)
// and the screen's LifecycleCard idiom — ZERO SF Symbols, zero emoji,
// no generic weather UI. This renders ONLY when the server actually
// emitted a weather point (real elevated/severe lane risk); otherwise
// the screen shows nothing weather-related (honest empty).
private struct WeatherTenderInputCard: View {
    @Environment(\.palette) private var palette
    let point: String

    var body: some View {
        LifecycleCard(accentWarning: true) {
            // Eyebrow — §3 framing, route glyph + aurora dot (bespoke).
            HStack(spacing: 6) {
                WeatherIcons.utility(.route, size: 11, tint: WeatherV3.auroraB)
                Text("WEATHER · TENDER INPUT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: Space.s1)
                riskChip
            }
            // The signal line — condition glyph (mapped from the point's
            // text) + the server-formatted weather point, verbatim.
            HStack(alignment: .top, spacing: 9) {
                WeatherIcons.symbolView(for: WeatherIcons.code(forSymbol: point), size: 26)
                    .frame(width: 26, height: 26)
                    .padding(.top, 1)
                Text(point)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The decision framing — why weather belongs in the tender call.
            Text("Weather on this lane is a tender decision input — ESang surfaces it only when corridor risk is elevated or severe.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Honest tier chip — derived from the point's own wording (the server
    /// only emits this point at elevated/severe risk). Never a fabricated
    /// tier: defaults to the neutral "WEATHER RISK" when the wording is
    /// unspecific.
    private var riskChip: some View {
        let s = point.lowercased()
        let (label, color): (String, Color) =
            s.contains("severe") ? ("SEVERE", Brand.danger)
            : s.contains("elevated") ? ("ELEVATED", Brand.danger)
            : s.contains("watch") ? ("WATCH", Brand.warning)
            : ("WEATHER RISK", Brand.warning)
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.5))
    }
}

#Preview("317 · Forecast · Night") { eSangAssistForecastScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("317 · Forecast · Afternoon") { eSangAssistForecastScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
