//
//  ShipperShipmentsView.swift
//  EusoTrip Watch App
//
//  Shipper persona — active outbound shipments with ETA status and a
//  glance at any in-flight exceptions. Tap-to-hand-off to the iPhone
//  for detailed tracking.
//

import SwiftUI
import WatchKit

struct ShipperShipment: Identifiable, Equatable {
    let id: String
    let displayId: String
    let lane: String
    let eta: Date?
    let status: String     // in_transit / delivered / delayed / loading
    let exception: String?
}

@MainActor
final class ShipperShipmentsStore: ObservableObject {
    static let shared = ShipperShipmentsStore()
    @Published var shipments: [ShipperShipment] = [
        .init(id: "s1", displayId: "SH-91204", lane: "MEM → JAX",
              eta: Date().addingTimeInterval(3600 * 4),
              status: "in_transit", exception: nil),
        .init(id: "s2", displayId: "SH-91189", lane: "SEA → BOI",
              eta: Date().addingTimeInterval(3600 * 9),
              status: "delayed", exception: "Weather hold on I-84"),
        .init(id: "s3", displayId: "SH-91141", lane: "NYC → BOS",
              eta: Date().addingTimeInterval(-60 * 30),
              status: "delivered", exception: nil)
    ]

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else { return }
        do {
            let client = EsangClient(auth: auth)
            let data = try await client.queryJSON("shipments.listActive", input: ["limit": 10])
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: [RemoteShipment]
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            struct RemoteShipment: Decodable {
                let id: String
                let displayId: String?
                let lane: String?
                let eta: String?
                let status: String?
                let exception: String?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            shipments = env.result.data.json.map {
                ShipperShipment(
                    id: $0.id,
                    displayId: $0.displayId ?? $0.id,
                    lane: $0.lane ?? "",
                    eta: ISO8601DateFormatter.iso.date(from: $0.eta ?? ""),
                    status: $0.status ?? "in_transit",
                    exception: $0.exception
                )
            }
        } catch {}
    }
}

struct ShipperShipmentsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @StateObject private var store = ShipperShipmentsStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: S.s1) {
                if store.shipments.isEmpty {
                    Text("No active shipments.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    ForEach(store.shipments) { s in
                        shipmentRow(s)
                    }
                }
                Button {
                    WKInterfaceDevice.current().play(.click)
                    connectivity.requestPhoneActivation(
                        transcript: "open shipments",
                        reply: "Opening shipments on your iPhone."
                    )
                } label: {
                    Label("Open on iPhone", systemImage: "iphone.and.arrow.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(LinearGradient.esangPrimary, in: RoundedRectangle(cornerRadius: R.sm))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.vertical, S.s1)
            .padding(.horizontal, S.s2)
        }
        .navigationTitle("Shipments")
        .task { await store.refresh(auth: auth) }
    }

    @ViewBuilder
    private func shipmentRow(_ s: ShipperShipment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(s.displayId).font(.system(size: 10, weight: .bold))
                Spacer()
                statusPill(s.status)
            }
            Text(s.lane)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let eta = s.eta {
                Text("ETA \(eta, style: .relative)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            if let ex = s.exception {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.esangAmber)
                    Text(ex)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.esangAmber)
                        .lineLimit(1)
                }
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    @ViewBuilder
    private func statusPill(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status.lowercased() {
            case "delivered": return ("Delivered", .esangGreen)
            case "delayed": return ("Delayed", .esangDanger)
            case "loading": return ("Loading", .esangAmber)
            default: return ("In Transit", .esangBlue)
            }
        }()
        Text(label)
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
    }
}
