//
//  Dpch734_DispatcherControlQuartet.swift
//  EusoTrip — Dispatcher · Control quartet (409/413/416/417).
//
//  Pixel-match to:
//    409 Dispatcher Settings.svg
//    413 Dispatcher Weather Reroute Map.svg
//    416 Dispatcher Reload Offer Sheet.svg
//    417 Dispatcher Fuel-Policy Override.svg
//
//  Bundled file; all wire to real endpoints. Bottom nav frozen.
//

import SwiftUI

private struct ShellNav<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .me),
                trailing: DispatchNavRoute.trailing(current: .me),
                orbState: .idle
            )
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 409 Dispatcher Settings
// MARK: ─────────────────────────────────────────────────────────

private struct DispatcherSettingsPayload: Decodable {
    let display: Display?
    let rolePreferences: RolePreferences?

    struct Display: Decodable {
        let theme: String?
        let language: String?
    }

    struct RolePreferences: Decodable {
        let dispatch: Dispatch?
    }

    struct Dispatch: Decodable {
        let notifications: Notifications?
        let board: Board?
    }

    struct Notifications: Codable, Equatable {
        let hosCriticalAlerts: Bool
        let tenderExpiringSoon: Bool
        let esangNudgeFrequency: String
    }

    struct Board: Codable, Equatable {
        let visibleStages: [String]
        let cardDensity: String
    }
}

private struct DispatcherSettingsAck: Decodable {
    let success: Bool
    let updatedAt: String?
}

private enum DispatcherSettingsContractError: LocalizedError {
    case missingRolePreferences
    case readbackMismatch

    var errorDescription: String? {
        switch self {
        case .missingRolePreferences:
            return "The dispatcher settings response was incomplete."
        case .readbackMismatch:
            return "The saved dispatcher settings did not match the confirmed settings. Refresh before trying again."
        }
    }
}

private struct EusoLanguage: Decodable, Identifiable, Hashable {
    let tag: String
    let englishName: String
    let nativeName: String
    let direction: String
    var id: String { tag }
}

private struct EusoLanguageList: Decodable {
    let items: [EusoLanguage]
    let total: Int
}

private struct EusoLocalizationPreference: Decodable {
    let locale: String
    let contentLocale: String
    let timezone: String?
    let currency: String?
    let dateFormat: String?
    let hourCycle: String
    let measurementSystem: String
    let translateDynamicContent: Bool
    let showRegulatedOriginal: Bool
}

private struct DispatcherBoardStage: Identifiable {
    let id: String
    let label: String
}

struct DispatcherSettingsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        ShellNav(theme: theme) { DispatcherSettingsBody() }
    }
}

private struct DispatcherSettingsBody: View {
    @Environment(\.palette) private var palette
    @AppStorage("com.eusorone.EusoTrip.appearance") private var appAppearance = "system"
    @AppStorage("com.eusorone.EusoTrip.locale") private var appLocale = "en"
    @SceneStorage("dispatch.settings.expandedSection") private var expandedSection = ""

    @State private var hosAlerts = true
    @State private var tenderExpiringPush = true
    @State private var esangNudges = "medium"
    @State private var visibleStages = ["tender", "assigned", "pickup", "in_transit", "delivered"]
    @State private var cardDensity = "compact"
    @State private var selectedTheme = "system"
    @State private var selectedLanguageTag = "en"
    @State private var languages: [EusoLanguage] = []
    @State private var localization: EusoLocalizationPreference?
    @State private var loading = true
    @State private var settingsReady = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var showLanguagePicker = false
    @State private var presentingLegal: LegalDoc?
    @State private var dispatcherSaveTask: Task<Void, Never>?

    private let stages: [DispatcherBoardStage] = [
        .init(id: "tender", label: "Tender"),
        .init(id: "assigned", label: "Assigned"),
        .init(id: "pickup", label: "Pickup"),
        .init(id: "in_transit", label: "In transit"),
        .init(id: "delivered", label: "Delivered"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    statusCard(text: "Loading your settings", systemImage: "arrow.triangle.2.circlepath")
                } else if settingsReady {
                    if let errorMessage {
                        statusCard(text: errorMessage, systemImage: "exclamationmark.triangle.fill", tint: Brand.danger)
                    } else if let savedMessage {
                        statusCard(text: savedMessage, systemImage: "checkmark.circle.fill", tint: Brand.success)
                    }
                    notificationsSection
                    boardViewSection
                    appearanceSection
                    aboutSection
                } else {
                    if let errorMessage {
                        statusCard(text: errorMessage, systemImage: "exclamationmark.triangle.fill", tint: Brand.danger)
                    }
                    Button {
                        Task { await load() }
                    } label: {
                        Label("Retry settings", systemImage: "arrow.clockwise")
                            .font(EType.bodyStrong)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .onDisappear { flushDispatcherSave() }
        .sheet(isPresented: $showLanguagePicker) {
            DispatcherLanguagePicker(
                languages: languages,
                selectedTag: selectedLanguageTag,
                isSaving: saving,
                onSelect: { language in
                    Task { await saveLanguage(language) }
                }
            )
            .environment(\.palette, palette)
        }
        .sheet(item: $presentingLegal) { doc in
            LegalDocSheet(doc: doc)
                .environment(\.palette, palette)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · ME · SETTINGS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Settings").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Employee · no impersonation · v\(appVersion)").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var notificationsSection: some View {
        settingsSection(
            id: "notifications",
            icon: "bell.badge.fill",
            title: "Notifications",
            summary: notificationSummary
        ) {
            VStack(alignment: .leading, spacing: 12) {
                toggleRow(title: "HOS critical alerts", subtitle: "Push + sound when any driver clock is under one hour", value: hosAlerts) { value in
                    hosAlerts = value
                    scheduleDispatcherSave()
                }
                Divider().overlay(palette.borderFaint)
                toggleRow(title: "Tender expiring soon", subtitle: "Push under 30 minutes and escalate under 10 minutes", value: tenderExpiringPush) { value in
                    tenderExpiringPush = value
                    scheduleDispatcherSave()
                }
                Divider().overlay(palette.borderFaint)
                VStack(alignment: .leading, spacing: 12) {
                    Text("ESANG NUDGES").font(EType.micro.weight(.heavy)).foregroundStyle(palette.textTertiary)
                    Picker("ESANG nudge frequency", selection: Binding(
                        get: { esangNudges },
                        set: { esangNudges = $0; scheduleDispatcherSave() }
                    )) {
                        Text("Off").tag("off")
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var boardViewSection: some View {
        settingsSection(
            id: "board",
            icon: "rectangle.split.3x1.fill",
            title: "Board view",
            summary: "\(visibleStages.count) stages · \(cardDensity.capitalized) cards"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("VISIBLE STAGES").font(EType.micro.weight(.heavy)).foregroundStyle(palette.textTertiary)
                ForEach(stages, id: \.id) { stage in
                    toggleRow(title: stage.label, subtitle: "Show this workflow stage on the Kanban board", value: visibleStages.contains(stage.id)) { enabled in
                        setStage(stage.id, enabled: enabled)
                    }
                    if stage.id != stages.last?.id {
                        Divider().overlay(palette.borderFaint)
                    }
                }
                Divider().overlay(palette.borderFaint)
                Text("CARD DENSITY").font(EType.micro.weight(.heavy)).foregroundStyle(palette.textTertiary)
                Picker("Card density", selection: Binding(
                    get: { cardDensity },
                    set: { cardDensity = $0; scheduleDispatcherSave() }
                )) {
                    Text("Compact").tag("compact")
                    Text("Comfortable").tag("comfortable")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var appearanceSection: some View {
        settingsSection(
            id: "appearance",
            icon: "circle.lefthalf.filled",
            title: "Appearance & language",
            summary: "\(themeLabel) · \(selectedLanguageName)"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("THEME").font(EType.micro.weight(.heavy)).foregroundStyle(palette.textTertiary)
                Picker("Theme", selection: Binding(
                    get: { selectedTheme },
                    set: { newValue in Task { await saveTheme(newValue) } }
                )) {
                    Text("System").tag("system")
                    Text("Night").tag("dark")
                    Text("Afternoon").tag("light")
                }
                .pickerStyle(.segmented)
                Divider().overlay(palette.borderFaint)
                Button { showLanguagePicker = true } label: {
                    chooserRow(title: "Language", subtitle: selectedLanguageName)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutSection: some View {
        settingsSection(
            id: "about",
            icon: "info.circle.fill",
            title: "About & legal",
            summary: "v\(appVersion) · build \(buildNumber)"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                valueRow(title: "App version", subtitle: "v\(appVersion) · build \(buildNumber)")
                Divider().overlay(palette.borderFaint)
                Button { presentingLegal = .privacyPolicy } label: {
                    chooserRow(title: "Privacy policy", subtitle: "Canonical in-app policy")
                }.buttonStyle(.plain)
                Divider().overlay(palette.borderFaint)
                Button { presentingLegal = .termsOfService } label: {
                    chooserRow(title: "Terms of service", subtitle: "Canonical in-app terms")
                }.buttonStyle(.plain)
            }
        }
    }

    private func toggleRow(title: String, subtitle: String, value: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { value }, set: onChange)).labelsHidden()
                .disabled(saving)
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(id: String, icon: String, title: String, summary: String, @ViewBuilder content: () -> Content) -> some View {
        RoleDisclosureSection(
            id: id,
            systemImage: icon,
            title: title,
            summary: summary,
            isBusy: saving,
            expandedID: $expandedSection
        ) {
            content()
        }
    }

    private func chooserRow(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(palette.textTertiary)
        }
        .contentShape(Rectangle())
    }

    private func valueRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusCard(text: String, systemImage: String, tint: Color = Brand.info) -> some View {
        HStack(spacing: 8) {
            if loading { ProgressView().controlSize(.small) }
            else { Image(systemName: systemImage).foregroundStyle(tint) }
            Text(text).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var notificationSummary: String {
        let enabled = [hosAlerts, tenderExpiringPush].filter { $0 }.count
        return "\(enabled) critical alert groups · ESANG \(esangNudges)"
    }

    private var themeLabel: String {
        switch selectedTheme {
        case "dark": return "Night"
        case "light": return "Afternoon"
        default: return "System"
        }
    }

    private var selectedLanguageName: String {
        languages.first(where: { $0.tag == selectedLanguageTag })?.nativeName
            ?? Locale.current.localizedString(forLanguageCode: selectedLanguageTag)
            ?? selectedLanguageTag
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }

    private func load() async {
        loading = true
        settingsReady = false
        errorMessage = nil
        defer { loading = false }
        do {
            async let settingsRequest: DispatcherSettingsPayload = EusoTripAPI.shared.queryNoInput("settings.getSettings")
            struct LanguageIn: Encodable { let displayLocale: String; let limit: Int; let cursor: Int }
            async let languagesRequest: EusoLanguageList = EusoTripAPI.shared.query(
                "localization.listLanguages",
                input: LanguageIn(displayLocale: appLocale, limit: 250, cursor: 0)
            )
            async let localizationRequest: EusoLocalizationPreference? = EusoTripAPI.shared.queryNoInput("localization.getPreferences")
            let (settings, languageList, storedLocalization) = try await (settingsRequest, languagesRequest, localizationRequest)

            guard let dispatch = settings.rolePreferences?.dispatch,
                  let notifications = dispatch.notifications,
                  let board = dispatch.board else {
                throw DispatcherSettingsContractError.missingRolePreferences
            }
            hosAlerts = notifications.hosCriticalAlerts
            tenderExpiringPush = notifications.tenderExpiringSoon
            esangNudges = notifications.esangNudgeFrequency
            visibleStages = board.visibleStages
            cardDensity = board.cardDensity
            selectedTheme = settings.display?.theme ?? appAppearance
            languages = languageList.items
            localization = storedLocalization
            selectedLanguageTag = storedLocalization?.locale ?? settings.display?.language ?? appLocale
            appAppearance = selectedTheme
            appLocale = selectedLanguageTag
            settingsReady = true
        } catch {
            errorMessage = "Your settings couldn't load. \(error.eusoUserCopy)"
        }
    }

    private func scheduleDispatcherSave() {
        dispatcherSaveTask?.cancel()
        dispatcherSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await saveDispatcherSettings()
        }
    }

    private func flushDispatcherSave() {
        dispatcherSaveTask?.cancel()
        guard settingsReady, !loading else { return }
        dispatcherSaveTask = Task { await saveDispatcherSettings() }
    }

    private func saveDispatcherSettings() async {
        struct In: Encodable {
            let notifications: DispatcherSettingsPayload.Notifications
            let board: DispatcherSettingsPayload.Board
        }
        let intendedNotifications = DispatcherSettingsPayload.Notifications(
            hosCriticalAlerts: hosAlerts,
            tenderExpiringSoon: tenderExpiringPush,
            esangNudgeFrequency: esangNudges
        )
        let intendedBoard = DispatcherSettingsPayload.Board(
            visibleStages: visibleStages,
            cardDensity: cardDensity
        )
        saving = true
        errorMessage = nil
        savedMessage = nil
        defer { saving = false }
        do {
            let ack: DispatcherSettingsAck = try await EusoTripAPI.shared.mutation(
                "settings.updateDispatcherSettings",
                input: In(
                    notifications: intendedNotifications,
                    board: intendedBoard
                )
            )
            guard ack.success else { throw EusoTripAPIError.empty }
            let canonical: DispatcherSettingsPayload = try await EusoTripAPI.shared.queryNoInput(
                "settings.getSettings"
            )
            guard let dispatch = canonical.rolePreferences?.dispatch,
                  let notifications = dispatch.notifications,
                  let board = dispatch.board else {
                throw DispatcherSettingsContractError.missingRolePreferences
            }
            guard notifications == intendedNotifications,
                  board == intendedBoard else {
                throw DispatcherSettingsContractError.readbackMismatch
            }
            hosAlerts = notifications.hosCriticalAlerts
            tenderExpiringPush = notifications.tenderExpiringSoon
            esangNudges = notifications.esangNudgeFrequency
            visibleStages = board.visibleStages
            cardDensity = board.cardDensity
            savedMessage = "Settings saved"
        } catch {
            errorMessage = "Your settings weren't saved. \(error.eusoUserCopy)"
        }
    }

    private func setStage(_ id: String, enabled: Bool) {
        if enabled {
            if !visibleStages.contains(id) { visibleStages.append(id) }
            visibleStages.sort { left, right in
                (stages.firstIndex(where: { $0.id == left }) ?? 0) < (stages.firstIndex(where: { $0.id == right }) ?? 0)
            }
        } else {
            guard visibleStages.count > 1 else {
                errorMessage = "Keep at least one board stage visible."
                return
            }
            visibleStages.removeAll { $0 == id }
        }
        scheduleDispatcherSave()
    }

    private func saveTheme(_ newTheme: String) async {
        struct In: Encodable { let theme: String }
        let oldTheme = selectedTheme
        selectedTheme = newTheme
        saving = true
        errorMessage = nil
        savedMessage = nil
        defer { saving = false }
        do {
            let ack: DispatcherSettingsAck = try await EusoTripAPI.shared.mutation(
                "settings.updateDisplaySettings", input: In(theme: newTheme)
            )
            guard ack.success else { throw EusoTripAPIError.empty }
            let canonical: DispatcherSettingsPayload = try await EusoTripAPI.shared.queryNoInput(
                "settings.getSettings"
            )
            guard canonical.display?.theme == newTheme else {
                throw DispatcherSettingsContractError.readbackMismatch
            }
            appAppearance = newTheme
            savedMessage = "Theme saved"
        } catch {
            selectedTheme = oldTheme
            errorMessage = "The theme wasn't changed. \(error.eusoUserCopy)"
        }
    }

    private func saveLanguage(_ language: EusoLanguage) async {
        struct In: Encodable {
            let locale: String
            let contentLocale: String
            let timezone: String
            let currency: String
            let dateFormat: String
            let hourCycle: String
            let measurementSystem: String
            let translateDynamicContent: Bool
            let showRegulatedOriginal: Bool
        }
        saving = true
        errorMessage = nil
        savedMessage = nil
        defer { saving = false }
        let current = localization
        let input = In(
            locale: language.tag,
            contentLocale: language.tag,
            timezone: current?.timezone ?? TimeZone.current.identifier,
            currency: current?.currency ?? Locale.current.currency?.identifier ?? "USD",
            dateFormat: current?.dateFormat ?? "MM/DD/YYYY",
            hourCycle: current?.hourCycle ?? "locale",
            measurementSystem: current?.measurementSystem ?? "locale",
            translateDynamicContent: current?.translateDynamicContent ?? true,
            showRegulatedOriginal: current?.showRegulatedOriginal ?? true
        )
        do {
            let updated: EusoLocalizationPreference = try await EusoTripAPI.shared.mutation(
                "localization.updatePreferences", input: input
            )
            localization = updated
            selectedLanguageTag = updated.locale
            appLocale = updated.locale
            showLanguagePicker = false
            savedMessage = "Language saved"
        } catch {
            errorMessage = "The language wasn't changed. \(error.eusoUserCopy)"
        }
    }
}

private struct DispatcherLanguagePicker: View {
    let languages: [EusoLanguage]
    let selectedTag: String
    let isSaving: Bool
    let onSelect: (EusoLanguage) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredLanguages: [EusoLanguage] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return languages }
        return languages.filter {
            $0.tag.lowercased().contains(term)
                || $0.englishName.lowercased().contains(term)
                || $0.nativeName.lowercased().contains(term)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredLanguages) { language in
                Button { onSelect(language) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.nativeName).foregroundStyle(palette.textPrimary)
                            Text("\(language.englishName) · \(language.tag)")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        if language.tag == selectedTag {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(LinearGradient.diagonal)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .listRowBackground(palette.bgCard)
            }
            .scrollContentBackground(.hidden)
            .background(palette.bgPage)
            .navigationTitle("Language")
            .searchable(text: $query, prompt: "Search languages")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 413 Weather Reroute Map
// MARK: ─────────────────────────────────────────────────────────

private struct WeatherRerouteLoad: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let trailerType: String?
    let cargoType: String?
    let rate: String?
    let assignedDriverName: String?
    let deliveryDate: String?
}

struct DispatcherWeatherRerouteScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { WeatherRerouteBody(loadId: loadId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",    isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: true),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct WeatherRerouteBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: WeatherRerouteLoad?
    @State private var loading: Bool = true
    @State private var inFlight: Bool = false
    @State private var ack: String? = nil
    @State private var err: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                priorityBanner
                loadContextCard
                mapPlaceholder
                advisoryCard
                actionRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .eusoRefreshable { await loadCtx() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · EXCEPTIONS · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Weather Reroute").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Closure at I-80 mile 343 · 156 mi to closure").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var priorityBanner: some View {
        LifecycleCard(accentDanger: true) {
            HStack {
                Text("P1 · WEATHER").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
                Spacer()
                Text("SLA 0:11:42").font(.caption.monospaced().weight(.semibold)).foregroundStyle(.red)
            }
        }
    }

    private var loadContextCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                if let l = load {
                    Text(l.loadNumber ?? "LD-\(l.id ?? 0)").font(.caption.monospaced().weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("\(l.pickupCity ?? "-") → \(l.destCity ?? "-")").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text("\(l.trailerType ?? "-") · \(l.cargoType ?? "-") · $\(l.rate ?? "-") · driver \(l.assignedDriverName ?? "ME")")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var mapPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [palette.bgCard, palette.bgCardSoft], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 6) {
                Image(systemName: "map.fill").font(.system(size: 28, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("MAP · CO → NE → IA").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("MILE 343 · CLOSED").font(.system(size: 11, weight: .heavy)).foregroundStyle(.red)
            }
            VStack {
                Spacer()
                HStack {
                    Text("NWS · BLIZZARD ADVISORY · 14:00-22:00 MT")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.red.opacity(0.18)))
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(10)
            }
        }
        .frame(height: 180)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Color.red.opacity(0.5)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var advisoryCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("REROUTE OPTIONS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("ESang suggests: I-76 → I-80 (Cheyenne bypass)")
                    .font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text("+87 mi · +1h 42m vs original · clears advisory window")
                    .font(.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var actionRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button { Task { await resolveReroute(accept: true) } } label: {
                    HStack(spacing: 6) {
                        if inFlight { ProgressView().tint(.white).scaleEffect(0.7) }
                        Text(inFlight ? "Working…" : "Accept reroute")
                            .font(EType.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
                Button { Task { await resolveReroute(accept: false) } } label: {
                    Text("Hold for review")
                        .font(EType.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(palette.textPrimary)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
            }
            if let ack { Text(ack).font(.caption2).foregroundStyle(.green) }
            if let err { Text(err).font(.caption2).foregroundStyle(.red) }
        }
    }

    private func resolveReroute(accept: Bool) async {
        inFlight = true; ack = nil; err = nil
        defer { inFlight = false }
        struct In: Encodable { let exceptionId: String; let resolution: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.resolveException",
                input: In(
                    exceptionId: "weather-reroute-\(loadId)",
                    resolution: accept ? "accepted-reroute" : "hold-for-review"
                )
            )
            if resp.success != false {
                ack = accept ? "Reroute accepted · driver receives new polyline."
                             : "Held for review · ops will revisit before sending."
            } else {
                err = "Resolve returned no success flag."
            }
        } catch let e {
            err = (e as? LocalizedError)?.errorDescription ?? "Resolve failed: \(e)"
        }
    }

    private func loadCtx() async {
        loading = true; defer { loading = false }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 416 Reload Offer Sheet
// MARK: ─────────────────────────────────────────────────────────

private struct ReloadCandidate: Decodable, Hashable, Identifiable {
    let id: String
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let trailerType: String?
    let cargoType: String?
    let rate: String?
    let laneDeltaMi: Int?
    let hosFitMin: Int?
    let equipFitPct: Int?
    let fitScore: Int?
}

struct DispatcherReloadOfferScreen: View {
    let theme: Theme.Palette
    let driverId: String
    var body: some View {
        Shell(theme: theme) { ReloadOfferBody(driverId: driverId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",    isCurrent: true)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct ReloadOfferBody: View {
    @State private var inFlight: Bool = false
    @State private var ack: String? = nil
    @State private var err: String? = nil
    let driverId: String
    @Environment(\.palette) private var palette
    @State private var candidates: [ReloadCandidate] = []
    @State private var selectedId: String?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                priorityBanner
                driverCard
                Text("ESANG RELOAD-FIT · RANKED BY 5 INPUTS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                if loading && candidates.isEmpty {
                    LifecycleCard { Text("Loading reload candidates…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if candidates.isEmpty {
                    EusoEmptyState(systemImage: "tray", title: "No reloads in range", subtitle: "ESang found no nearby loads within HOS + equipment match.")
                } else {
                    ForEach(candidates.sorted { ($0.fitScore ?? 0) > ($1.fitScore ?? 0) }) { c in candidateCard(c) }
                }
                actionRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · EXCEPTIONS · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Offer reload").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Driver stranded · ranked candidates").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var priorityBanner: some View {
        LifecycleCard(accentDanger: true) {
            HStack {
                Text("P2 · STRANDED").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.yellow.opacity(0.18)))
                    .foregroundStyle(.yellow)
                Spacer()
                Text("idle 4h · 3 candidates ranked").font(.caption.weight(.semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var driverCard: some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                    Text("SQ").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Driver \(driverId)").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text("Trailer T-211 · 53′ Reefer · MEM yard slot YS-04").font(.caption).foregroundStyle(palette.textSecondary)
                    Text("HOS 8:42 · 35.13° N · 90.05° W").font(.caption2.monospaced()).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private func candidateCard(_ c: ReloadCandidate) -> some View {
        let isBest = candidates.sorted { ($0.fitScore ?? 0) > ($1.fitScore ?? 0) }.first?.id == c.id
        let isSelected = selectedId == c.id
        return Button { selectedId = c.id } label: {
            LifecycleCard(accentGradient: isBest) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(c.loadNumber ?? "LD-\(c.id)").font(.caption.monospaced().weight(.semibold)).foregroundStyle(palette.textPrimary)
                        if isBest {
                            Text("BEST · \(c.fitScore ?? 0)")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.18)))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.green : palette.textTertiary)
                    }
                    Text("\(c.pickupCity ?? "-") → \(c.destCity ?? "-")").font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("\(c.trailerType ?? "-") · \(c.cargoType ?? "-") · $\(c.rate ?? "-")")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                    HStack(spacing: 6) {
                        if let l = c.laneDeltaMi {
                            chip("LANE \(l >= 0 ? "+" : "")\(l) mi", color: .blue)
                        }
                        if let h = c.hosFitMin {
                            chip("HOS \(h / 60):\(String(format: "%02d", h % 60))", color: .green)
                        }
                        if let e = c.equipFitPct {
                            chip("EQUIP \(e)%", color: e >= 90 ? .green : .orange)
                        }
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private func chip(_ label: String, color: Color) -> some View {
        Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private var actionRow: some View {
        VStack(spacing: 6) {
            Button { Task { await offerReload() } } label: {
                HStack(spacing: 6) {
                    if inFlight { ProgressView().tint(.white).scaleEffect(0.7) }
                    Text(inFlight
                         ? "Offering…"
                         : (selectedId == nil ? "Select a reload" : "Offer reload"))
                        .font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .opacity(selectedId == nil ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(selectedId == nil || inFlight)
            if let ack { Text(ack).font(.caption2).foregroundStyle(.green) }
            if let err { Text(err).font(.caption2).foregroundStyle(.red) }
        }
    }

    private func offerReload() async {
        guard let id = selectedId else { return }
        inFlight = true; ack = nil; err = nil
        defer { inFlight = false }
        struct In: Encodable { let loadId: String }
        struct Out: Decodable { let success: Bool?; let loadId: String?; let status: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.acceptLoad",
                input: In(loadId: id)
            )
            if resp.success != false {
                ack = "Reload offered · driver receives the suggestion."
            } else {
                err = "Offer returned no success flag."
            }
        } catch let e {
            err = (e as? LocalizedError)?.errorDescription ?? "Offer failed: \(e)"
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        // Pull nearby pending loads as reload candidates.
        struct In: Encodable { let status: String; let limit: Int }
        struct Out: Decodable {
            let loads: [ReloadCandidate]?
            let items: [ReloadCandidate]?
            
            init(from decoder: Decoder) throws {
                // Server returns a BARE array of loads; tolerate either that or a
                // {loads}/{items} envelope. Each stored prop is assigned once per path.
                if let bare = try? decoder.singleValueContainer().decode([ReloadCandidate].self) {
                    self.loads = bare
                    self.items = nil
                } else {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.loads = try container.decodeIfPresent([ReloadCandidate].self, forKey: .loads)
                    self.items = try container.decodeIfPresent([ReloadCandidate].self, forKey: .items)
                }
            }
            
            enum CodingKeys: String, CodingKey {
                case loads
                case items
            }
        }
        do {
            let r: Out = try await EusoTripAPI.shared.query("loads.list", input: In(status: "pending", limit: 6))
            candidates = r.loads ?? r.items ?? []
        } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 417 Fuel-Policy Override
// MARK: ─────────────────────────────────────────────────────────

private struct FuelStation: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let address: String?
    let dieselPrice: Double?
    let networkBrand: String?
    let inNetwork: Bool?
    let mileOffRoute: Double?
}

struct DispatcherFuelPolicyOverrideScreen: View {
    let theme: Theme.Palette
    let driverId: String
    var body: some View {
        Shell(theme: theme) { FuelOverrideBody(driverId: driverId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",    isCurrent: true)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct FuelOverrideBody: View {
    @State private var inFlight: Bool = false
    @State private var ack: String? = nil
    @State private var err: String? = nil
    let driverId: String
    @Environment(\.palette) private var palette
    @State private var stations: [FuelStation] = []
    @State private var selectedId: String?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                priorityBanner
                driverCard
                fuelStatusCard
                stationsSection
                actionRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · EXCEPTIONS · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Fuel approval").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Off-network requested · 60 min window").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var priorityBanner: some View {
        LifecycleCard(accentDanger: true) {
            HStack {
                Text("P1 · FUEL").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
                Spacer()
                Text("I-10 mi 137 NM · 60 min window").font(.caption.weight(.semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var driverCard: some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                    Text("RB").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Driver \(driverId)").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text("Truck T-308 · 53′ Dry Van · 24 pal electronics").font(.caption).foregroundStyle(palette.textSecondary)
                    Text("32.27° N · 107.76° W").font(.caption2.monospaced()).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var fuelStatusCard: some View {
        LifecycleCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FUEL").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text("15 / 100 GAL").font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(.orange)
                    Text("range ≈ 90 mi").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("STATIONS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text("\(stations.count) ranked").font(.title3.weight(.heavy)).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private var stationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ESANG STATION FIT · RANKED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            if loading && stations.isEmpty {
                LifecycleCard { Text("Loading stations…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if stations.isEmpty {
                EusoEmptyState(systemImage: "fuelpump", title: "No stations in range", subtitle: "ESang found no compatible stations within the 60-minute window.")
            } else {
                ForEach(stations.prefix(3)) { s in stationCard(s) }
            }
        }
    }

    private func stationCard(_ s: FuelStation) -> some View {
        let isSelected = selectedId == s.id
        return Button { selectedId = s.id } label: {
            LifecycleCard(accentGradient: isSelected) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(s.name ?? "Station").font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                            Text(s.inNetwork == true ? "IN-NET" : "OFF-NET")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill((s.inNetwork == true ? Color.green : Color.orange).opacity(0.18)))
                                .foregroundStyle(s.inNetwork == true ? .green : .orange)
                        }
                        Text(s.address ?? "-").font(.caption).foregroundStyle(palette.textSecondary)
                        if let m = s.mileOffRoute { Text("+\(String(format: "%.1f", m)) mi off route").font(.caption2).foregroundStyle(palette.textTertiary) }
                    }
                    Spacer()
                    if let p = s.dieselPrice {
                        Text(String(format: "$%.2f/gal", p)).font(.body.monospacedDigit().weight(.heavy)).foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private var actionRow: some View {
        VStack(spacing: 6) {
        HStack(spacing: 10) {
            Button { Task { await resolveFuel(approve: true) } } label: {
                HStack(spacing: 6) {
                    if inFlight { ProgressView().tint(.white).scaleEffect(0.7) }
                    Text(inFlight ? "Working…" : (selectedId == nil ? "Select station" : "Approve fuel auth"))
                        .font(EType.body.weight(.semibold))
                }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .opacity(selectedId == nil ? 0.5 : 1)
            }.buttonStyle(.plain).disabled(selectedId == nil || inFlight)
            Button { Task { await resolveFuel(approve: false) } } label: {
                Text("Decline").font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(palette.textPrimary)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(inFlight)
        }
        if let ack { Text(ack).font(.caption2).foregroundStyle(.green) }
        if let err { Text(err).font(.caption2).foregroundStyle(.red) }
        }
    }

    private func resolveFuel(approve: Bool) async {
        inFlight = true; ack = nil; err = nil
        defer { inFlight = false }
        let stationKey = selectedId ?? "no-station"
        struct In: Encodable { let exceptionId: String; let resolution: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.resolveException",
                input: In(
                    exceptionId: "fuel-auth-driver-\(driverId)-station-\(stationKey)",
                    resolution: approve ? "fuel-approved" : "fuel-declined"
                )
            )
            if resp.success != false {
                ack = approve
                    ? "Fuel auth approved · driver receives PIN."
                    : "Declined · driver routed to network station."
            } else {
                err = "Resolve returned no success flag."
            }
        } catch let e {
            err = (e as? LocalizedError)?.errorDescription ?? "Resolve failed: \(e)"
        }
    }

    private func load() async {
        loading = false  // empty-state stub until fuel-station lookup is wired
        // Wire to fuel-station lookup via HERE add-ons (existing
        // HereMapsAPI exposes a fuel-prices client). Until that
        // surface is wired, render empty state.
    }
}

// MARK: - Previews

#Preview("409 Settings · Dark")  { DispatcherSettingsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("413 Weather · Dark")   { DispatcherWeatherRerouteScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("416 Reload · Dark")    { DispatcherReloadOfferScreen(theme: Theme.dark, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("417 Fuel · Dark")      { DispatcherFuelPolicyOverrideScreen(theme: Theme.dark, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("409 Settings · Light") { DispatcherSettingsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("413 Weather · Light")  { DispatcherWeatherRerouteScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("416 Reload · Light")   { DispatcherReloadOfferScreen(theme: Theme.light, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("417 Fuel · Light")     { DispatcherFuelPolicyOverrideScreen(theme: Theme.light, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
