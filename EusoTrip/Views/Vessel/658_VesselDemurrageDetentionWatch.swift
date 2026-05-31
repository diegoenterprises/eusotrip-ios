//
//  658_VesselDemurrageDetentionWatch.swift
//  EusoTrip — Vessel Operator · Demurrage & Detention Watch (carrier fleet monitor).
//
//  Verbatim port of "658 Vessel Demurrage Detention Watch.svg" (Light + Dark).
//  Vessel counterpart of 558_RailDemurrageWatch. Carrier portfolio view of accruing
//  demurrage (container at terminal) + detention (container off-terminal) across the
//  fleet — distinct from the shipper-side 004 single-shipment detail. Nav anchored to
//  VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME),
//  Shipments tab current.
//
//  Data:
//    vesselShipments.getVesselDemurrage      (EXISTS vesselShipments.ts:632) -> list + KPIs
//    vesselShipments.calculateVesselDemurrage(EXISTS vesselShipments.ts:901) -> per-box accrual
//    vesselShipments.getVesselShipmentDetail (EXISTS vesselShipments.ts:162) -> row tap-through
//
//  LifecycleProductContext: dry FCL default; 40RF reefer (−18°C cold-chain) and IMDG
//  Class 8 (UN1830) flagged as stringent variants (not the default lens).
//

import SwiftUI

struct VesselDemurrageDetentionWatchScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselDemurrageDetentionWatchBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror getVesselDemurrage)

private struct DDContainer: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let containerSize: String?     // 40HC, 40RF, 20GP …
    let kind: String?              // "demurrage" | "detention"
    let lastFreeDay: String?
    let chargeUsd: Double?
    let daysOver: Int?
    let freeDaysLeft: Int?
    let reefer: Bool?
    let imdgClass: String?         // e.g. "8" if dangerous goods
    let detail: String?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        containerNumber = try container.decodeIfPresent(String.self, forKey: .containerNumber)
        containerSize = try container.decodeIfPresent(String.self, forKey: .containerSize)
        kind = try container.decodeIfPresent(String.self, forKey: .chargeType)
        lastFreeDay = try container.decodeIfPresent(String.self, forKey: .endDate)
        chargeUsd = try container.decodeIfPresent(Double.self, forKey: .totalCharge)
        daysOver = try container.decodeIfPresent(Int.self, forKey: .chargeableDays)
        freeDaysLeft = try container.decodeIfPresent(Int.self, forKey: .freeTimeDays)
        reefer = nil
        imdgClass = nil
        detail = nil
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case containerNumber
        case containerSize
        case chargeType
        case endDate
        case totalCharge
        case chargeableDays
        case freeTimeDays
    }
}

private struct DDWatch: Decodable {
    let demurrageUsd: Double?
    let detentionUsd: Double?
    let lfdPassedCount: Int?
    let containers: [DDContainer]?
    
    init(from decoder: Decoder) throws {
        var unkeyedContainer = try decoder.unkeyedContainer()
        var rows: [DDContainer] = []
        while !unkeyedContainer.isAtEnd {
            let row = try unkeyedContainer.decode(DDContainer.self)
            rows.append(row)
        }
        
        containers = rows.isEmpty ? nil : rows
        
        var demurrage: Double = 0
        var detention: Double = 0
        var lfdCount: Int = 0
        
        for row in rows {
            if row.kind == "demurrage" {
                demurrage += row.chargeUsd ?? 0
            } else if row.kind == "detention" {
                detention += row.chargeUsd ?? 0
            }
            if (row.daysOver ?? 0) > 0 {
                lfdCount += 1
            }
        }
        
        demurrageUsd = demurrage > 0 ? demurrage : nil
        detentionUsd = detention > 0 ? detention : nil
        lfdPassedCount = lfdCount > 0 ? lfdCount : nil
    }
}

// MARK: - Body

private struct VesselDemurrageDetentionWatchBody: View {
    @Environment(\.palette) private var palette
    @State private var watch: DDWatch? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private enum Risk { case clear, atRisk, breached }
    private func risk(_ c: DDContainer) -> Risk {
        if (c.daysOver ?? 0) > 0 { return .breached }
        if (c.freeDaysLeft ?? 99) <= 1 { return .atRisk }
        return .clear
    }
    private func tone(_ r: Risk) -> Color {
        switch r { case .clear: return Brand.success; case .atRisk: return Brand.warning; case .breached: return Brand.danger }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading D&D…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    kpiStrip
                    watchList
                    CTAButton(title: "Export D&D report", leadingIcon: "square.and.arrow.up")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · DEMURRAGE WATCH").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Demurrage & detention").font(.system(size: 25, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("getVesselDemurrage · per-container accrual").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "DEMURRAGE", value: "$\(Int(watch?.demurrageUsd ?? 0))", gradientNumeral: true)
            MetricTile(label: "DETENTION", value: "$\(Int(watch?.detentionUsd ?? 0))", accent: Brand.warning)
            MetricTile(label: "LFD PASSED", value: "\(watch?.lfdPassedCount ?? 0)", accent: Brand.danger)
        }
    }

    private var watchList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CONTAINERS · calculateVesselDemurrage").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            ForEach(watch?.containers ?? []) { c in
                let r = risk(c)
                LifecycleCard(accentDanger: r == .breached) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("\(c.containerNumber ?? "—") · \(c.containerSize ?? "—")").font(.system(size: 14, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
                            if c.reefer == true {
                                Text("REEFER").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.info)
                                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Brand.info.opacity(0.12)))
                            }
                            if let dg = c.imdgClass {
                                Text("IMDG Cl.\(dg)").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Brand.warning.opacity(0.16)))
                            }
                            Spacer()
                            Text("$\(Int(c.chargeUsd ?? 0))").font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(tone(r))
                        }
                        Text(c.detail ?? "LFD \(c.lastFreeDay ?? "—")").font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct Empty: Encodable {}
        do {
            self.watch = try await EusoTripAPI.shared.query("vesselShipments.getVesselDemurrage", input: Empty())
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("658 · Vessel D&D Watch · Night") { VesselDemurrageDetentionWatchScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("658 · Vessel D&D Watch · Light") { VesselDemurrageDetentionWatchScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
