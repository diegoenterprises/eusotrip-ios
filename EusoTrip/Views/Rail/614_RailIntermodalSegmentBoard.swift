//
//  614_RailIntermodalSegmentBoard.swift
//  EusoTrip — Rail · Rail Engineer · Intermodal Segment Board (brick 614).
//
//  Verbatim SwiftUI port of "05 Rail/614 Rail Intermodal Segment Board · Dark"
//  at the golden design-authority bar. CARRIER (Rail Engineer) vantage on ONE
//  intermodal shipment's door-to-door journey as mode-distinct SEGMENTS: a
//  bespoke SEGMENT-RELAY hero (origin dray → lift → rail line-haul → lift → dest
//  dray on a horizontal track, the active rail leg ringed + live), a 3-cell KPI
//  strip, an itemized segments card, an ESANG row, and a Tracking / Advance-
//  segment CTA pair. NOT the uniform lifecycle strip, NOT a map, NOT a stat grid.
//
//  Nav: REAL Rail Engineer enum HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//  transportMode = rail · US (BNSF transcon) · persona Owen Trask (OT) / Aurora
//  Rail Division (PROVISIONAL).
//
//  WIRING (web parity rail/intermodal/[id]/segments):
//    detail   → intermodal.getIntermodalShipmentDetail EXISTS · intermodal.ts:562
//               ({id}) → segments[] (legNumber,mode,origin/dest,estimated/actualHours,
//               status,departed/arrivedAt) + transfers[] (the ramp lifts).
//    tracking → intermodal.getIntermodalTracking       EXISTS · intermodal.ts:757
//               ({intermodalShipmentId}) → { currentMode, activeSegmentId }.
//    Advance segment → intermodal.advanceSegment        EXISTS · intermodal.ts:586
//               ({intermodalShipmentId,completedSegmentId}) → marks leg complete,
//               books the next; writes state machine + audit row.
//  There is NO flat "segment board" endpoint — the board is assembled honestly from
//  ONE shipment's real segments+transfers (STUB: cross-shipment aggregation). RBAC
//  protectedProcedure. The crossing-regime band shows regulatory constants.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Data shapes

private struct SBSegment614: Decodable, Identifiable {
    let id: Int
    let legNumber: Int?
    let mode: String?
    let originDescription: String?
    let destinationDescription: String?
    let carrierId: Int?
    let status: String?
    let estimatedHours: Double?
    let actualHours: Double?
    let departedAt: String?
    let arrivedAt: String?
}
private struct SBTransfer614: Decodable, Identifiable {
    let id: Int
    let fromSegmentId: Int?
    let toSegmentId: Int?
    let transferType: String?
    let facilityName: String?
    let facilityType: String?
    let dwellTimeHours: Double?
    let status: String?
}
private struct SBDetail614: Decodable {
    let id: Int
    let intermodalNumber: String?
    let status: String?
    let estimatedTransitDays: Int?
    let segments: [SBSegment614]?
    let transfers: [SBTransfer614]?
}
private struct SBTracking614: Decodable { let currentMode: String?; let activeSegmentId: Int? }

/// A unified relay item — a mode segment or a ramp lift.
private struct BoardItem614: Identifiable {
    enum Kind { case dray, lift, rail, ocean }
    enum State { case done, live, eta, planned }
    let id: String
    let kind: Kind
    let title: String
    let sub: String
    let state: State
    let durationText: String
    let segmentId: Int?
}

// MARK: - Screen wrapper

struct RailIntermodalSegmentBoardScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 50418

    var body: some View {
        Shell(theme: theme) { RailIntermodalSegmentBoardBody(shipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",  isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailIntermodalSegmentBoardBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let shipmentId: Int

    @State private var detail: SBDetail614? = nil
    @State private var tracking: SBTracking614? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var advancing = false
    @State private var actionBanner: String? = nil
    @State private var actionIsError = false

    private var segments: [SBSegment614] { (detail?.segments ?? []).sorted { ($0.legNumber ?? 0) < ($1.legNumber ?? 0) } }
    private var transfers: [SBTransfer614] { detail?.transfers ?? [] }

    /// Interleave segments + their lifts into one ordered relay of board items.
    private var board: [BoardItem614] {
        var out: [BoardItem614] = []
        for (i, s) in segments.enumerated() {
            out.append(item(from: s))
            // a transfer whose fromSegment is this one comes right after
            if let t = transfers.first(where: { $0.fromSegmentId == s.id }), i < segments.count - 1 {
                out.append(item(from: t))
            }
        }
        return out
    }

    private var activeItem: BoardItem614? {
        board.first { $0.state == .live } ?? board.first { $0.state == .eta }
    }
    private var doneCount: Int { board.filter { $0.state == .done }.count }
    private var totalTransitText: String {
        if let d = detail?.estimatedTransitDays { return "\(d)d" }
        let hrs = segments.reduce(0.0) { $0 + ($1.actualHours ?? $1.estimatedHours ?? 0) }
        return hrs >= 24 ? String(format: "%.0fd %.0fh", (hrs/24).rounded(.down), hrs.truncatingRemainder(dividingBy: 24)) : "\(Int(hrs))h"
    }
    private var nextXferText: String {
        if let next = board.first(where: { $0.kind == .lift && ($0.state == .eta || $0.state == .planned) }) { return next.durationText }
        return board.first { $0.state == .eta }?.durationText ?? "—"
    }
    private var overallPct: Int {
        guard !board.isEmpty else { return 0 }
        return Int(Double(doneCount) / Double(board.count) * 100)
    }

    private func item(from s: SBSegment614) -> BoardItem614 {
        let mode = (s.mode ?? "").uppercased()
        let kind: BoardItem614.Kind = mode == "RAIL" ? .rail : (mode == "VESSEL" ? .ocean : .dray)
        let hrs = s.actualHours ?? s.estimatedHours
        return BoardItem614(
            id: "seg\(s.id)", kind: kind,
            title: segTitle(s),
            sub: [s.originDescription.map(shortPlace), s.destinationDescription.map(shortPlace)].compactMap { $0 }.joined(separator: " → "),
            state: state(from: s.status),
            durationText: hrs.map(hoursText) ?? "—",
            segmentId: s.id)
    }
    private func item(from t: SBTransfer614) -> BoardItem614 {
        BoardItem614(
            id: "xfer\(t.id)", kind: .lift,
            title: liftTitle(t),
            sub: t.facilityName ?? (t.facilityType ?? "ramp").replacingOccurrences(of: "_", with: " "),
            state: transferState(t.status),
            durationText: t.dwellTimeHours.map(hoursText) ?? "—",
            segmentId: nil)
    }

    private func segTitle(_ s: SBSegment614) -> String {
        let mode = (s.mode ?? "").uppercased()
        if mode == "RAIL" { return "Rail line-haul · \(s.carrierId.map { "carrier #\($0)" } ?? "BNSF")" }
        if mode == "VESSEL" { return "Ocean leg" }
        return "\((s.legNumber ?? 1) == 1 ? "Origin" : "Dest") drayage"
    }
    private func liftTitle(_ t: SBTransfer614) -> String {
        (t.transferType ?? "").contains("to_rail") ? "Lift-on · ramp" : "Lift-off · ramp"
    }
    private func shortPlace(_ s: String) -> String { s.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? s }
    private func hoursText(_ h: Double) -> String { h >= 24 ? String(format: "%.0fd %.0fh", (h/24).rounded(.down), h.truncatingRemainder(dividingBy: 24)) : String(format: "%.1fh", h) }

    private func state(from s: String?) -> BoardItem614.State {
        switch (s ?? "").lowercased() {
        case "completed": return .done
        case "in_transit", "booked": return .live
        case "pending": return .eta
        default: return .planned
        }
    }
    private func transferState(_ s: String?) -> BoardItem614.State {
        switch (s ?? "").lowercased() {
        case "completed": return .done
        case "in_progress": return .live
        case "scheduled": return .eta
        default: return .planned
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                titleRow
                IridescentHairline().padding(.top, Space.s3)

                if loading {
                    skeleton.padding(.top, Space.s4)
                } else if let err = loadError {
                    errorCard(err).padding(.top, Space.s4)
                } else {
                    relayHero.padding(.top, Space.s4)
                    kpiStrip.padding(.top, Space.s4)
                    segmentsCard.padding(.top, Space.s4)
                    esangRow.padding(.top, Space.s4)
                    if let banner = actionBanner { actionBannerView(banner).padding(.top, Space.s3) }
                    ctaPair.padding(.top, Space.s4)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Top bar / title

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("✦ RAIL ENGINEER · SEGMENT BOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
            }
            Spacer()
            Text(detail?.intermodalNumber ?? "RAIL-\(shipmentId)")
                .font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textTertiary)
        }
    }

    private var titleRow: some View {
        HStack {
            Text("Segment board").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Spacer(minLength: Space.s2)
            HStack(spacing: 5) {
                Circle().fill(onPlan ? Brand.success : Brand.warning).frame(width: 6, height: 6)
                Text(onPlan ? "ON PLAN" : "WATCH").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(onPlan ? Brand.success : Brand.warning)
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill((onPlan ? Brand.success : Brand.warning).opacity(0.14)))
        }
        .padding(.top, Space.s3)
    }
    private var onPlan: Bool { !(detail?.status ?? "").lowercased().contains("delay") }

    // MARK: Segment-relay hero

    private var relayHero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("INTERMODAL JOURNEY · \(board.count) SEGMENT\(board.count == 1 ? "" : "S")")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(overallPct)% · \(totalTransitText)")
                    .font(.system(size: 9, weight: .heavy)).monospacedDigit().foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(.black.opacity(0.55)))
            }
            if board.isEmpty {
                Text("No segments to relay.").font(EType.caption).foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                relayTrack
                if let a = activeItem {
                    Text("ON \(a.title.uppercased()) · \(a.sub.uppercased())")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(Brand.info).lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
            crossingBand
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var relayTrack: some View {
        HStack(spacing: 0) {
            ForEach(Array(board.prefix(7).enumerated()), id: \.element.id) { idx, item in
                relayNode(item)
                if idx < min(board.count, 7) - 1 {
                    Rectangle()
                        .fill(item.state == .done ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textTertiary.opacity(0.5)))
                        .frame(height: item.state == .done ? 3.4 : 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 60)
    }

    private func relayNode(_ item: BoardItem614) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if item.state == .live {
                    Circle().fill(Brand.magenta.opacity(reduceMotion ? 0.25 : (pulse ? 0.1 : 0.35)))
                        .frame(width: 44, height: 44)
                }
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(nodeFill(item))
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(nodeStroke(item), lineWidth: 1.4))
                Image(systemName: nodeIcon(item.kind))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.state == .live ? .white : nodeStroke(item))
                if item.state == .done {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
                        .foregroundStyle(Brand.success).background(Circle().fill(palette.bgCard).frame(width: 12, height: 12))
                        .offset(x: 14, y: -14)
                }
            }
            Text(nodeLabel(item.kind)).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(width: 42)
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true } } }
    }
    @State private var pulse = false

    private func nodeFill(_ i: BoardItem614) -> AnyShapeStyle {
        switch i.state {
        case .live: return AnyShapeStyle(LinearGradient.diagonal)
        case .done: return AnyShapeStyle(Brand.success.opacity(0.16))
        default:    return AnyShapeStyle(Color(hex: 0x607D8B).opacity(0.12))
        }
    }
    private func nodeStroke(_ i: BoardItem614) -> Color {
        switch i.state { case .live: return .white; case .done: return Brand.success; default: return palette.textTertiary }
    }
    private func nodeIcon(_ k: BoardItem614.Kind) -> String {
        switch k { case .dray: return "box.truck.fill"; case .lift: return "arrow.up.and.down.and.arrow.left.and.right"; case .rail: return "tram.fill"; case .ocean: return "ferry.fill" }
    }
    private func nodeLabel(_ k: BoardItem614.Kind) -> String {
        switch k { case .dray: return "DRAY"; case .lift: return "LIFT"; case .rail: return "RAIL"; case .ocean: return "SEA" }
    }

    private var crossingBand: some View {
        HStack(spacing: Space.s2) {
            crossingCell("US · STB · CBP", active: true)
            crossingCell("CA · CTA · CBSA", active: false)
            crossingCell("MX · ARTF · SAT", active: false)
        }
    }
    private func crossingCell(_ t: String, active: Bool) -> some View {
        Text(t).font(.system(size: 8.5, weight: .heavy)).tracking(0.2)
            .foregroundStyle(active ? .white : palette.textSecondary)
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft))
            .clipShape(Capsule())
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s3) {
            kpiCell("TRANSIT", totalTransitText, highlight: false)
            kpiCell("SEGMENT", "\(doneCount) / \(board.count)", highlight: true)
            kpiCell("NEXT XFER", nextXferText, highlight: false)
        }
    }
    private func kpiCell(_ label: String, _ value: String, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(highlight ? .white.opacity(0.85) : palette.textTertiary)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(highlight ? .white : palette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(highlight ? Color.clear : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Segments list card

    private var segmentsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SEGMENTS · ORIGIN → DESTINATION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if board.isEmpty {
                EusoEmptyState(systemImage: "square.stack.3d.up",
                               title: "No segments",
                               subtitle: "Legs appear once the intermodal move is built.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(board.enumerated()), id: \.element.id) { idx, item in
                        segmentListRow(item)
                        if idx < board.count - 1 { Divider().overlay(palette.borderFaint).padding(.leading, Space.s4) }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            }
        }
    }

    private func segmentListRow(_ item: BoardItem614) -> some View {
        let live = item.state == .live
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(chipColor(item).opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: nodeIcon(item.kind)).font(.system(size: 15, weight: .semibold)).foregroundStyle(chipColor(item))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(item.sub).font(EType.mono(.caption)).tracking(0.2).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(stateWord(item.state)).font(.system(size: 11, weight: .bold)).tracking(0.3)
                    .foregroundStyle(live ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(stateColor(item.state)))
                Text(item.durationText).font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
        .background(live ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.06)) : AnyShapeStyle(Color.clear))
        .overlay(alignment: .leading) { if live { Rectangle().fill(LinearGradient.primary).frame(width: 3.5) } }
    }

    private func chipColor(_ i: BoardItem614) -> Color {
        switch i.state { case .done: return Brand.success; case .live: return Brand.info; default: return Color(hex: 0x607D8B) }
    }
    private func stateWord(_ s: BoardItem614.State) -> String {
        switch s { case .done: return "done"; case .live: return "live"; case .eta: return "eta"; case .planned: return "planned" }
    }
    private func stateColor(_ s: BoardItem614.State) -> Color {
        switch s { case .done: return Brand.success; case .live: return Brand.info; case .eta: return Brand.warning; case .planned: return palette.textTertiary }
    }

    // MARK: ESang row

    private var esangRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(esangHead).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(2)
                Text(esangSub).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private var esangHead: String {
        if let a = activeItem, a.kind == .rail { return "ESang: rail leg \(stateWord(a.state)) — lift-off feeds the dest dray" }
        return "ESang: \(doneCount) of \(board.count) segments cleared"
    }
    private var esangSub: String { "\(overallPct)% complete · next transfer in \(nextXferText) · gate-in opens free-time" }

    // MARK: Action banner + CTA

    private func actionBannerView(_ text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: actionIsError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(actionIsError ? Brand.danger : Brand.success)
            Text(text).font(EType.caption).foregroundStyle(actionIsError ? Brand.danger : palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background((actionIsError ? Brand.danger : Brand.success).opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder((actionIsError ? Brand.danger : Brand.success).opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button(action: openTracking) {
                HStack(spacing: 6) { Image(systemName: "magnifyingglass"); Text("Tracking") }
                    .font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(width: 150, height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }.buttonStyle(.plain)
            CTAButton(title: advancing ? "Advancing…" : "Advance segment",
                      action: { Task { await advance() } }, trailingIcon: "arrow.right", isLoading: advancing)
        }
    }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        struct TrackIn: Encodable { let intermodalShipmentId: Int }
        do {
            async let d: SBDetail614 = EusoTripAPI.shared.query("intermodal.getIntermodalShipmentDetail", input: DetailIn(id: shipmentId))
            async let t: SBTracking614? = EusoTripAPI.shared.query("intermodal.getIntermodalTracking", input: TrackIn(intermodalShipmentId: shipmentId))
            let (dd, tt) = try await (d, t)
            self.detail = dd; self.tracking = tt
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func advance() async {
        guard !advancing else { return }
        // Advance the current live segment; fall back to the tracking-reported active id.
        let completedId = board.first(where: { $0.state == .live })?.segmentId ?? tracking?.activeSegmentId
        guard let segId = completedId else {
            actionIsError = true; actionBanner = "No active segment to advance."; return
        }
        advancing = true; actionBanner = nil
        struct AdvanceIn: Encodable { let intermodalShipmentId: Int; let completedSegmentId: Int }
        struct AdvanceOut: Decodable { let success: Bool?; let nextSegmentId: Int?; let newStatus: String? }
        do {
            let out: AdvanceOut = try await EusoTripAPI.shared.mutation("intermodal.advanceSegment",
                input: AdvanceIn(intermodalShipmentId: shipmentId, completedSegmentId: segId))
            actionIsError = false
            actionBanner = out.nextSegmentId.map { "Segment advanced · next leg #\($0) booked" } ?? "Segment marked complete · \(out.newStatus ?? "advanced")"
            await load()
        } catch {
            actionIsError = true
            actionBanner = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        advancing = false
    }

    private func openTracking() {
        NotificationCenter.default.post(name: Notification.Name("eusoIntermodalTrack"), object: nil,
            userInfo: ["intermodalShipmentId": shipmentId, "activeSegmentId": tracking?.activeSegmentId as Any])
        actionIsError = false
        actionBanner = "Opening live tracking · \(activeItem?.title ?? "rail leg")"
    }

    // MARK: Scaffolds

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 184)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 72)
        }
    }
    private func errorCard(_ err: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Previews

#Preview("614 · Rail Intermodal Segment Board · Night") {
    RailIntermodalSegmentBoardScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("614 · Rail Intermodal Segment Board · Light") {
    RailIntermodalSegmentBoardScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
