//
//  363_MicPermission.swift
//  EusoTrip — Shipper · Microphone permission (Arc M).
//

import SwiftUI
import AVFoundation

struct MicPermissionScreen: View {
    let theme: Theme.Palette
    var body: some View {
        PermissionRationaleScreen(
            theme: theme,
            title: "Microphone",
            eyebrow: "Shipper · Mic",
            icon: "mic.fill",
            message: "Microphone access powers ESang voice — ask 'Where's my UN1203 load?' or 'Take Eusotrans LLC at $2,150' from anywhere.",
            bullets: [
                "ESang voice queries on the go",
                "Hold-to-talk dispatch chat",
                "Voice rate-confirm read-back",
                "Audio is transcribed on-device or via secured Gemini channel",
            ],
            onGrant: {
                AVAudioApplication.requestRecordPermission { _ in }
            }
        )
    }
}

#Preview("363 · Mic · Night") { MicPermissionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("363 · Mic · Afternoon") { MicPermissionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
