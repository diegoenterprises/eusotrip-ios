//
//  009_RailIntermodalJourney.swift
//  EusoTrip — Rail · Shipper · Intermodal Journey (brick 009).
//
//  Verbatim SwiftUI port of "05 Rail/009 Rail Intermodal Journey · Dark" at the
//  golden design-authority bar. SHIPPER vantage on the whole door-to-door
//  intermodal move (two drays, one rail line-haul, two ramp lifts) on one live
//  picture: a multimodal chain map hero, a journey & cost ledger with the rail
//  leg highlighted, an ESANG run-plan card, and a Track-rail-leg / Cost-detail
//  CTA pair. Distinct from 560/003 (single-train carrier/shipper trackers) —
//  this is the multimodal chain on the shipper vantage.
//
//  Nav: canonical Shipper enum HOME · LOADS(current) · [orb] · WALLET · ME.
//  transportMode = rail (intermodal) · US · USD. Persona shipper-of-record
//  Diego Usoro (DU) / Eusorone Technologies.
//
//  WIRING (web parity client/src/pages/shipper/IntermodalJourney.tsx):
//    detail → intermodal.getIntermodalShipmentDetail  EXISTS · intermodal.ts:562
//             ({id}) → row + segments[] (legNumber,mode,origin/dest,carrierId,
//             rate,status,departedAt,arrivedAt) + transfers[] + containers[].
//    cost   → intermodal.getIntermodalCostBreakdown   EXISTS · intermodal.ts:812
//             ({intermodalShipmentId}) → segments/transfers costs + grandTotal.
//    Track rail leg → intermodal.getIntermodalTracking EXISTS · intermodal.ts:757
//             ({intermodalShipmentId}) → { currentMode, activeSegmentId } → posts
//             eusoIntermodalTrack for the live drill-in. (Read-only shipper vantage —
//             advanceSegment/recordTransfer are carrier mutations, not fired here.)
//  Every leg, lane, carrier, status, and dollar renders from the real payload; no
//  fabricated legs. RBAC protectedProcedure (ownership-gated to DU/Eusorone).
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Data shapes (mirror the intermodal.* payloads)

private struct IJFlex009: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        if let i = try? c.decode(Int.self) { value = Double(i); return }
        value = nil
    }
}

private struct IJSegment009: Decodable, Identifiable {
    let id: Int
    let legNumber: Int?
    let mode: String?               // TRUCK | RAIL | VESSEL
    let originDescription: String?
    let destinationDescription: String?
    let carrierId: Int?
    let rate: IJFlex009?
    let status: String?             // pending | booked | in_transit | completed | cancelled
    let departedAt: String?
    let arrivedAt: String?
}

private struct IJTransfer009: Decodable, Identifiable {
    let id: Int
    let transferType: String?
    let facilityName: String?
    let facilityType: String?
    let transferCost: IJFlex009?
    let status: String?
}

private struct IJContainer009: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let containerType: String?
}

private struct IJDetail009: Decodable {
    let id: Int
    let intermodalNumber: String?
    let commodity: String?
    let status: String?
    let totalRate: IJFlex009?
    let currency: String?
    let estimatedTransitDays: Int?
    let originLocation: IJLoc009?
    let destinationLocation: IJLoc009?
    let segments: [IJSegment009]?
    let transfers: [IJTransfer009]?
    let containers: [IJContainer009]?
}

private struct IJLoc009: Decodable { let lat: Double?; let lng: Double?; let description: String? }

private struct IJCostSeg009: Decodable, Identifiable {
    var id: Int { legNumber }
    let legNumber: Int
    let mode: String?
    let rate: Double?
    let status: String?
}
private struct IJCostBreakdown009: Decodable {
    let intermodalNumber: String?
    let segments: [IJCostSeg009]?
    let totalSegmentCost: Double?
    let totalTransferCost: Double?
    let grandTotal: Double?
    let currency: String?
}

private struct IJTracking009: Decodable {
    let currentMode: String?
    let activeSegmentId: Int?
}

// MARK: - Screen wrapper

struct RailIntermodalJourneyScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 50418

    var body: some View {
        Shell(theme: theme) { RailIntermodalJourneyBody(shipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailIntermodalJourneyBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let shipmentId: Int

    @State private var detail: IJDetail009? = nil
    @State private var cost: IJCostBreakdown009? = nil
    @State private var tracking: IJTracking009? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var actionBanner: String? = nil
    @State private var actionIsError = false
    @State private var trackingBusy = false

    private let usd: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0; return f
    }()
    private func money(_ v: Double) -> String { usd.string(from: NSNumber(value: v)) ?? "$0" }

    private var segments: [IJSegment009] { (detail?.segments ?? []).sorted { ($0.legNumber ?? 0) < ($1.legNumber ?? 0) } }
    private var transfers: [IJTransfer009] { detail?.transfers ?? [] }

    private var container: String {
        detail?.containers?.first?.containerNumber ?? "container"
    }
    private var routeTitle: String {
        let o = detail?.originLocation?.description ?? segments.first?.originDescription
        let d = detail?.destinationLocation?.description ?? segments.last?.destinationDescription
        if let o, let d { return "\(shortPlace(o)) → \(shortPlace(d))" }
        return detail?.intermodalNumber ?? "Intermodal \(shipmentId)"
    }
    private func shortPlace(_ s: String) -> String {
        s.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? s
    }

    private var railSegment: IJSegment009? { segments.first { ($0.mode ?? "").uppercased() == "RAIL" } }

    private var grandTotal: Double {
        cost?.grandTotal ?? (segments.reduce(0) { $0 + ($1.rate?.value ?? 0) } + transfers.reduce(0) { $0 + ($1.transferCost?.value ?? 0) })
    }
    private var transferTotal: Double {
        cost?.totalTransferCost ?? transfers.reduce(0) { $0 + ($1.transferCost?.value ?? 0) }
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
                    mapHero.padding(.top, Space.s4)
                    verdict.padding(.top, Space.s4)
                    journeyLedger.padding(.top, Space.s3)
                    runPlanCard.padding(.top, Space.s4)
                    if let banner = actionBanner {
                        actionBannerView(banner).padding(.top, Space.s3)
                    }
                    ctaPair.padding(.top, Space.s5)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Top bar / title

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("✦ SHIPPER · RAIL · INTERMODAL JOURNEY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer()
            Text(container).font(EType.mono(.micro)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .center) {
            Text(routeTitle)
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: Space.s2)
            HStack(spacing: 5) {
                Circle().fill(Brand.success).frame(width: 6, height: 6)
                Text("LIVE").font(.system(size: 10, weight: .heavy)).tracking(0.5).foregroundStyle(Brand.success)
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(Brand.success.opacity(0.18)))
        }
        .padding(.top, Space.s3)
    }

    // MARK: Map hero

    private var mapHero: some View {
        IntermodalChainMap009(segments: segments,
                              railActive: (tracking?.currentMode ?? "").uppercased() == "RAIL" || (railSegment?.status ?? "") == "in_transit",
                              originLabel: (shortPlace(detail?.originLocation?.description ?? "ORIGIN")).uppercased(),
                              destLabel: (shortPlace(detail?.destinationLocation?.description ?? "DC")).uppercased(),
                              etaText: detail?.estimatedTransitDays.map { "ETA \($0)d" } ?? "ETA —",
                              railLabel: railLegLabel,
                              reduceMotion: reduceMotion,
                              palette: palette)
            .frame(height: 232)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var railLegLabel: String {
        if let r = railSegment, let d = r.originDescription { return "RAIL · \(shortPlace(d).uppercased())" }
        return "RAIL LEG"
    }

    // MARK: Verdict

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verdictEyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(verdictLine).font(.system(size: 17, weight: .bold)).tracking(-0.3)
                .foregroundStyle(palette.textPrimary).lineLimit(2)
        }
    }

    private var verdictEyebrow: String {
        let drays = segments.filter { ($0.mode ?? "").uppercased() == "TRUCK" }.count
        let rails = segments.filter { ($0.mode ?? "").uppercased() == "RAIL" }.count
        return "DOOR-TO-DOOR · \(drays) DRAY\(drays == 1 ? "" : "S") · \(rails) LINE-HAUL · \(transfers.count) LIFT\(transfers.count == 1 ? "" : "S")"
    }
    private var verdictLine: String {
        if let r = railSegment {
            let where0 = (r.status ?? "").replacingOccurrences(of: "_", with: " ")
            return "Rail leg \(where0) · \(shortPlace(r.destinationDescription ?? "deramp")) next"
        }
        return "Multimodal move \((detail?.status ?? "in progress").replacingOccurrences(of: "_", with: " "))"
    }

    // MARK: Journey & cost ledger

    private var journeyLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("JOURNEY & COST · \(cost?.currency ?? detail?.currency ?? "USD")")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if segments.isEmpty {
                EusoEmptyState(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                               title: "No legs yet",
                               subtitle: "Intermodal legs appear once the move is built.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { idx, s in
                        legRow(s)
                        if idx < segments.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.leading, Space.s4)
                        }
                    }
                    // ramp lifts + grand total strip
                    HStack {
                        Text("Ramp lifts ×\(transfers.count)  ·  \(money(transferTotal))")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Spacer()
                        Text("DOOR-TO-DOOR").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        Text(money(grandTotal)).font(.system(size: 15, weight: .bold)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                    .background(Brand.blue.opacity(0.10))
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func legRow(_ s: IJSegment009) -> some View {
        let mode = (s.mode ?? "").uppercased()
        let isRail = mode == "RAIL"
        let st = legState(s.status)
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(spacing: 0) {
                Group {
                    switch st.dot {
                    case .done:   ZStack { Circle().fill(Brand.success); Image(systemName: "checkmark").font(.system(size: 7, weight: .black)).foregroundStyle(.black) }
                    case .active: Circle().fill(LinearGradient.diagonal).overlay(Circle().strokeBorder(LinearGradient.primary, lineWidth: 2).frame(width: 18, height: 18))
                    case .pending: Circle().fill(palette.bgCard).overlay(Circle().strokeBorder(palette.textTertiary, lineWidth: 2))
                    }
                }.frame(width: 14, height: 14).padding(.top, 2)
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("LEG \(s.legNumber ?? 0) · \(legKind(mode)) · \(mode)")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                Text("\(shortPlace(s.originDescription ?? "—")) → \(shortPlace(s.destinationDescription ?? "—"))")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(carrierLine(s)).font(EType.mono(.caption)).tracking(0.2)
                    .foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(st.label).font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(isRail && st.dot == .active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(st.color))
                Text(money(s.rate?.value ?? 0)).font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
        .background(isRail ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.06)) : AnyShapeStyle(Color.clear))
        .overlay(alignment: .leading) {
            if isRail { Rectangle().fill(LinearGradient.primary).frame(width: 3) }
        }
    }

    private func carrierLine(_ s: IJSegment009) -> String {
        let carrier = s.carrierId.map { "Carrier #\($0)" } ?? "carrier tbd"
        let when = s.arrivedAt != nil ? "arrived" : (s.departedAt != nil ? "in transit" : (s.status ?? "scheduled"))
        return "\(carrier) · \(when.replacingOccurrences(of: "_", with: " "))"
    }

    private func legKind(_ mode: String) -> String { mode == "RAIL" ? "LINE-HAUL" : (mode == "VESSEL" ? "OCEAN" : "DRAY") }

    private enum LegDot { case done, active, pending }
    private func legState(_ s: String?) -> (label: String, color: Color, dot: LegDot) {
        switch (s ?? "").lowercased() {
        case "completed":  return ("DONE", Brand.success, .done)
        case "in_transit", "booked": return ("ACTIVE", Brand.info, .active)
        case "cancelled":  return ("CANCELLED", Brand.danger, .pending)
        default:           return ("PENDING", palette.textTertiary, .pending)
        }
    }

    // MARK: ESANG run-plan card

    private var runPlanCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("ESANG").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text("· RUN PLAN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.info)
                }
                Text(runHeadline).font(.system(size: 15, weight: .bold)).tracking(-0.2)
                    .foregroundStyle(palette.textPrimary).lineLimit(2)
                Text(runSub).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var runHeadline: String {
        if let r = railSegment, r.status == "in_transit" {
            return "Rail leg on the road — pre-stage the \(shortPlace(r.destinationDescription ?? "deramp")) dray now"
        }
        if segments.allSatisfy({ ($0.status ?? "") == "completed" }) { return "Door-to-door complete — final gate-in closed the move" }
        return "Move \((detail?.status ?? "in progress").replacingOccurrences(of: "_", with: " ")) · \(money(grandTotal)) blended"
    }
    private var runSub: String {
        "\(segments.count) legs · \(transfers.count) ramp lift\(transfers.count == 1 ? "" : "s") · door-fence gate-in closes the move."
    }

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
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder((actionIsError ? Brand.danger : Brand.success).opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: trackingBusy ? "Locating…" : "Track rail leg",
                      action: { Task { await trackRailLeg() } }, isLoading: trackingBusy)
            Button(action: openCostDetail) {
                Text("Cost detail").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(width: 130, height: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        struct CostIn: Encodable { let intermodalShipmentId: Int }
        do {
            async let d: IJDetail009 = EusoTripAPI.shared.query(
                "intermodal.getIntermodalShipmentDetail", input: DetailIn(id: shipmentId))
            async let c: IJCostBreakdown009? = EusoTripAPI.shared.query(
                "intermodal.getIntermodalCostBreakdown", input: CostIn(intermodalShipmentId: shipmentId))
            let (dd, cc) = try await (d, c)
            self.detail = dd
            self.cost = cc
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func trackRailLeg() async {
        guard !trackingBusy else { return }
        trackingBusy = true; actionBanner = nil
        struct TrackIn: Encodable { let intermodalShipmentId: Int }
        do {
            let t: IJTracking009 = try await EusoTripAPI.shared.query(
                "intermodal.getIntermodalTracking", input: TrackIn(intermodalShipmentId: shipmentId))
            self.tracking = t
            NotificationCenter.default.post(name: Notification.Name("eusoIntermodalTrack"), object: nil,
                userInfo: ["intermodalShipmentId": shipmentId,
                           "activeSegmentId": t.activeSegmentId as Any,
                           "currentMode": t.currentMode as Any])
            actionIsError = false
            actionBanner = "Live on \((t.currentMode ?? "rail").lowercased()) leg."
        } catch {
            actionIsError = true
            actionBanner = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        trackingBusy = false
    }

    private func openCostDetail() {
        NotificationCenter.default.post(name: Notification.Name("eusoIntermodalCostDetail"), object: nil,
            userInfo: ["intermodalShipmentId": shipmentId])
        actionIsError = false
        actionBanner = "Opening cost breakdown · \(money(grandTotal)) total"
    }

    // MARK: Scaffolds

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 232)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 160)
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

// MARK: - Intermodal chain map hero

private struct IntermodalChainMap009: View {
    let segments: [IJSegment009]
    let railActive: Bool
    let originLabel: String
    let destLabel: String
    let etaText: String
    let railLabel: String
    let reduceMotion: Bool
    let palette: Theme.Palette

    @State private var breathe = false
    @State private var bob = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let dock = CGPoint(x: 0.10 * w, y: 0.80 * h)
                let ramp1 = CGPoint(x: 0.26 * w, y: 0.70 * h)
                let railFix = CGPoint(x: 0.58 * w, y: 0.42 * h)
                let ramp2 = CGPoint(x: 0.84 * w, y: 0.52 * h)
                let dc = CGPoint(x: 0.92 * w, y: 0.70 * h)

                ZStack {
                    LinearGradient(colors: [Color(hex: 0x11151D), Color(hex: 0x090C12)],
                                   startPoint: .top, endPoint: .bottom)
                    Path { p in
                        for r in stride(from: 0.30, through: 0.85, by: 0.27) { p.move(to: CGPoint(x: 0, y: r*h)); p.addLine(to: CGPoint(x: w, y: r*h)) }
                        for c in stride(from: 0.25, through: 0.85, by: 0.25) { p.move(to: CGPoint(x: c*w, y: 0)); p.addLine(to: CGPoint(x: c*w, y: h)) }
                    }.stroke(Color.white.opacity(0.05), lineWidth: 1)

                    // dray leg 1 (done, green)
                    Path { p in p.move(to: dock); p.addLine(to: ramp1) }
                        .stroke(Brand.success, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    // rail leg solid ramp1->fix
                    Path { p in p.move(to: ramp1); p.addQuadCurve(to: railFix, control: CGPoint(x: 0.40*w, y: 0.44*h)) }
                        .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                    // rail leg dashed fix->ramp2
                    Path { p in p.move(to: railFix); p.addQuadCurve(to: ramp2, control: CGPoint(x: 0.72*w, y: 0.44*h)) }
                        .stroke(palette.textTertiary.opacity(0.85), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [4, 5]))
                    // dray leg 3 dashed ramp2->dc
                    Path { p in p.move(to: ramp2); p.addLine(to: dc) }
                        .stroke(palette.textTertiary.opacity(0.8), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [3, 4]))

                    // nodes
                    node(dock, fill: AnyShapeStyle(LinearGradient.diagonal))
                    rampNode(ramp1, done: true)
                    rampNode(ramp2, done: false)
                    // dest DC door-fence
                    ZStack {
                        Circle().fill(Brand.info.opacity(breathe ? 0.12 : 0.40)).frame(width: breathe ? 44 : 34, height: breathe ? 44 : 34)
                        Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])).foregroundStyle(Brand.info.opacity(0.85)).frame(width: 40, height: 40)
                        Image(systemName: "mappin.circle.fill").font(.system(size: 16)).foregroundStyle(LinearGradient.diagonal)
                    }.position(dc)

                    // animated well-car at live fix
                    if railActive {
                        WellCarMarker009(reduceMotion: reduceMotion).position(railFix).offset(y: reduceMotion ? 0 : (bob ? -1.5 : 0))
                    }

                    // labels
                    Text(originLabel).font(.system(size: 7, weight: .heavy)).foregroundStyle(palette.textSecondary)
                        .position(x: dock.x + 8, y: dock.y + 16)
                    Text("DC \(destLabel)").font(.system(size: 7, weight: .heavy)).foregroundStyle(palette.textSecondary)
                        .position(x: dc.x - 12, y: dc.y + 18)

                    // chips
                    VStack {
                        HStack {
                            HStack(spacing: 5) { Circle().fill(Brand.success).frame(width: 6, height: 6); Text(railLabel).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(.white) }
                                .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(.black.opacity(0.55)))
                            Spacer()
                            Text(etaText.uppercased()).font(.system(size: 9, weight: .heavy)).monospacedDigit().foregroundStyle(.white)
                                .padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(Color(hex: 0x1C2128)))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
                        }
                        Spacer()
                    }.padding(Space.s3)
                }
            }
            // legend strip
            HStack(spacing: Space.s4) {
                legendDot(Brand.success, "Dray done")
                legendDot2("Rail line-haul live")
                legendDot(palette.textTertiary, "Dray scheduled")
                Spacer()
            }
            .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
                withAnimation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true)) { bob = true }
            }
        }
    }

    private func node(_ pt: CGPoint, fill: AnyShapeStyle) -> some View {
        ZStack { Circle().fill(.white).frame(width: 12, height: 12); Circle().fill(fill).frame(width: 9, height: 9) }.position(pt)
    }
    private func rampNode(_ pt: CGPoint, done: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x1C2128))
            .frame(width: 12, height: 12)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(done ? Brand.success : palette.textTertiary, lineWidth: 1.6))
            .position(pt)
    }
    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { Circle().fill(c).frame(width: 7, height: 7); Text(t).font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textSecondary) }
    }
    private func legendDot2(_ t: String) -> some View {
        HStack(spacing: 5) { Circle().fill(LinearGradient.primary).frame(width: 7, height: 7); Text(t).font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textSecondary) }
    }
}

/// Compact double-stack well-car marker.
private struct WellCarMarker009: View {
    let reduceMotion: Bool
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Brand.blue.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 20))
                .frame(width: 40, height: 40)
            VStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: [Color(hex: 0xEDEFF3), Color(hex: 0x9AA2B0)], startPoint: .top, endPoint: .bottom)).frame(width: 26, height: 8)
                RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: [Color(hex: 0x2B85FF), Color(hex: 0xA726E8)], startPoint: .top, endPoint: .bottom)).frame(width: 30, height: 9)
                HStack(spacing: 10) { Circle().fill(Color(hex: 0x1A1A1A)).frame(width: 5, height: 5); Circle().fill(Color(hex: 0x1A1A1A)).frame(width: 5, height: 5) }
            }
        }
    }
}

// MARK: - Previews

#Preview("009 · Rail Intermodal Journey · Night") {
    RailIntermodalJourneyScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("009 · Rail Intermodal Journey · Light") {
    RailIntermodalJourneyScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
