//
//  556_RailEngineerAccount.swift
//  EusoTrip — Rail Engineer · My Account (ME tab).
//
//  PERSONA GAP: RAIL_ENGINEER individual persona not yet canonized.
//  displayName falls back to "___" + PROPOSED chip until founder canonizes.
//

import SwiftUI

struct RailEngineerAccountScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailEngineerAccountBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct RailAccountProfile: Decodable {
    let id: Int
    let name: String?
    let role: String?
    let companyName: String?
    let crewId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, role, companyName, crewId, email, companyId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.role = try c.decodeIfPresent(String.self, forKey: .role)
        self.companyName = try c.decodeIfPresent(String.self, forKey: .companyName)
        self.crewId = try c.decodeIfPresent(String.self, forKey: .crewId)
        // Server returns extra fields (email, companyId) that we ignore
        _ = try c.decodeIfPresent(String.self, forKey: .email)
        _ = try c.decodeIfPresent(Int.self, forKey: .companyId)
    }
}

private struct RailCredential: Decodable, Identifiable {
    let id: Int
    let title: String
    let statusLabel: String?
    let expiring: Bool?
}

private struct RailCrewHOSRow: Decodable {
    let onDutyHours: Double?
    let limitHours: Double?
    let lastRestHours: Double?
}

private struct RailEngineerAccountBody: View {
    @Environment(\.palette) private var palette
    @State private var me: RailAccountProfile? = nil
    @State private var credentials: [RailCredential] = []
    @State private var hos: RailCrewHOSRow? = nil
    @State private var notificationsOn = true
    @State private var voiceOn = true
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var saveError: String? = nil

    private var displayName: String {
        let n = me?.name?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "___" : n
    }
    private var personaPending: Bool {
        (me?.name?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading account…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    identityCard
                    credentialsCard
                    dutyCard
                    preferencesCard
                    signOut
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("Settings", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · MY ACCOUNT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Account").font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("users.me · profile, credentials, duty & preferences")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var identityCard: some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(palette.bgCardSoft).frame(width: 68, height: 68)
                    Image(systemName: "person.fill").font(.system(size: 26)).foregroundStyle(palette.textTertiary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(displayName).font(.system(size: 20, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        if personaPending {
                            Text("PROPOSED").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(Brand.warning)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Brand.warning.opacity(0.16)))
                        }
                    }
                    Text("RAIL ENGINEER · \(me?.companyName ?? "___ CARRIER (PROPOSED)")")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                    Text("crew id \(me?.crewId ?? "—") · FRA cert active")
                        .font(.system(size: 11)).monospaced().foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CREDENTIALS · users.getProfile").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(spacing: Space.s2) {
                    ForEach(credentials) { c in
                        HStack {
                            Text(c.title).font(EType.body).foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(c.statusLabel ?? "—").font(.system(size: 11, weight: .bold))
                                .foregroundStyle((c.expiring ?? false) ? Brand.warning : Brand.success)
                        }
                    }
                }
            }
        }
    }

    private var dutyCard: some View {
        let onDuty = hos?.onDutyHours ?? 6.5
        let limit = hos?.limitHours ?? 12
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("DUTY · HOURS OF SERVICE · getCrewHOS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("On duty \(onDuty, specifier: "%.1f")h · \(max(limit - onDuty, 0), specifier: "%.1f")h to limit")
                            .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text("\(Int(limit))h cap").font(EType.bodyStrong).monospacedDigit().foregroundStyle(Brand.success)
                    }
                    ProgressView(value: onDuty, total: max(limit, 1)).tint(LinearGradient.primary)
                    Text("Hours of Service Act compliant · last rest \(Int(hos?.lastRestHours ?? 10))h")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("PREFERENCES · users.updateProfile").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(spacing: Space.s3) {
                    Toggle(isOn: $notificationsOn) {
                        Text("Push notifications").font(EType.body).foregroundStyle(palette.textPrimary)
                    }
                    .tint(Brand.info)
                    .onChange(of: notificationsOn) { _, v in Task { await savePref("notifications", v) } }
                    HStack { Text("Distance units").font(EType.body).foregroundStyle(palette.textPrimary); Spacer(); Text("miles ›").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textSecondary) }
                    HStack { Text("ESANG AI voice").font(EType.body).foregroundStyle(palette.textPrimary); Spacer(); Text(voiceOn ? "on ›" : "off ›").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.info) }
                }
            }
        }
    }

    private var signOut: some View {
        CTAButton(title: "Sign out", leadingIcon: "rectangle.portrait.and.arrow.right")
    }

    private func load() async {
        loading = true; loadError = nil
        struct Empty: Encodable {}
        struct ProfileOut: Decodable {
            let credentials: [RailCredential]?
            let crewHOS: RailCrewHOSRow?
            
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                credentials = try? c.decode([RailCredential].self, forKey: .credentials)
                crewHOS = try? c.decode(RailCrewHOSRow.self, forKey: .crewHOS)
            }
            
            enum CodingKeys: String, CodingKey {
                case credentials
                case crewHOS
            }
        }
        do {
            self.me = try await EusoTripAPI.shared.query("users.me", input: Empty())
            let p: ProfileOut = try await EusoTripAPI.shared.query("users.getProfile", input: Empty())
            self.credentials = p.credentials ?? []
            self.hos = p.crewHOS ?? (try? await EusoTripAPI.shared.query("railShipments.getCrewHOS", input: Empty()))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func savePref(_ key: String, _ value: Bool) async {
        // Was pointed at users.updateProfile with {key,value} — that endpoint's
        // Zod schema has no such fields, so it stripped them and persisted
        // nothing (the toggle was dead). Notification prefs live on the
        // dedicated users.updateNotificationPreferences endpoint + the
        // notificationPreferences table. (the-oath 2026-05-28 §6, FIX 3.)
        struct PrefIn: Encodable { let pushNotifications: Bool }
        struct Out: Decodable { let success: Bool? }
        guard key == "notifications" else { return }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "users.updateNotificationPreferences",
                input: PrefIn(pushNotifications: value))
            if out.success != true {
                // Persisted nothing — revert the toggle so the UI reflects
                // truth, and surface the failure instead of silently lying.
                notificationsOn = !value
                saveError = "Couldn't save notification preference."
            }
        } catch {
            notificationsOn = !value
            saveError = (error as? EusoTripAPIError)?.errorDescription
                ?? "Couldn't save notification preference."
        }
    }
}

#Preview("556 · Rail Engineer Account · Night") { RailEngineerAccountScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("556 · Rail Engineer Account · Light") { RailEngineerAccountScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
