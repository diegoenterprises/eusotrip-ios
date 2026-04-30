//
//  397_RolePick.swift
//  EusoTrip — Shipper · Role pick (Arc B+ / Arc A onboarding).
//

import SwiftUI

struct RolePickScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RolePickBody() } nav: { shipperLifecycleNav() }
    }
}

private struct RolePickBody: View {
    @Environment(\.palette) private var palette
    @State private var role: String = "SHIPPER"
    @State private var sending: Bool = false
    @State private var actionError: String? = nil

    private let roles: [(key: String, label: String, sub: String, icon: String)] = [
        ("SHIPPER",  "Shipper",       "Post loads, manage rates, track shipments", "shippingbox.fill"),
        ("CATALYST", "Carrier (Catalyst)", "Bid on loads, manage fleet, get paid",  "truck.box.fill"),
        ("DRIVER",   "Driver",        "Drive loads, capture POD, get paystubs",   "person.fill"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                rolesGrid
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("EUSOTRIP · WELCOME").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pick your role").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("You can connect a second role later from the Me tab.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var rolesGrid: some View {
        VStack(spacing: 8) {
            ForEach(roles, id: \.key) { r in
                Button { role = r.key } label: {
                    LifecycleCard(accentGradient: role == r.key) {
                        HStack(spacing: 12) {
                            Image(systemName: r.icon).font(.system(size: 22, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.label).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                                Text(r.sub).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: role == r.key ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(role == r.key ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var ctaRow: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Setting up…" : "Continue").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending)
    }

    private func save() async {
        sending = true; actionError = nil
        struct In: Encodable { let role: String }
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("auth.setRole", input: In(role: role))
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "398"])
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("397 · Role pick · Night") { RolePickScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("397 · Role pick · Afternoon") { RolePickScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
