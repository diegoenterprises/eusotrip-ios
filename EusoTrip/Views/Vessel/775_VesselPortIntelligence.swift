//
//  775_VesselPortIntelligence.swift
//  EusoTrip — Vessel Operator · Port Intelligence.
//
//  Verbatim port of wireframe 775 (06 Vessel · Dark) — a purpose-built
//  PORT-CONDITIONS-COMPARISON-BOARD: a focus-port hero over a multi-port
//  comparison board so the operator ranks discharge ports head-to-head to
//  support a diversion decision ("which port clears my box fastest now").
//
//  Endpoints (server/routers/vesselShipments.ts):
//    getCrossBorderPorts (:3425 · {country} → CrossBorderPort[] {unlocode,
//      name, containerCapacityTEU, maxDraftMeters, customsAuthority,
//      hasRailAccess}) — the candidate ports + capability master.
//    getVesselsAtPort    (:2595 · {portId} → MarineTraffic vessels in/near a
//      port) — the LIVE vessels-waiting count per port.
//  Honest gap (surfaced to the-oath): there is no single congestion-index /
//  dwell aggregate today — the board ranks on LIVE vessels-at-port (real)
//  and marks the absolute index/dwell as pending. Propose
//  getPortCongestionIndex({unlocodes[]}) → {ports:[{unlocode, congestionIndex,
//  vesselsWaiting, avgWaitHrs, avgDwellDays, berthUtilPct, trend}]} (read-only,
//  derived from getVesselsAtPort + getBerthSchedule; no new write).
//

import SwiftUI

struct VesselPortIntelligenceScreen: View {
    let theme: Theme.Palette
    var focusUnlocode: String = "USLGB"

    var body: some View {
        Shell(theme: theme) { VesselPortIntelligenceBody(focusUnlocode: focusUnlocode) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct CrossBorderPort775: Decodable, Identifiable {
    var id: String { unlocode }
    let unlocode: String
    let name: String
    let stateProvince: String?
    let containerCapacityTEU: Int
    let maxDraftMeters: Double
    let customsAuthority: String?
    let hasRailAccess: Bool

    private enum CodingKeys: String, CodingKey {
        case unlocode, name, stateProvince, containerCapacityTEU, maxDraftMeters, customsAuthority, hasRailAccess
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        unlocode = (try? c.decode(String.self, forKey: .unlocode)) ?? "—"
        name     = (try? c.decode(String.self, forKey: .name)) ?? "Port"
        stateProvince = try? c.decode(String.self, forKey: .stateProvince)
        containerCapacityTEU = (try? c.decode(Int.self, forKey: .containerCapacityTEU)) ?? 0
        if let v = try? c.decode(Double.self, forKey: .maxDraftMeters) { maxDraftMeters = v }
        else if let s = try? c.decode(String.self, forKey: .maxDraftMeters), let v = Double(s) { maxDraftMeters = v }
        else { maxDraftMeters = 0 }
        customsAuthority = try? c.decode(String.self, forKey: .customsAuthority)
        hasRailAccess = (try? c.decode(Bool.self, forKey: .hasRailAccess)) ?? false
    }
    /// Short display name (drops the "Port of " prefix for the board).
    var shortName: String { name.replacingOccurrences(of: "Port of ", with: "") }
}

/// A port row fused with its live vessels-at-port count.
private struct PortTraffic775: Identifiable {
    let port: CrossBorderPort775
    let liveVessels: Int?
    var id: String { port.unlocode }
}

private struct VesselsAtPort775: Decodable {
    let count: Int
    private enum CodingKeys: String, CodingKey { case vessels, data, total }
    init(from d: Decoder) throws {
        if let c = try? d.container(keyedBy: CodingKeys.self) {
            if let arr = try? c.decode([AnyVessel775].self, forKey: .vessels) { count = arr.count; return }
            if let arr = try? c.decode([AnyVessel775].self, forKey: .data) { count = arr.count; return }
            if let n = try? c.decode(Int.self, forKey: .total) { count = n; return }
        }
        if let arr = try? d.singleValueContainer().decode([AnyVessel775].self) { count = arr.count; return }
        count = 0
    }
}
private struct AnyVessel775: Decodable { init(from decoder: Decoder) throws {} }

// MARK: - Body

private struct VesselPortIntelligenceBody: View {
    @Environment(\.palette) private var palette
    let focusUnlocode: String

    @State private var rows: [PortTraffic775] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var liveUnavailable = false

    private var focus: PortTraffic775? {
        rows.first(where: { $0.port.unlocode == focusUnlocode }) ?? rows.first
    }
    private var maxLive: Int { max(rows.compactMap { $0.liveVessels }.max() ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · PORT INTELLIGENCE",
                caption: "US WEST COAST",
                title: "Port Intelligence",
                idText: "VES-260524-7F02C1"
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else {
                    if let f = focus { focusHero(f) }
                    boardSection
                    if liveUnavailable {
                        VesselGapNote(text: "Live vessels-at-port feed returned no data — ranking holds on port capability. Absolute congestion index + dwell await getPortCongestionIndex (proposed aggregate over getVesselsAtPort + getBerthSchedule).")
                    } else {
                        VesselGapNote(text: "Ranking uses LIVE vessels-at-port. Absolute congestion index + avg dwell await getPortCongestionIndex (proposed read-only aggregate — no fabricated hours shown).")
                    }
                    esang
                    ctaPair
                }
                Color.clear.frame(height: Space.s6)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func focusHero(_ f: PortTraffic775) -> some View {
        let level = Congestion775.level(live: f.liveVessels, max: maxLive)
        return ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(f.port.shortName).font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(f.port.unlocode).font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(text: level.label, kind: level.pill)
                }
                // Relative-traffic gauge (real: live vessels vs busiest port)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.borderFaint).frame(height: 8)
                        Capsule().fill(level.color)
                            .frame(width: geo.size.width * Congestion775.frac(live: f.liveVessels, max: maxLive), height: 8)
                    }
                }.frame(height: 8)
                HStack(spacing: 0) {
                    heroStat(value: f.liveVessels.map { "\($0)" } ?? "—", label: "vessels near port")
                    heroStat(value: teuText(f.port.containerCapacityTEU), label: "annual TEU")
                    heroStat(value: String(format: "%.0fft", f.port.maxDraftMeters * 3.28084), label: "max draft")
                }
            }
        }
    }

    private func heroStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            Text(label).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionLabel775(text: "COMPARE DISCHARGE PORTS", endpoint: "getVesselsAtPort")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                    if idx > 0 { Divider().overlay(palette.borderFaint) }
                    portRow(r)
                }
                Divider().overlay(palette.borderFaint)
                Text("Live vessels-at-port · relative to the busiest candidate · refreshed just now")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    .padding(.top, Space.s3)
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func portRow(_ r: PortTraffic775) -> some View {
        let level = Congestion775.level(live: r.liveVessels, max: maxLive)
        return HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.port.shortName).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(metaLine(r)).font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.borderFaint).frame(height: 8).frame(maxHeight: .infinity)
                    Capsule().fill(level.color)
                        .frame(width: geo.size.width * Congestion775.frac(live: r.liveVessels, max: maxLive), height: 8)
                        .frame(maxHeight: .infinity)
                }
            }.frame(width: 96, height: 30)
            Text(r.liveVessels.map { "\($0)" } ?? "—")
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(level.color).frame(width: 26, alignment: .trailing)
            Text(level.label).font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(level.color).frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, Space.s3)
    }

    private func metaLine(_ r: PortTraffic775) -> String {
        var parts: [String] = [r.port.unlocode]
        if let v = r.liveVessels { parts.append("\(v) near") }
        parts.append(teuText(r.port.containerCapacityTEU) + " TEU")
        if r.port.hasRailAccess { parts.append("on-dock rail") }
        return parts.joined(separator: " · ")
    }

    private func teuText(_ teu: Int) -> String {
        if teu >= 1_000_000 { return String(format: "%.1fM", Double(teu) / 1_000_000) }
        if teu >= 1_000 { return "\(teu / 1000)K" }
        return "\(teu)"
    }

    private var esang: some View {
        // Recommend the least-busy rail-served candidate other than the focus.
        let candidates = rows.filter { $0.port.unlocode != focus?.port.unlocode && $0.port.hasRailAccess }
        let best = candidates.min(by: { ($0.liveVessels ?? Int.max) < ($1.liveVessels ?? Int.max) })
        return EsangAdvisory775(
            title: best.map { "Divert to \($0.port.shortName) \($0.port.unlocode) — lighter live traffic" }
                ?? "Focus port is the least congested candidate right now",
            message: best.map { "\($0.liveVessels.map { "\($0) vessels near" } ?? "clear") vs the focus port · on-dock rail intact" }
                ?? "Hold the current discharge plan"
        )
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Compare lanes", action: {})
            Button {} label: {
                Text("Port detail").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 140, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            }.buttonStyle(.plain)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 96)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 240)
        }
    }

    // MARK: - Networking

    private func load() async {
        loading = true; loadError = nil; liveUnavailable = false
        struct PortsIn: Encodable { let country: String }
        struct AtPortIn: Encodable { let portId: String }
        do {
            let ports: [CrossBorderPort775] = (try await EusoTripAPI.shared.query(
                "vesselShipments.getCrossBorderPorts", input: PortsIn(country: "US"))) ?? []
            // Fetch live vessels-at-port for each candidate (bounded set,
            // sequential — the API is MainActor-isolated so this stays simple
            // and avoids cross-actor capture of the port structs).
            var live: [String: Int] = [:]
            for p in ports {
                if let res: VesselsAtPort775 = try? await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselsAtPort", input: AtPortIn(portId: p.unlocode)) {
                    live[p.unlocode] = res.count
                }
            }
            var fused = ports.map { PortTraffic775(port: $0, liveVessels: live[$0.unlocode]) }
            // Rank by live traffic desc; ports without a live count sort last.
            fused.sort { ($0.liveVessels ?? -1) > ($1.liveVessels ?? -1) }
            self.rows = fused
            self.liveUnavailable = fused.allSatisfy { $0.liveVessels == nil }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Congestion level (relative to live max — no fabricated absolute index)

private enum Congestion775 {
    struct Level { let label: String; let color: Color; let pill: StatusPill.Kind }
    static func frac(live: Int?, max maxLive: Int) -> CGFloat {
        guard let live else { return 0 }
        let denom = Double(Swift.max(maxLive, 1))
        return CGFloat(Swift.min(1.0, Double(live) / denom))
    }
    static func level(live: Int?, max maxLive: Int) -> Level {
        guard let live else { return Level(label: "—", color: Brand.neutral.opacity(0.6), pill: .neutral) }
        let f = Double(live) / Double(Swift.max(maxLive, 1))
        if f >= 0.75 { return Level(label: "HIGH", color: Brand.danger, pill: .danger) }
        if f >= 0.40 { return Level(label: "MOD",  color: Brand.warning, pill: .warning) }
        return Level(label: "LOW", color: Brand.success, pill: .success)
    }
}

private struct SectionLabel775: View {
    @Environment(\.palette) private var palette
    let text: String; var endpoint: String? = nil
    var body: some View {
        HStack {
            Text(text).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            if let endpoint { Text(endpoint).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(palette.textTertiary) }
        }
    }
}

private struct EsangAdvisory775: View {
    @Environment(\.palette) private var palette
    let title: String; let message: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("775 · Port Intelligence · Night") { VesselPortIntelligenceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("775 · Port Intelligence · Light") { VesselPortIntelligenceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
