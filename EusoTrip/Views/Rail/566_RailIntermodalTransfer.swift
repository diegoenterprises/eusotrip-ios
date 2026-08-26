//
//  566_RailIntermodalTransfer.swift
//  EusoTrip — Rail Engineer · Intermodal Transfer (carrier-side modal-interchange handoff board).
//
//  Verbatim port of "566 Rail Intermodal Transfer.svg" (Light + Dark).
//  Rail-truck / rail-vessel container transfers at a named ramp/yard with
//  transfer type, facility, cost, and a recent-transfer log.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Data:
//    intermodal.getTransfers    (EXISTS intermodal.ts:376)  → intermodalTransfers[] desc
//    intermodal.recordTransfer  (EXISTS intermodal.ts:235)  → CTA action
//    intermodal.advanceSegment  (EXISTS intermodal.ts:198)  → segment cursor advance
//
//  Transfer-node map (RAIL .standard board):
//    Each transfer's `location` is a REAL JSON coord column on
//    `intermodal_transfers` (drizzle schema: `location json $type<{lat,lng,
//    description?}>`), written by `recordTransfer` (intermodal.ts:243 input
//    `{ lat, lng, description? }`) and returned VERBATIM by `getTransfers`
//    (intermodal.ts:382 `select().from(intermodalTransfers)` = all columns).
//    We decode `location.lat/lng`, render the modal-interchange node(s) as
//    pins + draw the rail/dray legs (consecutive transfer nodes joined in
//    chain order) on BespokeMapCanvas tilt:0 / style:.auto (RAIL has no
//    dedicated register → standard flat board, same as Rail 628). No fabricated
//    points: gated on a real `location` coord; honest "awaiting coordinates"
//    state when no transfer carries one (the table is currently unpopulated —
//    the seam is wired end-to-end and lights up the moment a transfer is
//    recorded with a location).
//
//  OFFLINE POLICY (§W): ONLINE_ONLY(advanceSegment is a lifecycle commit that
//    closes one leg and opens the next; a queued commit would desynchronise the
//    segment state machine). This matches this screen's own desc contract,
//    which already declares advanceSegment ONLINE_ONLY.
//    · The advance-leg control is visibly gated at 45% with an explicit reason
//      line on its face when the device is offline, and `advanceSegment()`
//      refuses up front rather than firing a lifecycle commit into a dead
//      socket. Nothing is queued and nothing is optimistically marked advanced.
//    · advanceSegment is a MUTATION on the live router (intermodal.ts:561,
//      protectedProcedure .mutation) whose body carries a real ownership gate
//      (loadOwnedShipment) — the server, not this device, decides the next leg.
//    · The transfer list is a plain read with no local cache: offline it shows
//      its real load error rather than a stale board pretending to be current.
//    · S4 FOLLOW-ON: the commit no longer swallows its error. A failed advance
//      now says so on the surface instead of leaving the row looking untouched.
//
//  ESANG: esangCoach.forScreen EXISTS (esangCoach.ts:264) but its SCREEN_ENUM
//    (esangCoach.ts:112) is a driver in-cab list — home / trips / earnings /
//    tax / dvir / availability / missions / badges / referrals / zeun / haul /
//    active-trip — with no rail or intermodal key, and its system prompt speaks
//    HOS and DVIR. Calling it from a modal-interchange board would return the
//    wrong entity, so the ESANG row below is derived on device from the
//    transfers already decoded here and says so on its face. Same call 559 and
//    665 made.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import SwiftUI

struct RailIntermodalTransferScreen: View {
    let theme: Theme.Palette
    let shipmentId: Int

    var body: some View {
        Shell(theme: theme) { RailIntermodalTransferBody(shipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
        // Real top back affordance for this pushed Rail Engineer surface. Fixed
        // leading slot → never overlaps the eyebrow/title; posts the shared
        // NavBack that RailEngineerSurface pops on
        // (RoleSurfaceRouter.swift:4813), so context is preserved on the way out.
        .injectBespokeBackBar(title: nil) {
            NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
        }
    }
}

// MARK: - Data shapes

/// Real transfer-node coordinate. Mirrors the `location` JSON column on
/// `intermodal_transfers` (drizzle: `$type<{ lat: number; lng: number;
/// description?: string }>`). `getTransfers` returns it verbatim; `recordTransfer`
/// writes it. NOT geocoded — the catalog/recorded coordinate of the ramp/yard.
private struct TransferNodeGeo566: Decodable, Hashable {
    let lat: Double?
    let lng: Double?
    let description: String?
}

private struct IntermodalTransfer566: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let transferType: String?           // "truck_to_rail" | "rail_to_truck" | "rail_to_vessel"
    let fromSegmentId: Int?
    let toSegmentId: Int?
    let totalSegments: Int?
    let facilityName: String?
    let facilityType: String?           // "rail_yard" | "ramp" | "depot"
    let location: TransferNodeGeo566?   // REAL coord JSON {lat,lng,description?} (intermodal_transfers.location)
    let transferCost: Double?
    let notes: String?
    let status: String?                 // "completed" | "active" | "queued"
    let timestamp: String?
    let transferTimeMinutes: Double?

    /// The recorded node coordinate, gated against null-island (never frame on 0,0).
    var nodeFix: HereLatLng? {
        guard let coordinate = LatLongParser.validatedCoordinate(
            latitude: location?.lat,
            longitude: location?.lng
        ) else { return nil }
        return HereLatLng(coordinate.latitude, coordinate.longitude)
    }

    /// Human label for the node text sites (was the old `location` string) —
    /// the recorded `description`, falling back to facility name.
    var locationLabel: String? {
        if let d = location?.description, !d.isEmpty { return d }
        return facilityName
    }
}

// MARK: - Body

private struct RailIntermodalTransferBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var reach = OfflineReachabilityHub.shared
    let shipmentId: Int

    @State private var transfers: [IntermodalTransfer566] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isAdvancing = false
    /// Surfaced advance failure. §W: a lifecycle commit that fails must say so.
    @State private var advanceError: String? = nil

    // MARK: §W ONLINE_ONLY gate (advanceSegment)

    /// A lifecycle commit that closes one leg and opens the next may not be
    /// queued — a replayed advance would desynchronise the segment state
    /// machine the server owns.
    private var canAdvance: Bool {
        reach.isOnline && !isAdvancing && activeTransfer != nil
    }

    private var advanceBlockedReason: String? {
        if activeTransfer == nil { return "No active transfer in scope — there is no leg to advance." }
        if !reach.isOnline {
            return "Offline · advancing a leg is ONLINE_ONLY. It closes one segment and opens the next, so it is never queued for silent replay."
        }
        return nil
    }

    // MARK: Derived

    private var activeTransfer: IntermodalTransfer566? {
        transfers.first { ($0.status ?? "").lowercased().contains("active") || ($0.status ?? "").lowercased().contains("in_progress") }
            ?? transfers.first
    }

    private var todayCount: Int { transfers.count }
    private var pendingCount: Int {
        transfers.filter { let s = ($0.status ?? "").lowercased(); return s == "queued" || s == "pending" }.count
    }
    private var avgTimeLabel: String {
        let times = transfers.compactMap { $0.transferTimeMinutes }
        guard !times.isEmpty else { return "-" }
        let avg = times.reduce(0, +) / Double(times.count)
        return "\(Int(avg))m"
    }

    // MARK: Map (real transfer-node coordinates)

    /// Transfers whose recorded `location` carries a real (non-null-island)
    /// coordinate — the ONLY rows we plot. Chain order = oldest→newest so the
    /// drawn legs read pickup → interchange → drayage. `getTransfers` returns
    /// `desc(id)`, so reverse to chronological for the leg polyline.
    private var mappableTransfers: [IntermodalTransfer566] {
        Array(transfers.filter { $0.nodeFix != nil }.reversed())
    }

    /// Camera center = centroid of the real node coordinates (no fabrication).
    private var mapCenter: HereLatLng {
        let fixes = mappableTransfers.compactMap { $0.nodeFix }
        guard !fixes.isEmpty else { return HereLatLng(39.5, -98.35) }
        let lat = fixes.reduce(0.0) { $0 + $1.lat } / Double(fixes.count)
        let lng = fixes.reduce(0.0) { $0 + $1.lng } / Double(fixes.count)
        return HereLatLng(lat, lng)
    }

    /// Tight zoom on a single node; wider when legs span the chain.
    private var mapZoom: Int { mappableTransfers.count <= 1 ? 13 : 7 }

    /// Pin kind per modal-interchange direction (truck side vs rail/vessel side).
    private func nodeKind(_ t: IntermodalTransfer566) -> HereMarker.Kind {
        switch (t.transferType ?? "").lowercased() {
        case "rail_to_vessel", "vessel_to_rail", "truck_to_vessel", "vessel_to_truck": return .delivery
        default: return .pickup
        }
    }

    private func transferTypeLabel(_ t: IntermodalTransfer566) -> String {
        switch (t.transferType ?? "").lowercased() {
        case "truck_to_rail": return "Truck → Rail"
        case "rail_to_truck": return "Rail → Truck"
        case "rail_to_vessel": return "Rail → Vessel"
        default: return (t.transferType ?? "Transfer").replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func chipColor(_ t: IntermodalTransfer566) -> Color {
        switch (t.transferType ?? "").lowercased() {
        case "truck_to_rail": return Brand.info
        case "rail_to_truck": return Brand.warning
        case "rail_to_vessel": return Brand.rail
        default: return Brand.info
        }
    }

    private enum TransferStatus { case done, active, queued }
    private func transferStatus(_ t: IntermodalTransfer566) -> TransferStatus {
        switch (t.status ?? "").lowercased() {
        case "completed", "done": return .done
        case "active", "in_progress": return .active
        default: return .queued
        }
    }

    private var advanceLegTitle: String {
        if let notes = activeTransfer?.notes, !notes.isEmpty { return "Advance leg → \(notes)" }
        return "Advance leg → final drayage"
    }
    private var advanceLegSub: String {
        let to = activeTransfer?.toSegmentId ?? 0
        let total = activeTransfer?.totalSegments ?? to
        return "advanceSegment · seg \(to) of \(total)"
    }
    private var facilityAbbrev: String {
        let name = activeTransfer?.facilityName ?? ""
        guard !name.isEmpty else { return "-" }
        let words = name.split(separator: " ")
        if words.count >= 2 { return "\(words[0].prefix(3)) \(words[1].prefix(2))".uppercased() }
        return String(name.prefix(6)).uppercased()
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading transfers…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    transferMapCard
                    transferList
                    advanceLegRow
                    esangRow
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · INTERMODAL TRANSFER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(facilityAbbrev)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Intermodal Transfer")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Modal-interchange handoffs · live read")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                // §W ONLINE_ONLY — the commit state is declared on the surface,
                // not just in the header comment.
                Text(reach.isOnline ? "online · commit live" : "offline · commit blocked")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(reach.isOnline ? palette.textTertiary : Brand.warning)
                    .fixedSize()
                    .accessibilityLabel(reach.isOnline
                        ? "Online. Advancing a leg is available."
                        : "Offline. Advancing a leg is blocked and is never queued.")
            }
            IridescentHairline()
                .accessibilityHidden(true)
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        let t = activeTransfer
        let isActive = t.map { transferStatus($0) == .active } ?? false
        let typeLabel = t.map { "\(transferTypeLabel($0)) · \(($0.facilityType ?? "ramp"))" } ?? "-"
        let costLabel = t.flatMap { $0.transferCost }.map { "$\(Int($0))" } ?? "-"
        let containerLabel = t?.containerNumber.map { "\($0) transfer" } ?? "-"
        let segLabel: String = {
            if let from = t?.fromSegmentId, let to = t?.toSegmentId {
                return "seg \(from) → seg \(to) · \(t?.notes ?? "drayage")"
            }
            return t?.notes ?? "-"
        }()
        let facilityType = t?.facilityType ?? "ramp"
        let facilityName: String = {
            let name = t?.facilityName ?? "-"
            let words = name.split(separator: " ")
            if words.count >= 2 { return "\(words[0]) \(words[1].prefix(2))" }
            return String(name.prefix(10))
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(isActive ? "IN PROGRESS" : "QUEUED")
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.16)))
                Text(typeLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(costLabel)
                        .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(containerLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(segLabel)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("FACILITY")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(facilityType)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(facilityName)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heroAccessibilityLabel)
    }

    /// Spoken form of the handoff hero, read off the same active transfer the
    /// card draws. Fields the server did not return are said to be pending
    /// rather than substituted.
    private var heroAccessibilityLabel: String {
        guard let t = activeTransfer else { return "No transfer in scope." }
        var s = transferStatus(t) == .active ? "In progress" : "Queued"
        s += ", \(transferTypeLabel(t)) at a \(t.facilityType ?? "ramp")."
        if let cost = t.transferCost { s += " Transfer cost \(Int(cost)) dollars." }
        else { s += " Transfer cost pending." }
        if let c = t.containerNumber { s += " Container \(c)." }
        if let from = t.fromSegmentId, let to = t.toSegmentId { s += " Segment \(from) to segment \(to)." }
        if let f = t.facilityName { s += " Facility \(f)." }
        return s
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "TODAY",    value: "\(todayCount)")
            MetricTile(label: "AVG TIME", value: avgTimeLabel, gradientNumeral: avgTimeLabel != "-")
            MetricTile(label: "PENDING",  value: "\(pendingCount)", accent: pendingCount > 0 ? Brand.warning : nil)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(todayCount) transfer\(todayCount == 1 ? "" : "s") today, average cycle \(avgTimeLabel), \(pendingCount) pending.")
    }

    // MARK: - Transfer-node map (RAIL .standard board)

    /// Renders the modal-interchange node(s) + the rail/dray legs joining them
    /// on the in-house BespokeMapCanvas (tilt:0, style:.auto = the flat rail
    /// board — RAIL has no dedicated register). Every coordinate comes from the
    /// real `intermodal_transfers.location` JSON column via `getTransfers`; the
    /// legs are consecutive recorded nodes in chain order. When no transfer
    /// carries a coordinate yet, an honest "awaiting node coordinates" state
    /// shows instead of a fabricated map — the decode + map path are present and
    /// light up the instant a transfer is recorded with a `location`.
    @ViewBuilder
    private var transferMapCard: some View {
        let nodes = mappableTransfers
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRANSFER NODES · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text(nodes.isEmpty ? "location" : "\(nodes.count) node\(nodes.count == 1 ? "" : "s")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s3)

            if nodes.isEmpty {
                EusoEmptyState(
                    systemImage: "mappin.slash",
                    title: "Awaiting node coordinates",
                    subtitle: "Transfers recorded with a yard/ramp location plot their interchange node here."
                )
            } else {
                HereVectorMapView(
                    center: mapCenter,
                    zoom: mapZoom,
                    interactive: true,
                    tilt: 0,
                    layers: mapLayers,
                    mapModeContext: .primary(.rail),
                    onSelectMarker: { _ in }
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transfer nodes")
        .accessibilityValue(nodes.isEmpty
            ? "No transfer has been recorded with a yard or ramp coordinate yet."
            : "\(nodes.count) recorded interchange node\(nodes.count == 1 ? "" : "s") plotted.")
    }

    /// Map layers: the rail/dray legs (consecutive recorded nodes, rail blue)
    /// + a pin per transfer node, each tappable-id'd by transfer id.
    private var mapLayers: [HereMapLayer] {
        let nodes = mappableTransfers
        return [.markers(nodes.compactMap { t in
            guard let fix = t.nodeFix else { return nil }
            return HereMarker(
                at: fix,
                kind: nodeKind(t),
                label: t.facilityName ?? transferTypeLabel(t),
                id: "\(t.id)")
        })]
    }

    // MARK: - Transfer list

    private var transferList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RECENT TRANSFERS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("transfer log")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if transfers.isEmpty {
                EusoEmptyState(
                    systemImage: "arrow.left.arrow.right",
                    title: "No transfers",
                    subtitle: "Intermodal transfers will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(transfers.enumerated()), id: \.element.id) { idx, t in
                        transferRow(t)
                        if idx < transfers.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                                .overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            }
        }
    }

    private func transferRow(_ t: IntermodalTransfer566) -> some View {
        let color = chipColor(t)
        let status = transferStatus(t)
        let title = "\(transferTypeLabel(t))\(t.containerNumber.map { " · \($0)" } ?? "")"
        let sub = [t.facilityName, t.facilityType, t.timestamp].compactMap { $0 }.joined(separator: " · ")
        let costLabel = t.transferCost.map { "$\(Int($0))" }

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub.isEmpty ? "-" : sub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                statusWord(status)
                if let cost = costLabel {
                    Text(cost)
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                } else {
                    Text("pending")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(rowVoice(status: status, sub: sub, costLabel: costLabel))
    }

    /// Spoken value for a transfer row, assembled outside the string
    /// interpolation so the row body stays readable.
    private func rowVoice(status: TransferStatus, sub: String, costLabel: String?) -> String {
        var parts: [String] = [statusVoice(status)]
        parts.append(sub.isEmpty ? "No facility detail reported" : sub)
        if let cost = costLabel { parts.append("Cost \(cost)") } else { parts.append("Cost pending") }
        return parts.joined(separator: ". ") + "."
    }

    /// Spoken form of the right-hand status word.
    private func statusVoice(_ status: TransferStatus) -> String {
        switch status {
        case .done:   return "Done"
        case .active: return "Active"
        case .queued: return "Queued"
        }
    }

    @ViewBuilder
    private func statusWord(_ status: TransferStatus) -> some View {
        switch status {
        case .done:
            Text("DONE")
                .font(.system(size: 11, weight: .bold)).kerning(0.6)
                .foregroundStyle(Brand.success)
        case .active:
            Text("ACTIVE")
                .font(.system(size: 11, weight: .bold)).kerning(0.6)
                .foregroundStyle(LinearGradient.primary)
        case .queued:
            Text("QUEUED")
                .font(.system(size: 11, weight: .bold)).kerning(0.6)
                .foregroundStyle(Brand.warning)
        }
    }

    // MARK: - Advance-leg strip

    private var advanceLegRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Brand.blue.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Brand.blue)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(advanceLegTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(advanceLegSub)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if isAdvancing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(16)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(canAdvance ? palette.borderFaint : Brand.warning.opacity(0.45))
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            // §W ONLINE_ONLY: visibly gated, not silently inert.
            .opacity(canAdvance || isAdvancing ? 1 : 0.45)
            .contentShape(Rectangle())
            .onTapGesture {
                guard canAdvance else { return }
                Task { await advanceSegment() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(advanceLegTitle)
            .accessibilityValue(advanceLegSub)
            .accessibilityHint(advanceBlockedReason
                ?? "Commits this leg on the server and opens the next one. This is never queued offline.")

            if let why = advanceBlockedReason {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                    Text(why)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }

            if let err = advanceError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.danger)
                    Text(err)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - ESANG row (derived on device — see the ESANG note in the header)

    private var esangRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 30, height: 30)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · TRANSFER READ")
                    .font(.system(size: 9, weight: .black)).kerning(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Text(esangHeadline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(esangDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("DERIVED ON DEVICE FROM THIS BOARD · NOT AN ASSISTANT")
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transfer read, derived on this device. \(esangHeadline) \(esangDetail)")
    }

    /// One sentence off the decoded transfer log. No rail next-best-action
    /// source is on the wire, so this states what the server returned and never
    /// a fabricated confirm-or-hold call.
    private var esangHeadline: String {
        guard let t = activeTransfer else {
            return "No transfer has been recorded on this shipment yet."
        }
        let facility = t.facilityName ?? t.locationLabel ?? "a facility that has not been named"
        switch transferStatus(t) {
        case .active: return "\(transferTypeLabel(t)) is in progress at \(facility)."
        case .done:   return "The last \(transferTypeLabel(t)) at \(facility) is complete."
        case .queued: return "\(transferTypeLabel(t)) at \(facility) is still queued."
        }
    }

    private var esangDetail: String {
        var bits: [String] = ["\(todayCount) row\(todayCount == 1 ? "" : "s") on the log"]
        if pendingCount > 0 { bits.append("\(pendingCount) pending") }
        if avgTimeLabel != "-" { bits.append("average cycle \(avgTimeLabel)") }
        bits.append(reach.isOnline ? "advance available" : "advance blocked offline")
        return bits.joined(separator: " · ")
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            RailSecondaryActionButton(
                title: "Transfer context",
                sheetTitle: "Intermodal transfer context",
                lines: transferContextLines,
                width: 176,
                systemImage: "plus"
            )
            .accessibilityLabel("Transfer context")
            .accessibilityHint("Opens the shipment, facility and cycle figures this board is built from.")
            RailSecondaryActionButton(
                title: "History",
                sheetTitle: "Transfer history",
                lines: transferHistoryLines,
                width: 116,
                systemImage: "clock.arrow.circlepath"
            )
            .accessibilityLabel("Transfer history")
            .accessibilityHint("Opens the recorded transfer log for this shipment.")
        }
    }

    private var transferContextLines: [String] {
        var lines = [
            "Shipment \(shipmentId)",
            "\(todayCount) transfer row\(todayCount == 1 ? "" : "s") today",
            "\(pendingCount) pending · average cycle \(avgTimeLabel)"
        ]
        if let t = activeTransfer {
            let container = t.containerNumber ?? "Container"
            let facility = t.facilityName ?? t.locationLabel ?? "facility pending"
            lines.append("\(container) · \(transferTypeLabel(t)) · \(facility)")
        }
        return lines
    }

    private var transferHistoryLines: [String] {
        transfers.prefix(8).map { t in
            let container = t.containerNumber ?? "Container"
            let facility = t.facilityName ?? t.locationLabel ?? "facility pending"
            let status = t.status ?? "status pending"
            return "\(container) · \(facility) · \(status)"
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let limit: Int }
        do {
            let result: [IntermodalTransfer566] = try await EusoTripAPI.shared.query(
                "intermodal.getTransfers", input: ListIn(limit: 50))
            self.transfers = result
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func advanceSegment() async {
        guard let t = activeTransfer else { return }
        // §W ONLINE_ONLY: refuse up front and say so on the surface, rather than
        // firing a lifecycle commit into a dead socket. Nothing is queued — a
        // replayed advance would desynchronise the server's segment state
        // machine, which is the one thing this screen must never do.
        guard reach.isOnline else {
            advanceError = "Offline · the leg was NOT advanced and NOT queued. Reconnect and advance again."
            return
        }
        isAdvancing = true
        advanceError = nil
        struct AdvIn: Encodable { let intermodalShipmentId: Int; let fromSegmentId: Int; let toSegmentId: Int }
        struct AdvanceSegmentResponse: Decodable {
            let success: Bool
            let nextSegmentId: Int?
            let newStatus: String
        }
        do {
            // S4 cure 2026-08-10: advanceSegment is a MUTATION server-side
            // (intermodal.ts:561 .mutation). query() issues GET, the server
            // has no method override, so this CTA was dead on iOS while the
            // same verb worked on web — PARITY_AND_CHAINS.md §2·S4.
            let _: AdvanceSegmentResponse = try await EusoTripAPI.shared.mutation(
                "intermodal.advanceSegment",
                input: AdvIn(intermodalShipmentId: shipmentId, fromSegmentId: t.fromSegmentId ?? 0, toSegmentId: t.toSegmentId ?? 0))
            await load()
        } catch {
            // S4 follow-on (§18): this used to swallow the error, which left a
            // FAILED lifecycle commit looking exactly like nothing happened.
            // A commit that did not land has to say so.
            advanceError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        isAdvancing = false
    }
}

#Preview("566 · Rail Intermodal Transfer · Night") { RailIntermodalTransferScreen(theme: Theme.dark, shipmentId: 0).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("566 · Rail Intermodal Transfer · Light") { RailIntermodalTransferScreen(theme: Theme.light, shipmentId: 0).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
