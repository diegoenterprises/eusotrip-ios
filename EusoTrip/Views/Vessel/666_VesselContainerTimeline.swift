//
//  666_VesselContainerTimeline.swift
//  EusoTrip — Vessel Operator · Container Timeline (CARRIER-SIDE · TIMELINE class).
//
//  Verbatim port of "666 Vessel Container Timeline.svg" (Dark). Web parity:
//  ContainerTracking.tsx (`/vessel/container/:id/timeline`). A single auditable
//  chain-of-events for ONE box — booking, gate-in, loaded, departed, in-transit
//  AIS, ETA discharge, gate-out — each node a done/current/future dot on a
//  vertical connector rail with mono timestamp + event title + location/actor sub.
//
//  Data:
//    vesselShipments.getContainerTracking  → { container, movements }  (vesselProcedure · server/routers/vesselShipments.ts:583)
//    vesselShipments.recordContainerMovement → { success }            (Add-event CTA · server/routers/vesselShipments.ts:609)
//
//  ZERO-FALLBACK (2026-06-09 · B21 fix): the hardcoded 7-node canonical chain (incl. a fake LIVE
//  AIS ping at 31.2°N 142.8°W) is DELETED — the timeline renders ONLY live movement rows, and the
//  previously-dead EusoEmptyState is the real empty state for unknown/quiet boxes. The hero
//  derives lane/spec/status/ETA from the live container row with em-dash absence — no invented
//  vessel name, lane or ETA.
//
//  NAV (VesselOperatorNavController): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//  transportMode=vessel · ISO 6346 · per-box drill-in.
//

import SwiftUI

struct VesselContainerTimelineScreen: View {
    let theme: Theme.Palette
    /// ISO 6346 box id this timeline is drilled into (query scope only — when the
    /// box is unknown server-side the screen renders its honest empty state).
    var containerNumber: String = "MSKU 7829301"

    var body: some View {
        Shell(theme: theme) {
            VesselContainerTimelineBody(containerNumber: containerNumber)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",         isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill",  isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror getContainerTracking → { container, movements })

private struct ContainerGeo: Decodable {
    let lat: Double?
    let lng: Double?
    let description: String?
}

private struct TimelineContainer: Decodable {
    let id: Int?
    let containerNumber: String?
    let isoType: String?
    let sizeType: String?
    let status: String?
    let currentLocation: ContainerGeo?
    let assignedShipmentId: Int?
}

private struct ContainerMovement: Decodable, Identifiable {
    let id: Int
    let containerId: Int?
    let shipmentId: Int?
    let eventType: String?
    let location: ContainerGeo?
    let portId: Int?
    let temperature: String?
    let humidity: String?
    let timestamp: String?
}

private struct ContainerTrackingResponse: Decodable {
    let container: TimelineContainer?
    let movements: [ContainerMovement]
}

private struct RecordMovementOut: Decodable {
    let success: Bool
}

// MARK: - Node model (canonical 7-node chain from the SVG)

/// A node in the vertical event chain. The done/current/future state drives
/// the dot treatment + the gradient/faint connector exactly as the SVG canon.
private struct TimelineNode: Identifiable {
    enum State { case done, current, future }
    let id = UUID()
    let timestamp: String   // mono — "May 12 · 09:20 CST"
    let title: String       // 14/700
    let sub: String         // location/actor
    let state: State
}

// MARK: - Body

private struct VesselContainerTimelineBody: View {
    @Environment(\.palette) private var palette

    let containerNumber: String

    @State private var tracking: ContainerTrackingResponse? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Add-event mutation state
    @State private var addingEvent = false
    @State private var addError: String? = nil
    @State private var addAck: String? = nil
    @State private var shareAck: String? = nil

    // B21: the hardcoded canonical 7-node chain is gone — only live movements render.

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s4) {
                    summaryHero
                    eventChainSection
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

    // MARK: - Top bar (DETAIL)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ VESSEL OPERATOR · CONTAINER TIMELINE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                // Live shipment ref when the box is assigned — em-dash otherwise.
                Text(tracking?.container?.assignedShipmentId.map { "SHIPMENT \($0)" } ?? "—")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Text(liveContainerNumber)
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    /// Live box id from the server row, falling back to the canon box.
    private var liveContainerNumber: String {
        tracking?.container?.containerNumber ?? containerNumber
    }

    // MARK: - Compact summary hero

    private var summaryHero: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.info.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "shippingbox")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Brand.info)
            }
            VStack(alignment: .leading, spacing: 3) {
                // Live current-location description — em-dash when the box is unknown
                // (no invented lane string).
                Text(tracking?.container?.currentLocation?.description ?? "—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(heroSpec)
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 3) {
                Text(heroStatus)
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(LinearGradient.primary)
                Text(tracking?.container?.id.map { "BOX #\($0)" } ?? "—")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(Color(hex: 0x1C2128))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// Live ISO size/type spec — em-dash when the box is unknown. No invented vessel name.
    private var heroSpec: String {
        guard let c = tracking?.container,
              let size = (c.sizeType ?? c.isoType).map({ humanSize($0) }) else { return "—" }
        return size
    }

    private func humanSize(_ raw: String) -> String {
        switch raw {
        case "40ft_hc":      return "40HC dry"
        case "40ft":         return "40ft dry"
        case "20ft":         return "20ft dry"
        case "45ft":         return "45ft dry"
        case "40ft_reefer":  return "40ft reefer"
        case "20ft_reefer":  return "20ft reefer"
        default:             return raw
        }
    }

    /// Live container status — em-dash when the box is unknown (never a default "ON WATER").
    private var heroStatus: String {
        switch (tracking?.container?.status ?? "").lowercased() {
        case "in_transit": return "ON WATER"
        case "at_port":    return "AT PORT"
        case "at_depot":   return "AT DEPOT"
        case "loaded":     return "LOADED"
        case "empty":      return "EMPTY"
        case "":           return "—"
        default:           return (tracking?.container?.status ?? "—").replacingOccurrences(of: "_", with: " ").uppercased()
        }
    }

    // MARK: - Event chain section

    private var eventChainSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(chainEyebrow)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            if loading {
                LifecycleCard {
                    Text("Loading event chain…")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }
            } else if displayNodes.isEmpty {
                EusoEmptyState(systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                               title: "No events recorded",
                               subtitle: "Gate, load and AIS events for this container will appear here.")
            } else {
                VerticalEventTimeline(nodes: displayNodes)
                    .padding(Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x1C2128))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private var chainEyebrow: String {
        "EVENT CHAIN · \(displayNodes.count) NODES · getContainerTracking"
    }

    /// The chain we render — LIVE movement rows only. An unknown/quiet box yields
    /// an empty chain and the honest EusoEmptyState above renders (B21: the
    /// canonical-fixture fallback is deleted).
    private var displayNodes: [TimelineNode] {
        guard let movements = tracking?.movements, !movements.isEmpty else {
            return []
        }
        // Server returns newest-first (orderBy desc timestamp). The timeline
        // reads oldest → newest top-to-bottom, with the most recent row as
        // the current node and any est rows after it as future.
        let ordered = movements.reversed().enumerated().map { (idx, m) -> TimelineNode in
            let isLast = idx == movements.count - 1
            return TimelineNode(
                timestamp: prettyTimestamp(m.timestamp),
                title: prettyEventType(m.eventType),
                sub: m.location?.description
                    ?? geoString(m.location)
                    ?? "-",
                state: isLast ? .current : .done
            )
        }
        return Array(ordered)
    }

    private func geoString(_ g: ContainerGeo?) -> String? {
        guard let g, let lat = g.lat, let lng = g.lng else { return nil }
        return String(format: "%.1f°, %.1f°", lat, lng)
    }

    private func prettyEventType(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Event" }
        switch raw {
        case "booking_confirmed": return "Booking confirmed"
        case "gate_in":           return "Gate-in at origin"
        case "loaded":            return "Loaded aboard vessel"
        case "departed":          return "Vessel departed"
        case "in_transit", "ais": return "In transit · AIS ping"
        case "eta_discharge":     return "ETA discharge"
        case "gate_out":          return "Gate-out · drayage"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func prettyTimestamp(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "-" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return raw }
        let out = DateFormatter()
        out.dateFormat = "MMM dd · HH:mm 'UTC'"
        return out.string(from: date)
    }

    // MARK: - CTA pair (Add event · Share link)

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button(action: { Task { await addEvent() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                        Text("Add event")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .opacity(addingEvent ? 0.6 : 1)
                }
                .buttonStyle(.plain)
                .disabled(addingEvent || tracking?.container?.id == nil)

                Button(action: { shareLink() }) {
                    Text("Share link")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 132, height: 48)
                        .background(Color(hex: 0x232932))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let addError {
                Text(addError)
                    .font(EType.caption).foregroundStyle(Brand.danger)
            }
            if let addAck {
                Text(addAck)
                    .font(EType.caption).foregroundStyle(Brand.success)
            }
            if let shareAck {
                Text(shareAck)
                    .font(EType.caption).foregroundStyle(Brand.info)
            }
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct TrackingIn: Encodable {
            let containerNumber: String
        }
        do {
            // The canon container id is the ISO 6346 number (e.g. "MSKU 7829301").
            // getContainerTracking resolves the row by containerNumber and returns
            // { container, movements } — both nullable/empty when the box isn't
            // on the server yet, which we surface as a real empty state above.
            let res: ContainerTrackingResponse = try await EusoTripAPI.shared.query(
                "vesselShipments.getContainerTracking",
                input: TrackingIn(containerNumber: liveContainerNumber.replacingOccurrences(of: " ", with: "")))
            self.tracking = res
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Add event (recordContainerMovement)

    private func addEvent() async {
        addError = nil; addAck = nil
        guard let containerId = tracking?.container?.id else {
            addError = "No live container row to append to."
            return
        }
        addingEvent = true
        struct RecordIn: Encodable {
            let containerId: Int
            let shipmentId: Int?
            let eventType: String
        }
        do {
            // Appends a movement + blockchainAuditTrail row server-side. The
            // event type defaults to an AIS ping for the carrier-side "Add
            // event" affordance; a full composer would collect the type/loc.
            let out: RecordMovementOut = try await EusoTripAPI.shared.mutation(
                "vesselShipments.recordContainerMovement",
                input: RecordIn(containerId: containerId,
                                shipmentId: tracking?.container?.assignedShipmentId,
                                eventType: "in_transit"))
            if out.success {
                addAck = "Event recorded to the chain."
                await load()
            } else {
                addError = "The server rejected the event."
            }
        } catch {
            addError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        addingEvent = false
    }

    // MARK: - Share link

    private func shareLink() {
        // Web parity surface: /vessel/container/:id/timeline. Copies the
        // canonical chain URL so Lena can export it for a claim or customs
        // query without a back-and-forth with the carrier.
        let idPart = tracking?.container?.id.map(String.init) ?? liveContainerNumber.replacingOccurrences(of: " ", with: "")
        let link = "https://eusotrip.com/vessel/container/\(idPart)/timeline"
        UIPasteboard.general.string = link
        shareAck = "Timeline link copied."
    }
}

// MARK: - VerticalEventTimeline (the bespoke left-rail node stack)

private struct VerticalEventTimeline: View {
    @Environment(\.palette) private var palette
    let nodes: [TimelineNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { idx, node in
                row(node, isLast: idx == nodes.count - 1)
            }
        }
    }

    private func row(_ node: TimelineNode, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            // Left rail: dot + connector
            VStack(spacing: 0) {
                dot(node.state)
                if !isLast {
                    connector(after: node.state)
                }
            }
            .frame(width: 18)

            // Node copy: mono timestamp + title 14/700 + sub
            VStack(alignment: .leading, spacing: 3) {
                Text(node.timestamp)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(node.state == .current ? Brand.blue : palette.textTertiary)
                Text(node.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(node.state == .future ? palette.textTertiary : palette.textPrimary)
                Text(node.sub)
                    .font(.system(size: 11))
                    .foregroundStyle(node.state == .future ? palette.textTertiary : palette.textSecondary)
            }
            .padding(.bottom, isLast ? 0 : Space.s5)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func dot(_ state: TimelineNode.State) -> some View {
        switch state {
        case .done:
            Circle()
                .fill(LinearGradient.primary)
                .frame(width: 12, height: 12)
                .padding(.top, 4)
        case .current:
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(LinearGradient.primary, lineWidth: 2.5))
                Circle()
                    .fill(LinearGradient.primary)
                    .frame(width: 7, height: 7)
            }
            .padding(.top, 2)
        case .future:
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 12, height: 12)
                .padding(.top, 4)
        }
    }

    /// Connector below the dot — solid gradient while the chain is still in
    /// the "done/current" run, faint white once we cross into future nodes.
    @ViewBuilder
    private func connector(after state: TimelineNode.State) -> some View {
        Group {
            if state == .future {
                Rectangle().fill(Color.white.opacity(0.12))
            } else {
                Rectangle().fill(LinearGradient.primary)
            }
        }
        .frame(width: 2.4)
        .frame(maxHeight: .infinity)
    }
}

#Preview("666 · Vessel Container Timeline · Night") {
    VesselContainerTimelineScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("666 · Vessel Container Timeline · Light") {
    VesselContainerTimelineScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
