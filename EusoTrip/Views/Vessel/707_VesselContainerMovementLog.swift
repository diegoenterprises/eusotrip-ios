//
//  707_VesselContainerMovementLog.swift
//  EusoTrip — Vessel Operator · Container Movement Log (CARRIER-SIDE · LEDGER class).
//
//  Verbatim port of "707 Vessel Container Movement Log.svg" (Dark + Light). A
//  bespoke PHYSICAL-MOVE LEDGER (deliberately different from 666's milestone
//  timeline): a today's-moves tally hero with a segmented move-type bar, then a
//  dense ledger where every row leads with a coloured move-type tag
//  (GATE IN / LOADED / DISCH / GATE OUT) + the ISO-6346 container id + a
//  from→to position + the move timestamp. A move ledger, not a stat dashboard.
//
//  Web parity: ContainerTracking.tsx (`/vessel/moves`).
//
//  DATA (endpoints confirmed on disk this fire):
//    containerTimeline.timeline {limit}
//        → { events[], total }  each event { source, eventType, location{description},
//            containerId, shipmentId, portId, temperature, timestamp }
//        (vesselProcedure · server/routers/containerTimeline.ts:19 — no container/shipment
//         filter ⇒ terminal-wide recent-move stream)
//    vesselShipments.getLandfallRegime {country}
//        → { country, arrivalInstrument, releaseInstrument, freeTimeBasis, currency }
//        (vesselProcedure → crossBorder.ts:4594 · gates the free-time regime US/CA/MX)
//    vesselShipments.recordContainerMovement {containerId, eventType, ...}
//        → { success }  (MUTATION · inserts containerTracking + blockchainAuditTrail
//         + logs vessel.container_movement_recorded · vesselShipments.ts:1142)
//
//  HONEST GAPS (surfaced to the-oath — NOT papered over):
//    • containerTracking has no handling-equipment / from-pos / to-pos columns —
//      the ledger row's "QC-1 · bay 14 → yard E-14" detail binds to the event's
//      location.description when present, else the eventType only. Propose adding
//      {equipmentId, fromPos, toPos} to containerTracking.recordMove.
//    • The reefer plug temperature binds to the real event.temperature (string)
//      when present; no fabricated 2.1°C.
//
//  NAV (VesselOperatorNavController): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//  transportMode=vessel · tri-country free-time band (US·CA·MX). Container ISO 6346.
//

import SwiftUI

struct VesselContainerMovementLogScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselContainerMovementLogBody()
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

private struct MoveGeo: Decodable { let description: String? }
private struct MoveEvent: Decodable {
    let source: String?
    let eventType: String?
    let location: MoveGeo?
    let containerId: Int?
    let shipmentId: Int?
    let portId: Int?
    let temperature: String?
    let timestamp: String?
}
private struct MovementResponse: Decodable { let events: [MoveEvent]; let total: Int }

private struct MovementLandfallRegime: Decodable {
    let country: String?
    let arrivalInstrument: String?
    let releaseInstrument: String?
    let freeTimeBasis: String?
    let currency: String?
}
private struct RecordMoveOut: Decodable { let success: Bool }

private enum MoveKind: String, CaseIterable {
    case gateIn, loaded, disch, gateOut, other
    var label: String {
        switch self {
        case .gateIn: return "GATE IN"; case .loaded: return "LOADED"
        case .disch: return "DISCH"; case .gateOut: return "GATE OUT"; case .other: return "MOVE"
        }
    }
    var color: Color {
        switch self {
        case .gateIn: return Brand.info; case .loaded: return Brand.blue
        case .disch: return Brand.success; case .gateOut: return Brand.neutral; case .other: return Brand.magenta
        }
    }
}

// MARK: - Body

private struct VesselContainerMovementLogBody: View {
    @Environment(\.palette) private var palette

    @State private var response: MovementResponse? = nil
    @State private var regime: MovementLandfallRegime? = nil
    @State private var country: String = "US"
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var recording = false
    @State private var recordAck: String? = nil
    @State private var recordError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline().padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s4) {
                    tallyHero
                    moveLedger
                    freeTimeBand
                    ctaPair
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var events: [MoveEvent] { response?.events ?? [] }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ VESSEL OPERATOR · MOVEMENT LOG")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("ISO 6346")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Movement log")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary).padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5)
    }

    // MARK: Tally hero + segmented move-type bar

    private var tallyHero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text("\(events.count)")
                    .font(.system(size: 34, weight: .bold, design: .monospaced)).tracking(-0.6)
                    .foregroundStyle(palette.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("moves logged").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text("terminal-wide · recent feed")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Circle().fill(Brand.success).frame(width: 5, height: 5)
                    Text("LIVE LOG").font(.system(size: 8, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.success)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Brand.success.opacity(0.20)))
            }
            segmentedBar
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl)
    }

    private var segmentedBar: some View {
        let counts = kindCounts
        let total = max(1, events.count)
        return VStack(alignment: .leading, spacing: Space.s2) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(MoveKind.allCases, id: \.self) { k in
                        let c = counts[k] ?? 0
                        if c > 0 {
                            RoundedRectangle(cornerRadius: 3).fill(k.color)
                                .frame(width: max(4, geo.size.width * CGFloat(c) / CGFloat(total)))
                        }
                    }
                    if events.isEmpty {
                        RoundedRectangle(cornerRadius: 3).fill(palette.borderFaint)
                    }
                }
            }
            .frame(height: 10)
            // legend
            HStack(spacing: Space.s3) {
                ForEach(MoveKind.allCases.filter { ($0 != .other) }, id: \.self) { k in
                    HStack(spacing: 4) {
                        Circle().fill(k.color).frame(width: 6, height: 6)
                        Text("\(k.label.capitalized) \(counts[k] ?? 0)")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    private var kindCounts: [MoveKind: Int] {
        var d: [MoveKind: Int] = [:]
        for e in events { let k = kind(e.eventType); d[k, default: 0] += 1 }
        return d
    }

    // MARK: Move ledger

    private var moveLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("MOVE LEDGER · ALL MOVE TYPES · ISO 6346")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            if loading {
                LifecycleCard { Text("Loading moves…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
            } else if events.isEmpty {
                EusoEmptyState(icon: Image(systemName: "shippingbox.and.arrow.backward"),
                               title: "No moves logged yet",
                               subtitle: "Gate, crane and yard moves stamp here as they happen — the dwell clock starts from the real move time.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.prefix(12).enumerated()), id: \.offset) { idx, e in
                        moveRow(e)
                        if idx < min(events.count, 12) - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s1)
                        }
                    }
                    Text("\(events.count) stamped · live feed · holds last on downtime")
                        .font(.system(size: 10.5)).foregroundStyle(palette.textTertiary)
                        .padding(.top, Space.s2)
                }
                .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.xl)
            }
        }
    }

    private func moveRow(_ e: MoveEvent) -> some View {
        let k = kind(e.eventType)
        return HStack(spacing: Space.s3) {
            Text(k.label)
                .font(.system(size: 9.5, weight: .heavy)).tracking(0.3).foregroundStyle(k.color)
                .frame(width: 56, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(k.color.opacity(0.20)))
            VStack(alignment: .leading, spacing: 3) {
                Text(e.containerId.map { "BOX #\($0)" } ?? "container")
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(e.location?.description ?? prettyEvent(e.eventType))
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 3) {
                Text(prettyTime(e.timestamp))
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                if let t = e.temperature, !t.isEmpty {
                    Text("\(t)° plug").font(.system(size: 10, design: .monospaced)).foregroundStyle(Brand.info)
                } else {
                    Text(e.source == "shipment_event" ? "milestone" : "move")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    // MARK: Tri-country free-time band

    private var freeTimeBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TERMINAL FREE-TIME")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("DWELL CLOCK GATES ON TERMINAL")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                ForEach(["US", "CA", "MX"], id: \.self) { c in
                    Button { Task { await selectCountry(c) } } label: {
                        Text(c)
                            .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(country == c ? .white : palette.textSecondary)
                            .frame(width: 44, height: 26)
                            .background(country == c ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(regime?.freeTimeBasis ?? "loading regime…")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text(regime?.releaseInstrument ?? "—")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("release on discharge · currency \(regime?.currency ?? "—")")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button { Task { await recordMove() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                        Text("Record container move").font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .opacity(recording || firstContainerId == nil ? 0.6 : 1)
                }
                .buttonStyle(.plain).disabled(recording || firstContainerId == nil)

                Button { Task { await load() } } label: {
                    Text("Refresh").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary).frame(width: 110, height: 48)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if firstContainerId == nil {
                Text("Record enables once a container is present in the move feed.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
            }
            if let recordAck { Text(recordAck).font(EType.caption).foregroundStyle(Brand.success) }
            if let recordError { Text(recordError).font(EType.caption).foregroundStyle(Brand.danger) }
        }
    }

    private var firstContainerId: Int? { events.first(where: { $0.containerId != nil })?.containerId }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct MovesIn: Encodable { let limit = 100 }
        struct RegimeIn: Encodable { let country: String }
        do {
            self.response = try await EusoTripAPI.shared.query("containerTimeline.timeline", input: MovesIn())
            self.regime = try? await EusoTripAPI.shared.query("vesselShipments.getLandfallRegime", input: RegimeIn(country: country))
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func selectCountry(_ c: String) async {
        country = c
        struct RegimeIn: Encodable { let country: String }
        regime = try? await EusoTripAPI.shared.query("vesselShipments.getLandfallRegime", input: RegimeIn(country: c))
    }

    private func recordMove() async {
        recordAck = nil; recordError = nil
        guard let cid = firstContainerId else { recordError = "No container in the feed to log a move for."; return }
        recording = true
        struct In: Encodable { let containerId: Int; let shipmentId: Int?; let eventType: String }
        let shipmentId = events.first(where: { $0.containerId == cid })?.shipmentId
        do {
            let out: RecordMoveOut = try await EusoTripAPI.shared.mutation(
                "vesselShipments.recordContainerMovement",
                input: In(containerId: cid, shipmentId: shipmentId, eventType: "gate_in"))
            recordAck = out.success ? "Move stamped — dwell clock started from now." : "The server rejected the move."
            await load()
        } catch {
            recordError = error.eusoUserCopy
        }
        recording = false
    }

    // MARK: helpers

    private func kind(_ raw: String?) -> MoveKind {
        let s = (raw ?? "").lowercased()
        if s.contains("gate_in") || s.contains("gatein") || s == "arrived" || s.contains("in_gate") { return .gateIn }
        if s.contains("gate_out") || s.contains("gateout") || s.contains("out_gate") || s.contains("depart") { return .gateOut }
        if s.contains("load") { return .loaded }
        if s.contains("disch") || s.contains("unload") { return .disch }
        return .other
    }
    private func prettyEvent(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "move" }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
    private func prettyTime(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let d = ISO8601DateFormatter().date(from: raw) ?? {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: raw)
        }()
        guard let d else { return raw }
        let out = DateFormatter(); out.dateFormat = "HH:mm"
        return out.string(from: d)
    }
}

#Preview("707 · Vessel Container Movement Log · Night") {
    VesselContainerMovementLogScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("707 · Vessel Container Movement Log · Light") {
    VesselContainerMovementLogScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
