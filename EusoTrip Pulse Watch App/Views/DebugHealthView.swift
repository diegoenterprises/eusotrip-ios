//
//  DebugHealthView.swift
//  EusoTrip Pulse Watch App
//
//  L5c — triple-tap health overlay. When the driver reports "orb is
//  dead," we need evidence: what permission state did the wrist see,
//  was WCSession reachable, how deep is the OfflineQueue, what was the
//  last OrbLog entry? This overlay surfaces all of it on-device and
//  ships a JSON diagnostic bundle to the iPhone pasteboard for support.
//
//  Surfaced via triple-tap on the time label (InstrumentPanel) in
//  DEBUG / TestFlight builds.
//

import SwiftUI
import WatchKit
import WatchConnectivity
import AVFoundation
#if canImport(Speech)
import Speech
#endif

struct DebugHealthView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var esang: EsangSession
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @ObservedObject private var orb = OrbStateMachine.shared
    @ObservedObject private var buffer = OrbLogBuffer.shared
    @ObservedObject private var queue = OfflineQueue.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                row("AUTH", auth.isSignedIn ? "signed-in" : "unpaired")
                row("WC",   connectivity.isReachable ? "reachable" : "offline")
                row("NET",  orb.networkReachable ? "reachable" : "offline")
                row("MIC",  micStatus)
                row("SPEECH", speechStatus)
                row("AUDIO", audioRoute)
                row("QUEUE", queueSummary)
                if let err = lastError {
                    row("LAST-ERROR", err)
                }

                Divider().padding(.vertical, 2)

                Text("Events")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.65))

                ForEach(buffer.events.reversed()) { ev in
                    HStack(alignment: .top, spacing: 4) {
                        Text(format(ev.at))
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                        Text(ev.level.uppercased())
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundStyle(tint(for: ev.level))
                            .frame(width: 30, alignment: .leading)
                        Text(ev.message)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(3)
                            .minimumScaleFactor(0.85)
                    }
                }

                Button {
                    copyDiag()
                } label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text("Copy Diag")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.esangBlue.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.esangBlue.opacity(0.6), lineWidth: 0.8)
                            )
                    )
                    .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .navigationTitle("Debug")
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ key: String, _ val: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 52, alignment: .leading)
            Text(val)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
        }
    }

    private var micStatus: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:     return "granted"
        case .denied:      return "denied"
        case .undetermined: return "not-determined"
        @unknown default:  return "unknown"
        }
    }

    private var speechStatus: String {
        #if canImport(Speech)
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:     return "authorized"
        case .denied:         return "denied"
        case .restricted:     return "restricted"
        case .notDetermined:  return "not-determined"
        @unknown default:     return "unknown"
        }
        #else
        return "n/a"
        #endif
    }

    private var audioRoute: String {
        AVAudioSession.sharedInstance().currentRoute
            .outputs.map(\.portName).joined(separator: ",")
    }

    private var queueSummary: String {
        let t = queue.entries.count
        let sos = queue.laneCount(.sos)
        let hos = queue.laneCount(.hos)
        let load = queue.laneCount(.load)
        let voice = queue.laneCount(.voice)
        let msg = queue.laneCount(.message)
        return "\(t) (sos=\(sos) hos=\(hos) ld=\(load) v=\(voice) m=\(msg))"
    }

    private var lastError: String? {
        if case .error(let msg) = esang.state { return msg }
        return nil
    }

    private func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    private func tint(for level: String) -> Color {
        switch level {
        case "error", "audio": return .esangDanger
        case "state":          return .esangMagenta
        case "tap":            return .esangBlue
        case "perm":           return .esangAmber
        default:               return .esangGreen
        }
    }

    private func copyDiag() {
        struct DiagBundle: Encodable {
            let ts: String
            let auth: Bool
            let wc: Bool
            let net: Bool
            let mic: String
            let speech: String
            let audio: String
            let queue: [String: Int]
            let state: String
            let lastError: String?
            let events: String
        }
        let f = ISO8601DateFormatter()
        let bundle = DiagBundle(
            ts: f.string(from: Date()),
            auth: auth.isSignedIn,
            wc: connectivity.isReachable,
            net: orb.networkReachable,
            mic: micStatus,
            speech: speechStatus,
            audio: audioRoute,
            queue: [
                "total": queue.entries.count,
                "sos": queue.laneCount(.sos),
                "hos": queue.laneCount(.hos),
                "load": queue.laneCount(.load),
                "voice": queue.laneCount(.voice),
                "message": queue.laneCount(.message),
            ],
            state: String(describing: esang.state),
            lastError: lastError,
            events: OrbLogBuffer.shared.jsonDump()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(bundle),
           let str = String(data: data, encoding: .utf8) {
            // watchOS has no UIPasteboard — forward to the phone via
            // WCSession so the driver can paste on iPhone and email
            // support (a.lynngambardella@gmail.com).
            let payload: [String: Any] = [
                "op": "debug.diag",
                "payload": str,
                "ts": Date().timeIntervalSince1970
            ]
            if WCSession.isSupported() {
                let session = WCSession.default
                if session.activationState == .activated {
                    if session.isReachable {
                        session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                            session.transferUserInfo(payload)
                        })
                    } else {
                        session.transferUserInfo(payload)
                    }
                }
            }
            WKInterfaceDevice.current().play(.success)
            OrbLog.info("diag.copy bytes=\(str.count)")
        }
    }
}
