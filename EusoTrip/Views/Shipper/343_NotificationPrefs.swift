//
//  343_NotificationPrefs.swift
//  EusoTrip — Shipper · Notification preferences (Arc K).
//

import SwiftUI

struct NotificationPrefsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { NotificationPrefsBody() } nav: { shipperLifecycleNav() }
    }
}

private struct NotificationPrefsBody: View {
    @Environment(\.palette) private var palette
    @State private var prefs: [String: ChannelToggle] = [:]
    @State private var loading = true
    @State private var sending = false
    @State private var saved = false

    private struct ChannelToggle { var push: Bool = true; var email: Bool = true; var sms: Bool = false }

    private let categories: [(key: String, label: String)] = [
        ("bid_received", "Bid received"),
        ("bid_awarded", "Bid awarded"),
        ("load_status_changed", "Load status change"),
        ("geofence_event", "Geofence pre-arrival / arrival"),
        ("settlement_paid", "Settlement paid"),
        ("settlement_disputed", "Settlement disputed"),
        ("doc_uploaded", "Document uploaded"),
        ("compliance_expiring", "Compliance expiring"),
        ("ai_recommendation", "ESang recommendation"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if saved { LifecycleCard(accentGradient: true) { Text("Saved.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                content
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bell.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · NOTIFICATIONS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Notification preferences").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var content: some View {
        VStack(spacing: 8) {
            ForEach(categories, id: \.key) { cat in
                LifecycleCard {
                    LifecycleSection(label: cat.label.uppercased(), icon: "bell")
                    HStack {
                        Text("Push").font(EType.body).foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 0)
                        Toggle("", isOn: bindingFor(cat.key, key: \.push)).labelsHidden()
                    }
                    HStack {
                        Text("Email").font(EType.body).foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 0)
                        Toggle("", isOn: bindingFor(cat.key, key: \.email)).labelsHidden()
                    }
                    HStack {
                        Text("SMS").font(EType.body).foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 0)
                        Toggle("", isOn: bindingFor(cat.key, key: \.sms)).labelsHidden()
                    }
                }
            }
        }
    }

    private func bindingFor(_ key: String, key kp: WritableKeyPath<ChannelToggle, Bool>) -> Binding<Bool> {
        Binding(
            get: { (prefs[key] ?? ChannelToggle())[keyPath: kp] },
            set: { v in
                var c = prefs[key] ?? ChannelToggle()
                c[keyPath: kp] = v
                prefs[key] = c
            }
        )
    }

    private var ctaRow: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Saving…" : "Save preferences").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending)
    }

    private func load() async {
        loading = true
        struct Channel: Decodable { let push: Bool?; let email: Bool?; let sms: Bool? }
        struct Out: Decodable { let prefs: [String: Channel]? }
        do {
            let r: Out = try await EusoTripAPI.shared.queryNoInput("users.getNotificationPreferences")
            for (k, v) in (r.prefs ?? [:]) {
                prefs[k] = ChannelToggle(push: v.push ?? true, email: v.email ?? true, sms: v.sms ?? false)
            }
        } catch { /* tolerate */ }
        loading = false
    }

    private func save() async {
        sending = true
        struct ChannelIn: Encodable { let push: Bool; let email: Bool; let sms: Bool }
        struct In: Encodable { let prefs: [String: ChannelIn] }
        struct Out: Decodable { let success: Bool }
        let payload: [String: ChannelIn] = prefs.mapValues { ChannelIn(push: $0.push, email: $0.email, sms: $0.sms) }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("users.setNotificationPreferences", input: In(prefs: payload))
            saved = true
        } catch { /* surface inline */ }
        sending = false
    }
}

#Preview("343 · Notification prefs · Night") { NotificationPrefsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("343 · Notification prefs · Afternoon") { NotificationPrefsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
