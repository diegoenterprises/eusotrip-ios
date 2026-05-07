//
//  250_PostLoadStep1Lane.swift
//  EusoTrip — Shipper · Post-a-Load · Step 1 LANE.
//
//  First step of the wizard. Origin + destination + pickup window.
//  Bound to the shared `PostLoadDraft`. "Continue" advances to 251
//  Equipment via NotificationCenter screen-swap.
//

import SwiftUI

struct PostLoadStep1LaneScreen: View {
    let theme: Theme.Palette
    @StateObject var draft = PostLoadDraft()

    var body: some View {
        Shell(theme: theme) {
            PostLoadStep1Body(draft: draft)
        } nav: {
            shipperLifecycleNav()
        }
    }
}

private struct PostLoadStep1Body: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                fieldsCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("POST A LOAD · STEP 1 · LANE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text("Where is the freight going?")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text("Enter origin, destination, and the pickup window.")
                .font(EType.body).foregroundStyle(palette.textSecondary)
                .lineLimit(2).minimumScaleFactor(0.85)
        }
    }

    private var fieldsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LANE", icon: "map")
            // Origin / destination use HereAddressField so the user gets
            // typeahead suggestions from the HERE Geocoding API and can
            // also paste raw coordinates ("32.7767,-96.7970") — the way
            // truckers capture pickup/delivery for unaddressed sites
            // (oilfield pads, agricultural lots, port slips). Coords
            // ride along to `shippers.create` so distance + map render
            // without a second-pass server geocode.
            field(label: "Origin") {
                HereAddressField(
                    text: $draft.origin,
                    lat:  $draft.originLat,
                    lng:  $draft.originLng,
                    placeholder: "City, ST or lat,lng"
                )
            }
            field(label: "Destination") {
                HereAddressField(
                    text: $draft.destination,
                    lat:  $draft.destLat,
                    lng:  $draft.destLng,
                    placeholder: "City, ST or lat,lng"
                )
            }
            field(label: "Pickup window") {
                DatePicker("", selection: Binding(
                    get: { draft.pickupDate ?? Date() },
                    set: { draft.pickupDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
            }
            field(label: "Delivery window (optional)") {
                DatePicker("", selection: Binding(
                    get: { draft.deliveryDate ?? Date().addingTimeInterval(86400) },
                    set: { draft.deliveryDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func field<Inner: View>(label: String, @ViewBuilder content: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            content()
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "256"])
            } label: {
                Text("Multi-stop / address book").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(palette.tintNeutral).clipShape(Capsule())
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "251"])
            } label: {
                Text("Continue").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }
}

#Preview("250 · Lane · Night") {
    PostLoadStep1LaneScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("250 · Lane · Afternoon") {
    PostLoadStep1LaneScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
