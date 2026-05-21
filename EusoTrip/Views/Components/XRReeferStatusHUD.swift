//
//  XRReeferStatusHUD.swift
//  EusoTrip — IO 2026 Tier 1 #12 · XR Reefer Temp HUD
//
//  Compact live-polling card for reefer hauls. Hosts a server-driven
//  poll loop against `xrChecklist.streamReeferStatus` — server picks
//  the interval (30s when in breach, 120s otherwise) and we honor it.
//
//  When the breach flag transitions from false → true, the HUD plays
//  the server's `spokenStatus` line through ESangTTSPlayer so the
//  driver hears the alarm without looking down. Subsequent polls
//  while still in breach do NOT re-speak — only the transition.
//
//  Designed to slot inside 018_ActiveEnrouteLoaded (and any other
//  driver lifecycle screen where the cargo is reefer). Gated by the
//  parent on `ctx.product == .reefer` so dry-van/flatbed/container
//  loads don't render the card.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire model

struct XRReeferStatusPayload: Decodable, Hashable {
    let loadId: Int?
    let observedAt: String?
    let setpointF: Double?
    let returnAirF: Double?
    let supplyAirF: Double?
    let mode: String?
    let fuelLevelFraction: Double?
    let activeAlarms: [String]
    let breach: Bool
    let spokenStatus: String
    let recommendedPollIntervalSeconds: Int

    /// Treat an empty payload (no observation rows yet) as "idle".
    var hasObservation: Bool { setpointF != nil || returnAirF != nil }
}

struct XRReeferStatusInput: Encodable {
    let loadId: String
    let expectedSetpointF: Double?
}

// MARK: - Store

@MainActor
final class XRReeferStatusStore: ObservableObject {
    @Published var status: XRReeferStatusPayload?
    @Published var pollingActive: Bool = false
    @Published var lastError: String?

    private let loadId: String
    private let expectedSetpointF: Double?
    private var pollTask: Task<Void, Never>?
    private var lastBreach: Bool = false

    init(loadId: String, expectedSetpointF: Double? = nil) {
        self.loadId = loadId
        self.expectedSetpointF = expectedSetpointF
    }

    func startPolling() {
        guard pollTask == nil, !loadId.isEmpty else { return }
        pollingActive = true
        pollTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        pollingActive = false
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await refreshOnce()
            // Use server-recommended cadence — 30s in breach, 120s normal.
            let nextSeconds = max(15, status?.recommendedPollIntervalSeconds ?? 120)
            do {
                try await Task.sleep(nanoseconds: UInt64(nextSeconds) * 1_000_000_000)
            } catch {
                return
            }
        }
    }

    func refreshOnce() async {
        do {
            let payload = XRReeferStatusInput(
                loadId: loadId,
                expectedSetpointF: expectedSetpointF
            )
            let resp: XRReeferStatusPayload = try await EusoTripAPI.shared
                .xrChecklist.streamReeferStatus(input: payload)
            // Speak only on false → true transitions.
            if resp.breach && !lastBreach && !resp.spokenStatus.isEmpty {
                Task.detached { @MainActor in
                    await ESangTTSPlayer.shared.speak(resp.spokenStatus)
                }
            }
            lastBreach = resp.breach
            self.status = resp
            self.lastError = nil
        } catch {
            self.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - HUD card

public struct XRReeferStatusHUD: View {
    public let loadId: String
    public let expectedSetpointF: Double?

    public init(loadId: String, expectedSetpointF: Double? = nil) {
        self.loadId = loadId
        self.expectedSetpointF = expectedSetpointF
    }

    @StateObject private var store: XRReeferStatusStore

    public init(store: XRReeferStatusStore) {
        self.loadId = ""
        self.expectedSetpointF = nil
        _store = StateObject(wrappedValue: store)
    }

    public init(_loadId loadId: String, _expectedSetpointF: Double? = nil) {
        self.loadId = loadId
        self.expectedSetpointF = _expectedSetpointF
        _store = StateObject(wrappedValue: XRReeferStatusStore(
            loadId: loadId, expectedSetpointF: _expectedSetpointF
        ))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let s = store.status, s.hasObservation {
                statRow(s)
                if s.breach {
                    breachBanner(s)
                }
                if !s.activeAlarms.isEmpty {
                    alarmsList(s.activeAlarms)
                }
            } else if store.pollingActive {
                Text("Waiting for the first Astra reefer read…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if let err = store.lastError {
                Text(err).font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(currentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(currentColor.opacity(0.35), lineWidth: 0.5)
        )
        .task {
            store.startPolling()
        }
        .onDisappear {
            store.stopPolling()
        }
    }

    // MARK: subviews

    private var currentColor: Color {
        if store.status?.breach == true { return .red }
        if store.status?.hasObservation == true { return .green }
        return .secondary
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "thermometer.snowflake")
                .font(.caption.weight(.bold))
            Text("REEFER · LIVE")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
            Spacer()
            if store.pollingActive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(currentColor)
                        .frame(width: 6, height: 6)
                    Text(pollIntervalLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .foregroundStyle(.secondary)
    }

    private var pollIntervalLabel: String {
        let s = store.status?.recommendedPollIntervalSeconds ?? 120
        return "every \(s)s"
    }

    private func statRow(_ s: XRReeferStatusPayload) -> some View {
        HStack(spacing: 14) {
            stat(label: "SET",    value: tempLabel(s.setpointF))
            stat(label: "RETURN", value: tempLabel(s.returnAirF), highlight: s.breach)
            if let mode = s.mode, !mode.isEmpty {
                stat(label: "MODE", value: mode.replacingOccurrences(of: "_", with: " ").uppercased())
            }
            if let f = s.fuelLevelFraction, f >= 0 {
                stat(label: "FUEL", value: "\(Int(f * 100))%")
            }
        }
    }

    private func stat(label: String, value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold)).tracking(0.8)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.body.weight(.heavy).monospacedDigit())
                .foregroundStyle(highlight ? Color.red : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tempLabel(_ f: Double?) -> String {
        guard let f else { return "—" }
        return String(format: "%.1f°F", f)
    }

    private func breachBanner(_ s: XRReeferStatusPayload) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(s.spokenStatus.isEmpty ? "Reefer breach detected." : s.spokenStatus)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.10))
        )
    }

    private func alarmsList(_ alarms: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ACTIVE ALARMS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
            ForEach(alarms, id: \.self) { a in
                Text("• \(a)").font(.caption2).foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Previews

#Preview("Idle · Dark") {
    XRReeferStatusHUD(_loadId: "preview-only-no-poll")
        .padding(20)
        .preferredColorScheme(.dark)
}

#Preview("Idle · Light") {
    XRReeferStatusHUD(_loadId: "preview-only-no-poll")
        .padding(20)
        .preferredColorScheme(.light)
}
