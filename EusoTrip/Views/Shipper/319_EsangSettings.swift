//
//  319_eSangSettings.swift
//  EusoTrip — Shipper · eSang · Settings (Arc I).
//

import SwiftUI

struct eSangSettingsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { eSangSettingsBody() } nav: { shipperLifecycleNav() }
    }
}

private struct eSangSettingsBody: View {
    @Environment(\.palette) private var palette
    @State private var voiceProfile: String = "Diego"
    @State private var language: String = "en-US"
    @State private var dndStart: Date = Date()
    @State private var dndEnd: Date = Date().addingTimeInterval(28800)
    @State private var voiceEnabled: Bool = true
    @State private var pushEnabled: Bool = true
    @State private var sending: Bool = false
    @State private var saved: Bool = false

    private let languages = ["en-US", "es-MX", "fr-CA", "pt-BR"]
    private let voiceProfiles = ["Diego", "Eusorone classic", "Pacific", "Heartland"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if saved { LifecycleCard(accentGradient: true) { Text("Saved.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                voiceCard
                languageCard
                dndCard
                channelsCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ESANG · SETTINGS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("eSang preferences").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var voiceCard: some View {
        LifecycleCard {
            LifecycleSection(label: "VOICE PROFILE", icon: "waveform")
            Picker("", selection: $voiceProfile) { ForEach(voiceProfiles, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu).labelsHidden()
        }
    }

    private var languageCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LANGUAGE", icon: "globe")
            Picker("", selection: $language) { ForEach(languages, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu).labelsHidden()
        }
    }

    private var dndCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DO-NOT-DISTURB WINDOW", icon: "moon.fill")
            HStack {
                DatePicker("", selection: $dndStart, displayedComponents: [.hourAndMinute]).labelsHidden()
                Text("→").foregroundStyle(palette.textTertiary)
                DatePicker("", selection: $dndEnd, displayedComponents: [.hourAndMinute]).labelsHidden()
            }
        }
    }

    private var channelsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CHANNELS", icon: "bell")
            Toggle("Voice", isOn: $voiceEnabled).font(EType.body)
            Toggle("Push", isOn: $pushEnabled).font(EType.body)
        }
    }

    private var ctaRow: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Saving…" : "Save").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending)
    }

    private func load() async {
        struct Out: Decodable {
            let voiceProfile: String?
            let language: String?
            let dndStart: String?
            let dndEnd: String?
            let voiceEnabled: Bool?
            let pushEnabled: Bool?
        }
        do {
            let s: Out = try await EusoTripAPI.shared.queryNoInput("esangAI.getPreferences")
            voiceProfile = s.voiceProfile ?? voiceProfile
            language = s.language ?? language
            voiceEnabled = s.voiceEnabled ?? voiceEnabled
            pushEnabled = s.pushEnabled ?? pushEnabled
        } catch { /* tolerate missing endpoint */ }
    }

    private func save() async {
        sending = true
        struct In: Encodable {
            let voiceProfile: String; let language: String; let voiceEnabled: Bool; let pushEnabled: Bool
        }
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("esangAI.savePreferences", input: In(voiceProfile: voiceProfile, language: language, voiceEnabled: voiceEnabled, pushEnabled: pushEnabled))
            saved = true
        } catch { /* surface inline */ }
        sending = false
    }
}

#Preview("319 · eSang settings · Night") { eSangSettingsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("319 · eSang settings · Afternoon") { eSangSettingsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
