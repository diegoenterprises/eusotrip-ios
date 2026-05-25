//
//  561_RailFacilityStatus.swift
//  EusoTrip — Rail Engineer · Facility Status (Class I yard, carrier-side).
//
//  Drill-down from 559_RailYardOperations yard row tap-through. Faithful port
//  of "05 Rail/Light-SVG/561 Rail Facility Status.svg" (Light + Dark).
//  RECONSTRUCTED to flagship DETAIL grammar per FOUNDER CADENCE DIRECTIVE
//  2026-05-24. Nav anchored to RailEngineerNavController,
//  Shipments tab current.
//
//  Data:
//    railShipments.getFacilityStatus (EXISTS railShipments.ts:748) → Class I live yard status
//    railShipments.getRailYards      (EXISTS railShipments.ts:461) → yard header (name, city, type)
//

import SwiftUI

struct RailFacilityStatusScreen: View {
    let theme: Theme.Palette
    let yardId: Int
    let railroad: String
    let facilityCode: String
    var body: some View {
        Shell(theme: theme) {
            RailFacilityStatusBody(yardId: yardId, railroad: railroad, facilityCode: facilityCode)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct RailYard561: Decodable {
    let id: Int
    let name: String
    let splcCode: String?
    let city: String?
    let state: String?
    let country: String?
    let yardType: String?
    let totalTracks: Int?
    let capacity: Int?
    let hasIntermodal: Bool?
    let hasHazmat: Bool?
    let operatingHours: YardHours561?
    let status: String?
}

private struct YardHours561: Decodable {
    let open: String?
    let close: String?
    let timezone: String?
}

// getFacilityStatus returns external Class I data — best-effort shape
private struct FacilityStatus561: Decodable {
    let congestionIndex: Double?
    let statusLabel: String?        // "FLUID" | "CONGESTED" | "EMBARGO"
    let inboundCars: Int?
    let avgDwellHours: Double?
    let gateQueueMinutes: Int?
    let liftCapacityPct: Double?
    let hazmatHold: Bool?
    let hazmatDetail: String?
    let nextGateSlot: String?
    let lastUpdatedMinutes: Int?
}

// MARK: - Body

private struct RailFacilityStatusBody: View {
    @Environment(\.palette) private var palette
    let yardId: Int
    let railroad: String
    let facilityCode: String
    @State private var yard: RailYard561? = nil
    @State private var status: FacilityStatus561? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private var statusColor: Color {
        switch (status?.statusLabel ?? "").uppercased() {
        case "FLUID":    return Brand.success
        case "CONGESTED": return Brand.warning
        case "EMBARGO":  return Brand.danger
        default:         return Brand.info
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard {
                        Text("Loading facility status…").font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    heroCard
                    kpiStrip
                    detailRows
                    yardContext
                    actions
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                Image(systemName: "building.2").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · FACILITY STATUS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            HStack {
                Text(yard?.name ?? facilityCode)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .minimumScaleFactor(0.65).lineLimit(1)
                Spacer()
                HStack(spacing: 4) {
                    Text(railroad.uppercased()).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
                    Text("·").foregroundStyle(palette.textTertiary)
                    Text(facilityCode.uppercased()).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
            }
            if let y = yard {
                Text([y.city, y.state, y.yardType?.replacingOccurrences(of: "_", with: " ")].compactMap { $0 }.joined(separator: " · "))
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            IridescentHairline()
        }
    }

    // MARK: Hero Card

    private var heroCard: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    let label = status?.statusLabel ?? "—"
                    Text(label.uppercased())
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(statusColor.opacity(0.14)))
                    if let y = yard, let city = y.city, let st = y.state {
                        Text("\(city), \(st) · \(y.operatingHours?.timezone ?? "24/7 gate")")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background(Capsule().fill(palette.bgCardSoft))
                    }
                    Spacer()
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        let ci = status?.congestionIndex.map { String(format: "%.2f", $0) } ?? "—"
                        Text(ci)
                            .font(.system(size: 34, weight: .bold)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("congestion index").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text(status?.hazmatHold == true ? "hazmat hold active" : "normal ops · no embargo")
                            .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("INBOUND").font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textTertiary)
                        Text("\(status?.inboundCars ?? 0)")
                            .font(.system(size: 22, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text("on ground").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: KPI Strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            let dwell = status?.avgDwellHours.map { "\(Int($0))h" } ?? "—"
            let queue = status?.gateQueueMinutes.map { "\($0)m" } ?? "—"
            let lift  = status?.liftCapacityPct.map { "\(Int($0))%" } ?? "—"
            MetricTile(label: "AVG DWELL", value: dwell)
            MetricTile(label: "GATE QUEUE", value: queue)
            MetricTile(label: "LIFT CAP", value: lift, gradientNumeral: true)
        }
    }

    // MARK: Detail Rows

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("FACILITY DETAIL · getFacilityStatus")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            LifecycleCard {
                VStack(spacing: 0) {
                    detailRow(
                        glyph: "arrow.up.to.line", tintColor: Brand.info,
                        title: "Outbound lift capacity",
                        sub: "crane availability · classIRailroadService",
                        value: status?.liftCapacityPct.map { "\(Int($0))%" } ?? "—",
                        badge: nil, badgeColor: nil
                    )
                    Divider().padding(.leading, 56)
                    if status?.hazmatHold == true {
                        detailRow(
                            glyph: "drop.triangle", tintColor: Brand.warning,
                            title: "Hazmat dwell hold",
                            sub: status?.hazmatDetail ?? "placard verification required",
                            value: nil,
                            badge: "HAZMAT", badgeColor: Brand.warning
                        )
                        Divider().padding(.leading, 56)
                    }
                    detailRow(
                        glyph: "calendar", tintColor: Brand.info,
                        title: "Next gate appointment",
                        sub: "next open slot · gate 3",
                        value: status?.nextGateSlot ?? "—",
                        badge: nil, badgeColor: nil
                    )
                }
            }
        }
    }

    private func detailRow(
        glyph: String, tintColor: Color,
        title: String, sub: String,
        value: String?, badge: String?, badgeColor: Color?
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tintColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: glyph)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tintColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            if let badge, let badgeColor {
                Text(badge)
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(badgeColor.opacity(0.14)))
            } else if let value {
                Text(value)
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    // MARK: Yard Context Strip

    private var yardContext: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("YARD HEADER · getRailYards")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    if let mins = status?.lastUpdatedMinutes {
                        Text("updated \(mins)m ago").font(EType.caption).foregroundStyle(palette.textTertiary)
                    }
                }
                if let y = yard {
                    let parts: [String] = [
                        y.name,
                        railroad.uppercased(),
                        y.hasIntermodal == true ? "intermodal ramp" : nil,
                        y.operatingHours.flatMap { h in
                            (h.open != nil && h.close != nil) ? "\(h.open ?? "")–\(h.close ?? "") \(h.timezone ?? "")" : "24/7 gate"
                        }
                    ].compactMap { $0 }
                    Text(parts.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Text("Capacity: \(yard?.capacity ?? 0) cars · \(yard?.totalTracks ?? 0) tracks · \(yard?.hasHazmat == true ? "hazmat certified" : "no hazmat")")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Reserve gate appt", action: {}, leadingIcon: "calendar.badge.plus")
            CTAButton(title: "Yard map", leadingIcon: "map")
        }
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct YardIn: Encodable { let railroadId: Int?; let limit: Int }
        struct FacilityIn: Encodable { let railroad: String; let facilityCode: String }
        do {
            // Yard header — query by SPLC/code pattern; yardId used as railroadId filter
            let yards: [RailYard561] = try await EusoTripAPI.shared.query(
                "railShipments.getRailYards",
                input: YardIn(railroadId: yardId > 0 ? yardId : nil, limit: 1))
            self.yard = yards.first

            // External Class I feed — best-effort, non-blocking on failure
            self.status = try? await EusoTripAPI.shared.query(
                "railShipments.getFacilityStatus",
                input: FacilityIn(railroad: railroad, facilityCode: facilityCode))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("561 · Facility Status · Night") {
    RailFacilityStatusScreen(theme: Theme.dark, yardId: 0, railroad: "BNSF", facilityCode: "CORW")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("561 · Facility Status · Light") {
    RailFacilityStatusScreen(theme: Theme.light, yardId: 0, railroad: "BNSF", facilityCode: "CORW")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
