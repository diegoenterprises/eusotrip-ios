//
//  588_RailFleetHealth.swift
//  EusoTrip — Rail 588 · Fleet Health
//

import SwiftUI

// MARK: - Outer shell

struct RailFleetHealthScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) {
            RailFleetHealthBody(railId: railId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct FleetSummary588: Decodable {
    let availabilityPct: Double?
    let healthyCount: Int?
    let watchCount: Int?
    let downCount: Int?
    let openWorkOrders: Int?
    let fleetStatus: String?
    let poolSize: Int?
}

private struct AssetHealthClass588: Decodable {
    let className: String?
    let unitCount: Int?
    let avgHealth: Int?
    let detail: String?
    let status: String?
}

private struct FleetPredictions588: Decodable {
    let flagCount: Int?
    let openWorkOrders: Int?
    let worstFlagDescription: String?
}

private struct RailIdIn588: Encodable { let railId: String }

// MARK: - Body

private struct RailFleetHealthBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var summary: FleetSummary588? = nil
    @State private var assetClasses: [AssetHealthClass588] = []
    @State private var predictions: FleetPredictions588? = nil

    // MARK: Derived

    private var availLabel: String {
        guard let pct = summary?.availabilityPct else { return "—" }
        return "\(Int(pct))%"
    }
    private var healthyCount: Int  { summary?.healthyCount  ?? 0 }
    private var watchCount: Int    { summary?.watchCount    ?? 0 }
    private var downCount: Int     { summary?.downCount     ?? 0 }
    private var workOrders: Int    { summary?.openWorkOrders ?? 0 }
    private var poolSize: Int      { summary?.poolSize       ?? 0 }
    private var fleetStatusLabel: String {
        switch (summary?.fleetStatus ?? "stable").lowercased() {
        case "degraded": return "DEGRADED"
        case "critical": return "CRITICAL"
        default:         return "STABLE"
        }
    }
    private var fleetStatusOk: Bool {
        (summary?.fleetStatus ?? "stable").lowercased() == "stable"
    }
    private var predictLine1: String {
        let flags   = predictions?.flagCount ?? 0
        let orders  = predictions?.openWorkOrders ?? workOrders
        return "\(flags) predictive flag\(flags == 1 ? "" : "s") next 30d · \(orders) open work order\(orders == 1 ? "" : "s")"
    }
    private var predictLine2: String {
        predictions?.worstFlagDescription ?? "No critical flags"
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
                byClassSection
                predictiveStrip
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
            Text("✦ RAIL ENGINEER · FLEET HEALTH")
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
            Text("Fleet health")
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
                HStack(spacing: Space.s2) {
                    Text(fleetStatusLabel)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill((fleetStatusOk ? Brand.success : Brand.warning).opacity(0.14)))
                        .foregroundColor(fleetStatusOk ? Brand.success : Brand.warning)

                    Text("\(poolSize)-unit pool")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.05)))
                        .foregroundColor(palette.textPrimary)
                }

                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: Space.s2) {
                        Text(availLabel)
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("available")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(palette.textSecondary)
                            Text("getFleetSummary")
                                .font(.system(size: 11))
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WORK ORD")
                            .font(.system(size: 10, weight: .black))
                            .kerning(0.6)
                            .foregroundColor(palette.textTertiary)
                        Text("\(workOrders)")
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundColor(palette.textPrimary)
                        Text("open")
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
            MetricTile(label: "HEALTHY", value: "\(healthyCount)", gradientNumeral: healthyCount > 0)
            MetricTile(label: "WATCH",   value: "\(watchCount)",
                       accent: watchCount > 0 ? Brand.warning : palette.textPrimary)
            MetricTile(label: "DOWN",    value: "\(downCount)",
                       accent: downCount > 0 ? Brand.danger : palette.textPrimary)
        }
    }

    // MARK: By-class list

    private var byClassSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("BY CLASS")
                .font(.system(size: 9, weight: .black))
                .kerning(1.0)
                .foregroundColor(palette.textTertiary)

            VStack(spacing: 0) {
                ForEach(Array(assetClasses.enumerated()), id: \.offset) { idx, cls in
                    if idx > 0 {
                        Divider()
                            .overlay(Color.black.opacity(0.06))
                            .padding(.horizontal, Space.s4)
                    }
                    classRow(cls)
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
    private func classRow(_ cls: AssetHealthClass588) -> some View {
        let (pillLabel, pillColor) = classPillInfo(cls.status)
        let rightVal = cls.unitCount.map { "\($0)" } ?? "—"

        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Brand.blue.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "train.side.front.car")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Brand.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(cls.className ?? "—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                if let detail = cls.detail {
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
                    .background(Capsule().fill(pillColor.opacity(0.14)))
                    .foregroundColor(pillColor)
                Text(rightVal)
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundColor(palette.textPrimary)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
    }

    // MARK: Predictive strip

    private var predictiveStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PREDICTIVE")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.8)
                    .foregroundColor(palette.textTertiary)
                Spacer()
            }
            Text(predictLine1)
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
            Text(predictLine2)
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
                title: "Maintenance alerts",
                action: {},
                leadingIcon: "plus",
                isLoading: false
            )
            Button("Fleet") {}
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

    private func classPillInfo(_ status: String?) -> (String, Color) {
        switch (status ?? "ok").lowercased() {
        case "ok":   return ("OK",   Brand.success)
        case "due":  return ("DUE",  Brand.warning)
        case "down": return ("DOWN", Brand.danger)
        default:     return ("—",    Brand.info)
        }
    }

    // MARK: Data loading

    private func loadAll() async {
        async let summaryTask: FleetSummary588 = EusoTripAPI.shared.query(
            "fleetMaintenance.getFleetSummary",
            input: RailIdIn588(railId: railId)
        )
        async let classTask: [AssetHealthClass588] = EusoTripAPI.shared.query(
            "railShipments.getAssetHealth",
            input: RailIdIn588(railId: railId)
        )
        async let predTask: FleetPredictions588 = EusoTripAPI.shared.query(
            "fleetMaintenance.getFleetPredictions",
            input: RailIdIn588(railId: railId)
        )

        summary      = try? await summaryTask
        assetClasses = (try? await classTask) ?? []
        predictions  = try? await predTask
    }
}
