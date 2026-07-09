//
//  ShipperShipmentsView.swift
//  EusoTrip Watch App
//
//  Shipper persona — active outbound shipments with ETA status and a
//  glance at any in-flight exceptions. Tap-to-hand-off to the iPhone
//  for detailed tracking.
//

import SwiftUI
import Combine
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
    /// No seed data. Doctrine: no mocks, no fake shipments. Empty
    /// until `shipments.listActive` answers; `lastError` surfaces a
    /// banner if the call fails so the shipper can't confuse "loading"
    /// with "empty."
    @Published var shipments: [ShipperShipment] = []
    @Published var hasLoadedOnce: Bool = false
    @Published var lastError: String?

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else {
            lastError = "Sign in on your iPhone"
            return
        }
        do {
            let client = EsangClient(auth: auth)
            let data = try await client.queryJSON("shipments.listActive", input: ["limit": 10])
            // REAL server contract (routers/shipments.ts:93-105): the
            // rows ride inside a { shipments: [...] } wrapper with
            // { id, title, status(bucket), pickupCity, destCity,
            //   updatedAt, eta }. The previous bare-array decode threw
            // a typeMismatch on EVERY response, so the shipper board
            // could never show data.
            struct Wrapper: Decodable {
                let shipments: [RemoteShipment]
            }
            struct RemoteShipment: Decodable {
                let id: String
                let title: String?
                let status: String?
                let pickupCity: String?
                let destCity: String?
                let eta: String?
            }
            let env = try JSONDecoder().decode(TRPCEnvelope<Wrapper>.self, from: data)
            shipments = env.result.data.json.shipments.map { s in
                let lane = [s.pickupCity, s.destCity]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " → ")
                return ShipperShipment(
                    id: s.id,
                    displayId: s.title ?? "Shipment #\(s.id)",
                    lane: lane,
                    eta: ISO8601DateFormatter.iso.date(from: s.eta ?? ""),
                    status: s.status ?? "in_transit",
                    exception: (s.status ?? "").lowercased() == "delayed" ? "Running behind schedule" : nil
                )
            }
            hasLoadedOnce = true
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Can't reach shipments"
        }
    }
}

struct ShipperShipmentsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @StateObject private var store = ShipperShipmentsStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: S.s1) {
                // Honest state ladder — an error can never present as
                // "No active shipments." (lastError/hasLoadedOnce were
                // published but never read before this fix).
                if let err = store.lastError, !store.hasLoadedOnce {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.esangAmber)
                        Text(err)
                            .font(.system(size: 9, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                    .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: R.sm))
                } else if store.shipments.isEmpty && store.hasLoadedOnce {
                    Text("No active shipments.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else if store.shipments.isEmpty {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading…")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
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
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Task { await store.refresh(auth: auth) }
        }
        // Clip shipment status pills and the brand-gradient "Open on
        // iPhone" footer button to the rounded bezel so they can't
        // show through the corner radius.
        .clipShape(ContainerRelativeShape())
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
