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
        
        // Server returns push, email, sms as objects with nested booleans (e.g., { loadUpdates: bool, ... })
        // Coerce to scalar by extracting the loadUpdates field from each object
        if let pushObj = try c.decodeIfPresent([String: Bool].self, forKey: .push) {
            self.push = pushObj["loadUpdates"]
        } else {
            self.push = try c.decodeIfPresent(Bool.self, forKey: .push)
        }
        
        if let emailObj = try c.decodeIfPresent([String: Bool].self, forKey: .email) {
            self.email = emailObj["loadUpdates"]
        } else {
            self.email = try c.decodeIfPresent(Bool.self, forKey: .email)
        }
        
        if let smsObj = try c.decodeIfPresent([String: Bool].self, forKey: .sms) {
            self.sms = smsObj["loadUpdates"]
        } else {
            self.sms = try c.decodeIfPresent(Bool.self, forKey: .sms)
        }
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
    @State private var settings: AppSettings?
    @State private var presets: [DispatchPreset] = []
    @State private var tenderAwarded: Bool = true
    @State private var lifecycleStage: Bool = true
    @State private var dvirHosAlerts: Bool = true
    @State private var loading: Bool = true
    @State private var saving: Bool = false
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

    var body: some View {
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
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showNewPreset) { newPresetSheet }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · SETTINGS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Settings").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Notifications · dispatch presets · security · about").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTIFICATIONS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            LifecycleCard {
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
                    Task { await saveNotifications() }
                }
        }
    }

    private var dispatchPresetsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DISPATCH PRESETS · \(presets.count)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("SECURITY").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 12) {
                    settingsRow(title: "Two-factor auth", subtitle: "Active · authenticator · SMS backup", cta: "Manage")
                    Divider().overlay(palette.borderFaint)
                    settingsRow(title: "Active sessions · 2", subtitle: "iPhone 17 Pro Max · Truck iPad Pro", cta: "View")
                    Divider().overlay(palette.borderFaint)
                    settingsRow(title: "Change password", subtitle: "Last changed 64 days ago", cta: "Update")
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ABOUT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 12) {
                    settingsRow(title: "App version", subtitle: "v2.8.1 · build 302 · EusoTrip 2027", cta: nil)
                    Divider().overlay(palette.borderFaint)
                    settingsRow(title: "Privacy policy", subtitle: "Read the latest", cta: "Open")
                    Divider().overlay(palette.borderFaint)
                    settingsRow(title: "Terms of service", subtitle: "Eusorone Technologies", cta: "Open")
                }
            }
        }
    }

    private func settingsRow(title: String, subtitle: String, cta: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            if let cta {
                Text(cta).font(.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
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
        loading = true; defer { loading = false }
        do {
            settings = try await EusoTripAPI.shared.queryNoInput("settings.getSettings")
            if let n = settings?.notifications {
                tenderAwarded = n.tenderAwarded ?? true
                lifecycleStage = n.lifecycleStage ?? true
                dvirHosAlerts = n.dvirHosAlerts ?? true
            }
        } catch { /* */ }
        do {
            struct In: Encodable { let limit: Int }
            presets = try await EusoTripAPI.shared.query("dispatch.getDispatchPresets", input: In(limit: 50))
        } catch {
            actionError = "Dispatch presets couldn't load. \(error.eusoUserCopy)"
        }
    }

    private func saveNotifications() async {
        saving = true; defer { saving = false }
        struct In: Encodable {
            let tenderAwarded: Bool
            let lifecycleStage: Bool
            let dvirHosAlerts: Bool
        }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "settings.updateNotificationSettings",
                input: In(tenderAwarded: tenderAwarded,
                          lifecycleStage: lifecycleStage,
                          dvirHosAlerts: dvirHosAlerts)
            )
        } catch { /* silent — toggle stays in local state */ }
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

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}

#Preview("311 Settings · Dark")  { CatalystSettingsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("311 Settings · Light") { CatalystSettingsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
