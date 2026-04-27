//
//  HereEVStrip.swift
//  EusoTrip — EV charging-nearby section backed by HERE EV
//  Products (exposed via the HERE Browse Places category
//  `700-7600-0322`).
//
//  Silent when HERE returns no stations (most rural truck corridors
//  today) — matches the "no fake data" doctrine. When stations are
//  returned, each card renders the station title, brand chain,
//  distance, and a connector-type pill row (CCS / CHAdeMO / Type 2
//  / Tesla) so an EV truck driver sees at a glance whether the
//  station matches their rig.
//
//  Future-proof for the vessel / rail vertical (shore-power
//  charging) — swap the category code via an init param.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

@MainActor
final class EVNearbyStore: ObservableObject {
    @Published private(set) var items: [HereBrowseItem] = []
    @Published private(set) var isLoading: Bool = false

    func refresh(center: CLLocationCoordinate2D) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await HereEVClient.shared.chargingStations(
                near: center,
                limit: 12
            )
            items = fresh
                .sorted { ($0.distance ?? .max) < ($1.distance ?? .max) }
        } catch {
            // Swallow — empty `items` means the section hides.
        }
    }
}

struct HereEVStrip: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = EVNearbyStore()
    let explicitCenter: CLLocationCoordinate2D?

    init(center: CLLocationCoordinate2D? = nil) {
        self.explicitCenter = center
    }

    var body: some View {
        Group {
            if store.items.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: Space.s2) {
                    header
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.s3) {
                            ForEach(store.items.prefix(6)) { item in
                                card(item)
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            }
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.car.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("EV CHARGING NEARBY")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
            Text("HERE · \(store.items.count)")
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func card(_ item: HereBrowseItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(item.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let d = item.distance {
                    Text(milesLabel(meters: d))
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            if let chain = item.chains?.first?.name, !chain.isEmpty {
                Text(chain)
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            if let connectors = item.chargingStation?.connectors, !connectors.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(connectors.prefix(4).enumerated()), id: \.offset) { _, c in
                        connectorChip(c)
                    }
                }
            }
            if let totalConnectors = item.chargingStation?.totalNumberOfConnectors {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Brand.success)
                    Text("\(totalConnectors) connector\(totalConnectors == 1 ? "" : "s")")
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(Space.s3)
        .frame(width: 220, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func connectorChip(_ c: HereChargingConnector) -> some View {
        let label = (c.connectorType?.name ?? "—")
            .uppercased()
        return Text(label)
            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(LinearGradient.diagonal.opacity(0.7)))
    }

    private func load() async {
        if let explicit = explicitCenter {
            await store.refresh(center: explicit)
            return
        }
        if let live = await DriverLocationResolver.shared.currentCoordinate() {
            await store.refresh(center: live)
        }
    }

    private func milesLabel(meters: Int) -> String {
        let mi = Double(meters) / 1609.344
        return mi < 10
            ? String(format: "%.1f mi", mi)
            : String(format: "%.0f mi", mi)
    }
}

// MARK: - Previews

#Preview("HereEVStrip · Dark") {
    HereEVStrip()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .padding()
        .background(Theme.dark.bgPage)
}

#Preview("HereEVStrip · Light") {
    HereEVStrip()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .padding()
        .background(Theme.light.bgPage)
}
