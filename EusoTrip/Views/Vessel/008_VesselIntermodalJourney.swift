//
//  008_VesselIntermodalJourney.swift
//  EusoTrip — Vessel Shipper · Intermodal Journey (shipper vantage).
//
//  Wireframe:  06 Vessel / 008 Vessel Intermodal Journey (canvas 440×956, Theme.dark).
//  Cross-mode sibling of: 05 Rail / 009 Rail Intermodal Journey.
//  PERSONA:    Diego Usoro · Eusorone Technologies (VESSEL_SHIPPER vantage).
//              Hero IM-50732 · Yantian CN → Ontario CA · 40' HC dry CMAU 5391740 ·
//              3 legs / 2 modes · leg 2 (ocean) active.
//  transportMode = vessel (line-haul leg); dray legs = truck.
//
//  tRPC (server/routers/intermodal.ts) — VERIFIED against the real procedure
//  bodies + drizzle/schema.ts (the-oath §43):
//    getIntermodalShipmentDetail (EXISTS :161) — primary read. Returns
//      { ...intermodal_shipments row, segments[], transfers[], containers[] }.
//      Every hero / container / timeline value binds to a real column on that
//      payload or an honest derivation — no fabricated demo defaults.
//    getIntermodalCostBreakdown (EXISTS :295) — the COST card. Returns
//      { intermodalNumber, segments[{legNumber,mode,rate,status}],
//        transfers[{transferType,cost,facilityName}], totalSegmentCost,
//        totalTransferCost, grandTotal, currency } — rate/cost/totals are
//      server-side parseFloat'd → JSON numbers (Double).
//    getIntermodalTracking (EXISTS :269) — "Track active leg" CTA. Returns
//      { segments[], containers[], currentMode, activeSegmentId }. Fired on the
//      button to resolve the active segment, then routes to live tracking.
//
//  NOTE (surfaced this fire — see _THE_OATH §43 + INTEGRATION.md):
//    getIntermodalShipmentDetail / getIntermodalTracking / getIntermodalCostBreakdown
//    currently take NO ctx and scope by NOTHING (IDOR — any authed user can read
//    any shipper's shipment by integer id). The staged backend patch closes that
//    before this screen ships; this view surfaces FORBIDDEN/NOT_FOUND honestly
//    via loadError instead of rendering another tenant's journey.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import SwiftUI

// MARK: - Decoders (match the real server return literals field-for-field)

/// Drizzle MySQL `decimal` columns serialize as strings over tRPC; numeric
/// JSON also occurs (cost-breakdown is pre-parsed server-side). This decodes
/// either shape without throwing.
private struct VIFlexDouble: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil
    }
}

private struct IMSegment008: Decodable, Identifiable {
    let id: Int
    let legNumber: Int?
    let mode: String?                 // "TRUCK" | "RAIL" | "VESSEL"
    let originDescription: String?
    let destinationDescription: String?
    let carrierId: Int?
    let rate: VIFlexDouble?
    let status: String?               // pending | booked | in_transit | completed | cancelled
    let departedAt: String?
    let arrivedAt: String?
}

private struct IMTransfer008: Decodable, Identifiable {
    let id: Int
    let fromSegmentId: Int?
    let toSegmentId: Int?
    let transferType: String?         // truck_to_vessel | vessel_to_truck | ...
    let facilityName: String?
    let facilityType: String?         // port_terminal | intermodal_ramp | ...
    let transferCost: VIFlexDouble?
    let status: String?               // scheduled | in_progress | completed | delayed | cancelled
}

private struct IMContainer008: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let containerType: String?        // intermodal_containers.containerType ("40ft_hc" ...)
    let sealNumber: String?
    let weightKg: VIFlexDouble?
}

/// getIntermodalShipmentDetail → { ...intermodal_shipments row, segments, transfers, containers }
private struct IMShipmentDetail008: Decodable {
    let id: Int
    let intermodalNumber: String?
    let originType: String?
    let destinationType: String?
    let commodity: String?
    let hazmatClass: String?
    let totalWeight: VIFlexDouble?
    let numberOfSegments: Int?
    let status: String?
    let totalRate: VIFlexDouble?
    let currency: String?
    let estimatedTransitDays: Int?
    let actualTransitDays: Int?
    let segments: [IMSegment008]?
    let transfers: [IMTransfer008]?
    let containers: [IMContainer008]?
}

private struct IMCostSegment008: Decodable, Identifiable {
    var id: Int { legNumber }
    let legNumber: Int
    let mode: String?
    let rate: Double?
    let status: String?
}
private struct IMCostTransfer008: Decodable, Identifiable {
    let id = UUID()
    let transferType: String?
    let cost: Double?
    let facilityName: String?
    private enum CodingKeys: String, CodingKey { case transferType, cost, facilityName }
}
/// getIntermodalCostBreakdown → numbers already parsed server-side.
private struct IMCostBreakdown008: Decodable {
    let intermodalNumber: String?
    let segments: [IMCostSegment008]?
    let transfers: [IMCostTransfer008]?
    let totalSegmentCost: Double?
    let totalTransferCost: Double?
    let grandTotal: Double?
    let currency: String?
}

/// getIntermodalTracking → active-leg resolver for the "Track" CTA.
private struct IMTracking008: Decodable {
    let currentMode: String?
    let activeSegmentId: Int?
}

// MARK: - Screen wrapper (Shipper · mode-agnostic nav: HOME · LOADS · [orb] · TRACK · ME)

struct VesselIntermodalJourneyScreen: View {
    var theme: Theme.Palette = Theme.dark
    /// intermodal_shipments.id — the real row this journey renders.
    var shipmentId: Int = 50732

    var body: some View {
        Shell(theme: theme) { VesselIntermodalJourneyBody(shipmentId: shipmentId) } nav: {
            // SVG bottom-nav: HOME · LOADS(active) · [orb] · TRACK · ME.
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Track", systemImage: "clock",           isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselIntermodalJourneyBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var detail: IMShipmentDetail008? = nil
    @State private var cost: IMCostBreakdown008? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// "Track active leg" / "Cost detail" write here on failure — never swallowed.
    @State private var actionError: String? = nil
    @State private var trackingActive = false
    @State private var showCostDetail = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s5)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if let actionError {
                        actionErrorBanner(actionError)
                    }

                    if loading {
                        loadingState
                    } else if let err = loadError {
                        errorCard(err)
                    } else if detail == nil {
                        EusoEmptyState(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                       title: "Journey not found",
                                       subtitle: "This intermodal shipment is no longer available or you don't have access to it.")
                    } else {
                        containerCard
                        journeyTimeline
                        costCard
                        actions
                    }

                    Color.clear.frame(height: 96)
                }
                .padding(.top, Space.s5)
            }
            .padding(.horizontal, Space.s5)
        }
        .task { await load() }
        .sheet(isPresented: $showCostDetail) { costDetailSheet }
    }

    // MARK: Top bar — back + eyebrow + hero + leg pill + lane subtitle

    private var heroNumber: String { detail?.intermodalNumber ?? "IM-—" }

    private var legPillText: String {
        let total = detail?.numberOfSegments ?? (detail?.segments?.count ?? 0)
        let active = activeLegNumber
        let mode = activeLegModeLabel
        if let active, total > 0 { return "LEG \(active) OF \(total) · \(mode)" }
        if total > 0 { return "\(total) LEGS · \(mode)" }
        return "INTERMODAL"
    }

    private var laneSubtitle: String {
        let segs = detail?.segments?.sorted { ($0.legNumber ?? 0) < ($1.legNumber ?? 0) } ?? []
        let origin = segs.first?.originDescription ?? "—"
        let dest = segs.last?.destinationDescription ?? "—"
        let legs = detail?.numberOfSegments ?? segs.count
        let modes = Set(segs.compactMap { $0.mode }).count
        return "\(origin) → \(dest) · \(legs) legs · \(modes) modes"
    }

    @ViewBuilder private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("✦ VESSEL SHIPPER · INTERMODAL JOURNEY")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Text(heroNumber)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .tracking(-0.5)
                    .foregroundStyle(palette.textPrimary)
                Text(laneSubtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s3)
            // LEG n OF m · MODE pill
            Text(legPillText)
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(LinearGradient.primary, in: Capsule())
                .padding(.top, 14)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Container / route summary card

    @ViewBuilder private var containerCard: some View {
        let cont = detail?.containers?.first
        let etaLabel = etaDaysLabel
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(containerHeaderLine(cont))
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(containerSpecLine(cont))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                    Text(doorToDoorLine)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: Space.s3)
                VStack(spacing: 2) {
                    Text("ETA").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    Text(etaLabel).font(.system(size: 15, weight: .bold)).foregroundStyle(Brand.info)
                }
                .frame(width: 64, height: 48)
                .background(Brand.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(Space.s5)
        .eusoCard()
    }

    private func containerHeaderLine(_ c: IMContainer008?) -> String {
        let num = c?.containerNumber ?? "CONTAINER"
        let size = c?.containerType.map { " · \($0)" } ?? ""
        return "CONTAINER · \(num)\(size)".uppercased()
    }
    private func containerSpecLine(_ c: IMContainer008?) -> String {
        var parts: [String] = []
        if let s = c?.containerType { parts.append(s) }
        if let kg = c?.weightKg?.value ?? detail?.totalWeight?.value {
            parts.append("\(Int(kg).formatted()) kg")
        }
        if let seal = c?.sealNumber { parts.append("seal \(seal)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
    private var doorToDoorLine: String {
        let days = detail?.estimatedTransitDays
        let commodity = detail?.commodity ?? "general cargo"
        if let days { return "Door-to-door est. \(days)d · \(commodity)" }
        return commodity
    }
    private var etaDaysLabel: String {
        if let d = detail?.estimatedTransitDays, let a = detail?.actualTransitDays {
            let remaining = max(0, d - a); return "\(remaining)d"
        }
        if let d = detail?.estimatedTransitDays { return "\(d)d" }
        return "—"
    }

    // MARK: Journey timeline (segments + transfers, in leg order)

    private var orderedSegments: [IMSegment008] {
        (detail?.segments ?? []).sorted { ($0.legNumber ?? 0) < ($1.legNumber ?? 0) }
    }

    @ViewBuilder private var journeyTimeline: some View {
        let segs = orderedSegments
        let transferCount = detail?.transfers?.count ?? max(0, segs.count - 1)
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("JOURNEY · \(segs.count) SEGMENTS · \(transferCount) PORT TRANSFERS")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            if segs.isEmpty {
                Text("No segments recorded for this journey yet.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s4)
                    .background(palette.bgCard, in: RoundedRectangle(cornerRadius: Radius.lg))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(segs.enumerated()), id: \.element.id) { idx, seg in
                        legRow(seg, isLast: idx == segs.count - 1)
                        if idx < segs.count - 1 {
                            transferRow(transferBetween(seg, segs[idx + 1]),
                                        fromMode: seg.mode, toMode: segs[idx + 1].mode)
                        }
                    }
                }
                .padding(Space.s5)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
                )
            }
        }
    }

    private enum LegState { case done, active, pending, cancelled }
    private func legState(_ s: IMSegment008) -> LegState {
        switch (s.status ?? "").lowercased() {
        case "completed":            return .done
        case "booked", "in_transit": return .active
        case "cancelled":            return .cancelled
        default:                     return .pending
        }
    }
    private var activeLegNumber: Int? {
        orderedSegments.first { legState($0) == .active }?.legNumber
            ?? orderedSegments.first { legState($0) == .pending }?.legNumber
    }
    private var activeLegModeLabel: String {
        let m = orderedSegments.first { legState($0) == .active }?.mode
            ?? orderedSegments.first { legState($0) == .pending }?.mode
        return modeLineHaulLabel(m)
    }

    private func modeLineHaulLabel(_ mode: String?) -> String {
        switch (mode ?? "").uppercased() {
        case "VESSEL": return "OCEAN"
        case "RAIL":   return "RAIL"
        case "TRUCK":  return "DRAY"
        default:       return "—"
        }
    }
    private func legKindLabel(_ mode: String?, isEndLeg: Bool) -> String {
        switch (mode ?? "").uppercased() {
        case "VESSEL": return "LINE-HAUL · OCEAN"
        case "RAIL":   return "LINE-HAUL · RAIL"
        case "TRUCK":  return "DRAY · TRUCK"
        default:       return "SEGMENT"
        }
    }

    @ViewBuilder private func legRow(_ seg: IMSegment008, isLast: Bool) -> some View {
        let st = legState(seg)
        let accent: Color = {
            switch st {
            case .done:      return Brand.success
            case .active:    return Brand.info
            case .cancelled: return Brand.danger
            case .pending:   return palette.textTertiary
            }
        }()
        HStack(alignment: .top, spacing: Space.s3) {
            // Spine + node
            VStack(spacing: 0) {
                ZStack {
                    if st == .active {
                        Circle().strokeBorder(LinearGradient.primary, lineWidth: 2).frame(width: 24, height: 24)
                    }
                    Circle()
                        .fill(st == .pending ? AnyShapeStyle(palette.bgCard) : AnyShapeStyle(LinearGradient.primary))
                        .overlay(Circle().strokeBorder(st == .pending ? palette.borderSoft : Color.clear, lineWidth: 1.6))
                        .frame(width: st == .active ? 14 : 12, height: st == .active ? 14 : 12)
                    if st == .done {
                        Image(systemName: "checkmark").font(.system(size: 7, weight: .black)).foregroundStyle(.white)
                    }
                }
                .frame(width: 24)
                if !isLast {
                    Rectangle()
                        .fill(st == .pending ? AnyShapeStyle(palette.borderSoft) : AnyShapeStyle(LinearGradient.primary))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("LEG \(seg.legNumber ?? 0) · \(legKindLabel(seg.mode, isEndLeg: isLast))")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(st == .active ? Brand.info : palette.textTertiary)
                    Spacer()
                    Text(legStatusTag(st))
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(accent)
                }
                Text(legLaneLine(seg))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(st == .pending ? palette.textTertiary : palette.textPrimary)
                Text(legDetailLine(seg))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(st == .pending ? palette.textTertiary : palette.textSecondary)
            }
            .padding(.bottom, isLast ? 0 : Space.s4)
        }
    }

    private func legStatusTag(_ s: LegState) -> String {
        switch s {
        case .done:      return "DONE"
        case .active:    return "ACTIVE"
        case .pending:   return "PENDING"
        case .cancelled: return "CANCELLED"
        }
    }
    private func legLaneLine(_ seg: IMSegment008) -> String {
        let o = seg.originDescription ?? "—"
        let d = seg.destinationDescription ?? "—"
        return "\(o) → \(d)"
    }
    private func legDetailLine(_ seg: IMSegment008) -> String {
        let st = legState(seg)
        switch st {
        case .done:
            if let a = seg.arrivedAt { return "Completed \(shortDate(a))" }
            return "Completed"
        case .active:   return "In transit"
        case .pending:  return "Pending"
        case .cancelled: return "Cancelled"
        }
    }

    private func transferBetween(_ a: IMSegment008, _ b: IMSegment008) -> IMTransfer008? {
        detail?.transfers?.first { $0.fromSegmentId == a.id && $0.toSegmentId == b.id }
    }

    @ViewBuilder private func transferRow(_ t: IMTransfer008?, fromMode: String?, toMode: String?) -> some View {
        let done = (t?.status ?? "").lowercased() == "completed"
        HStack(alignment: .center, spacing: Space.s3) {
            // Diamond node aligned to spine
            ZStack {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(done ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(done ? .clear : palette.textTertiary, lineWidth: 1.6))
                    .frame(width: 9, height: 9)
                    .rotationEffect(.degrees(45))
            }
            .frame(width: 24)
            Text(transferLine(t, fromMode: fromMode, toMode: toMode))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(done ? palette.textSecondary : palette.textTertiary)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func transferLine(_ t: IMTransfer008?, fromMode: String?, toMode: String?) -> String {
        let arrow = "\(modeShort(fromMode)) → \(modeShort(toMode))"
        let facility = t?.facilityName ?? facilityFromType(t?.facilityType) ?? "terminal"
        let state = (t?.status ?? "scheduled").replacingOccurrences(of: "_", with: " ")
        return "\(arrow) · \(facility) · \(state)"
    }
    private func modeShort(_ m: String?) -> String {
        switch (m ?? "").uppercased() {
        case "VESSEL": return "vessel"
        case "RAIL":   return "rail"
        case "TRUCK":  return "truck"
        default:       return "—"
        }
    }
    private func facilityFromType(_ t: String?) -> String? {
        guard let t else { return nil }
        return t.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: Cost breakdown card

    @ViewBuilder private var costCard: some View {
        let cur = cost?.currency ?? detail?.currency ?? "USD"
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("COST BREAKDOWN · \(cur)")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                if let segs = cost?.segments, !segs.isEmpty {
                    ForEach(segs) { s in
                        costRow(title: "Leg \(s.legNumber) · \(costModeLabel(s.mode))",
                                amount: money(s.rate, cur), muted: false)
                    }
                }
                if let totalTransfer = cost?.totalTransferCost, totalTransfer > 0 {
                    let n = cost?.transfers?.count ?? 0
                    costRow(title: "Port transfers ×\(n) (lift)", amount: money(totalTransfer, cur), muted: true)
                }
                if cost?.segments?.isEmpty ?? true {
                    Text("Cost breakdown unavailable.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, Space.s2)
                }
                Rectangle().fill(palette.borderSoft).frame(height: 1).padding(.vertical, Space.s2)
                HStack {
                    Text("GRAND TOTAL").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(money(cost?.grandTotal, cur))
                        .font(.system(size: 15, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Brand.info)
                }
            }
            .padding(Space.s5)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            )
        }
    }

    @ViewBuilder private func costRow(title: String, amount: String, muted: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(muted ? palette.textSecondary : palette.textPrimary)
            Spacer()
            Text(amount).font(.system(size: 12.5, weight: .bold)).monospacedDigit()
                .foregroundStyle(muted ? palette.textSecondary : palette.textPrimary)
        }
        .padding(.bottom, Space.s3)
    }
    private func costModeLabel(_ m: String?) -> String {
        switch (m ?? "").uppercased() {
        case "VESSEL": return "ocean line-haul"
        case "RAIL":   return "rail line-haul"
        case "TRUCK":  return "dray (truck)"
        default:       return "segment"
        }
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Track active leg",
                      action: { Task { await trackActiveLeg() } },
                      leadingIcon: "clock",
                      isLoading: trackingActive)
                .frame(maxWidth: .infinity)
            Button { showCostDetail = true } label: {
                Text("Cost detail")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 52)
                    .background(palette.bgCard, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var costDetailSheet: some View {
        let cur = cost?.currency ?? detail?.currency ?? "USD"
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Cost detail · \(heroNumber)").font(EType.h2).foregroundStyle(palette.textPrimary)
            if let segs = cost?.segments, !segs.isEmpty {
                ForEach(segs) { s in
                    HStack {
                        Text("Leg \(s.legNumber) · \(costModeLabel(s.mode))").font(EType.body)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(money(s.rate, cur)).font(EType.bodyStrong).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
            if let ts = cost?.transfers, !ts.isEmpty {
                ForEach(ts) { t in
                    HStack {
                        Text((t.facilityName ?? t.transferType ?? "transfer")).font(EType.body)
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        Text(money(t.cost, cur)).font(EType.bodyStrong).monospacedDigit()
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            Divider().overlay(palette.borderSoft)
            HStack {
                Text("Grand total").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer()
                Text(money(cost?.grandTotal, cur)).font(EType.bodyStrong).monospacedDigit()
                    .foregroundStyle(Brand.info)
            }
            Spacer()
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgPrimary.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    // MARK: States

    @ViewBuilder private var loadingState: some View {
        VStack(spacing: Space.s3) {
            ProgressView().tint(Brand.blue)
            Text("Loading journey…").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Space.s7)
    }
    @ViewBuilder private func errorCard(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label("Couldn't load journey", systemImage: "exclamationmark.triangle.fill")
                .font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s4)
        .background(palette.tintDanger, in: RoundedRectangle(cornerRadius: Radius.lg))
    }
    @ViewBuilder private func actionErrorBanner(_ msg: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button { actionError = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .background(palette.tintDanger, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: Formatting

    private func money(_ v: Double?, _ currency: String) -> String {
        guard let v else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = (v.truncatingRemainder(dividingBy: 1) == 0) ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    }
    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: iso) {
            let out = DateFormatter(); out.dateFormat = "MM-dd"; return out.string(from: d)
        }
        return String(iso.prefix(10))
    }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        struct CostIn: Encodable { let intermodalShipmentId: Int }
        do {
            async let d: IMShipmentDetail008? = EusoTripAPI.shared.query(
                "intermodal.getIntermodalShipmentDetail", input: DetailIn(id: shipmentId))
            async let c: IMCostBreakdown008? = EusoTripAPI.shared.query(
                "intermodal.getIntermodalCostBreakdown", input: CostIn(intermodalShipmentId: shipmentId))
            let (dd, cc) = try await (d, c)
            self.detail = dd
            self.cost = cc
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// "Track active leg" → resolve the active segment via getIntermodalTracking,
    /// then route to live tracking. Real effect, errors surfaced — never a dead tap.
    private func trackActiveLeg() async {
        actionError = nil; trackingActive = true
        defer { trackingActive = false }
        struct TrackIn: Encodable { let intermodalShipmentId: Int }
        do {
            let t: IMTracking008 = try await EusoTripAPI.shared.query(
                "intermodal.getIntermodalTracking", input: TrackIn(intermodalShipmentId: shipmentId))
            NotificationCenter.default.post(
                name: Notification.Name("eusoIntermodalTrack"),
                object: nil,
                userInfo: [
                    "intermodalShipmentId": shipmentId,
                    "activeSegmentId": t.activeSegmentId as Any,
                    "currentMode": t.currentMode as Any
                ])
        } catch {
            actionError = "Couldn't open live tracking — "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

#Preview("008 · Vessel Intermodal Journey · Night") {
    VesselIntermodalJourneyScreen(theme: Theme.dark, shipmentId: 50732)
        .preferredColorScheme(.dark)
}
#Preview("008 · Vessel Intermodal Journey · Day") {
    VesselIntermodalJourneyScreen(theme: Theme.light, shipmentId: 50732)
        .preferredColorScheme(.light)
}
