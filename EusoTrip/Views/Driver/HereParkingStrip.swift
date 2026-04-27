//
//  HereParkingStrip.swift
//  EusoTrip — Driver-facing parking-nearby section that plugs into
//  036 ESANG Smart Stop and any future HOS break planner.
//
//  Pulls a short list of off-street lots + garages + truck stops
//  from HERE Parking (Browse Places API filtered to the parking
//  category set) centered on an explicit coordinate or the driver's
//  live CoreLocation fix. When the tenant's HERE key includes the
//  Dynamic Parking add-on, per-item `parking` extension fields
//  (available spaces, truck spaces, pricing, amenities) render as
//  sub-chips on each card — otherwise we show the static POI
//  address + distance and nothing more.
//
//  The section is silent when HERE returns empty, matches the
//  existing "no fake data" doctrine the rest of the app follows.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

@MainActor
final class ParkingNearbyStore: ObservableObject {
    @Published private(set) var items: [HereBrowseParkingItem] = []
    @Published private(set) var isLoading: Bool = false

    func refresh(center: CLLocationCoordinate2D) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await HereParkingClient.shared.parkingNearby(
                center: center,
                limit: 20
            )
            items = fresh
                .sorted { ($0.distance ?? .max) < ($1.distance ?? .max) }
        } catch {
            // Swallow — the section hides cleanly when items stays []
        }
    }
}

struct HereParkingStrip: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ParkingNearbyStore()
    /// Optional explicit centre. When nil the strip uses the driver's
    /// live CoreLocation fix via `DriverLocationResolver`.
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
            Image(systemName: "parkingsign.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("PARKING NEARBY")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
            Text("HERE · \(store.items.count)")
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func card(_ item: HereBrowseParkingItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + distance
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
            // Address
            if let addr = item.address?.label, !addr.isEmpty {
                Text(addr)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            // Live availability + truck spaces when Dynamic Parking is
            // licensed on the tenant's HERE key.
            if let p = item.parking {
                VStack(alignment: .leading, spacing: 3) {
                    if let avail = p.availableSpaces, let total = p.totalSpaces {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(availabilityColor(avail: avail, total: total))
                                .frame(width: 6, height: 6)
                            Text("\(avail) of \(total) open")
                                .font(EType.micro).tracking(0.4)
                                .foregroundStyle(availabilityColor(avail: avail, total: total))
                        }
                    }
                    if let ts = p.truckAvailableSpaces {
                        HStack(spacing: 4) {
                            Image(systemName: "truck.box")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Brand.success)
                            Text("\(ts) truck spaces")
                                .font(EType.micro).tracking(0.4)
                                .foregroundStyle(Brand.success)
                        }
                    }
                    if let first = p.prices?.first,
                       let amount = first.amount,
                       let currency = first.currency {
                        Text(priceLabel(amount: amount, currency: currency, duration: first.durationMinutes))
                            .font(EType.micro).tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                    }
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

    // MARK: Helpers

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

    private func availabilityColor(avail: Int, total: Int) -> Color {
        guard total > 0 else { return palette.textTertiary }
        let pct = Double(avail) / Double(total)
        if pct > 0.3 { return Brand.success }
        if pct > 0.1 { return Brand.warning }
        return Brand.danger
    }

    private func priceLabel(amount: Double, currency: String, duration: Int?) -> String {
        let sym: String = {
            switch currency.uppercased() {
            case "USD": return "$"
            case "EUR": return "€"
            case "GBP": return "£"
            case "CAD": return "$"
            default:    return ""
            }
        }()
        if let d = duration {
            if d >= 60 && d % 60 == 0 {
                return "\(sym)\(String(format: "%.2f", amount)) / \(d / 60)h"
            }
            return "\(sym)\(String(format: "%.2f", amount)) / \(d)m"
        }
        return "\(sym)\(String(format: "%.2f", amount))"
    }
}

// MARK: - Previews

#Preview("HereParkingStrip · Dark") {
    HereParkingStrip()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .padding()
        .background(Theme.dark.bgPage)
}

#Preview("HereParkingStrip · Light") {
    HereParkingStrip()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .padding()
        .background(Theme.light.bgPage)
}
