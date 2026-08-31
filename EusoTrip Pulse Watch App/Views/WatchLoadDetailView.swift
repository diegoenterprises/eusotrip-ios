//
//  WatchLoadDetailView.swift
//  EusoTrip Watch App
//
//  Detail sheet for a single load. Accept / decline / log-arrival /
//  navigate actions live here.
//

import SwiftUI
import WatchKit

struct WatchLoadDetailView: View {
    let loadId: String

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var loads: LoadStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @Environment(\.dismiss) private var dismiss

    /// Honest action lifecycle — replaces the old instant
    /// enqueue-and-dismiss which read as success even when the
    /// underlying proc 404'd forever.
    @State private var isSending = false
    @State private var statusNote: String?

    var body: some View {
        // Never fall back to a synthetic load — if the ID isn't in the
        // store (active + upcoming), render an empty state that nudges
        // the driver back to the home page instead of showing fake data.
        let resolved: WatchLoad? = {
            if loads.active?.id == loadId { return loads.active }
            return loads.upcoming.first(where: { $0.id == loadId })
        }()
        guard let load = resolved else {
            return AnyView(emptyState)
        }
        return AnyView(detail(for: load))
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "shippingbox")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(LinearGradient.esangPrimary)
            Text("Load not on wrist")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            if let note = statusNote {
                Text(note)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            } else {
                // Working affordance — the old copy told the driver to
                // open the iPhone app but nothing here could make that
                // happen. This wakes the phone in the background; the
                // phone posts the one-tap "Open EusoTrip" notification.
                Button {
                    let dispatch = connectivity.requestPhoneActivation(
                        transcript: "open eusotrip home",
                        reply: "Opening EusoTrip on your iPhone.",
                        destination: .home
                    )
                    switch dispatch {
                    case .sent:
                        statusNote = "Sent - tap the EusoTrip notification on your iPhone."
                    case .queued:
                        statusNote = "Queued for your iPhone."
                    case .unavailable:
                        statusNote = "iPhone bridge unavailable - bring it nearby and try again."
                    }
                } label: {
                    Label("Open on iPhone", systemImage: "iphone.and.arrow.forward")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.esangBlue)
                .controlSize(.mini)
            }
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .padding(.top, 2)
        }
        .padding()
        // Handoff — while this dead-end is visible, put the EusoTrip
        // icon in the iPhone App Switcher / lock screen for instant open.
        .userActivity(EusoTripConfig.handoffActivityType, isActive: true) { activity in
            activity.title = "Open EusoTrip"
            activity.userInfo = ["transcript": ""]
            activity.isEligibleForHandoff = true
        }
    }

    @ViewBuilder
    private func detail(for load: WatchLoad) -> some View {
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
                row("Pickup",   load.pickupAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                row("Deliver",  load.deliverBy.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")

                VStack(spacing: S.s1) {
                    if let note = statusNote {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.esangAmber)
                            Text(note)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.esangAmber)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.esangAmber.opacity(0.15), in: RoundedRectangle(cornerRadius: R.sm))
                    }
                    actionButton(label: "Accept", systemImage: "checkmark.circle.fill", gradient: .esangSuccess) {
                        // Driver-side accept → drivers.acceptLoad
                        perform { OfflineQueue.shared.enqueueAcceptLoad(loadId: load.id, bidId: nil) }
                    }
                    actionButton(label: "I'm at pickup", systemImage: "mappin.circle.fill", gradient: .esangPrimary) {
                        // loads.updateLoadStatus → at_pickup
                        perform { OfflineQueue.shared.enqueueArrived(loadId: load.id, kind: "pickup", at: Date()) }
                    }
                    actionButton(label: "Delivered", systemImage: "shippingbox.and.arrow.backward.fill", gradient: .esangSuccess) {
                        // loads.updateLoadStatus → delivered
                        perform { OfflineQueue.shared.enqueueArrived(loadId: load.id, kind: "delivered", at: Date()) }
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
                .opacity(isSending ? 0.5 : 1)
                .disabled(isSending)
            }
            .padding(S.s2)
        }
        .navigationTitle(load.displayId)
        // Gradient action buttons at the bottom of the detail card
        // could flash into the corner curve when the ScrollView
        // overscrolls; clip to the bezel to prevent it.
        .clipShape(ContainerRelativeShape())
    }

    /// Enqueue an action, flush the outbox, then report the TRUTH:
    /// entry drained → success haptic + dismiss; entry still queued →
    /// keep the sheet up with an amber "queued" note (retry haptic).
    /// A dead endpoint can no longer masquerade as a done deal.
    private func perform(_ enqueue: @escaping () -> String) {
        guard !isSending else { return }
        isSending = true
        statusNote = nil
        WKInterfaceDevice.current().play(.click)
        let key = enqueue()
        Task {
            await OfflineQueue.shared.flush(auth: auth)
            if OfflineQueue.shared.isPending(key) {
                isSending = false
                statusNote = OfflineQueue.shared.lastError(for: key) == nil
                    ? "Queued — will send when you're back online."
                    : "Couldn't reach EusoTrip — queued for retry."
                WKInterfaceDevice.current().play(.retry)
            } else {
                WKInterfaceDevice.current().play(.success)
                dismiss()
            }
        }
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
