//
//  699_VesselParticulars.swift
//  EusoTrip — Vessel Operator · Vessel Particulars (CARRIER-SIDE · DETAIL/SPEC class).
//
//  Verbatim port of "699 Vessel Particulars.svg" (Dark + Light). A bespoke SHIP
//  GENERAL-ARRANGEMENT SIDE-ELEVATION hero (hull + accommodation block + company
//  funnel + on-deck container bays + waterline with load-line disc + draft/LOA
//  calipers) — an archetype carried by no other screen in the catalog. Then a
//  principal-particulars grid and a port-call / statutory-cert binder.
//
//  Web parity: VesselDetail.tsx (`/vessel/:imo/particulars`).
//
//  DATA (endpoints confirmed on disk this fire):
//    vesselShipments.getVesselParticulars {imoNumber}
//        → { name, type, flag, grossTonnage, deadweight, length, beam,
//            yearBuilt, owner, operator, callSign, classification } | null
//        (MarineTraffic AIS · vesselProcedure · server/routers/vesselShipments.ts:2570)
//    vesselShipments.getVesselPortCalls {imoNumber, days}
//        → [{ portName, unlocode, arrivalTime, departureTime, inPort, country }] | null
//        (vesselProcedure · vesselShipments.ts:2584)
//
//  HONEST GAPS (surfaced to the-oath — NOT papered over):
//    • The MarineTraffic particulars feed carries NO service speed, TEU/reefer
//      capacity, or statutory-certificate expiries. This port renders those cells
//      as an explicit "not in feed" state — never a fabricated 22.5 kn / 13,100
//      TEU / IOPP-2027 line. Propose vesselShipments.getVesselSpecs and
//      vesselCompliance.getCertificateBinder.
//    • getVesselParticulars returns null when MARINETRAFFIC_API_KEY is unset — the
//      whole screen then reads its honest "awaiting AIS feed" state, not zeros.
//
//  NAV (VesselOperatorNavController): HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//  transportMode=vessel · flag as reported. PERSONA Vessel Operator · Aurora Ocean Division.
//

import SwiftUI

struct VesselParticularsScreen: View {
    let theme: Theme.Palette
    /// IMO the particulars are drilled into (query scope). A blank/unknown IMO
    /// or an unconfigured AIS feed reads as the honest "awaiting feed" state.
    var imoNumber: String = "9456789"

    var body: some View {
        Shell(theme: theme) {
            VesselParticularsBody(imoNumber: imoNumber)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct VesselParticulars: Decodable {
    let imoNumber: String?
    let name: String?
    let type: String?
    let flag: String?
    let grossTonnage: Double?
    let deadweight: Double?
    let length: Double?
    let beam: Double?
    let yearBuilt: Int?
    let owner: String?
    let `operator`: String?
    let callSign: String?
    let classification: String?
}

private struct PortCall: Decodable, Identifiable {
    var id: String { (unlocode ?? portName ?? "") + (arrivalTime ?? "") }
    let portName: String?
    let unlocode: String?
    let arrivalTime: String?
    let departureTime: String?
    let inPort: Bool?
    let country: String?
}

// MARK: - Body

private struct VesselParticularsBody: View {
    @Environment(\.palette) private var palette
    let imoNumber: String

    @State private var particulars: VesselParticulars? = nil
    @State private var portCalls: [PortCall] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline().padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s4) {
                    shipHero
                    principalGrid
                    portCallBinder
                    esangCard
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
                Text("✦ VESSEL OPERATOR · PARTICULARS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("IMO \(particulars?.imoNumber ?? imoNumber)")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Vessel particulars")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary).padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5)
    }

    // MARK: Ship GA hero

    private var shipHero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(particulars?.name ?? "—")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(builtLine)
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: Space.s2)
                classPill
            }
            ShipProfile(loa: particulars?.length, beam: particulars?.beam)
                .frame(height: 128)
                .frame(maxWidth: .infinity)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    private var builtLine: String {
        let yr = particulars?.yearBuilt.map(String.init) ?? "—"
        let flag = particulars?.flag ?? "—"
        return "IMO \(particulars?.imoNumber ?? imoNumber) · \(yr) · \(flag)"
    }

    @ViewBuilder private var classPill: some View {
        if let cls = particulars?.classification, !cls.isEmpty {
            HStack(spacing: 6) {
                Circle().fill(Brand.success).frame(width: 6, height: 6)
                Text("IN CLASS · \(cls.uppercased())")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.3).foregroundStyle(Brand.success)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Brand.success.opacity(0.18)))
        } else {
            Text("CLASS · NOT IN FEED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.3).foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(palette.tintNeutral))
        }
    }

    // MARK: Principal particulars grid

    private var principalGrid: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("PRINCIPAL PARTICULARS · getVesselParticulars")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s3) {
                HStack(spacing: Space.s3) {
                    specCell("BUILT", particulars?.yearBuilt.map(String.init) ?? "—")
                    specCell("FLAG", particulars?.flag ?? "—")
                }
                HStack(spacing: Space.s3) {
                    specCell("GT / DWT", gtDwt)
                    specCell("TYPE", particulars?.type ?? "—")
                }
                HStack(spacing: Space.s3) {
                    specCell("LOA / BEAM", loaBeam)
                    specCell("CALL SIGN", particulars?.callSign ?? "—")
                }
                HStack(spacing: Space.s3) {
                    specCell("SERVICE SPEED", "not in feed", muted: true)
                    specCell("TEU / REEFER", "not in feed", muted: true)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity)
            .eusoCard(radius: Radius.lg)
        }
    }

    private func specCell(_ label: String, _ value: String, muted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 14, weight: .bold))
                .foregroundStyle(muted ? palette.textTertiary : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gtDwt: String {
        let gt = particulars?.grossTonnage.map { compact($0) } ?? "—"
        let dwt = particulars?.deadweight.map { compact($0) } ?? "—"
        return "\(gt) / \(dwt)"
    }
    private var loaBeam: String {
        let l = particulars?.length.map { String(format: "%.0f m", $0) } ?? "—"
        let b = particulars?.beam.map { String(format: "%.1f m", $0) } ?? "—"
        return "\(l) / \(b)"
    }
    private func compact(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.0fk", v / 1000) }
        return String(format: "%.0f", v)
    }

    // MARK: Port-call / cert binder

    private var portCallBinder: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("PORT-CALL HISTORY · getVesselPortCalls")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            if loading {
                LifecycleCard { Text("Loading port calls…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
            } else if portCalls.isEmpty {
                EusoEmptyState(icon: Image(systemName: "sailboat"),
                               title: "No port calls in feed",
                               subtitle: "AIS port-call history appears here when the MarineTraffic feed is provisioned for this IMO.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(portCalls.prefix(6).enumerated()), id: \.element.id) { idx, pc in
                        portCallRow(pc)
                        if idx < min(portCalls.count, 6) - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s1)
                        }
                    }
                }
                .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.lg)
            }

            Text("Statutory certificate binder (SMC · ISSC · IOPP) not in the AIS feed — pending vesselCompliance.getCertificateBinder.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
    }

    private func portCallRow(_ pc: PortCall) -> some View {
        HStack(spacing: Space.s3) {
            Circle().fill(pc.inPort == true ? Brand.success : Brand.neutral).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(pc.portName ?? pc.unlocode ?? "—")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(pc.unlocode ?? "—") · \(pc.country ?? "")")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Text(prettyDate(pc.arrivalTime))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(pc.inPort == true ? Brand.success : palette.textTertiary)
        }
    }

    // MARK: ESANG

    private var esangCard: some View {
        HStack(spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · CERT WATCH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(particulars == nil ? "Provision the AIS feed to watch this hull" : "In class — statutory binder is the long pole")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text("cert expiries pending getCertificateBinder")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl)
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct ImoIn: Encodable { let imoNumber: String }
        struct CallsIn: Encodable { let imoNumber: String; let days: Int }
        do {
            self.particulars = try await EusoTripAPI.shared.query("vesselShipments.getVesselParticulars", input: ImoIn(imoNumber: imoNumber))
            self.portCalls = (try? await EusoTripAPI.shared.query("vesselShipments.getVesselPortCalls", input: CallsIn(imoNumber: imoNumber, days: 30))) ?? []
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func prettyDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let iso = ISO8601DateFormatter()
        guard let d = iso.date(from: raw) ?? {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: raw)
        }() else { return raw }
        let out = DateFormatter(); out.dateFormat = "MMM dd"
        return out.string(from: d)
    }
}

// MARK: - ShipProfile (bespoke general-arrangement side elevation)

private struct ShipProfile: View {
    let loa: Double?
    let beam: Double?
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let deckY = h * 0.42
            let waterY = h * 0.62
            let hullBottom = h * 0.76
            let bowX = w * 0.94
            let sternX = w * 0.05

            ZStack(alignment: .topLeading) {
                // sea panel
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.info.opacity(0.10))

                // waterline
                Path { p in
                    p.move(to: CGPoint(x: sternX - 4, y: waterY)); p.addLine(to: CGPoint(x: w, y: waterY))
                }.stroke(Brand.info.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // hull
                hullPath(sternX: sternX, bowX: bowX, deckY: deckY, hullBottom: hullBottom)
                    .fill(Color(hex: 0x3C4D58))
                // submerged draft band
                hullPath(sternX: sternX, bowX: bowX, deckY: deckY, hullBottom: hullBottom)
                    .fill(Brand.info.opacity(0.22))
                    .mask(Rectangle().path(in: CGRect(x: 0, y: waterY, width: w, height: hullBottom - waterY)))

                // deck line
                Path { p in
                    p.move(to: CGPoint(x: sternX, y: deckY)); p.addLine(to: CGPoint(x: bowX - 6, y: deckY))
                }.stroke(Color(hex: 0x6E828E), lineWidth: 1)

                // accommodation block (aft)
                Rectangle().fill(Color(hex: 0x4A5C68))
                    .frame(width: w * 0.07, height: h * 0.16)
                    .position(x: sternX + w * 0.09, y: deckY - h * 0.08)
                // funnel
                RoundedRectangle(cornerRadius: 2).fill(LinearGradient.diagonal)
                    .frame(width: w * 0.03, height: h * 0.10)
                    .position(x: sternX + w * 0.10, y: deckY - h * 0.20)

                // on-deck container bays
                containerBays(sternX: sternX, bowX: bowX, deckY: deckY, w: w, h: h)

                // load-line (Plimsoll) disc
                ZStack {
                    Circle().strokeBorder(palette.textPrimary.opacity(0.55), lineWidth: 1.2).frame(width: 10, height: 10)
                    Rectangle().fill(palette.textPrimary.opacity(0.55)).frame(width: 16, height: 1.2)
                }
                .position(x: w * 0.44, y: waterY)

                // LOA caliper
                Path { p in
                    p.move(to: CGPoint(x: sternX, y: h * 0.92)); p.addLine(to: CGPoint(x: bowX, y: h * 0.92))
                    p.move(to: CGPoint(x: sternX, y: h * 0.90)); p.addLine(to: CGPoint(x: sternX, y: h * 0.94))
                    p.move(to: CGPoint(x: bowX, y: h * 0.90)); p.addLine(to: CGPoint(x: bowX, y: h * 0.94))
                }.stroke(palette.textTertiary, lineWidth: 1)
                Text(loaLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(palette.bgCard))
                    .position(x: w * 0.5, y: h * 0.92)

                // beam badge
                Text(beamLabel)
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(palette.bgCardSoft))
                    .position(x: w * 0.16, y: h * 0.10)
            }
        }
    }

    private var loaLabel: String { loa.map { String(format: "LOA %.0f m", $0) } ?? "LOA — m" }
    private var beamLabel: String { beam.map { String(format: "%.1f m beam", $0) } ?? "— beam" }

    private func hullPath(sternX: CGFloat, bowX: CGFloat, deckY: CGFloat, hullBottom: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: sternX, y: deckY))
            p.addLine(to: CGPoint(x: sternX, y: hullBottom - 6))
            p.addQuadCurve(to: CGPoint(x: sternX + 8, y: hullBottom), control: CGPoint(x: sternX, y: hullBottom))
            p.addLine(to: CGPoint(x: bowX - 30, y: hullBottom))
            p.addQuadCurve(to: CGPoint(x: bowX, y: (deckY + hullBottom) / 2), control: CGPoint(x: bowX + 6, y: hullBottom - 6))
            p.addLine(to: CGPoint(x: bowX - 6, y: deckY))
            p.closeSubpath()
        }
    }

    @ViewBuilder
    private func containerBays(sternX: CGFloat, bowX: CGFloat, deckY: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        let colors: [Color] = [Color(hex: 0x607D8B), Brand.info, Color(hex: 0x607D8B), Brand.warning, Color(hex: 0x607D8B), Color(hex: 0x607D8B)]
        let startX = sternX + w * 0.18
        let bayW = w * 0.085
        let gap = w * 0.012
        ForEach(0..<6, id: \.self) { i in
            let bx = startX + CGFloat(i) * (bayW + gap)
            let bh = h * (0.18 - Double(abs(2 - i)) * 0.012)
            RoundedRectangle(cornerRadius: 1)
                .fill(colors[i].opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 1).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6))
                .frame(width: bayW, height: bh)
                .position(x: bx + bayW / 2, y: deckY - bh / 2 - 1)
        }
    }
}

#Preview("699 · Vessel Particulars · Night") {
    VesselParticularsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("699 · Vessel Particulars · Light") {
    VesselParticularsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
