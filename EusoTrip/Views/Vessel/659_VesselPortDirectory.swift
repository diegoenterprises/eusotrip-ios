//
//  659_VesselPortDirectory.swift
//  EusoTrip — Vessel Operator · Port Directory (542-port database).
//
//  Verbatim port of wireframe 659 (06 Vessel · Dark). Carrier directory
//  of ports keyed to the `ports` table (name, unlocode, city/state,
//  portType, maxDraft, totalBerths, containerCapacityTEU, hasCranes,
//  hasRailAccess, customsOffice). Mirror of Rail 559 Yard Operations at
//  tri-mode parity. Gives the operator one searchable source of port
//  capability — draft, berths, TEU, crane/rail/CBP — so a box is routed
//  to a terminal that can actually handle it.
//
//  Endpoints (server/routers/vesselShipments.ts):
//    getPorts          (:1414 · {limit,offset,country?,search?,portType?})
//    getVesselsAtPort  (:1071 · {portId} · row tap-through to live port view)
//

import SwiftUI

struct VesselPortDirectoryScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselPortDirectoryBody() } nav: {
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

/// Maps the `ports` table row returned by `vesselShipments.getPorts`.
/// `id` is an INT auto-increment column server-side.
private struct VesselPort659: Decodable, Identifiable {
    let id: Int
    let name: String?
    let unlocode: String?
    let city: String?
    let state: String?
    let country: String?
    let portType: String?
    let maxDraft: Double?
    let totalBerths: Int?
    let containerCapacityTEU: Int?
    let hasCranes: Bool?
    let hasRailAccess: Bool?
    let customsOffice: String?
    let ftzNumber: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, unlocode, city, state, country, portType
        case maxDraft, totalBerths, containerCapacityTEU
        case hasCranes, hasRailAccess, customsOffice, ftzNumber
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `id` may arrive as Int (INT column) — decode defensively.
        if let i = try? c.decode(Int.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) {
            id = i
        } else {
            id = 0
        }
        name = try? c.decode(String.self, forKey: .name)
        unlocode = try? c.decode(String.self, forKey: .unlocode)
        city = try? c.decode(String.self, forKey: .city)
        state = try? c.decode(String.self, forKey: .state)
        country = try? c.decode(String.self, forKey: .country)
        portType = try? c.decode(String.self, forKey: .portType)
        // maxDraft is DECIMAL(6,2) — may serialize as a quoted string.
        if let d = try? c.decode(Double.self, forKey: .maxDraft) {
            maxDraft = d
        } else if let s = try? c.decode(String.self, forKey: .maxDraft) {
            maxDraft = Double(s)
        } else {
            maxDraft = nil
        }
        totalBerths = try? c.decode(Int.self, forKey: .totalBerths)
        containerCapacityTEU = try? c.decode(Int.self, forKey: .containerCapacityTEU)
        // BOOLEAN columns may arrive as Bool or 0/1.
        if let b = try? c.decode(Bool.self, forKey: .hasCranes) {
            hasCranes = b
        } else if let n = try? c.decode(Int.self, forKey: .hasCranes) {
            hasCranes = n != 0
        } else {
            hasCranes = nil
        }
        if let b = try? c.decode(Bool.self, forKey: .hasRailAccess) {
            hasRailAccess = b
        } else if let n = try? c.decode(Int.self, forKey: .hasRailAccess) {
            hasRailAccess = n != 0
        } else {
            hasRailAccess = nil
        }
        customsOffice = try? c.decode(String.self, forKey: .customsOffice)
        ftzNumber = try? c.decode(String.self, forKey: .ftzNumber)
    }
}

// MARK: - Body

private struct VesselPortDirectoryBody: View {
    @Environment(\.palette) private var palette
    @State private var ports: [VesselPort659] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var searchText: String = ""

    // Row tap-through → getVesselsAtPort live port view.
    @State private var portLookupId: Int? = nil
    @State private var portLookupLoading = false
    @State private var portLookupError: String? = nil
    @State private var portLookupResult: VesselsAtPortResult? = nil

    private var containerCount: Int {
        ports.filter { ($0.portType ?? "").lowercased() == "container_terminal" }.count
    }
    private var railAccessCount: Int {
        ports.filter { $0.hasRailAccess == true }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        loadingSkeleton
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else {
                        kpiStrip
                        portsSection
                    }
                    searchCTA
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + back chevron + title + subtitle)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("VESSEL OPERATOR · PORT DIRECTORY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Port directory")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
            }
            .padding(.top, Space.s4)
            Text("542-port directory · UN/LOCODE")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s3) {
            kpiTile(label: "PORTS",       value: "\(ports.count)", caption: "in directory", gradient: true)
            kpiTile(label: "CONTAINER",   value: "\(containerCount)", caption: "terminals")
            kpiTile(label: "RAIL-ACCESS", value: "\(railAccessCount)", caption: "rail-access")
        }
    }

    private func kpiTile(label: String, value: String, caption: String, gradient: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.bottom, 8)
            Group {
                if gradient {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value).foregroundStyle(palette.textPrimary)
                }
            }
            .font(.system(size: 22, weight: .bold))
            .monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.5)
            .padding(.bottom, 4)
            Text(caption)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Ports section

    @ViewBuilder
    private var portsSection: some View {
        let country = (ports.first?.country ?? "US")
        let countryLabel = countryName(country)
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("PORTS · \(countryLabel.uppercased())")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if ports.isEmpty {
                EusoEmptyState(
                    systemImage: "ferry",
                    title: "No ports in directory",
                    subtitle: "Ports keyed to the UN/LOCODE database will appear here."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(ports) { port in portRow(port) }
                }
            }
        }
    }

    private func portRow(_ port: VesselPort659) -> some View {
        let isContainer = (port.portType ?? "").lowercased() == "container_terminal"
        let accent: Color = isContainer ? Brand.blue : Brand.rail
        let isLookingUp = portLookupLoading && portLookupId == port.id
        return Button {
            Task { await lookupVessels(at: port) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: Space.s3) {
                    // Port glyph chip — anchor + arc (mirrors SVG path).
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accent.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "ferry.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(port.name ?? "Port")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                            portTypeBadge(port.portType)
                            Spacer(minLength: 4)
                            if isLookingUp {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(palette.textSecondary)
                            } else {
                                Text(port.unlocode ?? "—")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                        Text(metaLine(port))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                        Text(capabilityLine(port))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle((port.hasCranes == true && port.hasRailAccess == true) ? Brand.success : palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                if portLookupId == port.id, let err = portLookupError {
                    Text(err)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.danger)
                        .padding(.top, Space.s2)
                } else if portLookupId == port.id, let res = portLookupResult {
                    livePortStrip(res)
                        .padding(.top, Space.s2)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func portTypeBadge(_ portType: String?) -> some View {
        let t = (portType ?? "").lowercased()
        let isContainer = t == "container_terminal"
        let label: String = {
            switch t {
            case "container_terminal": return "CONTAINER"
            case "seaport":            return "SEAPORT"
            case "river_port":         return "RIVER"
            case "lake_port":          return "LAKE"
            case "inland_port":        return "INLAND"
            default:                   return (portType ?? "PORT").uppercased()
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(isContainer ? Brand.blue : palette.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(
                Capsule().fill(isContainer
                               ? Brand.blue.opacity(0.12)
                               : palette.textTertiary.opacity(0.16))
            )
    }

    /// "Long Beach, CA · 80 berths · 9.3M TEU · 50ft draft"
    private func metaLine(_ port: VesselPort659) -> String {
        var parts: [String] = []
        let place = [port.city, port.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        if !place.isEmpty { parts.append(place) }
        if let b = port.totalBerths { parts.append("\(b) berths") }
        if let teu = port.containerCapacityTEU {
            let m = Double(teu) / 1_000_000
            parts.append(String(format: "%.1fM TEU", m))
        }
        if let d = port.maxDraft { parts.append(String(format: "%.0fft draft", d)) }
        return parts.joined(separator: " · ")
    }

    /// "● cranes · rail access · CBP 2704"
    private func capabilityLine(_ port: VesselPort659) -> String {
        var caps: [String] = []
        if port.hasCranes == true { caps.append("cranes") }
        if port.hasRailAccess == true { caps.append("rail access") }
        if let ftz = port.ftzNumber, !ftz.isEmpty {
            caps.append("FTZ \(ftz)")
        } else if let cbp = port.customsOffice, !cbp.isEmpty {
            caps.append("CBP \(cbp)")
        }
        if caps.isEmpty { return "● no published capabilities" }
        return "● " + caps.joined(separator: " · ")
    }

    private func countryName(_ code: String) -> String {
        switch code.uppercased() {
        case "US", "USA": return "United States"
        case "CA", "CAN": return "Canada"
        case "MX", "MEX": return "Mexico"
        default:          return code
        }
    }

    // MARK: - Live port view (getVesselsAtPort)

    @ViewBuilder
    private func livePortStrip(_ res: VesselsAtPortResult) -> some View {
        if res.vessels.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text("No vessels currently at berth")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s2)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Brand.vessel)
                    Text("\(res.vessels.count) VESSEL\(res.vessels.count == 1 ? "" : "S") AT PORT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.vessel)
                }
                ForEach(res.vessels.prefix(4)) { v in
                    HStack(spacing: 6) {
                        Text(v.name ?? "Vessel")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        if let status = v.status, !status.isEmpty {
                            Text("· \(status)")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let imo = v.imoNumber, !imo.isEmpty {
                            Text("IMO \(imo)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s2)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }

    // MARK: - Search CTA

    private var searchCTA: some View {
        CTAButton(title: "Search port directory") {
            // Inline search is wired via the searchText filter on getPorts;
            // the CTA re-runs the directory query with the current term.
            Task { await load() }
        }
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        VStack(spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 78)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 78)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Load (getPorts)

    private func load() async {
        loading = true; loadError = nil
        struct PortsIn: Encodable {
            let limit: Int
            let offset: Int
            let search: String?
        }
        let term = searchText.trimmingCharacters(in: .whitespaces)
        let input = PortsIn(limit: 100, offset: 0, search: term.isEmpty ? nil : term)
        do {
            let rows: [VesselPort659] = try await EusoTripAPI.shared.query(
                "vesselShipments.getPorts", input: input)
            self.ports = rows
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Row tap-through (getVesselsAtPort)

    private func lookupVessels(at port: VesselPort659) async {
        // Toggle off if tapping the already-expanded row.
        if portLookupId == port.id, portLookupResult != nil || portLookupError != nil {
            portLookupId = nil
            portLookupResult = nil
            portLookupError = nil
            return
        }
        portLookupId = port.id
        portLookupResult = nil
        portLookupError = nil
        portLookupLoading = true
        struct AtPortIn: Encodable { let portId: String }
        do {
            // Server keys this query on portId (string). Returns a vessels
            // payload or null when MarineTraffic has nothing for the port.
            let res: VesselsAtPortResult? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselsAtPort", input: AtPortIn(portId: String(port.id)))
            if portLookupId == port.id {
                portLookupResult = res ?? VesselsAtPortResult(vessels: [])
            }
        } catch {
            if portLookupId == port.id {
                portLookupError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        portLookupLoading = false
    }
}

// MARK: - getVesselsAtPort payload

/// Live MarineTraffic vessels-at-port payload. The server returns the raw
/// provider object (or null); we decode the vessel list defensively so an
/// unexpected provider shape degrades to an empty live strip rather than
/// breaking the directory.
private struct VesselsAtPortResult: Decodable {
    let vessels: [AtPortVessel]

    private enum CodingKeys: String, CodingKey { case vessels, data }

    init(vessels: [AtPortVessel]) { self.vessels = vessels }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            if let v = try? c.decode([AtPortVessel].self, forKey: .vessels) {
                vessels = v; return
            }
            if let v = try? c.decode([AtPortVessel].self, forKey: .data) {
                vessels = v; return
            }
        }
        // Provider may return a bare array.
        if let arr = try? decoder.singleValueContainer().decode([AtPortVessel].self) {
            vessels = arr; return
        }
        vessels = []
    }
}

private struct AtPortVessel: Decodable, Identifiable {
    let id: String
    let name: String?
    let imoNumber: String?
    let status: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, imoNumber, imo, status, navStatus, shipName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let imoVal = (try? c.decode(String.self, forKey: .imoNumber))
            ?? (try? c.decode(String.self, forKey: .imo))
        let nameVal = (try? c.decode(String.self, forKey: .name))
            ?? (try? c.decode(String.self, forKey: .shipName))
        name = nameVal
        imoNumber = imoVal
        status = (try? c.decode(String.self, forKey: .status))
            ?? (try? c.decode(String.self, forKey: .navStatus))
        if let i = try? c.decode(String.self, forKey: .id) {
            id = i
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            id = imoVal ?? nameVal ?? UUID().uuidString
        }
    }
}

#Preview("659 · Vessel Port Directory · Night") { VesselPortDirectoryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("659 · Vessel Port Directory · Light") { VesselPortDirectoryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
