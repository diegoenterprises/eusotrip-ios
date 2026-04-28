//
//  225_ShipperHotZones.swift
//  EusoTrip 2027 UI — brick 225 (shipper · hot zones / market pulse)
//
//  National rate intelligence dashboard. Mirrors the shipper-relevant
//  slice of the web `/hot-zones` (`HotZones.tsx`) — where rates are
//  spiking, where capacity is tight, where loads are flowing. Sister
//  brick to driver `100_MeHotZones.swift` but flipped to a shipper
//  lens (rates the shipper PAYS, not receives, with cold-zone hints
//  for posting against capacity-rich lanes for a discount).
//
//  Wires:
//    • `hotZones.getRateFeed(equipment:)` — already-shipped
//      `HotZonesAPI`. Returns `HotZonesFeedResult { zones, coldZones,
//      marketPulse, timestamp }`.
//

import SwiftUI

// MARK: - Store

@MainActor
final class ShipperHotZonesStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded(HotZonesFeedResult)
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var equipment: String? = nil

    static let equipmentChips: [(String?, String)] = [
        (nil, "All"),
        ("DRY_VAN", "Dry van"),
        ("REEFER", "Reefer"),
        ("FLATBED", "Flatbed"),
        ("TANKER", "Tanker"),
    ]

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        do {
            let r = try await api.hotZones.getRateFeed(equipment: equipment)
            phase = .loaded(r)
        } catch {
            phase = .error("Couldn't reach market feed.")
        }
    }
}

// MARK: - Brick

struct ShipperHotZones: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperHotZonesStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                marketPulseCard
                equipmentRow
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.load() }
        .onChange(of: store.equipment) { _, _ in Task { await store.load() } }
        .refreshable { await store.load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flame.fill").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36).background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · MARKET PULSE").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Hot zones").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                if case .loaded(let f) = store.phase, let ts = f.timestamp {
                    Text("Updated \(Self.relative(ts)) · refresh interval \(f.refreshInterval ?? 60) s")
                        .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                } else {
                    Text("Where rates are spiking, capacity is tight, loads are flowing.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }.padding(.top, 4)
    }

    @ViewBuilder
    private var marketPulseCard: some View {
        if case .loaded(let f) = store.phase, let m = f.marketPulse {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("MARKET PULSE").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    if let c = m.criticalZones, c > 0 {
                        Label("\(c) critical", systemImage: "exclamationmark.octagon.fill")
                            .font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.danger)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(m.avgRate.map { String(format: "$%.2f", $0) } ?? "—")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                    Text("/ mi national avg").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                }
                HStack(spacing: 10) {
                    if let r = m.avgRatio {
                        pulsePill(label: "Load:Truck", value: String(format: "%.2f", r), tint: ratioColor(r))
                    }
                    if let l = m.totalLoads {
                        pulsePill(label: "Loads", value: "\(l)", tint: nil)
                    }
                    if let t = m.totalTrucks {
                        pulsePill(label: "Trucks", value: "\(t)", tint: nil)
                    }
                    if let f = m.avgFuelPrice {
                        pulsePill(label: "Diesel", value: String(format: "$%.2f", f), tint: nil)
                    }
                }
                if let w = m.activeWeatherAlerts, w > 0 {
                    Label("\(w) weather alerts active", systemImage: "cloud.bolt.rain.fill")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.warning)
                }
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var equipmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ShipperHotZonesStore.equipmentChips, id: \.1) { item in
                    chip(label: item.1, active: store.equipment == item.0) {
                        store.equipment = item.0
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("Pulling market feed…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m):
            errorCard(m)
        case .loaded(let f):
            VStack(alignment: .leading, spacing: Space.s4) {
                if !f.zones.isEmpty {
                    sectionHeader(title: "HOT ZONES", subtitle: "Rates surging · capacity tight", glyph: "flame.fill", tint: Brand.danger)
                    VStack(spacing: 8) {
                        ForEach(f.zones.prefix(20)) { z in hotZoneRow(z) }
                    }
                }
                if let cold = f.coldZones, !cold.isEmpty {
                    sectionHeader(title: "COLD ZONES", subtitle: "Capacity-rich · post here for a rate discount", glyph: "snowflake", tint: Brand.info)
                    VStack(spacing: 8) {
                        ForEach(cold.prefix(10)) { c in coldZoneRow(c) }
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, subtitle: String, glyph: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: glyph).font(.system(size: 11, weight: .heavy)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(tint)
                Text(subtitle).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer()
        }.padding(.bottom, 2)
    }

    private func hotZoneRow(_ z: HotZoneEntry) -> some View {
        let demandColor: Color = {
            switch z.demandLevel.uppercased() {
            case "CRITICAL": return Brand.danger
            case "HIGH":     return Brand.warning
            default:         return Brand.info
            }
        }()
        return HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                Text(z.state).font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(demandColor)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(z.zoneName).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                    statusPill(z.demandLevel, color: demandColor)
                    if let trend = z.demandTrend, trend.uppercased() == "RISING" {
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.danger)
                    }
                }
                HStack(spacing: 8) {
                    rateBadge(rate: z.liveRate, change: z.rateChangePercent)
                    miniPill("\(z.liveLoads) loads")
                    miniPill("\(z.liveTrucks) trucks")
                    miniPill("L:T \(String(format: "%.1f", z.liveRatio))")
                }
                if !z.topEquipment.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(z.topEquipment.prefix(3), id: \.self) { e in
                            Text(e.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.5)
                                .foregroundStyle(palette.textTertiary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(palette.bgCardSoft))
                                .overlay(Capsule().strokeBorder(palette.borderFaint))
                        }
                    }
                }
                if let blurb = z.nextWeekForecast, !blurb.isEmpty {
                    Text(blurb).font(EType.caption).foregroundStyle(palette.textSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func coldZoneRow(_ c: ColdZoneEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "snowflake").font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Brand.info)
                .frame(width: 36, height: 36)
                .background(Brand.info.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(c.name ?? c.state ?? "Unknown")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                    if let s = c.state {
                        miniPill(s.uppercased())
                    }
                }
                HStack(spacing: 8) {
                    if let r = c.liveRate {
                        Label(String(format: "$%.2f / mi", r), systemImage: "dollarsign.circle.fill")
                            .font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.info)
                    }
                    if let t = c.liveTrucks {
                        miniPill("\(t) trucks")
                    }
                    if let s = c.liveSurge {
                        miniPill(String(format: "Surge %.2f", s))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func chip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .heavy))
                .padding(.horizontal, Space.s3).padding(.vertical, 7)
                .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                .background(Capsule().fill(active ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18)) : AnyShapeStyle(palette.bgCard)))
                .overlay(Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func pulsePill(label: String, value: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(tint ?? palette.textPrimary).monospacedDigit()
        }
        .padding(.horizontal, Space.s2).padding(.vertical, 4)
        .background(Capsule().fill(palette.bgCardSoft.opacity(0.6)))
        .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private func rateBadge(rate: Double, change: Double?) -> some View {
        HStack(spacing: 3) {
            Text(String(format: "$%.2f", rate))
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
            if let c = change, c != 0 {
                Image(systemName: c > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(c > 0 ? Brand.success : Brand.danger)
                Text(String(format: "%+.1f%%", c)).font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(c > 0 ? Brand.success : Brand.danger)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(palette.bgCardSoft))
        .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private func statusPill(_ s: String, color: Color) -> some View {
        Text(s.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    private func miniPill(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.4)
            .foregroundStyle(palette.textTertiary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func ratioColor(_ r: Double) -> Color {
        if r >= 6 { return Brand.danger }
        if r >= 3 { return Brand.warning }
        return Brand.info
    }

    private static func relative(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s/60))m ago" }
        return "\(Int(s/3600))h ago"
    }
}

// MARK: - Previews

#Preview("HotZones · Dark") {
    ShipperHotZones().preferredColorScheme(.dark)
}

#Preview("HotZones · Light") {
    ShipperHotZones().preferredColorScheme(.light)
}
