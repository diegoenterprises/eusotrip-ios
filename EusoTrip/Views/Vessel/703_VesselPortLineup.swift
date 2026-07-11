//
//  703_VesselPortLineup.swift
//  EusoTrip — Vessel Operator · Port Lineup (CARRIER-SIDE · BOARD/OPERATIONS class).
//
//  PURPOSE-BUILT: the source wireframe "703 Vessel Port Lineup.svg" ships EMPTY
//  in the catalog (0 bytes, Dark + Light), so this screen is composed to the
//  golden bar from the real vesselShipments router blueprint + design authority.
//  A port-arrival QUEUE board: a lineup-summary hero, a berth-window strip with a
//  crane wind-limit flag, and the inbound/at-anchor vessel queue ordered by
//  arrival — a board, not a detail card.
//
//  Web parity: PortIntelligence.tsx (`/vessel/port/:id/lineup`).
//
//  DATA (endpoints confirmed on disk this fire):
//    vesselShipments.getVesselsAtPort {portId}
//        → [{ imoNumber, name, type, flag, speed, status, arrivalTime, draught }] | null
//        (MarineTraffic AIS · vesselProcedure · server/routers/vesselShipments.ts:2595)
//    vesselShipments.getBerthSchedule {portId, berthId?}
//        → [{ ...assignment, craneWindLimitKt, forecastGustKt, gustExceedsCraneLimit }]
//        (vesselProcedure · vesselShipments.ts:1927 — additive crane wind-limit seam)
//
//  HONEST GAPS (surfaced to the-oath — NOT papered over):
//    • getVesselsAtPort returns null when MARINETRAFFIC_API_KEY is unset — the
//      lineup then reads its "awaiting AIS feed" state, not fabricated vessels.
//    • forecastGustKt / gustExceedsCraneLimit are honest null off the Enterprise
//      weather tier; the crane flag only ambers on a real forecast+limit pair.
//
//  NAV (VesselOperatorNavController): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//  transportMode=vessel · port authority per country. PERSONA Vessel Operator · Aurora Ocean Division.
//

import SwiftUI

struct VesselPortLineupScreen: View {
    let theme: Theme.Palette
    var portId: Int = 1
    var portCode: String = "USLGB"

    var body: some View {
        Shell(theme: theme) {
            VesselPortLineupBody(portId: portId, portCode: portCode)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct VesselInPort: Decodable, Identifiable {
    var id: String { imoNumber ?? (name ?? UUID().uuidString) }
    let imoNumber: String?
    let name: String?
    let type: String?
    let flag: String?
    let speed: Double?
    let status: String?
    let arrivalTime: String?
    let draught: Double?
}
private struct BerthWindow: Decodable, Identifiable {
    let id: Int
    let berthId: Int?
    let vesselName: String?
    let status: String?
    let scheduledArrival: String?
    let scheduledDeparture: String?
    let craneWindLimitKt: Double?
    let forecastGustKt: Double?
    let gustExceedsCraneLimit: Bool?
}

// MARK: - Body

private struct VesselPortLineupBody: View {
    @Environment(\.palette) private var palette
    let portId: Int
    let portCode: String

    @State private var lineup: [VesselInPort] = []
    @State private var berths: [BerthWindow] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline().padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s4) {
                    lineupHero
                    berthStrip
                    lineupQueue
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ VESSEL OPERATOR · PORT LINEUP")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(portCode.uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Port lineup")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary).padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5)
    }

    // MARK: Lineup hero

    private var lineupHero: some View {
        HStack(spacing: 0) {
            heroStat("\(lineup.count)", "IN LINEUP")
            divider
            heroStat("\(atBerthCount)", "AT BERTH")
            divider
            heroStat("\(inboundCount)", "INBOUND")
            divider
            heroStat("\(berths.count)", "WINDOWS")
        }
        .padding(.vertical, Space.s4).padding(.horizontal, Space.s3)
        .frame(maxWidth: .infinity)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }
    private func heroStat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }
    private var divider: some View { Rectangle().fill(.white.opacity(0.22)).frame(width: 1, height: 30) }

    private var atBerthCount: Int { lineup.filter { isAtBerth($0.status) }.count }
    private var inboundCount: Int { lineup.count - atBerthCount }

    // MARK: Berth window strip

    private var berthStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("BERTH WINDOWS · getBerthSchedule")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if berths.isEmpty {
                LifecycleCard {
                    Text(loading ? "Loading berth windows…" : "No berth windows published for this port.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s2) {
                        ForEach(berths.prefix(8)) { b in berthCard(b) }
                    }
                }
            }
        }
    }

    private func berthCard(_ b: BerthWindow) -> some View {
        let amber = b.gustExceedsCraneLimit == true
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Berth \(b.berthId.map(String.init) ?? "—")")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                if amber {
                    Image(systemName: "wind").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.warning)
                }
            }
            Text(b.vesselName ?? "unassigned")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(windowTime(b))
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textTertiary)
            if let limit = b.craneWindLimitKt {
                Text("crane ≤ \(Int(limit)) kt\(b.forecastGustKt.map { " · gust \(Int($0))" } ?? "")")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(amber ? Brand.warning : palette.textTertiary)
            }
        }
        .padding(Space.s3).frame(width: 156, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(amber ? Brand.warning.opacity(0.55) : palette.borderFaint, lineWidth: 1))
    }

    // MARK: Lineup queue

    private var lineupQueue: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ARRIVAL QUEUE · getVesselsAtPort")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)

            if loading {
                LifecycleCard { Text("Loading lineup…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
            } else if lineup.isEmpty {
                EusoEmptyState(icon: Image(systemName: "sailboat"),
                               title: "No vessels in the lineup",
                               subtitle: "Inbound and at-anchor vessels appear here when the AIS port feed is provisioned.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedLineup.enumerated()), id: \.element.id) { idx, v in
                        lineupRow(v, position: idx + 1)
                        if idx < sortedLineup.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s1)
                        }
                    }
                }
                .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.xl)
            }
        }
    }

    private var sortedLineup: [VesselInPort] {
        lineup.sorted { ($0.arrivalTime ?? "") < ($1.arrivalTime ?? "") }
    }

    private func lineupRow(_ v: VesselInPort, position: Int) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(isAtBerth(v.status) ? Brand.success.opacity(0.18) : Brand.info.opacity(0.16)).frame(width: 40, height: 40)
                Text("\(position)").font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(isAtBerth(v.status) ? Brand.success : Brand.info)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(v.name ?? "IMO \(v.imoNumber ?? "—")")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(v.type ?? "vessel") · \(v.flag ?? "—")\(v.draught.map { " · \(String(format: "%.1f", $0))m dr" } ?? "")")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 3) {
                StatusPill(text: prettyStatus(v.status), kind: isAtBerth(v.status) ? .success : .info)
                Text(v.speed.map { String(format: "%.1f kn", $0) } ?? prettyArrival(v.arrivalTime))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct AtPortIn: Encodable { let portId: String }
        struct BerthIn: Encodable { let portId: Int }
        self.lineup = (try? await EusoTripAPI.shared.query("vesselShipments.getVesselsAtPort", input: AtPortIn(portId: String(portId)))) ?? []
        self.berths = (try? await EusoTripAPI.shared.query("vesselShipments.getBerthSchedule", input: BerthIn(portId: portId))) ?? []
        loading = false
    }

    // MARK: helpers

    private func isAtBerth(_ s: String?) -> Bool {
        let x = (s ?? "").lowercased()
        return x.contains("moor") || x.contains("berth") || x.contains("dock") || x == "in_port"
    }
    private func prettyStatus(_ s: String?) -> String {
        let x = (s ?? "").lowercased()
        if isAtBerth(s) { return "AT BERTH" }
        if x.contains("anchor") { return "AT ANCHOR" }
        if x.contains("under") || x.contains("way") { return "UNDERWAY" }
        return (s ?? "INBOUND").replacingOccurrences(of: "_", with: " ").uppercased()
    }
    private func windowTime(_ b: BerthWindow) -> String {
        "\(shortDT(b.scheduledArrival)) → \(shortDT(b.scheduledDeparture))"
    }
    private func prettyArrival(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        return "ETA \(shortDT(raw))"
    }
    private func shortDT(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let d = ISO8601DateFormatter().date(from: raw) ?? {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: raw)
        }()
        guard let d else { return raw }
        let out = DateFormatter(); out.dateFormat = "dd HH:mm"
        return out.string(from: d)
    }
}

#Preview("703 · Vessel Port Lineup · Night") {
    VesselPortLineupScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("703 · Vessel Port Lineup · Light") {
    VesselPortLineupScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
