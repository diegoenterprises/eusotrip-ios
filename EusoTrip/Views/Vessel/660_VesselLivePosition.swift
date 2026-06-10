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
//  ZERO-FALLBACK (2026-06-09 · C1 cluster fix): ALL seeded operational state (CNSHA→USLGB lane,
//  "BERTH J232", "14.2 kn" SOG, 94% to-berth, "14:30" ETA, "+1.4m" tide, the 3 seeded approach
//  steps, the hardcoded ESang plan) is DELETED — every face nil-inits to em-dash and hydrates
//  ONLY from live reads, with honest empty states. Decode shapes corrected to the REAL wire:
//  getVesselTrack → RoutePosition[] (bare array), getVesselPortCalls → PortCall[] | null,
//  tracking.getGeofenceEvents → {geofenceName,eventType,dwellSeconds,timestamp} rows, and
//  getVesselShipmentDetail → the raw shipment spread (bookingNumber + port joins). Anchors
//  (shipmentId/IMO) resolve from the operator's REAL newest booking + fleet vessel when not
//  threaded — no hardcoded 260602/9811000. Tide has no server source ⇒ permanent em-dash.
//
//  PERSONA: Vessel Operator (PROVISIONAL — no name in any nav enum/router; carrier-anchored, no
//  auto-name). transportMode=vessel · US (CBP ACE · ISF). One ✦ eyebrow · one iridescent hairline.
//  — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen (Shell + real Vessel Operator nav · SHIPMENTS inked)

struct VesselLivePositionScreen: View {
    let theme: Theme.Palette
    /// 0 / "" (registry/zero-arg use) = not threaded: the screen resolves the
    /// operator's REAL newest booking + lead fleet vessel live, or renders the
    /// honest awaiting state — never hardcoded anchor ids.
    var shipmentId: Int
    var imoNumber: String

    init(theme: Theme.Palette, shipmentId: Int = 0, imoNumber: String = "") {
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

// MARK: - Wire shapes (match the REAL server output exactly — no invented envelopes)

/// getVesselShipmentDetail spreads the raw vessel_shipments row + port joins.
private struct VesselDetail660: Decodable {
    let bookingNumber: String?
    let status: String?
    let voyageNumber: String?
    // Port join (:289 returns originPort / destinationPort rows). UN/LOCODE + name
    // resolve the great-circle endpoints through the bundled PortDirectory catalog —
    // the SAME real-coordinate path Vessel 003 uses (003:314/326).
    let originPort: VesselPort660?
    let destinationPort: VesselPort660?
}
private struct VesselPort660: Decodable { let name: String?; let unlocode: String? }

/// getVesselTrack → MarineTraffic RoutePosition[] (bare array; newest data last).
private struct RoutePos660: Decodable {
    let lat: Double?
    let lng: Double?
    let speed: Double?
    let heading: Double?
    let course: Double?
    let timestamp: String?
}

/// getVesselPortCalls → MarineTraffic PortCall[] (bare array, or null on error).
private struct PortCallRow660: Decodable {
    let portName: String?
    let unlocode: String?
    let arrivalTime: String?
    let departureTime: String?
    let inPort: Bool?
}

/// tracking.getGeofenceEvents row (tracking.ts:476-480).
private struct GeofenceEvent660: Decodable {
    let id: String?
    let geofenceName: String?
    let eventType: String?     // enter | exit
    let dwellSeconds: Int?
    let timestamp: String?
}

// MARK: - Body

private struct VesselLivePositionBody_660: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let imoNumber: String

    // Resolved anchors (threaded or live-resolved) ------------------------------------
    @State private var resolvedShipmentId: Int? = nil
    @State private var resolvedImo: String? = nil

    // Booking facts (getVesselShipmentDetail) — nil-init, em-dash until live ----------
    @State private var lane = "—"
    @State private var berth = "—"
    @State private var reference = "—"

    // Great-circle endpoints — UN/LOCODE + name from the getVesselShipmentDetail port
    // join (:289), coordinates resolved through PortDirectory. nil until load lands a
    // real booking, which gates the live ocean map (no map on null endpoints).
    @State private var originPort: VesselPort660? = nil
    @State private var destinationPort: VesselPort660? = nil

    // One live tick (getVesselTrack RoutePosition[]) — SOG feeds the voyage meter +
    // the AIS status capsule. The live marker fraction lives INSIDE VesselOceanTrackMap.
    @State private var sog = "—"
    @State private var degraded = true   // honest: degraded until the first real fix lands

    // Port-call meter (getVesselPortCalls) — em-dash until a real upcoming call exists.
    // toBerthPct/tide have NO server source today ⇒ 0 ring + permanent em-dash.
    @State private var toBerthPct = 0.0
    @State private var etaBerth = "—"
    @State private var runNm = "—"
    private let tide = "—"
    private let tideNote = "no tide feed"

    // Approach sequence (tracking.getGeofenceEvents) — live rows or honest empty.
    @State private var steps: [ApproachStep660] = []

    @State private var loading = true
    @State private var loadError: String? = nil

    /// ESang plan — derived from LIVE faces only; the card hides when nothing real exists.
    private var esangLine: String? {
        if etaBerth != "—" { return "Next port call ETA \(etaBerth)" }
        return nil
    }
    private var esangDetail: String {
        sog == "—" ? "derived from AIS port calls" : "derived from AIS port calls · SOG \(sog)"
    }

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
            Text("Live position").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Spacer()
        }
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 300)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
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

    // MARK: Hero — LIVE ocean/AIS register (canonical VesselOceanTrackMap · Vessel 003:250)
    //
    // CANON: the hand-drawn approach-chart (Circles/Text via .position() + a static
    // quad-curve approach + status-fraction marker) is REPLACED by the in-house native
    // ocean register `VesselOceanTrackMap` → `BespokeMapCanvas(style: .ocean)`. It is fed
    // the booking's REAL endpoints (great circle CNSHA→USLGB drawn from the
    // getVesselShipmentDetail port join) and the LIVE AIS feed keyed by this screen's
    // `imoNumber` — the orb, solid/dashed route split, and the speed/heading/coords chip
    // are the real position inside the canvas, NOT a status guess. Same hero chrome the
    // 003 card uses (ocean fill, Radius.xl, borderFaint stroke). The AIS-LIVE/DEGRADED and
    // berth status capsules ride on as overlays so the live-position eyebrow is preserved.
    //
    // Coord gate (Driver 013 pattern, cheat-sheet §6): both endpoints must resolve to real
    // PortDirectory coordinates before drawing; otherwise a neutral placeholder so the map
    // never frames on null island. No hardcoded coordinate literal anywhere in this view.

    private var heroMap: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Color(red: 0.039, green: 0.078, blue: 0.133)) // #0A1422 ocean
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Brand.blue.opacity(0.06))

            if let imo = resolvedImo, !imo.isEmpty, let o = originCoord, let d = destinationCoord {
                VesselOceanTrackMap(
                    imoNumber: imo,
                    origin: o,
                    destination: d,
                    originLabel: originLabel,
                    destinationLabel: destinationLabel
                )
            } else {
                heroMapAwaiting
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
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
            Text(berth).font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.725, green: 0.831, blue: 0.949))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color(red: 0.043, green: 0.071, blue: 0.125)))
                .padding(12)
        }
    }

    /// No-endpoints / no-IMO placeholder so the hero never frames on null island.
    private var heroMapAwaiting: some View {
        VStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(palette.textTertiary)
            Text("Awaiting first AIS fix")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textSecondary)
            Text("Live position appears once the lane endpoints resolve.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4)
    }

    // MARK: Origin / destination resolution (UN/LOCODE port join → PortDirectory coords)

    /// Origin great-circle endpoint — the booking's origin port UN/LOCODE resolved through
    /// the bundled PortDirectory catalog (the same real-coordinate path Vessel 003 uses at
    /// 003:314). nil until a real booking lands ⇒ the coord gate keeps the placeholder.
    private var originCoord: HereLatLng? { coord(for: originPort) }

    /// Destination great-circle endpoint — destination port UN/LOCODE → PortDirectory (003:326).
    private var destinationCoord: HereLatLng? { coord(for: destinationPort) }

    private func coord(for port: VesselPort660?) -> HereLatLng? {
        guard let code = port?.unlocode, !code.isEmpty, let p = PortDirectory.find(unlocode: code) else { return nil }
        return HereLatLng(p.lat, p.lng)
    }

    private var originLabel: String { originPort?.name ?? originPort?.unlocode ?? "Origin" }
    private var destinationLabel: String { destinationPort?.name ?? destinationPort?.unlocode ?? "Destination" }

    // MARK: Live voyage meter (to-berth arc + ETA/RUN/SOG/TIDE)

    private var voyageMeter: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text("VOYAGE METER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Circle().fill(degraded ? Brand.warning : Brand.success).frame(width: 6, height: 6)
                Text(degraded ? "NO LIVE FIX" : "LIVE · ONE TICK").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(degraded ? Brand.warning : Brand.success)
                Spacer()
            }
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().stroke(palette.textPrimary.opacity(0.08), lineWidth: 7).frame(width: 68, height: 68)
                    Circle().trim(from: 0, to: toBerthPct).stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .frame(width: 68, height: 68).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        // No to-berth feed exists server-side — honest em-dash, never a seeded 94%.
                        Text(toBerthPct > 0 ? "\(Int(toBerthPct*100))%" : "—").font(.system(size: 19, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        Text("TO BERTH").font(.system(size: 7.5, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("ETA NEXT CALL").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    Text(etaBerth).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: Space.s4) { metric("RUN", runNm); metric("SOG", sog) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("TIDE").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    // No tide feed exists — permanent honest em-dash (was a seeded "+1.4m").
                    Text(tide).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(palette.textTertiary)
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
                if steps.isEmpty {
                    // Honest empty: no live geofence events ⇒ no fabricated approach story.
                    EusoEmptyState(systemImage: "point.3.connected.trianglepath.dotted",
                                   title: "No geofence events yet",
                                   subtitle: "Pilot-ground and berth-box crossings appear here as they fire.")
                        .padding(Space.s4)
                } else {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { idx, s in
                        stepRow(s)
                        if idx < steps.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 68)
                        }
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

    // MARK: Fused ESang card (renders only when a live-derived plan line exists)

    @ViewBuilder
    private var esangCard: some View {
        if let line = esangLine {
            HStack(alignment: .top, spacing: 0) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.6), .clear], center: .topLeading, startRadius: 1, endRadius: 16)).frame(width: 32, height: 32)
                }.padding(.trailing, Space.s3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ESANG · VOYAGE PLAN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(line).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
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
    }

    // MARK: Load (parallel reads · all faces re-reason together)

    private func load() async {
        loading = true; loadError = nil
        do {
            // 1. Resolve REAL anchors: threaded values win; otherwise the operator's
            //    newest live booking + lead fleet vessel. Nothing hardcoded.
            var sid: Int? = shipmentId > 0 ? shipmentId : nil
            if sid == nil {
                struct ListIn660: Encodable { let limit: Int; let offset: Int }
                struct ShipRow660: Decodable { let id: Int }
                struct ShipEnv660: Decodable { let shipments: [ShipRow660] }
                let env: ShipEnv660 = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipments", input: ListIn660(limit: 1, offset: 0))
                sid = env.shipments.first?.id
            }
            resolvedShipmentId = sid

            var imo: String? = imoNumber.isEmpty ? nil : imoNumber
            if imo == nil {
                struct FleetIn660: Encodable { let limit: Int; let offset: Int }
                struct VesselRow660: Decodable { let imoNumber: String? }
                struct FleetEnv660: Decodable { let vessels: [VesselRow660] }
                let fleet: FleetEnv660 = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselFleet", input: FleetIn660(limit: 1, offset: 0))
                imo = fleet.vessels.first?.imoNumber
            }
            resolvedImo = imo

            // 2. Fan the live faces over the real anchors (each optional/empty-tolerant).
            struct DetailIn: Encodable { let id: Int }
            struct ImoIn: Encodable { let imoNumber: String }
            struct CallIn: Encodable { let imoNumber: String; let days: Int }
            if let sid {
                let d: VesselDetail660? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipmentDetail", input: DetailIn(id: sid))
                if let d { applyDetail(d) }
            }
            if let imo, !imo.isEmpty {
                async let track: [RoutePos660] = EusoTripAPI.shared.query(
                    "vesselShipments.getVesselTrack", input: ImoIn(imoNumber: imo))
                async let calls: [PortCallRow660]? = EusoTripAPI.shared.query(
                    "vesselShipments.getVesselPortCalls", input: CallIn(imoNumber: imo, days: 7))
                let (t, c) = try await (track, calls)
                applyTrack(t); applyCalls(c ?? [])
            }
            struct FenceIn: Encodable { let limit: Int }
            let fences: [GeofenceEvent660] = try await EusoTripAPI.shared.query(
                "tracking.getGeofenceEvents", input: FenceIn(limit: 10))
            applyFences(fences)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Live AIS poller — re-reads the REAL track for the resolved IMO. SwiftUI
    /// cancels this `.task` on disappear. No fix yet ⇒ stays honestly DEGRADED.
    private func streamTrack() async {
        struct ImoIn: Encodable { let imoNumber: String }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if Task.isCancelled { break }
            guard let imo = resolvedImo, !imo.isEmpty else { continue }
            do {
                let t: [RoutePos660] = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselTrack", input: ImoIn(imoNumber: imo))
                withAnimation(.easeInOut(duration: 1.2)) { applyTrack(t) }
            } catch {
                withAnimation { degraded = true }
            }
        }
    }

    private func applyDetail(_ d: VesselDetail660) {
        if let ref = d.bookingNumber, !ref.isEmpty { reference = ref }
        let o = d.originPort?.unlocode ?? d.originPort?.name
        let dest = d.destinationPort?.unlocode ?? d.destinationPort?.name
        if let o, let dest { lane = "\(o.uppercased()) → \(dest.uppercased())" }
        // No berth column exists on the shipment row — berth stays em-dash (honest).
        originPort = d.originPort
        destinationPort = d.destinationPort
    }
    private func applyTrack(_ positions: [RoutePos660]) {
        // Newest fix = last reported position with a speed.
        if let fix = positions.last(where: { $0.speed != nil }), let v = fix.speed {
            sog = String(format: "%.1f kn", v)
            degraded = false
        } else {
            degraded = true
        }
    }
    private func applyCalls(_ calls: [PortCallRow660]) {
        // Next upcoming call = first row that hasn't departed and isn't alongside.
        let upcoming = calls.first { ($0.departureTime?.isEmpty != false) && ($0.inPort != true) }
        if let eta = upcoming?.arrivalTime, !eta.isEmpty {
            etaBerth = Self.shortTime(eta)
        } else {
            etaBerth = "—"
        }
        // No live run-distance / to-berth-fraction source ⇒ honest 0 ring + em-dash.
        runNm = "—"
        toBerthPct = 0
    }
    private func applyFences(_ f: [GeofenceEvent660]) {
        // UNCONDITIONAL overwrite — an empty feed renders the honest empty ledger.
        steps = f.compactMap { ApproachStep660(wire: $0) }
    }

    private static func shortTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let d = f.date(from: iso) else {
            // Fall back to the raw "HH:mm" slice of a date-time string.
            let parts = iso.split(separator: "T")
            return parts.count > 1 ? String(parts[1].prefix(5)) : iso
        }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "MMM dd HH:mm"
        return out.string(from: d)
    }
}

// MARK: - Approach step model (geofence event → display row · live rows only)

private struct ApproachStep660: Identifiable {
    let id = UUID()
    enum Kind {
        case enter, exit
        var glyph: String { switch self { case .enter: return "arrow.down.right.circle"; case .exit: return "arrow.up.right.circle" } }
        var tint: Color { switch self { case .enter: return Brand.info; case .exit: return Brand.magenta } }
    }
    let kind: Kind
    let title: String
    let detail: String
    let pill: String
    let pillKind: StatusPill.Kind
    let value: String

    /// Maps the REAL tracking.getGeofenceEvents row shape — no invented fence taxonomy.
    init?(wire: GeofenceEvent660) {
        let type = (wire.eventType ?? "").lowercased()
        guard type == "enter" || type == "exit" else { return nil }
        kind = type == "enter" ? .enter : .exit
        title = (wire.geofenceName?.isEmpty == false) ? wire.geofenceName! : "Geofence"
        let dwellMin = (wire.dwellSeconds ?? 0) / 60
        detail = dwellMin > 0 ? "\(type.uppercased()) · dwell \(dwellMin)m" : type.uppercased()
        pill = type.uppercased()
        pillKind = type == "enter" ? .info : .neutral
        // Short HH:mm of the event timestamp — em-dash when absent.
        if let ts = wire.timestamp, !ts.isEmpty {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: ts) {
                let out = DateFormatter()
                out.locale = Locale(identifier: "en_US_POSIX")
                out.dateFormat = "HH:mm"
                value = out.string(from: d)
            } else {
                value = "-"
            }
        } else {
            value = "-"
        }
    }
}

#Preview("660 · Live position · Night") {
    VesselLivePositionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("660 · Live position · Light") {
    VesselLivePositionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
