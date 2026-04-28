//
//  262_AwardedPrePickup.swift
//  EusoTrip — Shipper · Stage 3 · AWARDED · pre-pickup (refactored).
//

import SwiftUI

struct AwardedPrePickupScreen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(
                loadId: loadId,
                eyebrow: "SHIPPER · AWARDED · STAGE 3 OF 8",
                cycleStatus: "assigned"
            ) { live in
                AwardedBody(live: live, loadId: loadId)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct AwardedBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            carrierCard
            driverCard
            etaCard
            commsRow
        }
    }

    private var carrierCard: some View {
        LifecycleCard(accentGradient: live.carrier != nil) {
            LifecycleSection(label: "CARRIER", icon: "checkmark.seal.fill")
            if let c = live.carrier {
                HStack(spacing: 10) {
                    Text(initials(c.name))
                        .font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 56, height: 56).background(LinearGradient.diagonal).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        Text(["USDOT \(dashIfEmpty(c.dotNumber))", "MC \(dashIfEmpty(c.mcNumber))"].joined(separator: " · "))
                            .font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("Awaiting carrier assignment.").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var driverCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DRIVER", icon: "person.fill")
            if let d = live.driver {
                LifecycleRow(label: "Name",  value: d.name)
                LifecycleRow(label: "Email", value: dashIfEmpty(d.email))
                LifecycleRow(label: "Phone", value: dashIfEmpty(d.phone))
            } else {
                Text("Awaiting driver assignment.").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            if let v = live.vehicle {
                LifecycleRow(label: "Truck",   value: dashIfEmpty(v.vehicleNumber))
                LifecycleRow(label: "VIN",     value: dashIfEmpty(v.vin))
                LifecycleRow(label: "Make",    value: [v.make, v.model].compactMap { $0 }.joined(separator: " "))
            }
        }
    }

    private var etaCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ETA TO PICKUP", icon: "location.north.line")
            LifecycleRow(label: "Pickup window", value: humanISO(live.load.pickupDate))
            LifecycleRow(label: "Facility",      value: dashIfEmpty(live.pickup?.facilityName))
            LifecycleRow(label: "Address",       value: dashIfEmpty(live.pickup?.address))
            if let appt = live.pickup?.appointmentStart {
                LifecycleRow(label: "Appointment", value: humanISO(appt))
            }
        }
    }

    private var commsRow: some View {
        HStack(spacing: 8) {
            commsButton(icon: "phone.fill", label: "Driver", action: callDriver, enabled: live.driver?.phone?.isEmpty == false)
            commsButton(icon: "phone.fill", label: "Facility", action: callFacility, enabled: live.pickup?.contactPhone?.isEmpty == false)
            commsButton(icon: "doc.text.fill", label: "Contract", action: openContract, enabled: true)
        }
    }

    private func commsButton(icon: String, label: String, action: @escaping () -> Void, enabled: Bool) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(enabled ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(!enabled)
    }

    private func callDriver() {
        guard let phone = live.driver?.phone, let url = URL(string: "tel://\(phone.filter(\.isNumber))") else { return }
        UIApplication.shared.open(url)
    }

    private func callFacility() {
        guard let phone = live.pickup?.contactPhone, let url = URL(string: "tel://\(phone.filter(\.isNumber))") else { return }
        UIApplication.shared.open(url)
    }

    private func openContract() {
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "300", "loadId": loadId]
        )
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)) }.joined().uppercased()
    }
}

#Preview("262 · Awarded · Pre-pickup · Night") {
    AwardedPrePickupScreen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}

#Preview("262 · Awarded · Pre-pickup · Afternoon") {
    AwardedPrePickupScreen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
