//
//  586_RailServiceLineup.swift
//  EusoTrip — Rail 586 · Service Lineup
//

import SwiftUI

// MARK: - Outer shell

struct RailServiceLineupScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) {
            RailServiceLineupBody(railId: railId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct TrainConsist586: Decodable {
    let trainSymbol: String?
    let carCount: Int?
    let scheduledCalls: Int?
    let clearedCalls: Int?
    let estimatedTransitHours: Int?
    let status: String?
    let nextCallLabel: String?
    let nextCallYardName: String?
}

private struct ServiceCall586: Decodable {
    let yardName: String?
    let detail: String?
    let status: String?
    let timeLabel: String?
}

private struct FacilityStatus586: Decodable {
    let facilityName: String?
    let rampStatus: String?
    let gateAvgMinutes: Int?
    let etaNote: String?
    let advisoryNote: String?
}

private struct RailIdIn586: Encodable { let railId: String }

// MARK: - Body

private struct RailServiceLineupBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var consist: TrainConsist586? = nil
    @State private var calls: [ServiceCall586] = []
    @State private var facility: FacilityStatus586? = nil

    // MARK: Derived

    private var trainSymbol: String  { consist?.trainSymbol   ?? "—" }
    private var carCount: Int        { consist?.carCount       ?? 0 }
    private var scheduledCalls: Int  { consist?.scheduledCalls ?? 0 }
    private var clearedCalls: Int    { consist?.clearedCalls   ?? 0 }
    private var transitLabel: String {
        guard let h = consist?.estimatedTransitHours else { return "—" }
        return "\(h)h"
    }
    private var trainStatusLabel: String {
        switch (consist?.status ?? "en_route").lowercased() {
        case "delayed":    return "DELAYED"
        case "terminated": return "TERMINATED"
        default:           return "EN ROUTE"
        }
    }
    private var trainStatusOk: Bool {
        let s = (consist?.status ?? "en_route").lowercased()
        return s == "en_route"
    }
    private var nextCallLabel: String    { consist?.nextCallLabel    ?? "—" }
    private var nextCallYard: String     { consist?.nextCallYardName ?? "—" }
    private var facilityLine1: String {
        let name  = facility?.facilityName ?? "—"
        let ramp  = (facility?.rampStatus ?? "open").lowercased() == "open" ? "ramp open" : "ramp closed"
        let gate  = facility?.gateAvgMinutes.map { "gate avg \($0) min" } ?? ""
        return [name, ramp, gate].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private var facilityLine2: String {
        let eta  = facility?.etaNote      ?? "ETA holds"
        let adv  = facility?.advisoryNote ?? "no network advisory on lane"
        return "\(eta) · \(adv)"
    }

    // MARK: View

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrow
                headline
                IridescentHairline()
                heroCard
                kpiStrip
                callsSection
                facilityStrip
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .task { await loadAll() }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · LINEUP")
                .font(.system(size: 9, weight: .black))
                .kerning(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(railId)
                .font(.system(size: 9, weight: .heavy).monospaced())
                .kerning(0.6)
                .foregroundColor(palette.textTertiary)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Service lineup")
                .font(.system(size: 28, weight: .heavy))
                .kerning(-0.4)
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: Hero card

    private var heroCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            VStack(alignment: .leading, spacing: Space.s3) {
                // Status + train symbol pills
                HStack(spacing: Space.s2) {
                    Text(trainStatusLabel)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill((trainStatusOk ? Brand.success : Brand.warning).opacity(0.14)))
                        .foregroundColor(trainStatusOk ? Brand.success : Brand.warning)

                    Text(trainSymbol)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.05)))
                        .foregroundColor(palette.textPrimary)
                }

                // Calls figure + next call right
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: Space.s2) {
                        Text("\(scheduledCalls)")
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("scheduled calls")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(palette.textSecondary)
                            Text("\(carCount) cars · getTrainConsists")
                                .font(.system(size: 11))
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT CALL")
                            .font(.system(size: 10, weight: .black))
                            .kerning(0.6)
                            .foregroundColor(palette.textTertiary)
                        Text(nextCallLabel)
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundColor(palette.textPrimary)
                        Text(nextCallYard)
                            .font(.system(size: 11))
                            .foregroundColor(palette.textSecondary)
                    }
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 116)
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "CALLS",   value: "\(scheduledCalls)", gradientNumeral: scheduledCalls > 0)
            MetricTile(label: "CLEARED", value: "\(clearedCalls)")
            MetricTile(label: "TO CHI",  value: transitLabel)
        }
    }

    // MARK: Calls list

    private var callsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CALLS")
                .font(.system(size: 9, weight: .black))
                .kerning(1.0)
                .foregroundColor(palette.textTertiary)

            VStack(spacing: 0) {
                ForEach(Array(calls.enumerated()), id: \.offset) { idx, call in
                    if idx > 0 {
                        Divider()
                            .overlay(Color.black.opacity(0.06))
                            .padding(.horizontal, Space.s4)
                    }
                    callRow(call)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func callRow(_ call: ServiceCall586) -> some View {
        let (pillLabel, pillColor, pillBg) = callPillInfo(call.status)
        let timeLabel = call.timeLabel ?? "—"

        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Brand.blue.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Brand.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(call.yardName ?? "—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                if let detail = call.detail {
                    Text(detail)
                        .font(.system(size: 11).monospaced())
                        .kerning(0.4)
                        .foregroundColor(palette.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(pillLabel)
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(pillBg))
                    .foregroundColor(pillColor)
                Text(timeLabel)
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundColor(palette.textPrimary)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
    }

    // MARK: Facility strip

    private var facilityStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("FACILITY")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.8)
                    .foregroundColor(palette.textTertiary)
                Spacer()
            }
            Text(facilityLine1)
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
            Text(facilityLine2)
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: "Notify on next call",
                action: {},
                leadingIcon: "plus",
                isLoading: false
            )
            Button("Lineup") {}
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    Capsule()
                        .fill(palette.bgCard)
                        .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))
                )
        }
    }

    // MARK: Helpers

    private func callPillInfo(_ status: String?) -> (String, Color, Color) {
        switch (status ?? "scheduled").lowercased() {
        case "departed":  return ("DEPARTED",  palette.textSecondary, Color.black.opacity(0.05))
        case "next":      return ("NEXT",       Brand.blue,           Brand.blue.opacity(0.12))
        case "scheduled": return ("SCHEDULED", Brand.warning,        Brand.warning.opacity(0.14))
        case "delayed":   return ("DELAYED",   Brand.danger,         Brand.danger.opacity(0.14))
        case "arrived":   return ("ARRIVED",   Brand.success,        Brand.success.opacity(0.14))
        default:          return ("—",         palette.textTertiary, Color.black.opacity(0.05))
        }
    }

    // MARK: Data loading

    private func loadAll() async {
        async let consistTask: TrainConsist586 = EusoTripAPI.shared.query(
            "railShipments.getTrainConsists",
            input: RailIdIn586(railId: railId)
        )
        async let callsTask: [ServiceCall586] = EusoTripAPI.shared.query(
            "railShipments.getRailYards",
            input: RailIdIn586(railId: railId)
        )
        async let facilityTask: FacilityStatus586 = EusoTripAPI.shared.query(
            "railShipments.getFacilityStatus",
            input: RailIdIn586(railId: railId)
        )

        consist  = try? await consistTask
        calls    = (try? await callsTask) ?? []
        facility = try? await facilityTask
    }
}
