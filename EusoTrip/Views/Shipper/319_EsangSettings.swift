//
//  319_eSangSettings.swift
//  EusoTrip — Shipper · eSang · Settings (Arc I).
//

import SwiftUI

private struct ESangVoiceOption: Decodable, Identifiable {
    let role: String
    let voiceId: String
    let name: String
    let gender: String
    let style: String?
    let region: String?

    var id: String { voiceId }
}

private struct ESangDialectOption: Decodable, Identifiable {
    let code: String
    let label: String
    let example: String

    var id: String { code }
}

private struct ESangPreferenceSnapshot: Decodable {
    let voiceProfile: String?
    let language: String?
    let voiceEnabled: Bool?
    let pushEnabled: Bool?
    let dndEnabled: Bool?
    let dndStart: String?
    let dndEnd: String?
    let timeZone: String?
    let updatedAt: String?
}

private enum ESangSettingsError: LocalizedError {
    case emptyVoiceCatalog
    case emptyDialectCatalog
    case invalidStoredTime
    case unverifiedWrite

    var errorDescription: String? {
        switch self {
        case .emptyVoiceCatalog:
            return "ESANG's voice catalog is unavailable. Nothing was changed - pull to refresh."
        case .emptyDialectCatalog:
            return "ESANG's language catalog is unavailable. Nothing was changed - pull to refresh."
        case .invalidStoredTime:
            return "The saved do-not-disturb window could not be read. Nothing was changed."
        case .unverifiedWrite:
            return "ESANG could not verify the saved settings. Nothing was reported as saved."
        }
    }
}

struct eSangSettingsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { eSangSettingsBody() } nav: { shipperLifecycleNav() }
    }
}

private struct eSangSettingsBody: View {
    @Environment(\.palette) private var palette
    @State private var voiceProfile: String = ""
    @State private var language: String = "system"
    @State private var dndStart: Date = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var dndEnd: Date = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var dndEnabled: Bool = false
    @State private var voiceEnabled: Bool = true
    @State private var pushEnabled: Bool = true
    @State private var sending: Bool = false
    @State private var loading: Bool = false
    @State private var saved: Bool = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var voiceProfiles: [ESangVoiceOption] = []
    @State private var dialects: [ESangDialectOption] = []
    @State private var timeZoneIdentifier: String = TimeZone.current.identifier

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if saved { LifecycleCard(accentGradient: true) { Text("Saved.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let loadError { errorCard(loadError) }
                if let saveError { errorCard(saveError) }
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
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12)
                Text("ESANG · SETTINGS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("eSang preferences").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var voiceCard: some View {
        LifecycleCard {
            LifecycleSection(label: "VOICE PROFILE", icon: "waveform")
            if voiceProfiles.isEmpty {
                HStack(spacing: 8) {
                    if loading { ProgressView().controlSize(.small) }
                    Text(loading ? "Loading available voices..." : "Voice catalog unavailable")
                        .font(EType.body)
                        .foregroundStyle(palette.textSecondary)
                }
            } else {
                Picker("Voice", selection: $voiceProfile) {
                    ForEach(voiceProfiles) { voice in
                        Text(voice.style.map { "\(voice.name) · \($0)" } ?? voice.name)
                            .tag(voice.voiceId)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var languageCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LANGUAGE & DIALECT", icon: "globe")
            if dialects.isEmpty {
                Text(loading ? "Loading available languages..." : "Language catalog unavailable")
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
            } else {
                Picker("Language and dialect", selection: $language) {
                    ForEach(dialects) { dialect in
                        Text(dialect.label).tag(dialect.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var dndCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DO-NOT-DISTURB WINDOW", icon: "moon.fill")
            Toggle("Use quiet hours", isOn: $dndEnabled).font(EType.body)
            HStack {
                DatePicker("", selection: $dndStart, displayedComponents: [.hourAndMinute]).labelsHidden()
                Text("→").foregroundStyle(palette.textTertiary)
                DatePicker("", selection: $dndEnd, displayedComponents: [.hourAndMinute]).labelsHidden()
            }
            .disabled(!dndEnabled)
            .opacity(dndEnabled ? 1 : 0.5)
            Text(TimeZone(identifier: timeZoneIdentifier)?.localizedName(for: .standard, locale: .current) ?? timeZoneIdentifier)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
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
        }
        .buttonStyle(.plain)
        .disabled(sending || loading || voiceProfiles.isEmpty || dialects.isEmpty)
    }

    private func errorCard(_ message: String) -> some View {
        LifecycleCard {
            Text(message)
                .font(EType.body)
                .foregroundStyle(.red)
        }
    }

    @MainActor
    private func load() async {
        struct VoiceCatalog: Decodable { let voices: [ESangVoiceOption] }
        struct DialectCatalog: Decodable { let dialects: [ESangDialectOption] }
        struct CurrentVoice: Decodable {
            let role: String
            let voiceId: String
            let name: String
            let gender: String
            let style: String?
            let region: String?
        }

        loading = true
        saved = false
        loadError = nil
        do {
            async let voicesRequest: VoiceCatalog = EusoTripAPI.shared.queryNoInput("esangVoice.getVoices")
            async let dialectsRequest: DialectCatalog = EusoTripAPI.shared.queryNoInput("esangVoice.listDialects")
            async let preferencesRequest: ESangPreferenceSnapshot = EusoTripAPI.shared.queryNoInput("esangAI.getPreferences")
            async let currentVoiceRequest: CurrentVoice = EusoTripAPI.shared.queryNoInput("esangVoice.getMyVoice")
            let (voiceCatalog, dialectCatalog, preferences, currentVoice) = try await (
                voicesRequest,
                dialectsRequest,
                preferencesRequest,
                currentVoiceRequest
            )

            var seenVoiceIDs = Set<String>()
            voiceProfiles = voiceCatalog.voices
                .filter { seenVoiceIDs.insert($0.voiceId).inserted }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            dialects = dialectCatalog.dialects
            guard !voiceProfiles.isEmpty else { throw ESangSettingsError.emptyVoiceCatalog }
            guard !dialects.isEmpty else { throw ESangSettingsError.emptyDialectCatalog }

            let requestedVoice = preferences.voiceProfile ?? currentVoice.voiceId
            voiceProfile = voiceProfiles.contains(where: { $0.voiceId == requestedVoice })
                ? requestedVoice
                : currentVoice.voiceId
            let requestedDialect = preferences.language ?? UserVoicePreference.shared.current.rawValue
            language = dialects.contains(where: { $0.code == requestedDialect })
                ? requestedDialect
                : "system"
            voiceEnabled = preferences.voiceEnabled ?? true
            pushEnabled = preferences.pushEnabled ?? true
            dndEnabled = preferences.dndEnabled ?? false
            timeZoneIdentifier = preferences.timeZone ?? TimeZone.current.identifier
            if let start = preferences.dndStart {
                guard let parsed = date(fromLocalTime: start) else { throw ESangSettingsError.invalidStoredTime }
                dndStart = parsed
            }
            if let end = preferences.dndEnd {
                guard let parsed = date(fromLocalTime: end) else { throw ESangSettingsError.invalidStoredTime }
                dndEnd = parsed
            }
            if preferences.updatedAt != nil {
                UserVoicePreference.shared.applyAuthoritativeSettings(
                    voiceProfile: voiceProfile,
                    dialect: language,
                    voiceEnabled: voiceEnabled,
                    pushEnabled: pushEnabled,
                    dndEnabled: dndEnabled,
                    dndStart: localTime(from: dndStart),
                    dndEnd: localTime(from: dndEnd)
                )
            }
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    @MainActor
    private func save() async {
        sending = true
        saved = false
        saveError = nil
        struct In: Encodable {
            let voiceProfile: String
            let language: String
            let voiceEnabled: Bool
            let pushEnabled: Bool
            let dndEnabled: Bool
            let dndStart: String
            let dndEnd: String
            let timeZone: String
        }
        struct Out: Decodable {
            let success: Bool
            let voiceProfile: String
            let language: String
            let voiceEnabled: Bool
            let pushEnabled: Bool
            let dndEnabled: Bool
            let dndStart: String
            let dndEnd: String
            let timeZone: String
            let updatedAt: String
        }
        do {
            guard voiceProfiles.contains(where: { $0.voiceId == voiceProfile }) else {
                throw ESangSettingsError.emptyVoiceCatalog
            }
            guard dialects.contains(where: { $0.code == language }) else {
                throw ESangSettingsError.emptyDialectCatalog
            }
            let request = In(
                voiceProfile: voiceProfile,
                language: language,
                voiceEnabled: voiceEnabled,
                pushEnabled: pushEnabled,
                dndEnabled: dndEnabled,
                dndStart: localTime(from: dndStart),
                dndEnd: localTime(from: dndEnd),
                timeZone: TimeZone.current.identifier
            )
            let written: Out = try await EusoTripAPI.shared.mutation(
                "esangAI.savePreferences",
                input: request
            )
            let verified: ESangPreferenceSnapshot = try await EusoTripAPI.shared.queryNoInput("esangAI.getPreferences")
            guard written.success,
                  written.voiceProfile == request.voiceProfile,
                  written.language == request.language,
                  written.voiceEnabled == request.voiceEnabled,
                  written.pushEnabled == request.pushEnabled,
                  written.dndEnabled == request.dndEnabled,
                  written.dndStart == request.dndStart,
                  written.dndEnd == request.dndEnd,
                  written.timeZone == request.timeZone,
                  !written.updatedAt.isEmpty,
                  verified.voiceProfile == request.voiceProfile,
                  verified.language == request.language,
                  verified.voiceEnabled == request.voiceEnabled,
                  verified.pushEnabled == request.pushEnabled,
                  verified.dndEnabled == request.dndEnabled,
                  verified.dndStart == request.dndStart,
                  verified.dndEnd == request.dndEnd,
                  verified.timeZone == request.timeZone,
                  verified.updatedAt == written.updatedAt else {
                throw ESangSettingsError.unverifiedWrite
            }
            UserVoicePreference.shared.applyAuthoritativeSettings(
                voiceProfile: request.voiceProfile,
                dialect: request.language,
                voiceEnabled: request.voiceEnabled,
                pushEnabled: request.pushEnabled,
                dndEnabled: request.dndEnabled,
                dndStart: request.dndStart,
                dndEnd: request.dndEnd
            )
            timeZoneIdentifier = request.timeZone
            saved = true
        } catch {
            saveError = error.eusoUserCopy
        }
        sending = false
    }

    private func localTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func date(fromLocalTime value: String) -> Date? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
    }
}

#Preview("319 · eSang settings · Night") { eSangSettingsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("319 · eSang settings · Afternoon") { eSangSettingsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
