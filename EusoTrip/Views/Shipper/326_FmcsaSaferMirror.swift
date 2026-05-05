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

private struct AISafetyAnalysis: Decodable, Hashable {
    let available: Bool
    let summary: String?
    let riskFlags: [String]?
    let recommendations: [String]?
}

private struct FmcsaBody: View {
    @Environment(\.palette) private var palette
    @State private var data: FmcsaSelf? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var ai: AISafetyAnalysis? = nil
    @State private var aiInflight: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Pulling FMCSA data…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let d = data {
                    authorityCard(d)
                    aiAnalysisCard(d)
                    basicCard(d)
                    inspectionCard(d)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    /// Gemini-driven safety analysis card. Calls
    /// `fmcsaData.getAiSafetyAnalysis` with the carrier DOT and
    /// surfaces the model's narrative summary + risk flags +
    /// recommendations. Loads lazily after the snapshot lands so
    /// the page renders fast and the AI block fills in.
    @ViewBuilder
    private func aiAnalysisCard(_ d: FmcsaSelf) -> some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESANG SAFETY ANALYSIS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if aiInflight {
                    ProgressView().progressViewStyle(.circular).controlSize(.small)
                }
            }
            if let s = ai?.summary, !s.isEmpty {
                Text(s)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let flags = ai?.riskFlags, !flags.isEmpty {
                    Divider().overlay(palette.borderFaint).padding(.vertical, 4)
                    Text("Risk flags").font(EType.micro).tracking(0.6).foregroundStyle(Brand.warning)
                    ForEach(Array(flags.enumerated()), id: \.offset) { _, f in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Brand.warning)
                            Text(f).font(EType.caption).foregroundStyle(palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let recs = ai?.recommendations, !recs.isEmpty {
                    Divider().overlay(palette.borderFaint).padding(.vertical, 4)
                    Text("Recommendations").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
                    ForEach(Array(recs.enumerated()), id: \.offset) { _, r in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(palette.textSecondary)
                            Text(r).font(EType.caption).foregroundStyle(palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else if !aiInflight {
                Text("Tap to run an AI safety analysis on this carrier")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .onTapGesture {
            if ai == nil && !aiInflight {
                Task { await loadAI(d) }
            }
        }
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
            let r: FmcsaSelf = try await EusoTripAPI.shared.queryNoInput("fmcsa.lookupSelf")
            data = r
            // Auto-fire AI analysis when DOT lands; the proc returns
            // `available: false` cleanly if Gemini isn't configured,
            // so we don't need to gate the call.
            if let dot = r.dotNumber, !dot.isEmpty {
                Task { await loadAI(r) }
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func loadAI(_ d: FmcsaSelf) async {
        guard !aiInflight, let dot = d.dotNumber, !dot.isEmpty else { return }
        aiInflight = true
        defer { Task { @MainActor in aiInflight = false } }
        struct In: Encodable { let dotNumber: String }
        do {
            let r: AISafetyAnalysis = try await EusoTripAPI.shared.query(
                "fmcsaData.getAiSafetyAnalysis",
                input: In(dotNumber: dot)
            )
            await MainActor.run { ai = r }
        } catch { /* silent — card stays prompting tap */ }
    }
}

#Preview("326 · FMCSA · Night") { FmcsaSaferMirrorScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("326 · FMCSA · Afternoon") { FmcsaSaferMirrorScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
