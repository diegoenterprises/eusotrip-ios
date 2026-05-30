//
//  680_VesselIntermodalSegmentBoard.swift
//  EusoTrip — Vessel Operator · Intermodal Segment Board (operator ops vantage
//  that ADVANCES legs and RECORDS port transfers for a dray-ocean-dray
//  intermodal shipment).
//
//  Verbatim port of "680 Vessel Intermodal Segment Board.svg" (Dark).
//  Operator-side counterpart to the shipper-read 008 Vessel Intermodal Journey
//  — this surface FIRES the two ops mutations 008 only reads. Same shipment
//  row 008 reads (backend coherence across vantages). Nav anchored to
//  VesselOperatorNavController (HOME · SHIPMENTS(current) · [orb] · COMPLIANCE
//  · ME), Shipments tab current.
//
//  Data (tRPC server/routers/intermodal.ts · router namespace `intermodal`):
//    intermodal.getIntermodalShipmentDetail (EXISTS :161 · input {id} ->
//      shipment + segments[] ordered by legNumber + transfers[] + containers[])
//    intermodal.getIntermodalTracking (EXISTS :269 · input {intermodalShipmentId}
//      -> currentMode, activeSegmentId)
//    intermodal.advanceSegment (EXISTS :184 · mutation {intermodalShipmentId,
//      completedSegmentId} -> sets segment completed, opens next leg booked,
//      inserts transfer fromMode_to_toMode, rolls shipment status)
//    intermodal.recordTransfer (EXISTS :235 · mutation {intermodalShipmentId,
//      fromSegmentId, toSegmentId, transferType, facilityType} · transferType
//      enum incl truck_to_vessel/vessel_to_truck · facilityType enum incl
//      port_terminal)
//
//  PURPOSE: the operator advances each intermodal leg and records the port
//  transfer from one screen, so the dray-ocean-dray box never stalls between
//  modes.
//

import SwiftUI

struct VesselIntermodalSegmentBoardScreen: View {
    let theme: Theme.Palette
    /// intermodal_shipments.id of the shipment whose legs the operator advances.
    /// 008 (shipper read) opens the same row from the journey list; 680 is the
    /// operator ops vantage onto it.
    let shipmentId: Int

    var body: some View {
        Shell(theme: theme) {
            VesselIntermodalSegmentBoardBody(shipmentId: shipmentId)
        } nav: {
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

// MARK: - Data shapes (mirror intermodal.ts return rows)

private struct IMSegment680: Decodable, Identifiable {
    let id: Int
    let legNumber: Int
    let mode: String?                    // TRUCK | RAIL | VESSEL
    let originDescription: String?
    let destinationDescription: String?
    let rate: String?
    let status: String?                  // pending | booked | in_transit | completed | cancelled
    let departedAt: String?
    let arrivedAt: String?
}

private struct IMTransfer680: Decodable, Identifiable {
    let id: Int
    let fromSegmentId: Int?
    let toSegmentId: Int?
    let transferType: String?            // truck_to_vessel | vessel_to_truck | …
    let facilityName: String?
    let facilityType: String?            // port_terminal | …
    let status: String?                  // scheduled | in_progress | completed | …
}

private struct IMContainer680: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let containerType: String?           // 40ft_hc | …
    let sealNumber: String?
    let currentMode: String?
    let status: String?
}

/// `getIntermodalShipmentDetail` returns `{ ...shipment, segments, transfers,
/// containers }` — the shipment columns are spread at the top level.
private struct IMShipmentDetail680: Decodable {
    let id: Int
    let intermodalNumber: String?
    let originType: String?
    let destinationType: String?
    let originLocation: IMLoc680?
    let destinationLocation: IMLoc680?
    let commodity: String?
    let numberOfSegments: Int?
    let status: String?                  // …second_leg_active…
    let segments: [IMSegment680]
    let transfers: [IMTransfer680]
    let containers: [IMContainer680]
}

private struct IMLoc680: Decodable {
    let lat: Double?
    let lng: Double?
    let description: String?
}

/// `getIntermodalTracking` -> currentMode + activeSegmentId (drives the
/// active-leg marker on the relay timeline).
private struct IMTracking680: Decodable {
    let currentMode: String?
    let activeSegmentId: Int?
}

// MARK: - Body

private struct VesselIntermodalSegmentBoardBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var detail: IMShipmentDetail680? = nil
    @State private var tracking: IMTracking680? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Mutation state
    @State private var advancing = false
    @State private var recording = false
    @State private var actionError: String? = nil
    @State private var actionDone: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if let d = detail {
                    shipmentContextCard(d)
                    segmentsLabel(d)
                    journeyRelayCard(d)
                    actionFeedback
                    advanceCTA(d)
                    recordTransferCTA(d)
                    opsMutationsCaption
                } else {
                    EusoEmptyState(
                        systemImage: "arrow.triangle.swap",
                        title: "No intermodal shipment",
                        subtitle: "This intermodal segment board has no shipment to advance."
                    )
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (back + eyebrow + title + subtitle)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            HStack(spacing: 5) {
                Text("✦ VESSEL OPERATOR · SEGMENT OPS BOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
            }
            .padding(.top, Space.s3)
            Text("Advance the legs")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
            Text(subtitle)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var subtitle: String {
        // "getIntermodalShipmentDetail · IM-50732 · 3 legs · 2 modes"
        let num = detail?.intermodalNumber ?? "IM-\(shipmentId)"
        let legs = detail?.numberOfSegments ?? detail?.segments.count ?? 0
        let modes = modeCount
        return "getIntermodalShipmentDetail · \(num) · \(legs) legs · \(modes) modes"
    }

    private var modeCount: Int {
        guard let segs = detail?.segments else { return 0 }
        return Set(segs.compactMap { $0.mode?.uppercased() }).count
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 256)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Shipment context card (gradient-rimmed)

    private func shipmentContextCard(_ d: IMShipmentDetail680) -> some View {
        // Hero copy: "CMAU 5391740 · 40' HC dry · FEU" / "IM-50732 · Shenzhen
        // CN → Ontario CA" / status pill "2ND LEG ACTIVE".
        let container = d.containers.first
        let title = containerTitle(container)
        let route = routeLine(d)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 14) {
                    // Container glyph (blue outline w/ corrugation strokes)
                    ContainerGlyph680()
                        .frame(width: 34, height: 22)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(route)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer()
                    statusBadge(d.status)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private func containerTitle(_ c: IMContainer680?) -> String {
        // "CMAU 5391740 · 40' HC dry · FEU"
        guard let c else {
            // No container row — fall back to the commodity / shipment number.
            return detail?.commodity ?? detail?.intermodalNumber ?? "Container"
        }
        var parts: [String] = []
        if let n = c.containerNumber, !n.isEmpty { parts.append(n) }
        if let t = c.containerType, !t.isEmpty { parts.append(containerTypeLabel(t)) }
        parts.append(isFEU(c.containerType) ? "FEU" : "TEU")
        return parts.joined(separator: " · ")
    }

    private func containerTypeLabel(_ raw: String) -> String {
        switch raw {
        case "20ft":          return "20'"
        case "40ft":          return "40'"
        case "40ft_hc":       return "40' HC dry"
        case "45ft":          return "45'"
        case "53ft_domestic": return "53' domestic"
        case "20ft_reefer":   return "20' reefer"
        case "40ft_reefer":   return "40' reefer"
        default:              return raw.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func isFEU(_ type: String?) -> Bool {
        // 40'+ boxes count as FEU (forty-foot equivalent unit), 20' as TEU.
        guard let t = type else { return false }
        return t.hasPrefix("40") || t.hasPrefix("45") || t.hasPrefix("53")
    }

    private func routeLine(_ d: IMShipmentDetail680) -> String {
        // "IM-50732 · Shenzhen CN → Ontario CA"
        let num = d.intermodalNumber ?? "IM-\(d.id)"
        let from = d.originLocation?.description
            ?? d.segments.first?.originDescription
            ?? "Origin"
        let to = d.destinationLocation?.description
            ?? d.segments.last?.destinationDescription
            ?? "Destination"
        return "\(num) · \(from) → \(to)"
    }

    private func statusBadge(_ status: String?) -> some View {
        let label = (status ?? "")
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
        return Text(label.isEmpty ? "—" : label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
            .foregroundStyle(Brand.blue)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Brand.blue.opacity(0.12)))
    }

    // MARK: - Segments label

    private func segmentsLabel(_ d: IMShipmentDetail680) -> some View {
        // "JOURNEY SEGMENTS · getIntermodalTracking · activeSegmentId = leg N"
        let legTxt: String = {
            guard let activeId = tracking?.activeSegmentId,
                  let seg = d.segments.first(where: { $0.id == activeId }) else {
                return "—"
            }
            return "leg \(seg.legNumber)"
        }()
        return Text("JOURNEY SEGMENTS · getIntermodalTracking · activeSegmentId = \(legTxt)")
            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Journey relay card (timeline of legs + transfers)

    private func journeyRelayCard(_ d: IMShipmentDetail680) -> some View {
        // Interleave ordered segments + their transfers into a single relay
        // rail: leg → transfer → leg → transfer → leg, matching the SVG's
        // dray-ocean-dray timeline.
        let rows = relayRows(d)
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                relayRow(row, isLast: idx == rows.count - 1)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private enum RelayKind { case completed, active, pending }

    private struct RelayRow {
        let title: String
        let subtitle: String
        let extra: String?
        let kind: RelayKind
        let isTransfer: Bool
    }

    private func relayRows(_ d: IMShipmentDetail680) -> [RelayRow] {
        var rows: [RelayRow] = []
        let segs = d.segments.sorted { $0.legNumber < $1.legNumber }
        for seg in segs {
            rows.append(segmentRow(seg))
            // Transfer that departs FROM this segment, if any.
            if let xfer = d.transfers.first(where: { $0.fromSegmentId == seg.id }) {
                rows.append(transferRow(xfer))
            }
        }
        return rows
    }

    private func segmentRow(_ seg: IMSegment680) -> RelayRow {
        let kind: RelayKind = {
            let s = (seg.status ?? "").lowercased()
            if s == "completed" { return .completed }
            if s == "in_transit" || s == "booked" || seg.id == tracking?.activeSegmentId { return .active }
            return .pending
        }()
        // "Leg 2 · Ocean line-haul · vessel"
        let modeName = modeLabel(seg.mode)
        let title = "Leg \(seg.legNumber) · \(legRole(seg)) · \(modeName.lowercased())"
        // "Yantian CNYAN → Long Beach USLGB · in transit"
        let from = seg.originDescription ?? "—"
        let to = seg.destinationDescription ?? "—"
        let statusTail: String = {
            switch kind {
            case .completed:
                if let a = seg.arrivedAt { return "completed \(shortDate(a))" }
                return "completed"
            case .active:    return "in transit"
            case .pending:   return "pending"
            }
        }()
        return RelayRow(
            title: title,
            subtitle: "\(from) → \(to) · \(statusTail)",
            extra: nil,
            kind: kind,
            isTransfer: false
        )
    }

    private func legRole(_ seg: IMSegment680) -> String {
        // Verbatim vocabulary: origin dray / ocean line-haul / delivery dray.
        let mode = (seg.mode ?? "").uppercased()
        switch mode {
        case "VESSEL": return "Ocean line-haul"
        case "RAIL":   return "Rail line-haul"
        case "TRUCK":
            if seg.legNumber == 1 { return "Origin dray" }
            return "Delivery dray"
        default:       return "Segment"
        }
    }

    private func transferRow(_ xfer: IMTransfer680) -> RelayRow {
        let kind: RelayKind = {
            switch (xfer.status ?? "").lowercased() {
            case "completed":          return .completed
            case "in_progress":        return .active
            default:                   return .pending
            }
        }()
        // "Transfer · truck → vessel"
        let title = "Transfer · \(transferModeArrow(xfer.transferType))"
        // "Yantian ICT · port_terminal · recordTransfer done"
        let facility = xfer.facilityName ?? "Transfer facility"
        let fType = xfer.facilityType ?? "—"
        let statusTail: String = {
            switch kind {
            case .completed: return "recordTransfer done"
            case .active:    return "in progress"
            case .pending:   return "awaiting discharge"
            }
        }()
        return RelayRow(
            title: title,
            subtitle: "\(facility) · \(fType) · \(statusTail)",
            extra: nil,
            kind: kind,
            isTransfer: true
        )
    }

    private func transferModeArrow(_ raw: String?) -> String {
        // truck_to_vessel -> "truck → vessel"
        guard let raw, raw.contains("_to_") else { return raw ?? "—" }
        let parts = raw.components(separatedBy: "_to_")
        guard parts.count == 2 else { return raw }
        return "\(parts[0]) → \(parts[1])"
    }

    private func relayRow(_ row: RelayRow, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Marker + connecting rail
            VStack(spacing: 0) {
                relayMarker(row.kind)
                if !isLast {
                    Rectangle()
                        .fill(Brand.blue.opacity(0.25))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(row.kind == .active
                                     ? AnyShapeStyle(LinearGradient.diagonal)
                                     : AnyShapeStyle(palette.textPrimary))
                Text(row.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
                if let extra = row.extra {
                    Text(extra)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.bottom, isLast ? 0 : Space.s4)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func relayMarker(_ kind: RelayKind) -> some View {
        switch kind {
        case .completed:
            ZStack {
                Circle().fill(Brand.success).frame(width: 14, height: 14)
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.white)
            }
        case .active:
            ZStack {
                Circle().stroke(LinearGradient.diagonal, lineWidth: 3).frame(width: 18, height: 18)
                Circle().fill(LinearGradient.diagonal).frame(width: 7, height: 7)
            }
        case .pending:
            Circle()
                .stroke(palette.textTertiary, lineWidth: 2)
                .frame(width: 12, height: 12)
        }
    }

    // MARK: - Action feedback (mutation result)

    @ViewBuilder
    private var actionFeedback: some View {
        if let e = actionError {
            LifecycleCard(accentDanger: true) {
                Text(e).font(EType.caption).foregroundStyle(Brand.danger)
            }
        } else if let ok = actionDone {
            LifecycleCard {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Brand.success)
                    Text(ok).font(EType.caption).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    // MARK: - Advance CTA (advanceSegment)

    private func advanceCTA(_ d: IMShipmentDetail680) -> some View {
        // "Advance ocean leg → discharge". Completes the active leg; server
        // opens next leg + inserts transfer + rolls shipment status.
        let active = activeSegment(d)
        let title: String = {
            guard let seg = active else { return "Advance current leg" }
            return "Advance \(modeLabel(seg.mode).lowercased()) leg → \(nextStepLabel(d, after: seg))"
        }()
        return CTAButton(
            title: advancing ? "Advancing…" : title,
            action: { Task { await advance(d) } },
            isLoading: advancing
        )
        .disabled(active == nil)
        .opacity(active == nil ? 0.5 : 1)
    }

    private func nextStepLabel(_ d: IMShipmentDetail680, after seg: IMSegment680) -> String {
        // If there's a transfer out of the active leg, name its destination
        // mode; else "discharge".
        if let xfer = d.transfers.first(where: { $0.fromSegmentId == seg.id }),
           let raw = xfer.transferType, raw.contains("_to_") {
            return raw.components(separatedBy: "_to_").last ?? "discharge"
        }
        if let next = d.segments.first(where: { $0.legNumber == seg.legNumber + 1 }) {
            return modeLabel(next.mode).lowercased()
        }
        return "discharge"
    }

    // MARK: - Record transfer CTA (recordTransfer)

    private func recordTransferCTA(_ d: IMShipmentDetail680) -> some View {
        // "Record vessel → truck transfer". Records the port transfer between
        // the active leg and the next leg.
        let pair = pendingTransferPair(d)
        let title: String = {
            guard let p = pair else { return "Record transfer" }
            return "Record \(transferModeArrow(p.transferType)) transfer"
        }()
        return Button {
            Task { await recordTransfer(d) }
        } label: {
            Text(recording ? "Recording…" : title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(recording || pair == nil)
        .opacity(pair == nil ? 0.5 : 1)
    }

    /// The from/to segment pair + derived transferType for the next port
    /// transfer the operator can record (out of the active leg into the next).
    private struct TransferPair {
        let fromSegmentId: Int
        let toSegmentId: Int
        let transferType: String
        let facilityName: String?
    }

    private func pendingTransferPair(_ d: IMShipmentDetail680) -> TransferPair? {
        guard let from = activeSegment(d),
              let to = d.segments.first(where: { $0.legNumber == from.legNumber + 1 })
        else { return nil }
        let fromMode = (from.mode ?? "").lowercased()
        let toMode = (to.mode ?? "").lowercased()
        guard !fromMode.isEmpty, !toMode.isEmpty else { return nil }
        let type = "\(fromMode)_to_\(toMode)"
        // If a transfer row already exists for this pair, surface its facility.
        let existing = d.transfers.first(where: { $0.fromSegmentId == from.id && $0.toSegmentId == to.id })
        return TransferPair(
            fromSegmentId: from.id,
            toSegmentId: to.id,
            transferType: type,
            facilityName: existing?.facilityName
        )
    }

    // MARK: - Ops mutations caption

    private var opsMutationsCaption: some View {
        Text("advanceSegment · recordTransfer · ops mutations")
            .font(.system(size: 10))
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Space.s2)
    }

    // MARK: - Helpers

    private func activeSegment(_ d: IMShipmentDetail680) -> IMSegment680? {
        if let activeId = tracking?.activeSegmentId,
           let seg = d.segments.first(where: { $0.id == activeId }) {
            return seg
        }
        // Fallback: first in_transit / booked leg.
        return d.segments
            .sorted { $0.legNumber < $1.legNumber }
            .first { ["in_transit", "booked"].contains(($0.status ?? "").lowercased()) }
    }

    private func modeLabel(_ raw: String?) -> String {
        switch (raw ?? "").uppercased() {
        case "TRUCK":  return "Truck"
        case "RAIL":   return "Rail"
        case "VESSEL": return "Vessel"
        default:       return "Segment"
        }
    }

    private func shortDate(_ iso: String) -> String {
        // Best-effort "MM-dd" trim from an ISO / date string.
        let f = ISO8601DateFormatter()
        if let d = f.date(from: iso) {
            let out = DateFormatter(); out.dateFormat = "MM-dd"
            return out.string(from: d)
        }
        // Plain "yyyy-MM-dd" -> "MM-dd"
        let parts = iso.prefix(10).split(separator: "-")
        if parts.count == 3 { return "\(parts[1])-\(parts[2])" }
        return String(iso.prefix(10))
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        struct TrackingIn: Encodable { let intermodalShipmentId: Int }
        do {
            async let det: IMShipmentDetail680 = EusoTripAPI.shared.query(
                "intermodal.getIntermodalShipmentDetail", input: DetailIn(id: shipmentId))
            async let trk: IMTracking680 = EusoTripAPI.shared.query(
                "intermodal.getIntermodalTracking", input: TrackingIn(intermodalShipmentId: shipmentId))
            let (d, t) = try await (det, trk)
            self.detail = d
            self.tracking = t
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - advanceSegment

    private func advance(_ d: IMShipmentDetail680) async {
        guard let seg = activeSegment(d) else { return }
        advancing = true; actionError = nil; actionDone = nil
        struct AdvanceIn: Encodable { let intermodalShipmentId: Int; let completedSegmentId: Int }
        struct AdvanceAck: Decodable { let success: Bool?; let nextSegmentId: Int?; let newStatus: String? }
        do {
            let ack: AdvanceAck = try await EusoTripAPI.shared.mutation(
                "intermodal.advanceSegment",
                input: AdvanceIn(intermodalShipmentId: d.id, completedSegmentId: seg.id))
            if ack.success == true {
                let status = (ack.newStatus ?? "advanced").replacingOccurrences(of: "_", with: " ")
                actionDone = "Leg \(seg.legNumber) completed · shipment now \(status)."
            } else {
                actionError = "advanceSegment did not confirm."
            }
            await load()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        advancing = false
    }

    // MARK: - recordTransfer

    private func recordTransfer(_ d: IMShipmentDetail680) async {
        guard let pair = pendingTransferPair(d) else { return }
        recording = true; actionError = nil; actionDone = nil
        struct TransferIn: Encodable {
            let intermodalShipmentId: Int
            let fromSegmentId: Int
            let toSegmentId: Int
            let transferType: String
            let facilityName: String?
            let facilityType: String
        }
        struct TransferAck: Decodable { let id: Int?; let success: Bool? }
        do {
            // facilityType: port-terminal transfer between dray + ocean legs.
            let ack: TransferAck = try await EusoTripAPI.shared.mutation(
                "intermodal.recordTransfer",
                input: TransferIn(
                    intermodalShipmentId: d.id,
                    fromSegmentId: pair.fromSegmentId,
                    toSegmentId: pair.toSegmentId,
                    transferType: pair.transferType,
                    facilityName: pair.facilityName,
                    facilityType: "port_terminal"))
            if ack.success == true {
                actionDone = "Transfer recorded · \(transferModeArrow(pair.transferType)) at port terminal."
            } else {
                actionError = "recordTransfer did not confirm."
            }
            await load()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        recording = false
    }
}

// MARK: - Container glyph (blue outline + corrugation strokes)

private struct ContainerGlyph680: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Brand.blue, lineWidth: 1.6)
                // Corrugation strokes
                Path { p in
                    let cols = 4
                    for i in 1...cols {
                        let x = w * CGFloat(i) / CGFloat(cols + 1)
                        p.move(to: CGPoint(x: x, y: 2))
                        p.addLine(to: CGPoint(x: x, y: h - 2))
                    }
                }
                .stroke(Brand.blue.opacity(0.6), lineWidth: 1.1)
            }
        }
    }
}

#Preview("680 · Vessel Intermodal Segment Board · Night") {
    VesselIntermodalSegmentBoardScreen(theme: Theme.dark, shipmentId: 50732)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("680 · Vessel Intermodal Segment Board · Light") {
    VesselIntermodalSegmentBoardScreen(theme: Theme.light, shipmentId: 50732)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
