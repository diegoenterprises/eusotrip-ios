//
//  171_DriverTruckParking.swift
//  EusoTrip — Screen 171 · Driver Truck Parking (LIVE-wired)
//
//  Purpose: when the HOS clock is running down, put the nearest real truck
//  parking + live space counts in front of the driver so they lock a legal
//  spot before the lot fills — not after they're out of hours.
//
//  Wiring manifest:
//    Nearby parking · EusoTrip Network
//        HereParkingClient.shared.parkingNearby(center:)  — Services/HereMaps/
//        HereParkingClient.swift:84 (HERE Browse; truck-parking + truck-stop
//        categories). Live space counts arrive only when the tenant licenses
//        Dynamic Parking — otherwise static POIs land (honest, no faked count).
//    Live availability · TPIMS
//        driverMobile.getTruckParking  EXISTS · routers/driverMobile.ts:1014
//        (reads FHWA TPIMS rows from hz_rate_indices; empty until synced).
//    DriverLocationResolver.shared.currentCoordinate() — Services/
//        DriverLocationResolver.swift:106 (CoreLocation fix for proximity).
//  transportMode = truck · country US. HERE is branded "EusoTrip Network"
//  in all user copy per house doctrine (engine name never surfaces).
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//

import SwiftUI
import CoreLocation

// MARK: - TPIMS wire model

private struct TpimsSite: Decodable, Identifiable {
    let id: String
    let name: String
    let state: String?
    let totalSpaces: Int?
    let availableSpaces: Int?
    let distance: Double?
    let availabilityPercentage: Int?
    let statusColor: String?
}
private struct TpimsResult: Decodable { let locations: [TpimsSite]; let total: Int }

// MARK: - ViewModel

@MainActor
private final class TruckParkingViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, locationDenied, error(String) }
    @Published var phase: Phase = .idle
    @Published var network: [HereBrowseParkingItem] = []
    @Published var tpims: [TpimsSite] = []

    let laneLabel: String
    init(laneLabel: String) { self.laneLabel = laneLabel }

    private struct Coord: Encodable { let lat: Double; let lng: Double }
    private struct ParkingIn: Encodable { let location: Coord; let radius: Int; let minSpaces: Int }

    func load() async {
        phase = .loading
        guard let c = await DriverLocationResolver.shared.currentCoordinate() else {
            phase = .locationDenied
            return
        }
        // Nearby parking via the EusoTrip Network (HERE Browse) — real POIs.
        network = (try? await HereParkingClient.shared.parkingNearby(center: c, limit: 20)) ?? []
        // Live TPIMS availability where the FHWA feed is synced (may be empty).
        do {
            let r: TpimsResult = try await EusoTripAPI.shared.query(
                "driverMobile.getTruckParking",
                input: ParkingIn(location: Coord(lat: c.latitude, lng: c.longitude),
                                 radius: 80, minSpaces: 1))
            tpims = r.locations
        } catch { tpims = [] }
        phase = .ready
    }
}

// MARK: - Screen body

struct TruckParkingView: View {
    @Environment(\.palette) var palette
    @StateObject private var vm: TruckParkingViewModel

    init(laneLabel: String = "") {
        _vm = StateObject(wrappedValue: TruckParkingViewModel(laneLabel: laneLabel))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DriverUtilityHeader(eyebrow: "DRIVER · PARKING", caption: "HOS-AWARE",
                                title: "Truck Parking",
                                subtitle: vm.laneLabel.isEmpty ? "ahead on route" : vm.laneLabel,
                                rightTop: "MICHAEL EUSORONE · DR-00427",
                                rightBottom: "Eusotrans LLC")
            IridescentHairline().padding(.top, Space.s3)
            switch vm.phase {
            case .idle, .loading:   DriverUtilityLoading(text: "Finding parking nearby…")
            case .locationDenied:   locationDenied
            case .error(let m):     DriverUtilityError(message: m) { Task { await vm.load() } }
            case .ready:            content
            }
        }
        .task { if case .idle = vm.phase { await vm.load() } }
    }

    private var locationDenied: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "location.slash")
                .font(.system(size: 26, weight: .regular)).foregroundStyle(Brand.warning)
            Text("Location off").font(EType.h2).foregroundStyle(palette.textPrimary)
            Text("Turn on location so we can put the nearest truck parking in front of you.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, Space.s6)
            Button("Try again") { Task { await vm.load() } }
                .font(EType.bodyStrong).foregroundStyle(LinearGradient.diagonal)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var content: some View {
        VStack(spacing: Space.s4) {
            summaryTiles
            tpimsCard
            networkCard
            CTAButton(title: "Refresh stops", action: { Task { await vm.load() } },
                      leadingIcon: "arrow.clockwise")
        }
        .padding(Space.s5)
    }

    private var summaryTiles: some View {
        HStack(spacing: Space.s3) {
            MetricTile(label: "Stops nearby", value: "\(vm.network.count)", gradientNumeral: true)
            MetricTile(label: "Live counts", value: "\(vm.tpims.count)")
            MetricTile(label: "Open spots", value: openSpotsText,
                       accent: openSpots > 0 ? Brand.success : nil)
        }
    }

    private var openSpots: Int { vm.tpims.compactMap { $0.availableSpaces }.reduce(0, +) }
    private var openSpotsText: String { openSpots > 0 ? "\(openSpots)" : "—" }

    // Live availability (TPIMS)
    private var tpimsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("LIVE AVAILABILITY").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("TPIMS").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            if vm.tpims.isEmpty {
                DriverUtilityEmpty(systemImage: "parkingsign",
                                   title: "No live counts on this corridor",
                                   detail: "State TPIMS space counts aren't reporting here right now. Nearby lots are listed below.")
            } else {
                ForEach(vm.tpims.prefix(4)) { site in
                    tpimsRow(site)
                    if site.id != vm.tpims.prefix(4).last?.id {
                        Divider().overlay(palette.borderFaint)
                    }
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func tpimsRow(_ s: TpimsSite) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text([s.state, s.distance.map { String(format: "%.1f mi", $0) }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            if let avail = s.availableSpaces {
                Text("\(avail) open")
                    .font(EType.mono(.caption)).fontWeight(.bold)
                    .foregroundStyle(spaceTint(s))
            } else {
                Text("—").font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func spaceTint(_ s: TpimsSite) -> Color {
        switch (s.statusColor ?? "").lowercased() {
        case "green":  return Brand.success
        case "yellow": return Brand.warning
        case "red":    return Brand.danger
        default:       return palette.textPrimary
        }
    }

    // Nearby parking (EusoTrip Network / HERE)
    private var networkCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("NEARBY PARKING").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("EUSOTRIP NETWORK").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            if vm.network.isEmpty {
                DriverUtilityEmpty(systemImage: "mappin.slash",
                                   title: "No lots found nearby",
                                   detail: "Nothing within range on the network right now — try again as you move up the corridor.")
            } else {
                ForEach(vm.network.prefix(6)) { item in
                    networkRow(item)
                    if item.id != vm.network.prefix(6).last?.id {
                        Divider().overlay(palette.borderFaint)
                    }
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func networkRow(_ item: HereBrowseParkingItem) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(networkSub(item)).font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(distanceText(item.distance))
                .font(EType.mono(.caption)).fontWeight(.bold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.vertical, 2)
    }

    private func networkSub(_ item: HereBrowseParkingItem) -> String {
        if let p = item.parking, let a = p.truckAvailableSpaces ?? p.availableSpaces {
            let t = p.truckSpaces ?? p.totalSpaces
            return t != nil ? "\(a)/\(t!) truck spaces" : "\(a) spaces open"
        }
        return "availability n/a · call ahead"
    }

    private func distanceText(_ meters: Int?) -> String {
        guard let meters else { return "—" }
        let mi = Double(meters) / 1609.34
        return String(format: "%.1f mi", mi)
    }
}

// MARK: - Screen (Shell + Driver nav · ME current)

struct TruckParkingScreen: View {
    let theme: Theme.Palette
    var laneLabel: String = ""
    var body: some View {
        Shell(theme: theme) {
            TruckParkingView(laneLabel: laneLabel)
        } nav: {
            BottomNav(leading: driverUtilityNavLeading(),
                      trailing: driverUtilityNavTrailing(meCurrent: true), orbState: .idle)
        }
    }
}

#Preview("Truck Parking · Dark") {
    TruckParkingScreen(theme: Theme.dark, laneLabel: "I-10 EB · AZ")
        .preferredColorScheme(.dark).environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
#Preview("Truck Parking · Light") {
    TruckParkingScreen(theme: Theme.light, laneLabel: "I-10 EB · AZ")
        .preferredColorScheme(.light).environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
