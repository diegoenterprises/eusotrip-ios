//
//  243_ShipperLifecycleSextet.swift
//  EusoTrip — Shipper · Lifecycle counterparty sextet
//                    (243 / 244 / 245 / 246 / 247 / 249).
//
//  Bundled file because all six SVGs share the same structure:
//    Header eyebrow + stage subtitle
//    §-banner with stage citation
//    Carrier card (driver + dispatcher + USDOT/MC)
//    4-tile KPI grid (stage-specific)
//
//  Pixel-match to:
//    243 Shipper At Gate.svg
//    244 Shipper At Dock.svg
//    245 Shipper Departing.svg
//    246 Shipper Pre-Delivery.svg
//    247 Shipper At Delivery.svg
//    249 Shipper Load Closed.svg
//
//  All six read off loads.getById(loadId) and the existing lifecycle
//  status field. Bottom nav frozen per doctrine.
//

import SwiftUI

private struct LifecycleLoad: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let pickupState: String?
    let destCity: String?
    let destState: String?
    let trailerType: String?
    let cargoType: String?
    let status: String?
    let rate: String?
    let palletCount: Int?
    let assignedDriverName: String?
    let carrierName: String?
    let dockNumber: String?
    let dwellMinutes: Int?
    let temperatureF: Double?
    let pickupDate: String?
    let deliveryDate: String?
    let actualDeliveryDate: String?
    let podCertId: String?
}

// MARK: - Shared body factory

private struct LifecycleSection: Hashable {
    let stage: String       // "AT GATE", "AT DOCK", ...
    let citation: String    // "§277 · WITHIN-TRACK THIRD-PORT 2/3"
    let title: String       // "Driver at the gate"
    let kpis: [LifecycleKPI]
}

private struct LifecycleKPI: Hashable {
    let label: String
    let value: String
    let subtitle: String
    let color: Color
}

private struct LifecycleScreenShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content

    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Post",  systemImage: "plus.rectangle",  isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true),
                           NavSlot(label: "Me",    systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct LifecycleBody: View {
    let loadId: String
    let stageEyebrow: String
    let sectionFor: (LifecycleLoad?) -> LifecycleSection
    let subtitleFor: (LifecycleLoad?) -> String

    @Environment(\.palette) private var palette
    @State private var load: LifecycleLoad?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && load == nil {
                    LifecycleCard { Text("Loading load context…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    let s = sectionFor(load)
                    contextBanner(s)
                    if let l = load { carrierCard(l) }
                    kpiGrid(s.kpis)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load(loadId) }
        .refreshable { await load(loadId) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(stageEyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(sectionFor(load).title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(subtitleFor(load)).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func contextBanner(_ s: LifecycleSection) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(s.stage) · \(s.citation)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                if let l = load {
                    Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · \(l.pickupCity ?? "—") → \(l.destCity ?? "—") · \(l.trailerType ?? "—")")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private func carrierCard(_ l: LifecycleLoad) -> some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                    Text(initialsFor(l.assignedDriverName)).font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.carrierName ?? "—").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    if let n = l.assignedDriverName { Text(n).font(.caption).foregroundStyle(palette.textSecondary) }
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ kpis: [LifecycleKPI]) -> some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(kpis, id: \.self) { k in
                kpi(k.label, k.value, k.subtitle, k.color)
            }
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private func initialsFor(_ name: String?) -> String {
        guard let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return "—" }
        let parts = n.split(separator: " ").map(String.init)
        let f = parts.first?.first.map(String.init) ?? ""
        let l = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        return (f + l).uppercased()
    }

    @MainActor
    private func load(_ id: String) async {
        loading = true; defer { loading = false }
        struct In: Encodable { let id: String }
        do { self.load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: id)) } catch { /* */ }
    }
}

// MARK: - 243 At Gate

struct ShipperAtGateScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        LifecycleScreenShell(theme: theme) {
            LifecycleBody(
                loadId: loadId,
                stageEyebrow: "SHIPPER · LOADS · IN TRANSIT · AT GATE",
                sectionFor: { l in
                    LifecycleSection(
                        stage: "SHIPPER AT GATE",
                        citation: "§277 · WITHIN-TRACK THIRD-PORT 2/3",
                        title: "Driver at the gate",
                        kpis: [
                            .init(label: "DOCK", value: l?.dockNumber ?? "—", subtitle: "bay live", color: .blue),
                            .init(label: "DWELL", value: "0:00", subtitle: "2H FREE", color: .green),
                            .init(label: "PAYABLE", value: "$\(l?.rate ?? "—")", subtitle: "NET-30", color: .green),
                            .init(label: "ETA-LOAD", value: "~2h", subtitle: "estimated", color: .orange),
                        ]
                    )
                },
                subtitleFor: { l in "Dock \(l?.dockNumber ?? "—") · ME at gate · 0:00 ago" }
            )
        }
    }
}

// MARK: - 244 At Dock

struct ShipperAtDockScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        LifecycleScreenShell(theme: theme) {
            LifecycleBody(
                loadId: loadId,
                stageEyebrow: "SHIPPER · LOADS · PICKUP · AT DOCK",
                sectionFor: { l in
                    LifecycleSection(
                        stage: "SHIPPER AT DOCK",
                        citation: "§278 · WITHIN-TRACK FOURTH-PORT 2/3",
                        title: "At dock · loading",
                        kpis: [
                            .init(label: "DOCK", value: l?.dockNumber ?? "—", subtitle: "IN · loading", color: .orange),
                            .init(label: "PALLETS", value: "\(l?.palletCount ?? 0)", subtitle: "to load", color: .blue),
                            .init(label: "TEMP", value: tempLabel(l?.temperatureF), subtitle: "SEAL · pickup", color: .blue),
                            .init(label: "PAYABLE", value: "$\(l?.rate ?? "—")", subtitle: "NET-30 · queued", color: .green),
                        ]
                    )
                },
                subtitleFor: { _ in "Loading in progress · BOL pre-sign queued" }
            )
        }
    }
}

// MARK: - 245 Departing

struct ShipperDepartingScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        LifecycleScreenShell(theme: theme) {
            LifecycleBody(
                loadId: loadId,
                stageEyebrow: "SHIPPER · LOADS · PICKUP · DEPARTING",
                sectionFor: { l in
                    LifecycleSection(
                        stage: "SHIPPER DEPARTING",
                        citation: "§284 · WITHIN-TRACK FIFTH-PORT 2/3",
                        title: "Departing pickup",
                        kpis: [
                            .init(label: "STATUS", value: "DEPARTED", subtitle: "gate-out cleared", color: .green),
                            .init(label: "PALLETS", value: "\(l?.palletCount ?? 0)", subtitle: "loaded · sealed", color: .blue),
                            .init(label: "ETA-DEL", value: etaText(l?.deliveryDate), subtitle: "delivery window", color: .blue),
                            .init(label: "BOL", value: "PRE-SIGN", subtitle: "ME · TR pending", color: .orange),
                        ]
                    )
                },
                subtitleFor: { _ in "Gate-out cleared · BOL pre-sign captured · ME rolling" }
            )
        }
    }
}

// MARK: - 246 Pre-Delivery

struct ShipperPreDeliveryScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        LifecycleScreenShell(theme: theme) {
            LifecycleBody(
                loadId: loadId,
                stageEyebrow: "SHIPPER · LOADS · IN TRANSIT · PRE-DELIVERY",
                sectionFor: { l in
                    LifecycleSection(
                        stage: "SHIPPER PRE-DELIVERY",
                        citation: "§289 · WITHIN-TRACK SIXTH-PORT 2/3",
                        title: "Pre-delivery approach",
                        kpis: [
                            .init(label: "ETA", value: etaText(l?.deliveryDate), subtitle: "to dock", color: .blue),
                            .init(label: "TEMP", value: tempLabel(l?.temperatureF), subtitle: "in-range · sealed", color: .green),
                            .init(label: "PALLETS", value: "\(l?.palletCount ?? 0)", subtitle: "sealed in transit", color: .blue),
                            .init(label: "BOL", value: "READY", subtitle: "TR co-sign queued", color: .blue),
                        ]
                    )
                },
                subtitleFor: { _ in "Approaching receiver · BOL co-sign queued · TR notified" }
            )
        }
    }
}

// MARK: - 247 At Delivery

struct ShipperAtDeliveryScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        LifecycleScreenShell(theme: theme) {
            LifecycleBody(
                loadId: loadId,
                stageEyebrow: "SHIPPER · LOADS · DELIVERY · AT DOCK",
                sectionFor: { l in
                    LifecycleSection(
                        stage: "SHIPPER AT DELIVERY",
                        citation: "§290 · WITHIN-TRACK SEVENTH-PORT 2/3",
                        title: "My delivery · arrived",
                        kpis: [
                            .init(label: "ETA", value: "0m", subtitle: "ARRIVED · OTA", color: .green),
                            .init(label: "DOCK", value: l?.dockNumber ?? "—", subtitle: "IN · receiving", color: .orange),
                            .init(label: "TEMP", value: tempLabel(l?.temperatureF), subtitle: "SEAL · arrival", color: .blue),
                            .init(label: "PAYABLE", value: "$\(l?.rate ?? "—")", subtitle: "NET-30 · staged", color: .green),
                        ]
                    )
                },
                subtitleFor: { l in "Dock \(l?.dockNumber ?? "—") receiving bay · BOL co-sign begun · 0/\(l?.palletCount ?? 0) staged" }
            )
        }
    }
}

// MARK: - 249 Load Closed

struct ShipperLoadClosedScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        LifecycleScreenShell(theme: theme) {
            LifecycleBody(
                loadId: loadId,
                stageEyebrow: "SHIPPER · LOADS · CLOSED",
                sectionFor: { l in
                    let pal = l?.palletCount ?? 0
                    return LifecycleSection(
                        stage: "SHIPPER LOAD CLOSED",
                        citation: "§294 · WITHIN-TRACK NINTH-PORT OPENS",
                        title: "Load closed · sealed",
                        kpis: [
                            .init(label: "PALLETS", value: "\(pal)/\(pal)", subtitle: "FINAL · sealed", color: .green),
                            .init(label: "POD CERT", value: "ISSUED", subtitle: l?.podCertId ?? "ePOD chain sealed", color: .green),
                            .init(label: "TEMP", value: tempLabel(l?.temperatureF), subtitle: "SEAL · final", color: .blue),
                            .init(label: "PAYABLE", value: "RELEASED", subtitle: "NET-30 · armed", color: .green),
                        ]
                    )
                },
                subtitleFor: { _ in "ePOD ISSUED · NET-30 released · chain sealed · archived" }
            )
        }
    }
}

// MARK: - Helpers

private func tempLabel(_ f: Double?) -> String {
    guard let f else { return "—" }
    return String(format: "%.0f°F", f)
}

private func etaText(_ iso: String?) -> String {
    guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
    let mins = Int(d.timeIntervalSinceNow / 60)
    if mins < 0 { return "ARRIVED" }
    if mins < 60 { return "\(mins)m" }
    let h = mins / 60
    return "\(h)h \(mins % 60)m"
}

// MARK: - Previews

#Preview("243 Gate · Dark")    { ShipperAtGateScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("244 Dock · Light")   { ShipperAtDockScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("245 Depart · Dark")  { ShipperDepartingScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("246 Pre-Del · Light"){ ShipperPreDeliveryScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("247 At Del · Dark")  { ShipperAtDeliveryScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("249 Closed · Light") { ShipperLoadClosedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
