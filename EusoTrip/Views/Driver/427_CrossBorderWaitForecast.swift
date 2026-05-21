//
//  427_CrossBorderShipping.swift
//  Cross-border crossing recommendation — IO 2026 P0-11.
//
//  Driver approaches the US-MX or US-CA border. This view pulls
//  the live CBP wait times + the cross-border ports-of-entry
//  directory, ranks crossings by (drive time + current wait +
//  FAST lane bias), and surfaces the recommendation card the
//  founder spec calls for:
//
//    "Heavy queue at WB Convent St; Colombia Solidarity ETA -45 min"
//
//  The driver taps an alternate to accept; the existing HERE
//  re-routing pipeline (per the driver lifecycle store) fires
//  with the new destination waypoint. Voice acceptance lands as
//  part of P0-1's ESang dispatcher — that side is already wired.
//
//  Drop into: EusoTrip/Views/Driver/427_CrossBorderShipping.swift
//

import SwiftUI
import CoreLocation

public struct CrossBorderShippingView: View {
    let fromLat: Double
    let fromLng: Double
    let border: String        // "US-CA" | "US-MX" | "ALL"
    let fastEligible: Bool
    let hazmatRequired: Bool
    let currentPortCode: String?
    let onAcceptAlternate: ((CrossingRecommendation) -> Void)?

    @State private var recommendations: [CrossingRecommendation] = []
    @State private var baseline: BaselineCrossing? = nil
    @State private var live: Bool = false
    @State private var cacheAgeSeconds: Int = 0
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    /// Tier 3 #11 (2026-05-21) — present the USMCA filing assistant
    /// sheet from the border-crossing screen. The driver gets the
    /// next filing step out loud via ESangTTSPlayer.
    @State private var showUSMCA: Bool = false

    public init(
        fromLat: Double,
        fromLng: Double,
        border: String = "US-MX",
        fastEligible: Bool = false,
        hazmatRequired: Bool = false,
        currentPortCode: String? = nil,
        onAcceptAlternate: ((CrossingRecommendation) -> Void)? = nil
    ) {
        self.fromLat = fromLat
        self.fromLng = fromLng
        self.border = border
        self.fastEligible = fastEligible
        self.hazmatRequired = hazmatRequired
        self.currentPortCode = currentPortCode
        self.onAcceptAlternate = onAcceptAlternate
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Reading CBP wait times…").foregroundStyle(.secondary)
                    }
                }
                if let err = errorMessage {
                    Text(err).foregroundStyle(.red).font(.callout)
                }
                if let primary = recommendations.first {
                    primaryCrossingCard(primary)
                }
                if recommendations.count > 1 {
                    alternatesList
                }
                usmcaCTA
                sourceLine
            }
            .padding(16)
        }
        .navigationTitle("Border Crossing")
        .sheet(isPresented: $showUSMCA) {
            USMCAFilingAssistantSheet(loadId: nil)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "globe.americas.fill")
                    .foregroundStyle(LinearGradient(
                        colors: [.cyan, .green],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text("ESANG · BORDER WAIT FORECAST")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            Text("Live CBP wait + drive time + FAST lane.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func primaryCrossingCard(_ c: CrossingRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: c.severitySymbol)
                    .foregroundStyle(c.severityColor)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name)
                        .font(.headline)
                    Text("\(c.border) · \(c.state)\(c.province.map { " ↔ \($0)" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                stat(label: "Drive", value: "\(c.driveMinutes) min")
                stat(label: "CBP wait", value: "\(c.effectiveWaitMinutes) min")
                stat(label: "Total", value: "\(c.totalMinutes) min", highlight: true)
            }
            if c.fastLaneAvailable && fastEligible {
                Label("FAST lane available", systemImage: "bolt.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.08)))
    }

    @ViewBuilder
    private func stat(label: String, value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(highlight ? Color.accentColor : .primary)
        }
    }

    private var alternatesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alternates")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(recommendations.dropFirst()) { alt in
                alternateRow(alt)
            }
        }
    }

    @ViewBuilder
    private func alternateRow(_ c: CrossingRecommendation) -> some View {
        Button {
            onAcceptAlternate?(c)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: c.severitySymbol)
                    .foregroundStyle(c.severityColor)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text("\(c.driveMinutes) min drive · \(c.effectiveWaitMinutes) min wait")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if c.fastLaneAvailable && fastEligible {
                            Label("FAST", systemImage: "bolt.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.green)
                                .font(.caption2)
                        }
                    }
                }
                Spacer(minLength: 0)
                deltaPill(c.deltaMinutes)
            }
            .padding(10)
            .background(.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func deltaPill(_ delta: Int) -> some View {
        let prefix = delta > 0 ? "+" : ""
        let color: Color = delta < 0 ? .green : (delta == 0 ? .secondary : .red)
        Text("\(prefix)\(delta) min")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var usmcaCTA: some View {
        Button {
            showUSMCA = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("USMCA Filing Help")
                        .font(.callout.weight(.semibold))
                    Text("ESANG checks your cert + tells you the next filing step out loud.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private var sourceLine: some View {
        Text(live
             ? "Live CBP Border Wait Times API · refreshed \(cacheAgeSeconds)s ago"
             : "CBP API unavailable — directory average wait shown")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        struct In: Encodable {
            let fromLat: Double
            let fromLng: Double
            let border: String
            let fastEligible: Bool
            let hazmatRequired: Bool
            let currentPortCode: String?
            let limit: Int
        }
        let payload = In(
            fromLat: fromLat, fromLng: fromLng,
            border: border,
            fastEligible: fastEligible,
            hazmatRequired: hazmatRequired,
            currentPortCode: currentPortCode,
            limit: 4
        )
        struct Out: Decodable {
            let recommendations: [CrossingRecommendation]
            let baseline: BaselineCrossing?
            let live: Bool
            let cacheAgeSeconds: Int
            let sampledAt: String
        }
        do {
            let result: Out = try await EusoTripAPI.shared.query(
                "crossBorder.recommendCrossings",
                input: payload
            )
            recommendations = result.recommendations
            baseline        = result.baseline
            live            = result.live
            cacheAgeSeconds = result.cacheAgeSeconds
        } catch {
            errorMessage = "Couldn't load border data: \((error as NSError).localizedDescription)"
        }
    }
}

// MARK: - Wire types

public struct CrossingRecommendation: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let code: String
    public let name: String
    public let border: String
    public let state: String
    public let province: String?
    public let lat: Double
    public let lng: Double
    public let milesFromCaller: Int
    public let driveMinutes: Int
    public let commercialWaitMinutes: Int
    public let fastWaitMinutes: Int?
    public let effectiveWaitMinutes: Int
    public let fastLaneAvailable: Bool
    public let hazmatCapable: Bool
    public let severity: String
    public let totalMinutes: Int
    public let live: Bool
    public let source: String
    public let deltaMinutes: Int
    public let isBaseline: Bool

    public var severitySymbol: String {
        switch severity {
        case "low":      return "checkmark.circle.fill"
        case "moderate": return "clock.fill"
        case "high":     return "exclamationmark.triangle.fill"
        case "critical": return "exclamationmark.octagon.fill"
        default:         return "questionmark.circle"
        }
    }
    public var severityColor: Color {
        switch severity {
        case "low":      return .green
        case "moderate": return .yellow
        case "high":     return .orange
        case "critical": return .red
        default:         return .secondary
        }
    }
}

public struct BaselineCrossing: Decodable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let totalMinutes: Int
}

// MARK: - Previews

#Preview("Cross-Border · Dark") {
    NavigationStack {
        CrossBorderShippingView(
            fromLat: 27.50, fromLng: -99.50,
            border: "US-MX",
            fastEligible: true,
            hazmatRequired: false,
            currentPortCode: "2304"
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Cross-Border · Light") {
    NavigationStack {
        CrossBorderShippingView(
            fromLat: 27.50, fromLng: -99.50,
            border: "US-MX",
            fastEligible: true,
            hazmatRequired: false,
            currentPortCode: "2304"
        )
    }
    .preferredColorScheme(.light)
}
