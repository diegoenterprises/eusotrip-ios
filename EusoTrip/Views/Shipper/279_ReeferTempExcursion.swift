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
            LifecycleMapCard(live: live, label: "TRUCK POSITION", icon: "thermometer.high", mode: .full)
            // 799-class probe chart over the SAME live `reeferTemp.getReadings`
            // rows the ledger below lists — grouped by zone, chronological.
            // Only mounts when ≥2 samples exist in some zone (a single point
            // is not a trace); the FSMA 40°F ceiling is a regulatory constant
            // and no commanded-setpoint column ships on this proc, so the SET
            // rail is honestly omitted.
            if !chartZones.isEmpty {
                ReeferTempLogChart(
                    zones: chartZones,
                    setpointF: nil,
                    ceilingF: 40,
                    title: "REEFER TEMP LOG · LIVE"
                )
            }
            tempCard
            ctaRow
        }
        .task { await loadReadings() }
    }

    /// Group the live readings by zone → chart traces. Mirrors the 652
    /// vessel grouping; canonical front/center/rear first, then extras.
    private var chartZones: [TempZone] {
        guard !readings.isEmpty else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func parse(_ s: String) -> Date? {
            iso.date(from: s) ?? isoPlain.date(from: s)
        }
        var grouped: [String: [TempZone.Reading]] = [:]
        for r in readings {
            guard let t = parse(r.timestamp) else { continue }
            let key = (r.zone ?? "center").lowercased()
            grouped[key, default: []].append(.init(t: t, tempF: r.temp))
        }
        func zone(_ key: String, _ name: String, _ pos: TempZone.Position, _ color: Color) -> TempZone? {
            guard let rs = grouped[key]?.sorted(by: { $0.t < $1.t }), rs.count >= 2 else { return nil }
            return TempZone(name: name, position: pos, color: color, readings: rs)
        }
        var zones: [TempZone] = []
        if let z = zone("front",  "Front",  .front,  Brand.success) { zones.append(z) }
        if let z = zone("center", "Center", .center, Brand.blue)    { zones.append(z) }
        if let z = zone("rear",   "Rear",   .rear,   Brand.warning) { zones.append(z) }
        let extras = grouped.keys
            .filter { !["front", "center", "rear"].contains($0) }
            .sorted().prefix(3)
        for key in extras {
            if let z = zone(key, key.capitalized, .center, Brand.info) { zones.append(z) }
        }
        return zones
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
                        Text(r.zone ?? "-").font(EType.caption).foregroundStyle(palette.textSecondary)
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
