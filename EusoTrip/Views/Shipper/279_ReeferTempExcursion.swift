//
//  279_ReeferTempExcursion.swift
//  EusoTrip — Shipper · REEFER · temp excursion (refactored).
//
//  Pulls the same lifecycle snapshot + reefer-temp readings via the
//  existing `reeferTemp.getReadings` endpoint identified in the audit.
//

import SwiftUI

struct ReeferTempExcursionScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · REEFER · TEMP EXCURSION", cycleStatus: "in_transit") { live in
                ReeferBody(live: live, loadId: loadId)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct ReeferBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    @State private var readings: [ReeferReading] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    private struct ReeferReading: Decodable, Hashable {
        let zone: String?
        let temp: Double
        let timestamp: String
    }
    private struct ReadingsInput: Encodable { let loadId: Int }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            cargoCard
            tempCard
            ctaRow
        }
        .task { await loadReadings() }
    }

    private var cargoCard: some View {
        LifecycleCard(accentDanger: true) {
            LifecycleSection(label: "CARGO", icon: "shippingbox")
            LifecycleRow(label: "Cargo type", value: dashIfEmpty(live.load.cargoType))
            LifecycleRow(label: "Equipment",  value: dashIfEmpty(live.load.equipmentType))
            LifecycleRow(label: "Lane",       value: laneDisplay(live))
            LifecycleRow(label: "Driver",     value: dashIfEmpty(live.driver?.name))
            LifecycleRow(label: "Carrier",    value: dashIfEmpty(live.carrier?.name))
        }
    }

    private var tempCard: some View {
        LifecycleCard {
            LifecycleSection(label: "TEMP READINGS", icon: "thermometer")
            if loading {
                Text("Loading reefer log…").font(EType.caption).foregroundStyle(palette.textSecondary)
            } else if let err = loadError {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            } else if readings.isEmpty {
                Text("No reefer log entries on file for this load.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                ForEach(readings.suffix(8), id: \.self) { r in
                    HStack {
                        Text(humanISO(r.timestamp, format: "HH:mm")).font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textTertiary)
                        Text(r.zone ?? "—").font(EType.caption).foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                        Text(String(format: "%.1f°F", r.temp))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(r.temp > 38 || r.temp < 33 ? Brand.danger : palette.textPrimary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "219", "loadId": loadId, "mode": "create", "claimType": "reefer_excursion"])
            } label: {
                Text("File freight claim").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Button {
                if let p = live.driver?.phone, let url = URL(string: "tel://\(p.filter(\.isNumber))") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(systemName: "phone.fill").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44).background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(live.driver?.phone?.isEmpty != false)
        }
    }

    private func loadReadings() async {
        loading = true; loadError = nil
        let intId = Int(loadId.replacingOccurrences(of: "load_", with: "")) ?? Int(loadId) ?? -1
        guard intId > 0 else { loading = false; return }
        do {
            let rs: [ReeferReading] = try await EusoTripAPI.shared.query(
                "reeferTemp.getReadings",
                input: ReadingsInput(loadId: intId)
            )
            readings = rs
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("279 · Reefer · Temp excursion · Night") {
    ReeferTempExcursionScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("279 · Reefer · Temp excursion · Afternoon") {
    ReeferTempExcursionScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
