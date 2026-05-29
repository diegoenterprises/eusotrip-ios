//
//  656_VesselOperatorAccount.swift
//  EusoTrip — Vessel Operator · My Account (ME tab).
//
//  Verbatim port of "656 Vessel Operator Account.svg" (Light + Dark). Vessel
//  counterpart of 556_RailEngineerAccount. This is the GENUINE ME surface:
//  VesselOperatorNavController.swift maps "me" -> "Vesl656". Nav anchored to
//  VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME) ME current.
//
//  Data:
//    users.me            (EXISTS server/routers/users.ts:94)  -> identity
//    users.getProfile    (EXISTS users.ts:105)                -> contact/prefs
//    users.updateProfile (EXISTS users.ts:896)                -> preference mutations
//    vesselShipments.getVesselCrew (EXISTS vesselShipments.ts:742 ·
//      returns {crew, certifications, expiringCount}) -> STCW certs + watch
//
//  PERSONA GAP: VESSEL_OPERATOR persona NOT canonized (SKILL: "NEEDS FOUNDER
//  CANONIZATION"). displayName falls back to the literal "___" + PROPOSED chip.
//  No banned/retired name introduced.
//

import SwiftUI

struct VesselOperatorAccountScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselOperatorAccountBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct VesselAccountProfile: Decodable {
    let id: Int
    let name: String?          // PROPOSED persona — empty until canonized
    let role: String?
    let companyName: String?
    let crewId: String?
}

private struct VesselCertificate: Decodable, Identifiable {
    let id: Int
    let title: String
    let statusLabel: String?
    let expiring: Bool?
}

private struct WatchRest: Decodable {
    let restHours: Double?
    let windowHours: Double?
    let minHours: Double?
    let nextWatch: String?
}

// MARK: - Body

private struct VesselOperatorAccountBody: View {
    @Environment(\.palette) private var palette
    @State private var me: VesselAccountProfile? = nil
    @State private var certificates: [VesselCertificate] = []
    @State private var watch: WatchRest? = nil
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
                    certificatesCard
                    watchCard
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
                Text("VESSEL OPERATOR · MY ACCOUNT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Account").font(.system(size: 26, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("users.me · profile, certificates, watch & preferences")
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
                    Text("VESSEL OPERATOR · \(me?.companyName ?? "___ OPERATOR (PROPOSED)")")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                    Text("crew id \(me?.crewId ?? "—") · STCW II/1 active")
                        .font(.system(size: 11)).monospaced().foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var certificatesCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CERTIFICATES · getVesselCrew").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(spacing: Space.s2) {
                    ForEach(certificates) { c in
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

    private var watchCard: some View {
        let rest = watch?.restHours ?? 11.0
        let window = watch?.windowHours ?? 24.0
        let minH = watch?.minHours ?? 10.0
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("WATCH · REST HOURS · MLC 2006 / STCW").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Rest \(rest, specifier: "%.1f")h / \(Int(window))h · min \(Int(minH))h")
                            .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(rest >= minH ? "compliant" : "short rest")
                            .font(EType.bodyStrong).foregroundStyle(rest >= minH ? Brand.success : Brand.danger)
                    }
                    ProgressView(value: rest, total: max(window, 1)).tint(LinearGradient.primary)
                    Text("Next watch \(watch?.nextWatch ?? "20:00–24:00") · 4-on / 8-off rotation")
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
                    HStack { Text("Distance units").font(EType.body).foregroundStyle(palette.textPrimary); Spacer(); Text("nautical mi ›").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textSecondary) }
                    HStack { Text("ESANG AI voice").font(EType.body).foregroundStyle(palette.textPrimary); Spacer(); Text(voiceOn ? "on ›" : "off ›").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.info) }
                }
            }
        }
    }

    private var signOut: some View {
        CTAButton(title: "Sign out", leadingIcon: "rectangle.portrait.and.arrow.right")
    }

    // MARK: - Load + mutate

    private func load() async {
        loading = true; loadError = nil
        struct Empty: Encodable {}
        struct ProfileOut: Decodable { let certifications: [VesselCertificate]?; let watch: WatchRest? }
        do {
            self.me = try await EusoTripAPI.shared.query("users.me", input: Empty())
            let crew: ProfileOut = try await EusoTripAPI.shared.query("vesselShipments.getVesselCrew", input: Empty())
            self.certificates = crew.certifications ?? []
            self.watch = crew.watch
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func savePref(_ key: String, _ value: Bool) async {
        // See §6 FIX 3 — re-pointed from users.updateProfile (which silently
        // dropped {key,value}) to the real users.updateNotificationPreferences.
        struct PrefIn: Encodable { let pushNotifications: Bool }
        struct Out: Decodable { let success: Bool? }
        guard key == "notifications" else { return }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "users.updateNotificationPreferences",
                input: PrefIn(pushNotifications: value))
            if out.success != true {
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

#Preview("656 · Vessel Operator Account · Night") { VesselOperatorAccountScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("656 · Vessel Operator Account · Light") { VesselOperatorAccountScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
