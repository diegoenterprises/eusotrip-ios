//
//  319_eSangSettings.swift
//  EusoTrip — Shipper · eSang · Settings (Arc I).
//

import SwiftUI

private func esangLocalTime(hour: Int, minute: Int) -> Date {
    let calendar = Calendar.autoupdatingCurrent
    let startOfDay = calendar.startOfDay(for: Date())
    return calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: startOfDay) ?? Date()
}

private struct ESangVoiceOption: Decodable, Identifiable {
    let role: String
    let voiceId: String
    let name: String
    let gender: String
    let style: String?
    let region: String?

    var id: String { voiceId }
    var detail: String { style ?? region ?? role.replacingOccurrences(of: "_", with: " ").capitalized }
}

private struct ESangLanguageOption: Identifiable {
    let id: String
    let label: String
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
    @State private var language: String = "en-US"
    @State private var dndEnabled: Bool = false
    @State private var dndStart: Date = esangLocalTime(hour: 22, minute: 0)
    @State private var dndEnd: Date = esangLocalTime(hour: 7, minute: 0)
    @State private var voiceEnabled: Bool = true
    @State private var pushEnabled: Bool = true
    @State private var voiceOptions: [ESangVoiceOption] = []
    @State private var loading: Bool = false
    @State private var sending: Bool = false
    @State private var saved: Bool = false
    @State private var errorMessage: String?
    @State private var showDialectPicker: Bool = false
    @State private var showLanguagePicker: Bool = false

    private static let languageOptions: [ESangLanguageOption] = {
        var seen = Set<String>()
        var options = [ESangLanguageOption(id: "system", label: "System default")]
        seen.insert("system")
        for identifier in Locale.availableIdentifiers {
            let wire = Locale.identifier(.icu, from: identifier)
                .replacingOccurrences(of: "_", with: "-")
            guard isSupportedLanguageIdentifier(wire), seen.insert(wire).inserted else { continue }
            let label = Locale.current.localizedString(forIdentifier: wire) ?? wire
            options.append(.init(id: wire, label: label))
        }
        let head = options.removeFirst()
        return [head] + options.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if saved { LifecycleCard(accentGradient: true) { Text("Saved.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let errorMessage {
                    LifecycleCard {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(EType.body)
                            .foregroundStyle(palette.warning)
                    }
                }
                voiceCard
                dialectCard
                languageCard
                dndCard
                channelsCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .eusoRefreshTask { await load() }
        .sheet(isPresented: $showDialectPicker) {
            VoiceDialectPicker()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showLanguagePicker) {
            ESangLanguagePicker(options: Self.languageOptions, selection: $language)
                .presentationDetents([.large])
        }
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
            if loading && voiceOptions.isEmpty {
                ProgressView().tint(palette.textSecondary)
            } else if voiceOptions.isEmpty {
                Text("Voice catalog unavailable")
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
            } else {
                Picker("Voice", selection: $voiceProfile) {
                    ForEach(voiceOptions) { voice in
                        Text("\(voice.name) · \(voice.detail)").tag(voice.voiceId)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    /// 2026-05-20 · IO 2026 P0-4 — regional dialect. Opens
    /// `VoiceDialectPicker` as a sheet per the animation doctrine
    /// (NavigationLink is banned platform-wide; sheet keeps the
    /// 0.18s cross-fade intact).
    @ViewBuilder
    private var dialectCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DIALECT", icon: "globe")
            Button {
                showDialectPicker = true
            } label: {
                HStack {
                    Text(UserVoicePreference.shared.current.displayName)
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var languageCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LANGUAGE", icon: "globe")
            Button {
                showLanguagePicker = true
            } label: {
                HStack {
                    Text(Self.languageOptions.first(where: { $0.id == language })?.label ?? language)
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var dndCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DO-NOT-DISTURB WINDOW", icon: "moon.fill")
            Toggle("Quiet hours", isOn: $dndEnabled).font(EType.body)
            HStack {
                DatePicker("", selection: $dndStart, displayedComponents: [.hourAndMinute]).labelsHidden()
                Text("→").foregroundStyle(palette.textTertiary)
                DatePicker("", selection: $dndEnd, displayedComponents: [.hourAndMinute]).labelsHidden()
            }
            .disabled(!dndEnabled)
            .opacity(dndEnabled ? 1 : 0.55)
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
        .disabled(sending || loading || voiceOptions.isEmpty || voiceProfile.isEmpty)
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        struct PreferencesOut: Decodable {
            let voiceProfile: String?
            let language: String?
            let dndEnabled: Bool?
            let dndStart: String?
            let dndEnd: String?
            let voiceEnabled: Bool?
            let pushEnabled: Bool?
            let timeZone: String?
        }
        struct VoiceCatalogOut: Decodable {
            let voices: [ESangVoiceOption]
        }
        struct MyVoiceOut: Decodable {
            let voiceId: String
        }
        do {
            async let preferencesRequest: PreferencesOut = EusoTripAPI.shared.queryNoInput("esangAI.getPreferences")
            async let catalogRequest: VoiceCatalogOut = EusoTripAPI.shared.queryNoInput("esangVoice.getVoices")
            async let myVoiceRequest: MyVoiceOut = EusoTripAPI.shared.queryNoInput("esangVoice.getMyVoice")
            let (preferences, catalog, myVoice) = try await (preferencesRequest, catalogRequest, myVoiceRequest)

            var seen = Set<String>()
            voiceOptions = catalog.voices.filter { seen.insert($0.voiceId).inserted }
            guard !voiceOptions.isEmpty else {
                errorMessage = "No ESANG voices are currently available."
                return
            }

            if let storedVoice = preferences.voiceProfile,
               voiceOptions.contains(where: { $0.voiceId == storedVoice }) {
                voiceProfile = storedVoice
            } else {
                voiceProfile = myVoice.voiceId
                if preferences.voiceProfile != nil {
                    errorMessage = "Your saved voice is no longer available. Choose a current voice and save."
                }
            }
            language = preferences.language ?? language
            dndEnabled = preferences.dndEnabled ?? false
            if let value = preferences.dndStart, let parsed = Self.parseLocalTime(value) { dndStart = parsed }
            if let value = preferences.dndEnd, let parsed = Self.parseLocalTime(value) { dndEnd = parsed }
            voiceEnabled = preferences.voiceEnabled ?? voiceEnabled
            pushEnabled = preferences.pushEnabled ?? pushEnabled
        } catch {
            errorMessage = "Couldn't load ESANG preferences. \(error.eusoUserCopy)"
        }
    }

    private func save() async {
        guard !voiceProfile.isEmpty else {
            errorMessage = "Choose an available ESANG voice before saving."
            return
        }
        sending = true
        saved = false
        errorMessage = nil
        defer { sending = false }
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
            let timeZone: String?
        }
        do {
            let result: Out = try await EusoTripAPI.shared.mutation(
                "esangAI.savePreferences",
                input: In(
                    voiceProfile: voiceProfile,
                    language: language,
                    voiceEnabled: voiceEnabled,
                    pushEnabled: pushEnabled,
                    dndEnabled: dndEnabled,
                    dndStart: Self.formatLocalTime(dndStart),
                    dndEnd: Self.formatLocalTime(dndEnd),
                    timeZone: TimeZone.autoupdatingCurrent.identifier
                )
            )
            guard result.success else {
                errorMessage = "ESANG did not confirm the settings update."
                return
            }
            voiceProfile = result.voiceProfile
            language = result.language
            voiceEnabled = result.voiceEnabled
            pushEnabled = result.pushEnabled
            dndEnabled = result.dndEnabled
            if let parsed = Self.parseLocalTime(result.dndStart) { dndStart = parsed }
            if let parsed = Self.parseLocalTime(result.dndEnd) { dndEnd = parsed }
            saved = true
        } catch {
            errorMessage = "Couldn't save ESANG preferences. \(error.eusoUserCopy)"
        }
    }

    private static func isSupportedLanguageIdentifier(_ value: String) -> Bool {
        guard (2...35).contains(value.count) else { return false }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard let first = parts.first,
              (2...3).contains(first.count),
              first.allSatisfy({ $0.isLetter }) else { return false }
        return parts.dropFirst().allSatisfy { part in
            (2...8).contains(part.count) && part.allSatisfy { $0.isLetter || $0.isNumber }
        }
    }

    private static func parseLocalTime(_ value: String) -> Date? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return esangLocalTime(hour: hour, minute: minute)
    }

    private static func formatLocalTime(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: value)
    }
}

private struct ESangLanguagePicker: View {
    let options: [ESangLanguageOption]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var visibleOptions: [ESangLanguageOption] {
        guard !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return options }
        return options.filter {
            $0.label.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List(visibleOptions) { option in
                Button {
                    selection = option.id
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label).foregroundStyle(.primary)
                            Text(option.id).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if selection == option.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("ESANG language")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search languages")
        }
    }
}

#Preview("319 · eSang settings · Night") { eSangSettingsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("319 · eSang settings · Afternoon") { eSangSettingsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
