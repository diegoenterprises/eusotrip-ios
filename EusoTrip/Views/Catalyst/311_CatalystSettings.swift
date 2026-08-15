//
//  311_CatalystSettings.swift
//  EusoTrip — Catalyst · Settings (brick 311).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/311 Catalyst Settings.svg`.
//  Notifications · dispatch presets · security · about.
//
//  Wire bindings:
//    settings.getSettings                  — current pref bundle
//    settings.updateNotificationSettings   — toggle persistence
//    dispatch.getDispatchPresets           — dispatchTemplates table list
//    dispatch.createDispatchPreset         — durable company-scoped template
//

import SwiftUI

private struct AppSettings: Decodable, Hashable {
    let notifications: NotifPrefs?
    let display: DisplayPrefs?
    let privacy: PrivacyPrefs?
}
private struct NotifPrefs: Decodable, Hashable {
    let tenderAwarded: Bool?
    let lifecycleStage: Bool?
    let dvirHosAlerts: Bool?
    let push: Bool?
    let email: Bool?
    let sms: Bool?

    enum CodingKeys: String, CodingKey {
        case tenderAwarded, lifecycleStage, dvirHosAlerts, push, email, sms
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tenderAwarded = try c.decodeIfPresent(Bool.self, forKey: .tenderAwarded)
        self.lifecycleStage = try c.decodeIfPresent(Bool.self, forKey: .lifecycleStage)
        self.dvirHosAlerts = try c.decodeIfPresent(Bool.self, forKey: .dvirHosAlerts)
        
        // The shared settings contract has shipped both scalar channels and
        // nested channel maps. Decode either representation without letting a
        // type mismatch prevent the Catalyst-specific fields from loading.
        self.push = Self.decodeChannel(.push, from: c)
        self.email = Self.decodeChannel(.email, from: c)
        self.sms = Self.decodeChannel(.sms, from: c)
    }

    private static func decodeChannel(
        _ key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> Bool? {
        if let scalar = try? container.decode(Bool.self, forKey: key) {
            return scalar
        }
        if let channels = try? container.decode([String: Bool].self, forKey: key) {
            return channels["loadUpdates"]
                ?? channels["enabled"]
                ?? channels.values.first
        }
        return nil
    }
}
private struct DisplayPrefs: Decodable, Hashable {
    let theme: String?
    let language: String?
    let timezone: String?
}
private struct PrivacyPrefs: Decodable, Hashable {
    let shareLocation: Bool?
    let profileVisibility: String?
}

private struct DispatchPreset: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let description: String?
    let lane: String?
    let equipment: String?
    let autoAccept: Bool?
    let cargoSummary: String?
    let floorRate: String?
    let awardedYTD: Int?
}

private struct CatalystNotificationSnapshot: Equatable {
    let tenderAwarded: Bool
    let lifecycleStage: Bool
    let dvirHosAlerts: Bool
}

private enum CatalystSecurityDestination: String, Identifiable {
    case twoFactor
    case sessions
    case password

    var id: String { rawValue }
}

private enum CatalystSettingsFailure: LocalizedError {
    case rejected
    case incompleteNotificationContract

    var errorDescription: String? {
        switch self {
        case .rejected:
            return "The server did not confirm the change."
        case .incompleteNotificationContract:
            return "The notification settings response was incomplete."
        }
    }
}

struct CatalystSettingsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { SettingsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Fleet",  systemImage: "truck.box.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct SettingsBody: View {
    @Environment(\.palette) private var palette
    @SceneStorage("catalyst.settings.expandedSection") private var expandedSection = "notifications"
    @SceneStorage("catalyst.settings.returnAnchor") private var returnAnchor = "section-notifications"
    @State private var settings: AppSettings?
    @State private var presets: [DispatchPreset] = []
    @State private var tenderAwarded: Bool = true
    @State private var lifecycleStage: Bool = true
    @State private var dvirHosAlerts: Bool = true
    @State private var loading: Bool = true
    @State private var saving: Bool = false
    @State private var applyingServerSettings: Bool = false
    @State private var persistedNotifications = CatalystNotificationSnapshot(
        tenderAwarded: true,
        lifecycleStage: true,
        dvirHosAlerts: true
    )
    @State private var notificationSaveTask: Task<Void, Never>?
    @State private var settingsLoadError: String?
    @State private var notificationError: String?
    @State private var showNewPreset: Bool = false
    @State private var savingPreset: Bool = false
    @State private var actionMessage: String?
    @State private var actionError: String?
    @State private var presetName: String = ""
    @State private var presetOriginCity: String = ""
    @State private var presetOriginState: String = ""
    @State private var presetDestinationCity: String = ""
    @State private var presetDestinationState: String = ""
    @State private var presetCargoType: String = ""
    @State private var presetTrailerType: String = ""
    @State private var presetRate: String = ""
    @State private var presetInstructions: String = ""
    @State private var securityDestination: CatalystSecurityDestination?
    @State private var presentingLegal: LegalDoc?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    notificationsSection
                    dispatchPresetsSection
                    securitySection
                    aboutSection
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }
            .onAppear { restorePosition(using: proxy) }
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .sheet(isPresented: $showNewPreset) { newPresetSheet }
        .sheet(item: $presentingLegal) { document in
            LegalDocSheet(doc: document)
        }
        .fullScreenCover(item: $securityDestination) { destination in
            securityDestinationView(destination)
                .modifier(EusoEdgeSwipeBack(isEnabled: true) {
                    securityDestination = nil
                })
        }
        .onDisappear { flushNotificationSave() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · SETTINGS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Settings").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Notifications · dispatch presets · security · about").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var notificationsSection: some View {
        settingsHub(
            id: "notifications",
            icon: "bell.badge.fill",
            title: "Notifications",
            summary: "Tender · lifecycle · safety exceptions",
            rowCount: 3
        ) {
            if let settingsLoadError {
                inlineFailure(settingsLoadError) {
                    Task { await loadSettings() }
                }
            }
            if let notificationError {
                inlineFailure(notificationError) {
                    scheduleNotificationSave()
                }
            }
            if saving {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Saving notification preferences…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            if settingsLoadError == nil {
                VStack(alignment: .leading, spacing: 12) {
                    notifToggle(title: "Tender awarded",
                                subtitle: "Push · email · in-app · ESang ping",
                                binding: $tenderAwarded)
                    Divider().overlay(palette.borderFaint)
                    notifToggle(title: "Lifecycle stage advance",
                                subtitle: "Posted → Bidding → Awarded → Pickup → In transit → Delivery",
                                binding: $lifecycleStage)
                    Divider().overlay(palette.borderFaint)
                    notifToggle(title: "DVIR & HOS exception alerts",
                                subtitle: "Pre-trip · post-trip · 30m HOS · escort GPS divergence",
                                binding: $dvirHosAlerts)
                }
            }
        }
    }

    private func notifToggle(title: String, subtitle: String, binding: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .onChange(of: binding.wrappedValue) { _, _ in
                    scheduleNotificationSave()
                }
                .disabled(settingsLoadError != nil)
        }
    }

    private var dispatchPresetsSection: some View {
        settingsHub(
            id: "presets",
            icon: "slider.horizontal.3",
            title: "Dispatch presets",
            summary: "Reusable lanes · equipment · floor rates",
            rowCount: presets.count
        ) {
            HStack {
                Text("SAVED PRESETS · \(presets.count)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Button {
                    openNewPresetSheet()
                } label: {
                    Text("+ New preset").font(.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
            }
            actionFeedback
            if loading && presets.isEmpty {
                LifecycleCard { Text("Loading presets…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if presets.isEmpty {
                LifecycleCard { Text("No presets yet. Tap + New preset to save your first auto-accept rule.").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else {
                ForEach(presets) { p in presetCard(p) }
            }
        }
    }

    private func presetCard(_ p: DispatchPreset) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(presetTitle(p))
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    if p.autoAccept == true {
                        Text("AUTO-ACCEPT")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.18)))
                            .foregroundStyle(Color.green)
                    }
                }
                let parts: [String] = [
                    p.lane,
                    p.equipment,
                    p.cargoSummary,
                    p.floorRate.map { "floor $\($0)" },
                    p.awardedYTD.map { "\($0) awarded YTD" },
                ].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var actionFeedback: some View {
        if let actionError {
            LifecycleCard(accentDanger: true) {
                Text(actionError).font(EType.caption).foregroundStyle(Brand.danger)
            }
        } else if let actionMessage {
            LifecycleCard {
                Text(actionMessage).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var newPresetSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("New Dispatch Preset")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Save a reusable lane, equipment and rate template to your company dispatch catalog.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    LifecycleCard {
                        VStack(spacing: 10) {
                            presetField("Name", text: $presetName)
                            presetField("Origin city", text: $presetOriginCity)
                            presetField("Origin state", text: $presetOriginState, limit: 2)
                            presetField("Destination city", text: $presetDestinationCity)
                            presetField("Destination state", text: $presetDestinationState, limit: 2)
                            presetField("Trailer type", text: $presetTrailerType)
                            presetField("Cargo type", text: $presetCargoType)
                            presetField("Floor rate", text: $presetRate, keyboard: .decimalPad)
                            presetField("Instructions", text: $presetInstructions)
                        }
                    }
                    if let actionError {
                        Text(actionError)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                    }
                    Button {
                        Task { await createPreset() }
                    } label: {
                        HStack {
                            if savingPreset { ProgressView().tint(.white) }
                            Text(savingPreset ? "Saving…" : "Save preset")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(savingPreset || !presetFormValid)
                }
                .padding(18)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showNewPreset = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func presetField(_ title: String, text: Binding<String>, limit: Int? = nil, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            TextField(title, text: text)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .textInputAutocapitalization(limit == 2 ? .characters : .words)
                .keyboardType(keyboard)
                .onChange(of: text.wrappedValue) { _, value in
                    guard let limit, value.count > limit else { return }
                    text.wrappedValue = String(value.prefix(limit)).uppercased()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.bgSecondary))
        }
    }

    private var securitySection: some View {
        settingsHub(
            id: "security",
            icon: "lock.shield.fill",
            title: "Security",
            summary: "Two-factor · sessions · password",
            rowCount: 3
        ) {
            settingsActionRow(
                title: "Two-factor authentication",
                subtitle: "Manage authenticator and recovery codes",
                anchor: "security-two-factor"
            ) { securityDestination = .twoFactor }
            Divider().overlay(palette.borderFaint)
            settingsActionRow(
                title: "Active sessions",
                subtitle: "Review and revoke signed-in devices",
                anchor: "security-sessions"
            ) { securityDestination = .sessions }
            Divider().overlay(palette.borderFaint)
            settingsActionRow(
                title: "Change password",
                subtitle: "Verify your current password before changing it",
                anchor: "security-password"
            ) { securityDestination = .password }
        }
    }

    private var aboutSection: some View {
        settingsHub(
            id: "about",
            icon: "info.circle.fill",
            title: "About",
            summary: "Version · privacy · terms",
            rowCount: 3
        ) {
            settingsValueRow(title: "App version", subtitle: versionLabel)
            Divider().overlay(palette.borderFaint)
            settingsActionRow(
                title: "Privacy policy",
                subtitle: "Canonical in-app policy",
                anchor: "about-privacy"
            ) { presentingLegal = .privacyPolicy }
            Divider().overlay(palette.borderFaint)
            settingsActionRow(
                title: "Terms of service",
                subtitle: "Canonical in-app terms",
                anchor: "about-terms"
            ) { presentingLegal = .termsOfService }
        }
    }

    private func settingsHub<Content: View>(
        id: String,
        icon: String,
        title: String,
        summary: String,
        rowCount: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isOpen = expandedSection == id
        return LifecycleCard {
            Button {
                withAnimation(.easeOut(duration: 0.22)) {
                    expandedSection = isOpen ? "" : id
                    returnAnchor = "section-\(id)"
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Text(summary)
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    Spacer(minLength: 0)
                    Text("\(rowCount)")
                        .font(.system(size: 10, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(palette.bgCardSoft))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                Rectangle()
                    .fill(palette.borderFaint.opacity(0.4))
                    .frame(height: 1)
                    .padding(.vertical, 6)
                VStack(alignment: .leading, spacing: 12) { content() }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .id("section-\(id)")
    }

    private func settingsActionRow(
        title: String,
        subtitle: String,
        anchor: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            returnAnchor = anchor
            action()
        } label: {
            settingsRowLabel(title: title, subtitle: subtitle, showsChevron: true)
        }
        .buttonStyle(.plain)
        .id(anchor)
    }

    private func settingsValueRow(title: String, subtitle: String) -> some View {
        settingsRowLabel(title: title, subtitle: subtitle, showsChevron: false)
    }

    private func settingsRowLabel(title: String, subtitle: String, showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func presetTitle(_ preset: DispatchPreset) -> String {
        if let name = preset.name, !name.isEmpty { return name }
        return "\(preset.lane ?? "-") · \(preset.equipment ?? "-")"
    }

    private var presetFormValid: Bool {
        !presetName.trimmed.isEmpty &&
        !presetOriginCity.trimmed.isEmpty &&
        presetOriginState.trimmed.count == 2 &&
        !presetDestinationCity.trimmed.isEmpty &&
        presetDestinationState.trimmed.count == 2 &&
        !presetTrailerType.trimmed.isEmpty
    }

    private var currentNotificationSnapshot: CatalystNotificationSnapshot {
        CatalystNotificationSnapshot(
            tenderAwarded: tenderAwarded,
            lifecycleStage: lifecycleStage,
            dvirHosAlerts: dvirHosAlerts
        )
    }

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "v\(version) · build \(build)"
    }

    @ViewBuilder
    private func inlineFailure(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: retry)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func securityDestinationView(_ destination: CatalystSecurityDestination) -> some View {
        ZStack(alignment: .topLeading) {
            switch destination {
            case .twoFactor:
                TwoFactorManageScreen(
                    theme: palette,
                    roleLabel: "CATALYST",
                    showsBottomNav: false
                )
            case .sessions:
                SecuritySessionsScreen(
                    theme: palette,
                    roleLabel: "CATALYST",
                    showsBottomNav: false
                )
            case .password:
                CatalystChangePasswordScreen(theme: palette) {
                    actionMessage = "Password changed. Other sessions remain visible under Active sessions."
                    securityDestination = nil
                }
            }

            Button {
                securityDestination = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(palette.bgCard.opacity(0.96), in: Circle())
                    .overlay(Circle().strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .padding(.top, 8)
            .accessibilityLabel("Back to settings")
        }
    }

    private func openNewPresetSheet() {
        actionError = nil
        actionMessage = nil
        presetName = ""
        presetOriginCity = ""
        presetOriginState = ""
        presetDestinationCity = ""
        presetDestinationState = ""
        presetCargoType = ""
        presetTrailerType = ""
        presetRate = ""
        presetInstructions = ""
        showNewPreset = true
    }

    private func load() async {
        loading = true
        defer { loading = false }
        await loadSettings()
        do {
            struct In: Encodable { let limit: Int }
            presets = try await EusoTripAPI.shared.query("dispatch.getDispatchPresets", input: In(limit: 50))
        } catch {
            actionError = "Dispatch presets couldn't load. \(error.eusoUserCopy)"
        }
    }

    private func loadSettings() async {
        settingsLoadError = nil
        do {
            let response: AppSettings = try await EusoTripAPI.shared.queryNoInput("settings.getSettings")
            guard let notifications = response.notifications,
                  let tenderAwarded = notifications.tenderAwarded,
                  let lifecycleStage = notifications.lifecycleStage,
                  let dvirHosAlerts = notifications.dvirHosAlerts else {
                throw CatalystSettingsFailure.incompleteNotificationContract
            }
            settings = response
            let snapshot = CatalystNotificationSnapshot(
                tenderAwarded: tenderAwarded,
                lifecycleStage: lifecycleStage,
                dvirHosAlerts: dvirHosAlerts
            )
            applyingServerSettings = true
            tenderAwarded = snapshot.tenderAwarded
            lifecycleStage = snapshot.lifecycleStage
            dvirHosAlerts = snapshot.dvirHosAlerts
            persistedNotifications = snapshot
            applyingServerSettings = false
            notificationError = nil
        } catch {
            settingsLoadError = "Notification preferences couldn't load. \(error.eusoUserCopy)"
        }
    }

    private func scheduleNotificationSave() {
        guard !applyingServerSettings, settingsLoadError == nil else { return }
        notificationSaveTask?.cancel()
        let attempted = currentNotificationSnapshot
        notificationSaveTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await saveNotifications(attempted)
        }
    }

    private func flushNotificationSave() {
        notificationSaveTask?.cancel()
        guard !applyingServerSettings,
              settingsLoadError == nil,
              currentNotificationSnapshot != persistedNotifications else { return }
        let attempted = currentNotificationSnapshot
        notificationSaveTask = Task { await saveNotifications(attempted) }
    }

    private func saveNotifications(_ attempted: CatalystNotificationSnapshot) async {
        saving = true
        notificationError = nil
        defer { saving = false }
        struct In: Encodable {
            let tenderAwarded: Bool
            let lifecycleStage: Bool
            let dvirHosAlerts: Bool
        }
        struct Out: Decodable { let success: Bool }
        do {
            let output: Out = try await EusoTripAPI.shared.mutation(
                "settings.updateNotificationSettings",
                input: In(tenderAwarded: attempted.tenderAwarded,
                          lifecycleStage: attempted.lifecycleStage,
                          dvirHosAlerts: attempted.dvirHosAlerts)
            )
            guard output.success else { throw CatalystSettingsFailure.rejected }
            persistedNotifications = attempted
        } catch {
            if currentNotificationSnapshot == attempted {
                applyingServerSettings = true
                tenderAwarded = persistedNotifications.tenderAwarded
                lifecycleStage = persistedNotifications.lifecycleStage
                dvirHosAlerts = persistedNotifications.dvirHosAlerts
                applyingServerSettings = false
            }
            notificationError = "Notification preferences weren't saved. \(error.eusoUserCopy)"
        }
    }

    private func restorePosition(using proxy: ScrollViewProxy) {
        let fallback = "section-\(expandedSection.isEmpty ? "notifications" : expandedSection)"
        eusoRestoreScrollPosition(using: proxy, anchor: returnAnchor, fallback: fallback)
    }

    private func createPreset() async {
        actionError = nil
        actionMessage = nil
        guard presetFormValid else {
            actionError = "Name, lane states and trailer type are required."
            return
        }
        let cleanRate = presetRate.trimmed
        if !cleanRate.isEmpty && Decimal(string: cleanRate) == nil {
            actionError = "Floor rate must be a number."
            return
        }
        savingPreset = true
        defer { savingPreset = false }
        struct In: Encodable {
            let name: String
            let originCity: String
            let originState: String
            let destinationCity: String
            let destinationState: String
            let cargoType: String?
            let trailerType: String
            let rate: Decimal?
            let specialInstructions: String?
        }
        struct Out: Decodable { let success: Bool?; let id: String?; let name: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.createDispatchPreset",
                input: In(name: presetName.trimmed,
                          originCity: presetOriginCity.trimmed,
                          originState: presetOriginState.trimmed.uppercased(),
                          destinationCity: presetDestinationCity.trimmed,
                          destinationState: presetDestinationState.trimmed.uppercased(),
                          cargoType: presetCargoType.trimmed.nilIfEmpty,
                          trailerType: presetTrailerType.trimmed,
                          rate: cleanRate.isEmpty ? nil : Decimal(string: cleanRate),
                          specialInstructions: presetInstructions.trimmed.nilIfEmpty)
            )
            actionMessage = "Preset saved\(out.name.map { ": \($0)" } ?? "")."
            showNewPreset = false
            await load()
        } catch {
            actionError = "Dispatch preset wasn't saved. \(error.eusoUserCopy)"
        }
    }
}

private struct CatalystChangePasswordScreen: View {
    let theme: Theme.Palette
    let onChanged: () -> Void

    @Environment(\.palette) private var palette
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        Shell(theme: theme) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(LinearGradient.diagonal)
                            Text("CATALYST · ACCOUNT SECURITY")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1)
                                .foregroundStyle(LinearGradient.diagonal)
                        }
                        Text("Change password")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Text("Your current password is verified before the account credential changes.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }

                    LifecycleCard {
                        passwordField("Current password", text: $currentPassword, contentType: .password)
                        Divider().overlay(palette.borderFaint)
                        passwordField("New password", text: $newPassword, contentType: .newPassword)
                        Divider().overlay(palette.borderFaint)
                        passwordField("Confirm new password", text: $confirmation, contentType: .newPassword)
                    }

                    Text("Use at least 12 characters. The new password must differ from the current password.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)

                    if let errorMessage {
                        LifecycleCard(accentDanger: true) {
                            Text(errorMessage)
                                .font(EType.caption)
                                .foregroundStyle(Brand.danger)
                        }
                    }

                    Button {
                        Task { await changePassword() }
                    } label: {
                        HStack(spacing: 8) {
                            if saving { ProgressView().tint(.white) }
                            Text(saving ? "Changing password…" : "Change password")
                                .font(EType.body.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || !formValid)

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 14)
                .padding(.top, 64)
            }
        } nav: {
            EmptyView()
        }
    }

    private func passwordField(
        _ title: String,
        text: Binding<String>,
        contentType: UITextContentType
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            SecureField(title, text: text)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.vertical, 4)
    }

    private var formValid: Bool {
        !currentPassword.isEmpty &&
        newPassword.count >= 12 &&
        newPassword != currentPassword &&
        newPassword == confirmation
    }

    @MainActor
    private func changePassword() async {
        guard formValid else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        struct Input: Encodable {
            let currentPassword: String
            let newPassword: String
        }
        struct Output: Decodable {
            let success: Bool
            let changedAt: String?
        }
        do {
            let output: Output = try await EusoTripAPI.shared.mutation(
                "profile.changePassword",
                input: Input(currentPassword: currentPassword, newPassword: newPassword)
            )
            guard output.success else { throw CatalystSettingsFailure.rejected }
            currentPassword = ""
            newPassword = ""
            confirmation = ""
            onChanged()
        } catch {
            errorMessage = "Password wasn't changed. \(error.eusoUserCopy)"
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}

#Preview("311 Settings · Dark")  { CatalystSettingsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("311 Settings · Light") { CatalystSettingsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
