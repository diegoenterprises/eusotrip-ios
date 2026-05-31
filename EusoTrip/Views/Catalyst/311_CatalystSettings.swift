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
//    dispatch.getDispatchPresets (read via dispatchTemplates table) — list
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
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
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
                    NotificationCenter.default.post(name: NSNotification.Name("eusoCatalystNewPresetRequested"), object: nil)
                } label: {
                    Text("+ New preset").font(.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
            }
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
                    Text("\(p.lane ?? "—") · \(p.equipment ?? "—")")
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
        // Presets are sourced from existing dispatchTemplates table.
        // Future: settings.getDispatchPresets once shipped.
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
}

#Preview("311 Settings · Dark")  { CatalystSettingsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("311 Settings · Light") { CatalystSettingsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
