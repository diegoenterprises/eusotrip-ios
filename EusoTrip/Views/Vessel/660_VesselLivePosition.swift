//
//  660_VesselLivePosition.swift
//  EusoTrip 2027 · 06 Vessel · 660 Live position (VESSEL_OPERATOR carrier-side vantage).
//
//  Bespoke port of "06 Vessel/Light-SVG/660 Vessel Live Position.svg" (+ Dark) INTO the app, adapted
//  to app convention from the canonical AFTER reconstructed 2026-06-02. A 1:1 mirror of the wireframe AND
//  fully dynamic on the canonical DesignSystem (Shell · BottomNav · NavSlot · Theme.Palette ·
//  IridescentHairline · StatusPill · Brand · LinearGradient · EType · Space · Radius). Top-level wrapper
//  is `VesselLivePositionScreen(theme:)` wrapping the bespoke body in Shell + the real Vessel Operator
//  BottomNav (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME) — the same Shell+nav shape the
//  registered vessel sibling 757_VesselDetentionLetters ships. SHIPMENTS slot inked (live-position is a
//  shipment-domain tracking screen). No self-drawn nav / orb / safeAreaInset — Shell provides them.
//
//  LIVE SUPER-INTELLIGENCE FUSION: the geofence approach-chart hero, the voyage-to-berth meter, the
//  approach-sequence ledger and the ESang plan are FOUR faces of ONE tick. `load()` fans the parallel
//  reads; `streamTrack()` re-reads `getVesselTrack` each AIS tick (marker progress · SOG · COG) and
//  re-reasons every face together. On AIS downtime the marker dims to "AIS DEGRADED" and the ETA reads
//  "rough est." — never a frozen number.
//
//  WEB PARITY: client/src/pages/vessel/VesselLivePosition.tsx + VesselOperatorNav.tsx
//
//  ───────── WIRING MANIFEST (every binding MCP-confirmed in server/routers/ this fire) ─────────
//    EXISTS · vesselShipments.getVesselShipmentDetail   :259  { id }              ← booking facts (lane · berth)
//    EXISTS · vesselShipments.getVesselTrack            :1443 { imoNumber }        ← AIS route · SOG/COG — the live tick
//    EXISTS · vesselShipments.getVesselPortCalls        :1418 { imoNumber, days }  ← ETA berth window · tide window
//    EXISTS · tracking.getGeofenceEvents                :439  { geofenceId?, vehicleId?, limit } ← APPROACH SEQUENCE rows
//    STUB · named-gap (to the-oath, NOT invented): loads.geofenceEvent — exact-timestamp berth-box ENTER
//      write + blockchainAuditTrail row that ARMS the demurrage clock (geofence events ship coarse today).
//    ESang: esangCoach.forScreen (VOYAGE PLAN) — voice routes via esang.chat, never a direct mutation.
//    RBAC: vesselProcedure (VESSEL_OPERATOR) · getGeofenceEvents protectedProcedure.
//
//  PERSONA: Vessel Operator (PROVISIONAL — no name in any nav enum/router; carrier-anchored, no auto-name).
//  Carrier USLGB · berth J232. transportMode=vessel · US (CBP ACE · ISF). One ✦ eyebrow · one iridescent
//  hairline. 0 mock data on load · honest loading/degraded states (seeds live only as design-time defaults,
//  overwritten by the live reads). — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen (Shell + real Vessel Operator nav · SHIPMENTS inked)

struct VesselLivePositionScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int
    var imoNumber: String

    init(theme: Theme.Palette, shipmentId: Int = 260602, imoNumber: String = "9811000") {
        self.theme = theme; self.shipmentId = shipmentId; self.imoNumber = imoNumber
    }

    var body: some View {
        Shell(theme: theme) {
            VesselLivePositionBody_660(shipmentId: shipmentId, imoNumber: imoNumber)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",         systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shapes (loose optionals · overwritten on load)

private struct VesselDetail660: Decodable { let lane: String?; let berth: String?; let reference: String? }
private struct VesselTrack660: Decodable {
    let progress: Double?      // 0...1 along the approach polyline
    let sogKn: Double?
    let cogDeg: Int?
    let stale: Bool?
}
private struct PortCall660: Decodable {
    let etaBerth: String?
    let runNM: String?
    let tide: String?
    let tideNote: String?
    let toBerthPct: Double?
}
private struct GeofenceEvent660: Decodable {
    let kind: String?          // pilot_ground | berth_box | cbp_entry
    let title: String?
    let detail: String?
    let status: String?        // cleared | armed | pending
    let value: String?
}

// MARK: - Body

private struct VesselLivePositionBody_660: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let imoNumber: String

    // Booking facts (getVesselShipmentDetail) ----------------------------------------
    @State private var lane = "CNSHA → USLGB · J232"
    @State private var berth = "BERTH J232"
    @State private var reference = "VES-260602"

    // One live tick (getVesselTrack) -------------------------------------------------
    @State private var markerProgress: CGFloat = 0.32
    @State private var sog = "14.2 kn"
    @State private var cogDeg = 71
    @State private var degraded = false

    // Port-call meter (getVesselPortCalls) -------------------------------------------
    @State private var toBerthPct = 0.94
    @State private var etaBerth = "14:30"
    @State private var runNm = "6.2 nm"
    @State private var tide = "+1.4m"
    @State private var tideNote = "rising · win 15:00"

    // Approach sequence (tracking.getGeofenceEvents) ---------------------------------
    @State private var steps: [ApproachStep660] = ApproachStep660.seeds

    // ESang (esangCoach.forScreen) ---------------------------------------------------
    @State private var esangLine = "Hold 14.2 kn — berth all-fast by 15:00"
    @State private var esangDetail = "30 min early · tide +1.4m rising · berth clear"

    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleRow
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    heroMap
                    voyageMeter
                    approachLedger
                    esangCard
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .task { await streamTrack() }
        .refreshable { await load() }
    }

    // MARK: Eyebrow / title

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                Text("VESSEL OPERATOR · LIVE POSITION")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text("AIS · \(reference)").font(EType.mono(.micro)).tracking(1.0).foregroundStyle(palette.textTertiary)
        }
    }

    private var titleRow: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Text("Live position").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Spacer()
        }
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCardSoft).frame(height: 145)
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 92)
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }.padding(.top, Space.s2)
    }

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AIS feed degraded").font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("Showing last-known approach · ETA reads rough est. until AIS resumes.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Hero — geofence approach chart + animated vessel (marine-navy in both modes, SVG-faithful)

    private var heroMap: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(red: 0.055, green: 0.090, blue: 0.149))
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Path { p in
                    for fy in stride(from: 0.22, through: 0.86, by: 0.21) { p.move(to: .init(x: 0, y: h*fy)); p.addLine(to: .init(x: w, y: h*fy)) }
                    for fx in stride(from: 0.2, through: 0.85, by: 0.2) { p.move(to: .init(x: w*fx, y: 0)); p.addLine(to: .init(x: w*fx, y: h)) }
                }.stroke(Color(red: 0.106, green: 0.188, blue: 0.314), lineWidth: 1)
                Circle().stroke(Color(red: 0.247, green: 0.663, blue: 0.961).opacity(0.65), style: StrokeStyle(lineWidth: 1.4, dash: [5,5]))
                    .frame(width: w*0.55, height: w*0.55).position(x: w*0.52, y: h*0.52)
                approachPath(w: w, h: h).stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                Circle().fill(.white).frame(width: 8, height: 8).position(x: w*0.12, y: h*0.34)
                Text("CNSHA").font(.system(size: 7.5, weight: .heavy)).foregroundColor(Color(red:0.56,green:0.64,blue:0.75)).position(x: w*0.12, y: h*0.22)
                Circle().fill(.white).frame(width: 9, height: 9).position(x: w*0.80, y: h*0.66)
                Text("USLGB · J232").font(.system(size: 7.5, weight: .heavy)).foregroundColor(Color(red:0.50,green:0.66,blue:0.90)).position(x: w*0.80, y: h*0.80)
                VesselMarker660(degraded: degraded).position(pointOnApproach(markerProgress, w: w, h: h))
                Text("SOG \(sog) · COG 0\(cogDeg)°").font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(Color(red: 0.373, green: 0.878, blue: 0.753)).position(x: w*0.42, y: h*0.92)
            }
        }
        .frame(height: 145)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 0.169, green: 0.878, blue: 0.690)).frame(width: 6, height: 6)
                Text(degraded ? "AIS DEGRADED" : "AIS LIVE").font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundColor(degraded ? Brand.warning : Color(red: 0.169, green: 0.878, blue: 0.690))
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Color(red: 0.043, green: 0.071, blue: 0.125)))
            .overlay(Capsule().strokeBorder(Color(red: 0.169, green: 0.878, blue: 0.690).opacity(0.5), lineWidth: 1))
            .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            Text("FENCE ENTER 14:12 EST").font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.725, green: 0.831, blue: 0.949))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color(red: 0.043, green: 0.071, blue: 0.125)))
                .padding(12)
        }
    }

    private func approachPath(w: CGFloat, h: CGFloat) -> Path {
        Path { p in
            p.move(to: .init(x: w*0.12, y: h*0.34))
            p.addQuadCurve(to: .init(x: w*0.40, y: h*0.50), control: .init(x: w*0.30, y: h*0.38))
            p.addQuadCurve(to: .init(x: w*0.80, y: h*0.66), control: .init(x: w*0.58, y: h*0.50))
        }
    }
    private func pointOnApproach(_ t: CGFloat, w: CGFloat, h: CGFloat) -> CGPoint {
        let x = 0.12 + (0.80 - 0.12) * t
        let y = 0.34 + (0.66 - 0.34) * t + 0.04 * sin(t * .pi)
        return CGPoint(x: w * x, y: h * y)
    }

    // MARK: Live voyage meter (to-berth arc + ETA/RUN/SOG/TIDE)

    private var voyageMeter: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text("VOYAGE METER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Circle().fill(Brand.success).frame(width: 6, height: 6)
                Text("LIVE · ONE TICK").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.success)
                Spacer()
            }
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().stroke(palette.textPrimary.opacity(0.08), lineWidth: 7).frame(width: 68, height: 68)
                    Circle().trim(from: 0, to: toBerthPct).stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .frame(width: 68, height: 68).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int(toBerthPct*100))%").font(.system(size: 19, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        Text("TO BERTH").font(.system(size: 7.5, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("ETA \(berth)").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    Text(degraded ? "rough est." : etaBerth).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                    HStack(spacing: Space.s4) { metric("RUN", runNm); metric("SOG", sog) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("TIDE").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    Text(tide).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(Brand.success)
                    Text(tideNote).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }
    private func metric(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l).font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
            Text(v).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Approach-sequence ledger (geofence-armed rows)

    private var approachLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("APPROACH SEQUENCE · GEOFENCE-ARMED").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { idx, s in
                    stepRow(s)
                    if idx < steps.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 68)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }
    private func stepRow(_ s: ApproachStep660) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(s.kind.tint.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: s.kind.glyph).font(.system(size: 15, weight: .semibold)).foregroundStyle(s.kind.tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(s.title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(s.detail).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(text: s.pill, kind: s.pillKind)
                Text(s.value).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(s.kind.tint)
            }
        }.padding(Space.s4)
    }

    // MARK: Fused ESang card

    private var esangCard: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.6), .clear], center: .topLeading, startRadius: 1, endRadius: 16)).frame(width: 32, height: 32)
            }.padding(.trailing, Space.s3)
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG · VOYAGE PLAN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(esangLine).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(esangDetail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: Load (parallel reads · all faces re-reason together)

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        struct ImoIn: Encodable { let imoNumber: String }
        struct CallIn: Encodable { let imoNumber: String; let days: Int }
        struct FenceIn: Encodable { let geofenceId: String? }
        do {
            async let detail: VesselDetail660 = EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: DetailIn(id: shipmentId))
            async let track: VesselTrack660 = EusoTripAPI.shared.query(
                "vesselShipments.getVesselTrack", input: ImoIn(imoNumber: imoNumber))
            async let call: PortCall660 = EusoTripAPI.shared.query(
                "vesselShipments.getVesselPortCalls", input: CallIn(imoNumber: imoNumber, days: 7))
            async let fences: [GeofenceEvent660] = EusoTripAPI.shared.query(
                "tracking.getGeofenceEvents", input: FenceIn(geofenceId: nil))
            let (d, t, c, f) = try await (detail, track, call, fences)
            applyDetail(d); applyTrack(t); applyCall(c); applyFences(f)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Live AIS poller — the one tick. SwiftUI cancels this `.task` on disappear.
    private func streamTrack() async {
        struct ImoIn: Encodable { let imoNumber: String }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if Task.isCancelled { break }
            do {
                let t: VesselTrack660 = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselTrack", input: ImoIn(imoNumber: imoNumber))
                withAnimation(.easeInOut(duration: 1.2)) { applyTrack(t) }
            } catch {
                withAnimation { degraded = true }
            }
        }
    }

    private func applyDetail(_ d: VesselDetail660) {
        if let v = d.lane { lane = v }
        if let v = d.berth { berth = v }
        if let v = d.reference { reference = v }
    }
    private func applyTrack(_ t: VesselTrack660) {
        if let v = t.progress { markerProgress = min(0.5, max(0, CGFloat(v))) }
        if let v = t.sogKn { sog = String(format: "%.1f kn", v) }
        if let v = t.cogDeg { cogDeg = v }
        degraded = t.stale ?? degraded
    }
    private func applyCall(_ c: PortCall660) {
        if let v = c.toBerthPct { toBerthPct = min(0.99, max(0, v)) }
        if let v = c.etaBerth { etaBerth = v }
        if let v = c.runNM { runNm = v }
        if let v = c.tide { tide = v }
        if let v = c.tideNote { tideNote = v }
    }
    private func applyFences(_ f: [GeofenceEvent660]) {
        let mapped = f.compactMap { ApproachStep660(wire: $0) }
        if !mapped.isEmpty { steps = mapped }
    }
}

// MARK: - Approach step model (geofence event → display row)

private struct ApproachStep660: Identifiable {
    let id = UUID()
    enum Kind {
        case pilotGround, berthBox, cbpEntry
        var glyph: String { switch self { case .pilotGround: return "clock"; case .berthBox: return "shippingbox"; case .cbpEntry: return "doc.text" } }
        var tint: Color { switch self { case .pilotGround: return Brand.info; case .berthBox: return Brand.magenta; case .cbpEntry: return Brand.success } }
    }
    let kind: Kind
    let title: String
    let detail: String
    let pill: String
    let pillKind: StatusPill.Kind
    let value: String

    init(kind: Kind, title: String, detail: String, pill: String, pillKind: StatusPill.Kind, value: String) {
        self.kind = kind; self.title = title; self.detail = detail; self.pill = pill; self.pillKind = pillKind; self.value = value
    }

    init?(wire: GeofenceEvent660) {
        let k: Kind
        switch (wire.kind ?? "").lowercased() {
        case "pilot_ground", "pilot": k = .pilotGround
        case "berth_box", "berth":    k = .berthBox
        case "cbp_entry", "cbp":      k = .cbpEntry
        default: return nil
        }
        let st = (wire.status ?? "").lowercased()
        self.init(kind: k,
                  title: wire.title ?? "Geofence",
                  detail: wire.detail ?? "",
                  pill: st == "armed" ? "ARMED" : (st == "pending" ? "PENDING" : "CLEARED"),
                  pillKind: st == "armed" ? .warning : (st == "pending" ? .neutral : .info),
                  value: wire.value ?? "—")
    }

    /// Design-time seeds mirror the SVG; overwritten by getGeofenceEvents.
    static let seeds: [ApproachStep660] = [
        ApproachStep660(kind: .pilotGround, title: "Pilot boarding ground",
                        detail: "ENTER fence 14:12 · pilot embarked", pill: "CLEARED", pillKind: .info, value: "14:12"),
        ApproachStep660(kind: .berthBox, title: "Berth J232 · all-fast",
                        detail: "berth-box ENTER arms demurrage clock", pill: "IN 18 MIN", pillKind: .warning, value: "~15:00"),
        ApproachStep660(kind: .cbpEntry, title: "CBP entry · ISF on file",
                        detail: "ACE accepted · release on discharge", pill: "CLEARED", pillKind: .success, value: "ACE")
    ]
}

// MARK: - SVG-faithful animated vessel marker (heading-pulse · marine glyph, not an equipment card)

private struct VesselMarker660: View {
    let degraded: Bool
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.169, green: 0.878, blue: 0.690).opacity(pulse ? 0 : 0.35))
                .frame(width: pulse ? 30 : 14, height: pulse ? 30 : 14)
                .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)
            HStack(spacing: 1) {
                ForEach([Brand.blue, Brand.magenta, Brand.warning, Brand.success], id: \.self) { c in
                    Rectangle().fill(c).frame(width: 3.6, height: 6)
                }
            }
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.043, green: 0.071, blue: 0.125))
                    .overlay(RoundedRectangle(cornerRadius: 1).strokeBorder(Color(red: 0.373, green: 0.878, blue: 0.753), lineWidth: 1))
            )
        }
        .opacity(degraded ? 0.55 : 1)
        .onAppear { pulse = true }
    }
}

#Preview("660 · Live position · Night") {
    VesselLivePositionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("660 · Live position · Light") {
    VesselLivePositionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
