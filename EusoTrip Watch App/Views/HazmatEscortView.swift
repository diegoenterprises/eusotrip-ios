//
//  HazmatEscortView.swift
//  EusoTrip Watch App
//
//  Phase 3 — escort status for a hazmat load. Shows the nearest escort
//  vehicle's distance + ETA plus a "Check in" button that pings the
//  escort coordinator. Spec §12.4 (hazmat escort protocol).
//

import SwiftUI
import WatchKit

struct HazmatEscortView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = HazmatEscortStore()

    var body: some View {
        ScrollView {
            VStack(spacing: S.s2) {
                HStack(spacing: 4) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(Color.esangHazmat)
                    Text("HAZMAT ESCORT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                }
                .padding(.top, 2)

                statusCard

                if let escort = store.assigned {
                    assignedCard(escort)
                } else {
                    unassignedCard
                }

                Button {
                    WKInterfaceDevice.current().play(.click)
                    Task {
                        _ = try? await EsangClient(auth: auth).mutateJSON(
                            "hazmatEscort.checkIn",
                            input: ["source": "watch"]
                        )
                        dismiss()
                    }
                } label: {
                    Label("Check In", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(LinearGradient.esangSuccess, in: RoundedRectangle(cornerRadius: R.sm))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    connectivity.requestPhoneActivation(
                        transcript: "open escort coordinator",
                        reply: "Opening escort coordinator on your iPhone."
                    )
                    dismiss()
                } label: {
                    Label("Coordinator on iPhone", systemImage: "iphone.and.arrow.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(Color.esangBlue, in: RoundedRectangle(cornerRadius: R.sm))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(S.s2)
        }
        .navigationTitle("Escort")
        .task { await store.refresh(auth: auth) }
    }

    private var statusCard: some View {
        HStack {
            Circle()
                .fill(store.active ? Color.esangGreen : Color.esangAmber)
                .frame(width: 8, height: 8)
            Text(store.active ? "Active" : "Standby")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(store.protocolCode ?? "—")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    @ViewBuilder
    private func assignedCard(_ e: EscortAssignment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ASSIGNED UNIT")
                .font(.system(size: 8, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "car.fill")
                    .foregroundStyle(Color.esangBlue)
                Text(e.callSign)
                    .font(.system(size: 12, weight: .bold))
            }
            HStack {
                Text("\(e.distanceMiles) mi")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("ETA \(e.etaMinutes)m")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    private var unassignedCard: some View {
        VStack(spacing: 3) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 18))
                .foregroundStyle(Color.esangAmber)
            Text("Awaiting escort assignment")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }
}

struct EscortAssignment: Equatable {
    let callSign: String
    let distanceMiles: Int
    let etaMinutes: Int
}

@MainActor
final class HazmatEscortStore: ObservableObject {
    @Published var active: Bool = false
    @Published var protocolCode: String?
    @Published var assigned: EscortAssignment?

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else { return }
        do {
            let client = EsangClient(auth: auth)
            let data = try await client.queryJSON("hazmatEscort.getStatus")
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: Status
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            struct Status: Decodable {
                let active: Bool?
                let protocolCode: String?
                let callSign: String?
                let distanceMiles: Int?
                let etaMinutes: Int?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            let s = env.result.data.json
            active = s.active ?? false
            protocolCode = s.protocolCode
            if let call = s.callSign, let dist = s.distanceMiles, let eta = s.etaMinutes {
                assigned = EscortAssignment(callSign: call, distanceMiles: dist, etaMinutes: eta)
            } else {
                assigned = nil
            }
        } catch {}
    }
}
