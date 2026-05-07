//
//  228_ShipperRFPDetail.swift
//  EusoTrip 2027 UI — Shipper · RFP Detail (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — new file at slot 228 to match wireframe
//  canon at /02 Shipper/Code/228_ShipperRFPDetail.swift. Persona:
//  Diego Usoro / Eusorone Technologies (companyId 1) per §11. The
//  drilldown surface that opens from 215 RFP Manager when the
//  shipper taps a row to see closing-pill + bid responses + scoring.
//
//  Note: slot 228 also holds `228_ShipperBOLs.swift` in the iOS
//  tree (different scope, different struct names — no conflict).
//  Wireframe canon governs the UI of this file specifically.
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · RFP DETAIL / "{N} BIDS · {Xh} LEFT" warn
//    2. Back chevron + breadcrumb "RFPs"
//    3. Title block      32pt RFP title + sub line "Eusorone Technologies · {N} bids · MATRIX-50"
//    4. IridescentHairline
//    5. Hero RFP card    3pt warn tier rim + RFP id + closing pill + lane title +
//                        spec line + Posted-by Diego Usoro + 4-stage lifecycle strip
//    6. KPI quartet      4-cell · BIDS (gradient) · LOW · HIGH · GAP (warn)
//    7. BID RESPONSES    section eyebrow + 3 ranked rows + 1 compact row
//    8. View all link    gradient mid-link
//
//  Real wiring preserved: `rfpManager.getRFPDetail(rfpId:)` +
//  `rfpManager.getBidResponses(rfpId:)` + `rfpManager.scoreResponses(rfpId:)`.
//  Mutation surface (publish, award) lives in 215 RFP Manager.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2145 — `RFPManagerAPI.RFP` doesn't ship `originCity /
//                originState / destinationCity / destinationState`
//                lane metadata at the RFP-root level (lanes nested
//                array has it). Lane title falls back to the first
//                Lane's origin → destination, then to RFP title.
//    EUSO-2146 — Bid responses don't ship a per-row tier badge
//                (RECOMMENDED / LANE PRO / LOW RATE). Badge derives
//                client-side from scorecard recommendation +
//                lane-bid rank.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy; §4.3 single iridescent hairline; §11 / §11.2
//  Diego canon; §15.2 status-aware tier rim grammar; §17.2 KPI
//  quartet recipe; §19.2 file-scoped LifecycleStrip4Detail +
//  warnGrad helpers; §20.4 no dead buttons; §22.2 textTertiary /
//  warning informational counter.
//

import SwiftUI

// MARK: - Lifecycle stages

private enum RFPDetailStage: CaseIterable { case posted, bidding, award, closed
    var label: String {
        switch self {
        case .posted:  return "POSTED"
        case .bidding: return "BIDDING"
        case .award:   return "AWARD"
        case .closed:  return "CLOSED"
        }
    }
}

private func deriveStage(from status: String?) -> RFPDetailStage {
    switch (status ?? "").lowercased() {
    case "draft":              return .posted
    case "published",
         "in_review":          return .bidding
    case "awarded":            return .award
    case "closed",
         "cancelled",
         "canceled":           return .closed
    default:                   return .bidding
    }
}

// MARK: - Store

@MainActor
final class ShipperRFPDetailStore: ObservableObject {
    enum Phase {
        case loading
        case loaded(rfp: RFPManagerAPI.RFP,
                    bids: [RFPManagerAPI.BidResponse],
                    scorecards: [RFPManagerAPI.Scorecard])
        case error(String)
    }

    @Published private(set) var phase: Phase = .loading
    let rfpId: String
    private let api: EusoTripAPI

    init(rfpId: String, api: EusoTripAPI = .shared) {
        self.rfpId = rfpId
        self.api = api
    }

    func load() async {
        phase = .loading
        do {
            async let rfpTask = api.rfp.getRFPDetail(rfpId: rfpId)
            async let bidsTask: [RFPManagerAPI.BidResponse] = (try? await api.rfp.getBidResponses(rfpId: rfpId)) ?? []
            async let scoreTask: [RFPManagerAPI.Scorecard]  = (try? await api.rfp.scoreResponses(rfpId: rfpId)) ?? []
            let (rfp, bids, scorecards) = try await (rfpTask, bidsTask, scoreTask)
            phase = .loaded(rfp: rfp, bids: bids, scorecards: scorecards)
        } catch {
            phase = .error("Couldn't load RFP detail.")
        }
    }
}

// MARK: - Screen root

struct ShipperRFPDetail: View {
    let rfpId: String
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var store: ShipperRFPDetailStore

    init(rfpId: String = "0") {
        self.rfpId = rfpId
        _store = StateObject(wrappedValue: ShipperRFPDetailStore(rfpId: rfpId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                crumbRow
                    .padding(.top, Space.s2)
                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · RFP DETAIL")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(counterColor)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s3)
    }

    private var counterEyebrow: String {
        if case .loaded(let rfp, let bids, _) = store.phase {
            let hours = hoursLeft(rfp.responseDeadline) ?? 0
            return "\(bids.count) BIDS · \(hours)h LEFT"
        }
        return "—"
    }

    private var counterColor: Color {
        if case .loaded(let rfp, _, _) = store.phase,
           let h = hoursLeft(rfp.responseDeadline), h <= 48 {
            return Brand.warning
        }
        return palette.textTertiary
    }

    private var counterAccessibility: String {
        if case .loaded(_, let bids, _) = store.phase {
            return "\(bids.count) bid responses"
        }
        return "Loading RFP detail"
    }

    private func hoursLeft(_ iso: String?) -> Int? {
        guard let s = iso, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        guard let date else { return nil }
        return max(0, Int(date.timeIntervalSinceNow / 3600))
    }

    // MARK: Back chevron + breadcrumb

    private var crumbRow: some View {
        Button(action: tapBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("RFPs")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, Space.s3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to RFPs")
    }

    private func tapBack() {
        // observability post — real effect: dismiss() env handler
        dismiss()
        NotificationCenter.default.post(
            name: .eusoShipperRfpDetailBack,
            object: nil,
            userInfo: [
                "source": "228_ShipperRFPDetail",
                "rfpId": rfpId
            ]
        )
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 92)
                }
            }
            .padding(.horizontal, Space.s3)
        case .error(let m):
            errorCard(m)
                .padding(.horizontal, Space.s3)
        case .loaded(let rfp, let bids, let scorecards):
            VStack(alignment: .leading, spacing: 0) {
                titleBlock(rfp, bids: bids)
                IridescentHairline()
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)

                heroCard(rfp)
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)

                kpiQuartet(rfp, bids: bids)
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)

                sectionLabel("BID RESPONSES · \(bids.count) RANKED")
                    .padding(.top, Space.s5)

                let ranked = rankBids(bids: bids, scorecards: scorecards)
                let topThree = Array(ranked.prefix(3))
                let compact = ranked.count > 3 ? ranked[3] : nil

                VStack(spacing: Space.s3) {
                    ForEach(topThree, id: \.bid.id) { row in
                        bidRowView(row)
                    }
                    if let compact {
                        compactBidRowView(compact)
                    }
                }
                .padding(.horizontal, Space.s3)
                .padding(.top, Space.s3)

                if bids.count > 4 {
                    viewAllLink(bids.count)
                        .padding(.horizontal, Space.s3)
                        .padding(.top, Space.s4)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s3)
    }

    // MARK: Title block

    private func titleBlock(_ rfp: RFPManagerAPI.RFP, bids: [RFPManagerAPI.BidResponse]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rfp.title)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            Text("Eusorone Technologies · \(bids.count) bids · MATRIX-50")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
        .padding(.top, Space.s2)
    }

    // MARK: Hero RFP card (3pt warn rim · RFP id · closing pill · lane · spec · posted-by Diego · lifecycle strip)

    private func heroCard(_ rfp: RFPManagerAPI.RFP) -> some View {
        let stage = deriveStage(from: rfp.status)
        let hours = hoursLeft(rfp.responseDeadline)
        let isWarn = (hours ?? 999) <= 48
        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isWarn ? AnyShapeStyle(LinearGradient.warnGrad) : AnyShapeStyle(LinearGradient.diagonal))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(rfpDisplayId(rfp))
                        .font(EType.mono(.micro))
                        .tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    closingPill(hours: hours, status: rfp.status)
                }
                .padding(.top, Space.s4)

                Text(laneTitle(rfp))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .padding(.top, Space.s2 + 2)

                Text(specLine(rfp))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 4)

                postedByRow(rfp)
                    .padding(.top, Space.s2 + 2)

                LifecycleStrip4Detail(activeStage: stage)
                    .padding(.top, Space.s4 + 2)
                    .padding(.bottom, Space.s4)
            }
            .padding(.leading, Space.s4)
            .padding(.trailing, Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rfpDisplayId(rfp)), \(rfp.title), \(stage.label)")
    }

    private func rfpDisplayId(_ rfp: RFPManagerAPI.RFP) -> String {
        rfp.id.uppercased().hasPrefix("RFP-") ? rfp.id : "RFP-\(rfp.id)"
    }

    private func laneTitle(_ rfp: RFPManagerAPI.RFP) -> String {
        if let first = rfp.lanes.first {
            let o = "\(first.origin.city), \(first.origin.state)"
            let d = "\(first.destination.city), \(first.destination.state)"
            return "\(o) → \(d)"
        }
        return rfp.title
    }

    private func specLine(_ rfp: RFPManagerAPI.RFP) -> String {
        guard let first = rfp.lanes.first else { return "RFP details" }
        var parts: [String] = []
        let eq = first.equipmentRequired.replacingOccurrences(of: "_", with: " ").capitalized
        parts.append(eq)
        if first.hazmat == true { parts.append("Hazmat") }
        parts.append("\(first.estimatedDistance) mi")
        if rfp.lanes.count > 1 {
            parts.append("+\(rfp.lanes.count - 1) more lanes")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func closingPill(hours: Int?, status: String?) -> some View {
        let s = (status ?? "").lowercased()
        if s == "awarded" {
            Text("AWARDED")
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: 84, height: 20)
                .background(Capsule().fill(Brand.success))
        } else if s == "closed" || s == "cancelled" || s == "canceled" {
            Text("CLOSED")
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 84, height: 20)
                .overlay(Capsule().strokeBorder(palette.textTertiary, lineWidth: 1))
                .background(Capsule().fill(palette.bgCard))
        } else if let h = hours, h <= 48 {
            Text("CLOSING · \(h)h LEFT")
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: 148, height: 20)
                .background(Capsule().fill(LinearGradient.warnGrad))
        } else if let h = hours {
            let days = max(1, Int((Double(h) / 24.0).rounded(.up)))
            Text("ACTIVE · \(days)d")
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(LinearGradient.primary)
                .frame(width: 84, height: 20)
                .overlay(Capsule().strokeBorder(LinearGradient.primary, lineWidth: 1))
                .background(Capsule().fill(palette.bgCard))
        } else {
            Text("ACTIVE")
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(LinearGradient.primary)
                .frame(width: 84, height: 20)
                .overlay(Capsule().strokeBorder(LinearGradient.primary, lineWidth: 1))
                .background(Capsule().fill(palette.bgCard))
        }
    }

    private func postedByRow(_ rfp: RFPManagerAPI.RFP) -> some View {
        let sub: String = {
            if let p = rfp.publishedAt {
                return relativeShort(p)
            }
            return "draft"
        }()
        return HStack(spacing: Space.s2) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 14, height: 14)
                Text("DU")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 0) {
                Text("Posted by ").foregroundStyle(palette.textSecondary)
                Text("Diego Usoro").fontWeight(.bold).foregroundStyle(palette.textPrimary)
                Text(" · \(sub)").foregroundStyle(palette.textSecondary)
            }
            .font(.system(size: 10.5))
            Spacer(minLength: 0)
        }
    }

    private func relativeShort(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let s = Date().timeIntervalSince(d)
        if s < 3600 { return "\(Int(s/60))m ago" }
        if s < 86400 { return "\(Int(s/3600))h ago" }
        return "\(Int(s/86400))d ago"
    }

    // MARK: KPI quartet (BIDS / LOW / HIGH / GAP)

    private func kpiQuartet(_ rfp: RFPManagerAPI.RFP, bids: [RFPManagerAPI.BidResponse]) -> some View {
        let allRates = bids.flatMap { $0.laneBids.map { $0.bidRate } }
        let low = allRates.min() ?? 0
        let high = allRates.max() ?? 0
        let gap = high - low
        let gapPct = high > 0 ? (gap / high) * 100 : 0
        return HStack(spacing: 0) {
            kpiCellView(label: "BIDS", value: "\(bids.count)", style: .gradient, sub: "")
            kpiDivider
            kpiCellView(label: "LOW",
                        value: low > 0 ? "$\(formatNumber(low))" : "—",
                        style: .primary,
                        sub: lowestBidder(bids))
            kpiDivider
            kpiCellView(label: "HIGH",
                        value: high > 0 ? "$\(formatNumber(high))" : "—",
                        style: .primary,
                        sub: highestBidder(bids))
            kpiDivider
            kpiCellView(label: "GAP",
                        value: gap > 0 ? "$\(formatNumber(gap))" : "—",
                        style: gap > 0 ? .warn : .primary,
                        sub: gap > 0 ? String(format: "%.0f%% spread", gapPct) : "")
        }
        .padding(.vertical, Space.s4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 44)
    }

    private enum KpiStyle { case gradient, primary, warn }

    @ViewBuilder
    private func kpiCellView(label: String, value: String, style: KpiStyle, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                switch style {
                case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                case .primary:  Text(value).foregroundStyle(palette.textPrimary)
                case .warn:     Text(value).foregroundStyle(Brand.warning)
                }
            }
            .font(.system(size: 22, weight: .bold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            Text(sub)
                .font(.system(size: 9))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private func formatNumber(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%,.0f", v).replacingOccurrences(of: ",000", with: ",000") }
        return String(format: "%.0f", v)
    }

    private func lowestBidder(_ bids: [RFPManagerAPI.BidResponse]) -> String {
        guard let pair = bids.flatMap({ b in b.laneBids.map { (b, $0.bidRate) } }).min(by: { $0.1 < $1.1 }) else { return "" }
        return pair.0.carrierName.split(separator: " ").first.map(String.init) ?? pair.0.carrierName
    }

    private func highestBidder(_ bids: [RFPManagerAPI.BidResponse]) -> String {
        guard let pair = bids.flatMap({ b in b.laneBids.map { (b, $0.bidRate) } }).max(by: { $0.1 < $1.1 }) else { return "" }
        return pair.0.carrierName.split(separator: " ").first.map(String.init) ?? pair.0.carrierName
    }

    // MARK: Bid response row

    private struct BidRanked {
        let bid: RFPManagerAPI.BidResponse
        let scorecard: RFPManagerAPI.Scorecard?
        let rank: Int
    }

    private func rankBids(bids: [RFPManagerAPI.BidResponse],
                          scorecards: [RFPManagerAPI.Scorecard]) -> [BidRanked] {
        let scoreById: [Int: RFPManagerAPI.Scorecard] = Dictionary(uniqueKeysWithValues: scorecards.map { ($0.carrierId, $0) })
        let withScore = bids.map { b -> (RFPManagerAPI.BidResponse, RFPManagerAPI.Scorecard?) in
            (b, scoreById[b.carrierId])
        }
        let sorted = withScore.sorted { lhs, rhs in
            (lhs.1?.overallScore ?? 0) > (rhs.1?.overallScore ?? 0)
        }
        return sorted.enumerated().map { idx, pair in
            BidRanked(bid: pair.0, scorecard: pair.1, rank: idx + 1)
        }
    }

    private func bidRowView(_ row: BidRanked) -> some View {
        let recommended = (row.scorecard?.recommendation ?? "").lowercased() == "award"
        let tierRim: AnyShapeStyle = recommended
            ? AnyShapeStyle(LinearGradient.diagonal)
            : (row.rank == 2 ? AnyShapeStyle(Brand.success)
               : AnyShapeStyle(palette.textTertiary))

        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tierRim)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    scoreBadge(row)
                    Spacer()
                    bidBadge(row, recommended: recommended)
                }
                .padding(.top, Space.s4)

                Text(row.bid.carrierName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .padding(.top, Space.s2 + 2)

                Text(credLine(row))
                    .font(EType.mono(.caption))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.top, 4)

                bidStatRow(row)
                    .padding(.top, Space.s2 + 2)
                    .padding(.bottom, Space.s4)
            }
            .padding(.leading, Space.s4)
            .padding(.trailing, Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibility(row))
    }

    private func scoreBadge(_ row: BidRanked) -> some View {
        let scoreText = row.scorecard.map { "\($0.overallScore)" } ?? "—"
        let isTop = row.rank == 1
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isTop ? AnyShapeStyle(LinearGradient.diagonal)
                            : AnyShapeStyle(palette.bgCardSoft))
            Text(scoreText)
                .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(isTop ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textPrimary))
        }
        .frame(width: 36, height: 24)
    }

    @ViewBuilder
    private func bidBadge(_ row: BidRanked, recommended: Bool) -> some View {
        if recommended {
            Text("RECOMMENDED")
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(.white)
                .frame(width: 92, height: 18)
                .background(Capsule().fill(LinearGradient.diagonal))
        } else if row.rank == 2 {
            Text("LANE PRO")
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(Brand.success)
                .frame(width: 60, height: 18)
                .background(Capsule().fill(Brand.success.opacity(0.14)))
        } else if (row.scorecard?.recommendation ?? "").lowercased() == "decline" {
            Text("DECLINE")
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(Brand.danger)
                .frame(width: 60, height: 18)
                .background(Capsule().fill(Brand.danger.opacity(0.14)))
        } else {
            // EUSO-2146 — fallback "LOW RATE" derived from min lane bid.
            Text("BID #\(row.rank)")
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 60, height: 18)
                .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 0.75))
                .background(Capsule().fill(palette.bgCardSoft))
        }
    }

    private func credLine(_ row: BidRanked) -> String {
        var parts: [String] = []
        if let tier = row.bid.carrierTier, !tier.isEmpty {
            parts.append(tier.uppercased())
        }
        if let safety = row.bid.safetyScore {
            parts.append("Safety \(safety)")
        }
        if let fleet = row.bid.fleetSize {
            parts.append("Fleet \(fleet)")
        }
        return parts.isEmpty ? "Carrier #\(row.bid.carrierId)" : parts.joined(separator: " · ")
    }

    private func bidStatRow(_ row: BidRanked) -> some View {
        let firstLane = row.bid.laneBids.first
        let rate = firstLane.map { "$\(formatNumber($0.bidRate))" } ?? "—"
        let transit = firstLane?.transitDays.map { "\($0)d" } ?? "—"
        let onTime = row.bid.onTimeRate.map { "\($0)%" } ?? "—"
        let cap = firstLane?.capacityPerWeek.map { "\($0)/wk" } ?? "—"
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            statCell(value: rate, unit: "rate", color: palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            statCell(value: transit, unit: "transit", color: palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            statCell(value: cap, unit: "cap", color: palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            statCell(value: onTime, unit: "on-time",
                     color: row.bid.onTimeRate.map { $0 >= 95 ? Brand.success : palette.textPrimary } ?? palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statCell(value: String, unit: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
            Text(unit)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func rowAccessibility(_ row: BidRanked) -> String {
        let score = row.scorecard?.overallScore ?? 0
        return "Rank \(row.rank), \(row.bid.carrierName), score \(score)"
    }

    // MARK: Compact bid row (4th row)

    private func compactBidRowView(_ row: BidRanked) -> some View {
        let score = row.scorecard.map { "\($0.overallScore)" } ?? "—"
        let firstLane = row.bid.laneBids.first
        let rate = firstLane.map { "$\(formatNumber($0.bidRate))" } ?? "—"
        let transit = firstLane?.transitDays.map { "\($0)d transit" } ?? ""
        let onTime = row.bid.onTimeRate.map { "\($0)% on-time" } ?? ""
        let parts = [rate, transit, onTime].filter { !$0.isEmpty }
        let subline = parts.joined(separator: " · ")

        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(palette.textTertiary)
                .frame(width: 3)
            HStack(alignment: .center, spacing: Space.s3) {
                Text(score)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 20)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.bid.carrierName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(subline)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Spacer()
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: View all link

    private func viewAllLink(_ count: Int) -> some View {
        Button(action: tapViewAll) {
            Text("View all \(count) bids → composite-score ranked")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LinearGradient.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func tapViewAll() {
        NotificationCenter.default.post(
            name: .eusoShipperRfpDetailViewAll,
            object: nil,
            userInfo: [
                "source": "228_ShipperRFPDetail",
                "rfpId": rfpId
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/rfp/\(rfpId)/bids") {
            openURL(url)
        }
    }

    // MARK: Error

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Brand.info)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - 4-stage lifecycle strip (file-scoped per §19.2)

private struct LifecycleStrip4Detail: View {
    let activeStage: RFPDetailStage
    @Environment(\.palette) var palette

    private let stages: [(key: RFPDetailStage, label: String)] = [
        (.posted,  "POSTED"),
        (.bidding, "BIDDING"),
        (.award,   "AWARD"),
        (.closed,  "CLOSED"),
    ]

    private var activeIndex: Int {
        stages.firstIndex(where: { $0.key == activeStage }) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let count = stages.count
            let stride = total / CGFloat(count - 1)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(palette.borderFaint)
                    .frame(width: total, height: 2)
                Rectangle()
                    .fill(LinearGradient.primary)
                    .frame(width: stride * CGFloat(activeIndex), height: 2)
                ForEach(0..<count, id: \.self) { i in
                    let isActive = i == activeIndex
                    let isCompleted = i < activeIndex
                    Circle()
                        .fill(isCompleted || isActive
                              ? AnyShapeStyle(LinearGradient.diagonal)
                              : AnyShapeStyle(palette.borderFaint))
                        .frame(width: isActive ? 9 : 7, height: isActive ? 9 : 7)
                        .offset(x: stride * CGFloat(i) - (isActive ? 4.5 : 3.5))
                }
                ForEach(0..<count, id: \.self) { i in
                    let isActive = i == activeIndex
                    let isCompleted = i < activeIndex
                    let label = stages[i].label
                    Text(label)
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(
                            isActive
                                ? AnyShapeStyle(LinearGradient.primary)
                                : (isCompleted
                                    ? AnyShapeStyle(palette.textSecondary)
                                    : AnyShapeStyle(palette.textTertiary))
                        )
                        .offset(x: anchoredOffset(for: i, count: count, stride: stride, label: label),
                                y: -10)
                }
            }
        }
        .frame(height: 18)
    }

    private func anchoredOffset(for i: Int, count: Int, stride: CGFloat, label: String) -> CGFloat {
        let approxWidth: CGFloat = CGFloat(label.count) * 4.2
        let baseX = stride * CGFloat(i)
        if i == 0 { return baseX }
        if i == count - 1 { return baseX - approxWidth }
        return baseX - approxWidth / 2
    }
}

// MARK: - File-scoped warn gradient (§19.2 · named to avoid clashes)

private extension LinearGradient {
    static let warnGrad = LinearGradient(
        colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Back chevron tap on RFP Detail.
    static let eusoShipperRfpDetailBack    = Notification.Name("eusoShipperRfpDetailBack")
    /// "View all {N} bids" gradient mid-link tap.
    static let eusoShipperRfpDetailViewAll = Notification.Name("eusoShipperRfpDetailViewAll")
}

// MARK: - Previews

#Preview("228 · RFP Detail · Dark") {
    ShipperRFPDetail(rfpId: "RFP-260427-7C3A09F18B")
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("228 · RFP Detail · Light") {
    ShipperRFPDetail(rfpId: "RFP-260427-7C3A09F18B")
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
