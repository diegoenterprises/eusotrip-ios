//
//  HereMatrixCandidatesStrip.swift
//  EusoTrip — parallel-ETA ranking for candidate truck stops.
//
//  Wires HERE Matrix Routing v8 (HereMatrixClient) on top of the
//  HERE Parking nearby query (HereParkingClient) so the driver
//  sees the actual travel-time delta between today's "ESANG
//  picked this" stop and the next two best candidates.
//
//  Why this is here:
//    036 ESANG Smart Stop renders one ranked stop. Real dispatch
//    needs to know the cost of *not* taking it — i.e. how much
//    time the driver gives up by detouring vs. holding the line.
//    Matrix Routing computes truck-aware travel times for every
//    (origin, destination) pair in a single call, which is the
//    right primitive for this comparison.
//
//  Behaviour:
//    • Pulls the live CoreLocation fix from DriverLocationResolver.
//    • Asks HereParkingClient for the 5 nearest parking POIs.
//    • Calls HereMatrixClient with origin = live fix and
//      destinations = the top 5 candidates, using
//      `TruckProfile.standardUSSemiEmpty` as the truck shape.
//    • Renders the candidates ordered by travel time, capped at
//      3 cards.
//    • Hides cleanly when location is denied, parking is empty,
//      matrix call fails, or the tenant key lacks Matrix access.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

@MainActor
final class HereMatrixCandidatesStore: ObservableObject {

    struct Ranked: Identifiable, Hashable {
        let id: String
        let title: String
        let etaSeconds: Int
        let meters: Int
    }

    @Published private(set) var ranked: [Ranked] = []
    @Published private(set) var isLoading: Bool = false

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let origin = await DriverLocationResolver.shared.currentCoordinate() else {
            ranked = []
            return
        }

        let parking: [HereBrowseParkingItem]
        do {
            parking = try await HereParkingClient.shared.parkingNearby(
                center: origin,
                limit: 5
            )
        } catch {
            ranked = []
            return
        }
        guard !parking.isEmpty else {
            ranked = []
            return
        }

        let dests = parking.compactMap { item -> (String, String, CLLocationCoordinate2D)? in
            guard let pos = item.position else { return nil }
            return (item.id, item.title, pos.coordinate)
        }
        guard !dests.isEmpty else {
            ranked = []
            return
        }

        let response: HereMatrixResponse
        do {
            response = try await HereMatrixClient.shared.matrix(
                origins: [origin],
                destinations: dests.map(\.2),
                profile: .standardUSSemiEmpty
            )
        } catch {
            ranked = []
            return
        }

        let times = response.matrix.travelTimes ?? []
        let dists = response.matrix.distances ?? []
        guard times.count == dests.count else {
            ranked = []
            return
        }

        var rows: [Ranked] = []
        for (idx, dest) in dests.enumerated() {
            rows.append(Ranked(
                id: dest.0,
                title: dest.1,
                etaSeconds: times[idx],
                meters: idx < dists.count ? dists[idx] : 0
            ))
        }
        ranked = rows.sorted { $0.etaSeconds < $1.etaSeconds }
    }
}

struct HereMatrixCandidatesStrip: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = HereMatrixCandidatesStore()

    var body: some View {
        Group {
            if store.ranked.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: Space.s2) {
                    header
                    VStack(spacing: 6) {
                        ForEach(Array(store.ranked.prefix(3).enumerated()), id: \.element.id) { idx, row in
                            candidateRow(rank: idx + 1, row: row)
                        }
                    }
                }
            }
        }
        .task { await store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.grid.cross.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("PARALLEL ETA · MATRIX")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
            Text("HERE · \(store.ranked.count)")
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func candidateRow(rank: Int, row: HereMatrixCandidatesStore.Ranked) -> some View {
        HStack(spacing: 8) {
            Text("#\(rank)")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 22, alignment: .leading)
            Text(row.title)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(milesLabel(row.meters))
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
            Text(etaLabel(row.etaSeconds))
                .font(EType.bodyStrong)
                .foregroundStyle(rank == 1 ? AnyShapeStyle(LinearGradient.diagonal)
                                            : AnyShapeStyle(palette.textPrimary))
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func milesLabel(_ meters: Int) -> String {
        let mi = Double(meters) / 1609.344
        return mi < 10
            ? String(format: "%.1f mi", mi)
            : String(format: "%.0f mi", mi)
    }

    private func etaLabel(_ seconds: Int) -> String {
        let mins = seconds / 60
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        let m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

#Preview("HereMatrixCandidatesStrip · Dark") {
    HereMatrixCandidatesStrip()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .padding()
        .background(Theme.dark.bgPage)
}

#Preview("HereMatrixCandidatesStrip · Light") {
    HereMatrixCandidatesStrip()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .padding()
        .background(Theme.light.bgPage)
}
