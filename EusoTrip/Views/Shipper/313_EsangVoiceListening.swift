//
//  313_EsangVoiceListening.swift
//  EusoTrip — Shipper · ESang · Voice listening (Arc I).
//

import SwiftUI
import AVFoundation

struct EsangVoiceListeningScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VoiceListeningBody() } nav: { shipperLifecycleNav() }
    }
}

private struct VoiceListeningBody: View {
    @Environment(\.palette) private var palette
    @State private var pulse: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.s4) {
            Spacer()
            ZStack {
                Circle().stroke(LinearGradient.diagonal, lineWidth: 2)
                    .frame(width: pulse ? 220 : 160, height: pulse ? 220 : 160)
                    .opacity(pulse ? 0.0 : 0.7)
                Circle().fill(LinearGradient.diagonal).frame(width: 120, height: 120)
                    .shadow(color: Brand.gradientEnd.opacity(0.5), radius: 20)
                Image(systemName: "mic.fill").font(.system(size: 44, weight: .heavy)).foregroundStyle(.white)
            }
            Text("Listening…").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Ask anything: 'Where's my UN1203 load?', 'Take Eusotrans LLC at $2,150', 'Post a load Houston to Dallas.'")
                .font(EType.caption).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 32)
            Spacer()
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "314"])
            } label: {
                Text("Stop & transcribe").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse.toggle() }
        }
    }
}

#Preview("313 · Listening · Night") { EsangVoiceListeningScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("313 · Listening · Afternoon") { EsangVoiceListeningScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
