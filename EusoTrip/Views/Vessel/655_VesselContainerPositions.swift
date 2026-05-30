//
//  655_VesselContainerPositions.swift
//  EusoTrip — Vessel Operator · Container Positions (carrier vantage).
//
//  Fleet-level container view drilled from the SHIPMENTS tab — distinct from
//  the per-booking container roster on 653. Verbatim port of
//  "655 Vessel Container Positions.svg" (Light + Dark). Nav anchored to
//  VesselOperatorNavController.swift; Shipments tab current (filled symbol).
//  Data shape mirrors vesselShipments.getContainerPositions → { containers, total }
//  (server/routers/vesselShipments.ts:878).
//

import SwiftUI

struct VesselContainerPositionsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselContainerPositionsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                  isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
        // Real top back affordance (replaces the old decorative chevron in
        // the body header). Fixed leading slot → never overlaps the title;
        // posts the shared NavBack the VesselOperatorSurface pops on.
        .injectBespokeBackBar(title: nil) {
            NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
        }
    }
}

// MARK: - Data shape (mirror shippingContainers row)

private struct OceanContainerPos: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let containerType: String?
    let status: String?         // at_port | on_board | on_water | discharged | gate_out
    let location: String?
    let imdgClass: String?
    let isReefer: Bool?
}

private struct ContainerPositionsResponse: Decodable {
    let containers: [OceanContainerPos]
    let total: Int
}

// MARK: - Body

private struct VesselContainerPositionsBody: View {
    @Environment(\.palette) private var palette
    @State private var containers: [OceanContainerPos] = []
    @State private var total = 0
    @State private var loading = true
    @State private var loadError: String? = nil

    private var onBoard: Int  { containers.filter { ($0.status ?? "") == "on_board" || ($0.status ?? "") == "on_water" }.count }
    private var atPort: Int   { containers.filter { ($0.status ?? "") == "at_port" }.count }
    private var hazmat: Int   { containers.filter { $0.imdgClass != nil }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading containers…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if containers.isEmpty {
                    EusoEmptyState(systemImage: "shippingbox", title: "No containers",
                                   subtitle: "Tracked containers will appear here.")
                } else {
                    summaryTiles
                    Text("CONTAINERS · getContainerPositions")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    VStack(spacing: Space.s2) { ForEach(containers) { containerRow($0) } }
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
                Image(systemName: "shippingbox.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · CONTAINERS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Container positions").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("\(total) containers tracked · ISO 6346").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var summaryTiles: some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "ON BOARD", value: "\(onBoard)", icon: "ferry.fill")
            LifecycleStatTile(label: "AT PORT",  value: "\(atPort)",  icon: "building.columns")
            LifecycleStatTile(label: "HAZMAT",   value: "\(hazmat)",  icon: "exclamationmark.triangle",
                              danger: hazmat > 0)
        }
    }

    private func containerRow(_ c: OceanContainerPos) -> some View {
        let (label, tone): (String, Color) = {
            if c.imdgClass != nil { return ("HAZMAT", Brand.warning) }
            if c.isReefer == true { return ("REEFER", Brand.info) }
            switch (c.status ?? "") {
            case "on_board":   return ("ON BOARD", Brand.info)
            case "on_water":   return ("ON WATER", Brand.info)
            case "discharged": return ("DISCH.",   Brand.success)
            case "at_port":    return ("AT PORT",  palette.textTertiary)
            default:           return ((c.status ?? "—").uppercased(), palette.textSecondary)
            }
        }()
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(c.containerNumber ?? "—")\(c.containerType.map { " · \($0)" } ?? "")")
                    .font(.system(size: 13, weight: .semibold)).monospaced().foregroundStyle(palette.textPrimary)
                Text(c.location ?? "—").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(label).font(.system(size: 8.5, weight: .heavy)).tracking(0.5).foregroundStyle(tone)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(tone.opacity(0.16)).clipShape(Capsule())
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func load() async {
        loading = true; loadError = nil
        struct PosIn: Encodable { let limit: Int }
        do {
            let result: ContainerPositionsResponse = try await EusoTripAPI.shared.query(
                "vesselShipments.getContainerPositions", input: PosIn(limit: 100))
            self.containers = result.containers
            self.total = result.total
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("655 · Vessel Container Positions · Night") { VesselContainerPositionsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("655 · Vessel Container Positions · Light") { VesselContainerPositionsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
