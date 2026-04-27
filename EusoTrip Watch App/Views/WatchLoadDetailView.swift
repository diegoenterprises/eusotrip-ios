//
//  WatchLoadDetailView.swift
//  EusoTrip Watch App
//
//  Detail sheet for a single load. Accept / decline / log-arrival /
//  navigate actions live here.
//

import SwiftUI

struct WatchLoadDetailView: View {
    let loadId: String

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var loads: LoadStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let load = loads.active?.id == loadId ? loads.active! : (loads.upcoming.first(where: { $0.id == loadId }) ?? WatchLoad.placeholder)
        ScrollView {
            VStack(alignment: .leading, spacing: S.s2) {
                HStack {
                    Text(load.displayId).font(.system(size: 14, weight: .bold))
                    Spacer()
                    if load.hazmat {
                        Text("HAZMAT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.esangHazmat, in: Capsule())
                    }
                }
                Text("\(load.originShort) → \(load.destShort)")
                    .font(.system(size: 14, weight: .semibold))
                Divider().background(Color.esangBorder)
                row("Rate",      load.totalRate.map { "$\(Int($0))" } ?? "—")
                row("Miles",     load.miles.map { "\(Int($0))" } ?? "—")
                row("$/mi",      load.ratePerMile.map { String(format: "$%.2f", $0) } ?? "—")
                if let t = load.temperatureF {
                    row("Temp",  "\(t)°F")
                }
                row("Equipment", load.equipment?.replacingOccurrences(of: "_", with: " ") ?? "—")
                if let broker = load.brokerName {
                    row("Broker",  broker)
                }
                row("Pickup",   load.pickupAt.formatted(date: .abbreviated, time: .shortened))
                row("Deliver",  load.deliverBy.formatted(date: .abbreviated, time: .shortened))

                VStack(spacing: S.s1) {
                    actionButton(label: "Accept", systemImage: "checkmark.circle.fill", gradient: .esangSuccess) {
                        OfflineQueue.shared.enqueueAcceptLoad(loadId: load.id, bidId: nil)
                        Task { await OfflineQueue.shared.flush(auth: auth) }
                        dismiss()
                    }
                    actionButton(label: "I'm at pickup", systemImage: "mappin.circle.fill", gradient: .esangPrimary) {
                        OfflineQueue.shared.enqueueArrived(loadId: load.id, kind: "pickup", at: Date())
                        Task { await OfflineQueue.shared.flush(auth: auth) }
                        dismiss()
                    }
                    actionButton(label: "Delivered", systemImage: "shippingbox.and.arrow.backward.fill", gradient: .esangSuccess) {
                        OfflineQueue.shared.enqueueArrived(loadId: load.id, kind: "delivery", at: Date())
                        Task { await OfflineQueue.shared.flush(auth: auth) }
                        dismiss()
                    }
                    actionButton(label: "Navigate on iPhone", systemImage: "map.fill", gradient: .esangPrimary) {
                        connectivity.requestPhoneActivation(
                            transcript: "navigate to \(load.destShort)",
                            reply: "Opening Maps on your iPhone."
                        )
                        dismiss()
                    }
                }
                .padding(.top, 4)
            }
            .padding(S.s2)
        }
        .navigationTitle(load.displayId)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func actionButton(label: String, systemImage: String, gradient: LinearGradient, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(gradient, in: RoundedRectangle(cornerRadius: R.sm))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
