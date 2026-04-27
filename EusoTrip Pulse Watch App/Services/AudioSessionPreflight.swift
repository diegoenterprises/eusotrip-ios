//
//  AudioSessionPreflight.swift
//  EusoTrip Pulse Watch App
//
//  L4 — audio route preflight. Before AVAudioEngine.start() is called
//  from EsangSession.startListening, verify the AVAudioSession can
//  actually transition into .playAndRecord. On watchOS 26.4, a route
//  held by HKWorkoutSession (the DrivingSessionManager background
//  session) can silently refuse the activation and the subsequent
//  installTap(onBus:) call gets a 0-channel format, which is an
//  Objective-C exception on the wrist — not a Swift throw. Diagnosing
//  that from the driver's wrist required this surface.
//
//  The preflight:
//    1. Requests .playAndRecord / .spokenAudio with HFP allowed.
//    2. Activates the session with .notifyOthersOnDeactivation so a
//       running Workout builder yields its audio route gracefully.
//    3. On failure, throws EsangError.audioRouteUnavailable so the
//       caller surfaces a hint-card error instead of installing a tap
//       onto a format with channelCount == 0.
//

import Foundation
import AVFoundation

enum AudioSessionPreflight {
    /// Throws EsangError.audioRouteUnavailable if the session cannot be
    /// activated for voice capture. Always safe to call — idempotent.
    static func check() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            // .spokenAudio mode + HFP so Bluetooth headsets + car
            // systems can carry the mic path. duckOthers so any music
            // on the phone / car stereo dips during capture.
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.duckOthers, .allowBluetoothHFP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            OrbLog.info("audio.preflight ok route=\(session.currentRoute.outputs.map(\.portName))")
        } catch {
            OrbLog.audio("preflight failed: \(error.localizedDescription)")
            throw EsangError.audioRouteUnavailable
        }
    }
}
