//
//  HazmatEscortView.swift
//  EusoTrip Watch App
//
//  Phase 3 — escort status for a hazmat load. Decodes the REAL
//  `hazmatEscort.getStatus` contract (routers/hazmatEscort.ts:76-124):
//  `active` is an OBJECT (assignmentId, loadId, position, status,
//  startedAt, nextCheckInAt, load{loadNumber, hazmatClass, unNumber,
//  origin/dest city+state}) or null when idle. "Check In" sends the
//  required { assignmentId, lat, lon } (hazmatEscort.ts:130-137) and
//  surfaces failures loudly — a hazmat check-in must never silently
//  vanish.
//

import SwiftUI
import Combine
import WatchKit
import CoreLocation

struct HazmatEscortView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = HazmatEscortStore()
    @State private var checkingIn = false

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

                if let err = store.lastError, !store.hasLoadedOnce {
                    errorCard(err)
                } else if let escort = store.assigned {
                    assignedCard(escort)
                } else if store.hasLoadedOnce {
                    unassignedCard
                } else {
                    loadingCard
                }

                if let note = store.checkInNote {
                    Text(note)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(store.checkInFailed ? Color.esangDanger : Color.esangGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                }

                // Check In only renders when a live assignment exists —
                // the server requires its assignmentId, so an unassigned
                // escort tapping a dead button was pure theater.
                if store.assigned != nil {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        guard !checkingIn else { return }
                        checkingIn = true
                        Task {
                            await store.checkIn(auth: auth)
                            checkingIn = false
                        }
                    } label: {
                        Label(checkingIn ? "Checking in…" : "Check In",
                              systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(LinearGradient.esangSuccess, in: RoundedRectangle(cornerRadius: R.sm))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(checkingIn)
                }

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
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Task { await store.refresh(auth: auth) }
        }
        // Clip full-width action buttons and the success-gradient
        // "Check In" row to the bezel so they don't poke into the
        // curved corners.
        .clipShape(ContainerRelativeShape())
    }

    private var statusCard: some View {
        HStack {
            Circle()
                .fill(store.assigned != nil ? Color.esangGreen : Color.esangAmber)
                .frame(width: 8, height: 8)
            Text(store.assigned != nil ? "Active" : "Standby")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(store.assigned?.position?.uppercased() ?? "—")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    @ViewBuilder
    private func assignedCard(_ e: EscortAssignment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ASSIGNED LOAD")
                .font(.system(size: 8, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "truck.box.fill")
                    .foregroundStyle(Color.esangBlue)
                Text(e.loadNumber ?? "Load #\(e.loadId)")
                    .font(.system(size: 12, weight: .bold))
            }
            if let lane = e.lane {
                Text(lane)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                if let hazmat = e.hazmatLabel {
                    Text(hazmat)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.esangHazmat, in: Capsule())
                }
                Spacer()
                if let next = e.nextCheckInAt {
                    Text("Next check-in \(next, style: .relative)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.esangAmber)
                        .monospacedDigit()
                }
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

    private var loadingCard: some View {
        HStack(spacing: 4) {
            ProgressView().scaleEffect(0.7)
            Text("Loading…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
    }

    private func errorCard(_ err: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.esangAmber)
            Text(err)
                .font(.system(size: 9, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: R.sm))
    }
}

/// The live escort assignment, decoded from the REAL server contract.
struct EscortAssignment: Equatable {
    let assignmentId: Int
    let loadId: Int
    let position: String?
    let status: String?
    let nextCheckInAt: Date?
    let loadNumber: String?
    let lane: String?
    let hazmatLabel: String?
}

@MainActor
final class HazmatEscortStore: NSObject, ObservableObject {
    @Published var assigned: EscortAssignment?
    @Published var hasLoadedOnce = false
    @Published var lastError: String?
    @Published var checkInNote: String?
    @Published var checkInFailed = false

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else {
            lastError = "Sign in on your iPhone"
            return
        }
        do {
            let client = EsangClient(auth: auth)
            let data = try await client.queryJSON("hazmatEscort.getStatus")
            struct LoadInfo: Decodable {
                let id: Int?
                let loadNumber: String?
                let originCity: String?
                let originState: String?
                let destCity: String?
                let destState: String?
                let hazmatClass: String?
                let unNumber: String?
            }
            struct Active: Decodable {
                let assignmentId: Int
                let loadId: Int
                let position: String?
                let status: String?
                let startedAt: String?
                let nextCheckInAt: String?
                let load: LoadInfo?
            }
            struct Status: Decodable { let active: Active? }
            let env = try JSONDecoder().decode(TRPCEnvelope<Status>.self, from: data)
            if let a = env.result.data.json.active {
                let lane: String? = {
                    let from = [a.load?.originCity, a.load?.originState]
                        .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
                    let to = [a.load?.destCity, a.load?.destState]
                        .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
                    guard !from.isEmpty || !to.isEmpty else { return nil }
                    return "\(from) → \(to)"
                }()
                let hazmat: String? = {
                    let parts = [a.load?.hazmatClass.map { "Class \($0)" },
                                 a.load?.unNumber].compactMap { $0 }
                    return parts.isEmpty ? nil : parts.joined(separator: " · ")
                }()
                assigned = EscortAssignment(
                    assignmentId: a.assignmentId,
                    loadId: a.loadId,
                    position: a.position,
                    status: a.status,
                    nextCheckInAt: ISO8601DateFormatter.iso.date(from: a.nextCheckInAt ?? ""),
                    loadNumber: a.load?.loadNumber,
                    lane: lane,
                    hazmatLabel: hazmat
                )
            } else {
                assigned = nil
            }
            hasLoadedOnce = true
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? "Can't reach escort status"
        }
    }

    /// Records a check-in waypoint with the REQUIRED { assignmentId,
    /// lat, lon } payload. Failure is loud — an error note, never a
    /// silent dismiss reading as success.
    func checkIn(auth: AuthStore) async {
        guard let assignment = assigned else { return }
        guard let coord = locationManager.location?.coordinate else {
            checkInFailed = true
            checkInNote = "No GPS fix yet — try again in a moment."
            WKInterfaceDevice.current().play(.failure)
            return
        }
        do {
            _ = try await EsangClient(auth: auth).mutateJSON(
                "hazmatEscort.checkIn",
                input: [
                    "assignmentId": assignment.assignmentId,
                    "lat": coord.latitude,
                    "lon": coord.longitude,
                    "note": "Checked in from EusoTrip Pulse"
                ]
            )
            checkInFailed = false
            checkInNote = "Checked in ✓"
            WKInterfaceDevice.current().play(.success)
            await refresh(auth: auth) // slide the next-check-in deadline
        } catch {
            checkInFailed = true
            checkInNote = "Check-in didn't reach the coordinator — try again."
            WKInterfaceDevice.current().play(.failure)
        }
    }
}

#Preview("Hazmat escort — Dark") {
    HazmatEscortView()
        .environmentObject(AuthStore.preview)
        .environmentObject(WatchConnectivityManager.shared)
        .preferredColorScheme(.dark)
}

#Preview("Hazmat escort — Light") {
    HazmatEscortView()
        .environmentObject(AuthStore.preview)
        .environmentObject(WatchConnectivityManager.shared)
        .preferredColorScheme(.light)
}
