//
//  215_ShipperRFP.swift
//  EusoTrip 2027 UI — Shipper · RFP Manager (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/215_ShipperRFP.swift. Persona: Diego Usoro /
//  Eusorone Technologies (companyId 1) per §11. RFP IDs reuse the
//  LD- hex tail (`RFP-260427-XXXXXXXXXX`) so the audit trail joins
//  the `loads` and `rfps` tables on the same suffix per §11.2.
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · RFP MANAGER / "{N} ACTIVE · {M} BIDS"
//    2. Title block      RFPs / "Eusorone Technologies · request for proposals · MATRIX-50"
//    3. IridescentHairline
//    4. KPI summary card 3-cell · ACTIVE · TOTAL BIDS · AWARDED YTD ($ saved trail)
//    5. Filter chip row  All / Active / Awarded / Closed / Drafts
//    6. RFP rows         3pt left tier rim · RFP id · status pill · lane title ·
//                        spec line · 3-stat row · 4-stage lifecycle strip
//    7. Compact closed   76pt variant for status=closed / cancelled rows
//    8. Inline detail    expands below the active row · lanes + bids + scoring
//    9. "+ New RFP" CTA  gradient ribbon
//
//  Real wiring preserved: `rfpManager.getRFPs / getBidResponses /
//  scoreResponses / publishRFP / awardLane` via `ShipperRFPStore`.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2116 — no rolled-up "$ saved YTD" metric on the API surface.
//                Awarded YTD KPI cell trail paints "—" until backend
//                ships `rfpManager.getStats` returning the YTD sum of
//                (targetRate − awardedRate) per awarded lane.
//    EUSO-2117 — no per-RFP low/high bid range on the list envelope.
//                Stat triplet shows "{N} bids · low — · high —" until
//                backend folds aggregate min/max into `getRFPs`.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy; §4.3 single iridescent hairline; §7 breathe
//  density; §11 / §11.2 Diego canon + RFP-260427 audit-trail
//  convention; §11.4 / §13 carrier mix; §15.2 4-stage lifecycle strip
//  + per-row tier rim + composite-score recipes; §16.2 action ribbon
//  CTA pattern; §17.2 status pill grammar (closingSoon warn-grad /
//  activeOutlined gradient outline / awarded success / closed
//  neutral); §19.2 file-scoped LifecycleStrip4 + warnGrad helpers;
//  §20.4 no dead buttons (filter / row / new-RFP / publish / award
//  all post notifications or fire mutations); §22.2 textTertiary
//  counter (informational).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Status helpers (file-local)

private struct StatusStyle {
    let label: String
    let color: Color
}

private func statusStyle(for status: String, palette: Theme.Palette) -> StatusStyle {
    switch status.lowercased() {
    case "draft":     return StatusStyle(label: "Draft",      color: palette.textSecondary)
    case "published": return StatusStyle(label: "Published",  color: Brand.info)
    case "in_review": return StatusStyle(label: "In review",  color: Brand.warning)
    case "awarded":   return StatusStyle(label: "Awarded",    color: Brand.success)
    case "closed":    return StatusStyle(label: "Closed",     color: palette.textTertiary)
    case "cancelled", "canceled":
                       return StatusStyle(label: "Cancelled",  color: Brand.danger)
    default:           return StatusStyle(label: status.capitalized, color: palette.textSecondary)
    }
}

private struct RecommendationStyle {
    let label: String
    let icon: String
    let color: Color
}

private func recommendationStyle(_ rec: String) -> RecommendationStyle {
    switch rec.lowercased() {
    case "award":     return RecommendationStyle(label: "Recommend award", icon: "trophy.fill", color: Brand.success)
    case "shortlist": return RecommendationStyle(label: "Shortlist",       icon: "star.fill",   color: Brand.warning)
    case "decline":   return RecommendationStyle(label: "Decline",         icon: "exclamationmark.triangle.fill", color: Brand.danger)
    default:           return RecommendationStyle(label: rec.capitalized,    icon: "questionmark.circle", color: Brand.info)
    }
}

private func tierColor(_ tier: String?, palette: Theme.Palette) -> Color {
    switch (tier ?? "").lowercased() {
    case "gold":     return Brand.warning
    case "silver":   return palette.textSecondary
    case "bronze":   return Color(red: 0.85, green: 0.55, blue: 0.30)
    default:          return palette.textTertiary
    }
}

// MARK: - Tier rim + lifecycle stage + filter

private enum TierRim { case gradient, warn, success, neutral }

private enum RFPStage { case posted, bidding, award, closed }

private enum RFPFilter: String, CaseIterable, Identifiable {
    case all, active, awarded, closed, drafts
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:     return "All"
        case .active:  return "Active"
        case .awarded: return "Awarded"
        case .closed:  return "Closed"
        case .drafts:  return "Drafts"
        }
    }
}

// MARK: - Store

@MainActor
final class ShipperRFPStore: ObservableObject {
    enum LoadState {
        case loading
        case empty
        case error(String)
        case loaded([RFPManagerAPI.RFP])
    }

    @Published private(set) var state: LoadState = .loading
    @Published private(set) var bids: [RFPManagerAPI.BidResponse] = []
    @Published private(set) var scorecards: [RFPManagerAPI.Scorecard] = []
    @Published var mutatingRfpId: String?
    @Published var lastToast: String?

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let rows = try await api.rfp.getRFPs()
            state = rows.isEmpty ? .empty : .loaded(rows)
        } catch {
            state = .error("Couldn't reach the RFP service.")
        }
    }

    func loadDetail(for rfpId: String) async {
        async let bidsTask = (try? await api.rfp.getBidResponses(rfpId: rfpId)) ?? []
        async let scoreTask = (try? await api.rfp.scoreResponses(rfpId: rfpId)) ?? []
        let (b, s) = await (bidsTask, scoreTask)
        bids = b
        scorecards = s
    }

    func publish(rfpId: String) async -> Bool {
        mutatingRfpId = rfpId
        defer { mutatingRfpId = nil }
        do {
            let res = try await api.rfp.publishRFP(rfpId: rfpId)
            await refresh()
            flashToast(res.success
                       ? "Published — \(res.distributedTo) carriers notified"
                       : "Publish failed")
            return res.success
        } catch {
            flashToast("Publish failed")
            return false
        }
    }

    func award(rfpId: String, laneId: String, carrierId: Int, rate: Double? = nil) async -> Bool {
        mutatingRfpId = rfpId
        defer { mutatingRfpId = nil }
        do {
            let res = try await api.rfp.awardLane(
                rfpId: rfpId, laneId: laneId,
                carrierId: carrierId, awardedRate: rate
            )
            if res.success { await refresh() }
            flashToast(res.success ? "Awarded · contract drafted" : "Award failed")
            return res.success
        } catch {
            flashToast("Award failed")
            return false
        }
    }

    private func flashToast(_ text: String) {
        lastToast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { self.lastToast = nil }
        }
    }
}

// MARK: - Screen root

struct ShipperRFP: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = ShipperRFPStore()

    @State private var selectedRfpId: String?
    @State private var filter: RFPFilter = .all
    @State private var showNewRFPComposer: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s5)

                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $showNewRFPComposer) {
            NewRFPComposerSheet { committed in
                if committed {
                    Task { await store.refresh() }
                }
                showNewRFPComposer = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // RealtimeService → RFPs refresh when carriers submit bids,
        // award decisions are made, or RFP windows open/close.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.refresh() }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.lastToast {
                Text(toast)
                    .font(EType.caption)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .background(palette.bgCard.opacity(0.95))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .padding(.bottom, Space.s6)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.lastToast)
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
            value: filter
        )
        .onChange(of: selectedRfpId) { _, newId in
            guard let id = newId else { return }
            Task { await store.loadDetail(for: id) }
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · RFP MANAGER")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s3)
    }

    private var counterEyebrow: String {
        if case .loaded(let rfps) = store.state {
            let active = rfps.filter { isActive($0.status) }.count
            let bids = rfps.reduce(0) { $0 + $1.responsesReceived }
            return "\(active) ACTIVE · \(bids) BIDS"
        }
        return "—"
    }

    private var counterAccessibility: String {
        if case .loaded(let rfps) = store.state {
            let active = rfps.filter { isActive($0.status) }.count
            let bids = rfps.reduce(0) { $0 + $1.responsesReceived }
            return "\(active) active RFPs, \(bids) total bids"
        }
        return "Loading RFPs"
    }

    private func isActive(_ status: String) -> Bool {
        switch status.lowercased() {
        case "published", "in_review": return true
        default: return false
        }
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RFPs")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · request for proposals · MATRIX-50")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 124)
                }
            }
            .padding(.horizontal, Space.s3)
        case .empty:
            emptyHero
                .padding(.horizontal, Space.s3)
        case .error(let msg):
            errorBanner(msg)
                .padding(.horizontal, Space.s3)
        case .loaded(let rfps):
            VStack(alignment: .leading, spacing: 0) {
                kpiSummaryCard(rfps)
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s3)

                filterRow
                    .padding(.top, Space.s5)

                rfpList(filteredRows(rfps))
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)

                newRFPButton
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s5)
            }
        }
    }

    private func filteredRows(_ rfps: [RFPManagerAPI.RFP]) -> [RFPManagerAPI.RFP] {
        switch filter {
        case .all: return rfps
        case .active:
            return rfps.filter { isActive($0.status) }
        case .awarded:
            return rfps.filter { $0.status.lowercased() == "awarded" }
        case .closed:
            return rfps.filter {
                let s = $0.status.lowercased()
                return s == "closed" || s == "cancelled" || s == "canceled"
            }
        case .drafts:
            return rfps.filter { $0.status.lowercased() == "draft" }
        }
    }

    // MARK: KPI summary card (ACTIVE / TOTAL BIDS / AWARDED YTD)

    private func kpiSummaryCard(_ rfps: [RFPManagerAPI.RFP]) -> some View {
        let active = rfps.filter { isActive($0.status) }.count
        let totalBids = rfps.reduce(0) { $0 + $1.responsesReceived }
        let awardedYtd = rfps.filter { $0.status.lowercased() == "awarded" }.count

        return HStack(spacing: 0) {
            kpiCell(label: "ACTIVE", value: "\(active)", gradient: true, delta: nil, deltaColor: .clear, valueColor: nil)
            divider
            kpiCell(label: "TOTAL BIDS", value: "\(totalBids)", gradient: false, delta: nil, deltaColor: .clear, valueColor: nil)
            divider
            // EUSO-2116 — backend doesn't ship `$ saved` aggregate yet.
            kpiCell(label: "AWARDED YTD", value: "\(awardedYtd)", gradient: false, delta: "—", deltaColor: palette.textTertiary, valueColor: Brand.success)
        }
        .padding(.vertical, Space.s4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 36)
    }

    @ViewBuilder
    private func kpiCell(label: String,
                         value: String,
                         gradient: Bool,
                         delta: String?,
                         deltaColor: Color,
                         valueColor: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Group {
                    if gradient {
                        Text(value).foregroundStyle(LinearGradient.diagonal)
                    } else if let valueColor {
                        Text(value).foregroundStyle(valueColor)
                    } else {
                        Text(value).foregroundStyle(palette.textPrimary)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())

                if let delta {
                    Text(delta)
                        .font(EType.caption)
                        .foregroundStyle(deltaColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    // MARK: Filter row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(RFPFilter.allCases) { f in
                    Button(action: { tapFilter(f) }) {
                        Text(f.label)
                            .font(.system(size: 11, weight: f == filter ? .bold : .semibold))
                            .foregroundStyle(f == filter ? Color.white : palette.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background {
                                if f == filter {
                                    Capsule().fill(LinearGradient.primary)
                                } else {
                                    Capsule().fill(palette.bgCardSoft)
                                }
                            }
                            .overlay {
                                if f != filter {
                                    Capsule().strokeBorder(palette.borderFaint)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(f.label) filter")
                    .accessibilityAddTraits(f == filter ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, Space.s3)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [palette.bgPage.opacity(0), palette.bgPage],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 28)
            .allowsHitTesting(false)
        }
    }

    // MARK: RFP list

    @ViewBuilder
    private func rfpList(_ rfps: [RFPManagerAPI.RFP]) -> some View {
        VStack(spacing: Space.s4) {
            if rfps.isEmpty {
                Text("No RFPs match this filter.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.s4)
            } else {
                ForEach(rfps) { rfp in
                    rfpRow(rfp)
                    if selectedRfpId == rfp.id {
                        rfpDetailBlock(rfp)
                    }
                }
            }
        }
    }

    // MARK: Wireframe-canon RFP row (3pt tier rim + spec + 3-stat + lifecycle strip)

    @ViewBuilder
    private func rfpRow(_ rfp: RFPManagerAPI.RFP) -> some View {
        let canonStatus = canonStatus(for: rfp)
        if canonStatus.isCompactClosed {
            rfpCompactRow(rfp)
        } else {
            rfpFullRow(rfp, canon: canonStatus)
        }
    }

    private struct CanonStatus {
        let tier: TierRim
        let pillKind: PillKind
        let pillLegend: String
        let pillWidth: CGFloat
        let stage: RFPStage
        let isCompactClosed: Bool
        enum PillKind { case closingSoon, activeOutlined, awarded, closed, draft }
    }

    private func canonStatus(for rfp: RFPManagerAPI.RFP) -> CanonStatus {
        let s = rfp.status.lowercased()
        let daysLeft = daysUntilDeadline(rfp.responseDeadline)
        switch s {
        case "draft":
            return CanonStatus(tier: .neutral, pillKind: .draft,
                               pillLegend: "DRAFT", pillWidth: 84,
                               stage: .posted, isCompactClosed: false)
        case "published", "in_review":
            if let d = daysLeft, d <= 1 {
                let hours = max(0, hoursUntilDeadline(rfp.responseDeadline) ?? 0)
                return CanonStatus(tier: .warn, pillKind: .closingSoon,
                                   pillLegend: "CLOSING · \(hours)h LEFT",
                                   pillWidth: 148, stage: .bidding,
                                   isCompactClosed: false)
            }
            let legend = daysLeft.map { "ACTIVE · \($0)d" } ?? "ACTIVE"
            return CanonStatus(tier: .gradient, pillKind: .activeOutlined,
                               pillLegend: legend, pillWidth: 84,
                               stage: .bidding, isCompactClosed: false)
        case "awarded":
            return CanonStatus(tier: .success, pillKind: .awarded,
                               pillLegend: "AWARDED", pillWidth: 84,
                               stage: .award, isCompactClosed: false)
        case "closed", "cancelled", "canceled":
            return CanonStatus(tier: .neutral, pillKind: .closed,
                               pillLegend: "CLOSED", pillWidth: 84,
                               stage: .closed, isCompactClosed: true)
        default:
            return CanonStatus(tier: .neutral, pillKind: .closed,
                               pillLegend: rfp.status.uppercased(), pillWidth: 84,
                               stage: .posted, isCompactClosed: false)
        }
    }

    private func daysUntilDeadline(_ iso: String?) -> Int? {
        guard let s = iso, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        guard let date else { return nil }
        let interval = date.timeIntervalSinceNow
        return max(0, Int((interval / 86400).rounded(.up)))
    }

    private func hoursUntilDeadline(_ iso: String?) -> Int? {
        guard let s = iso, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        guard let date else { return nil }
        return max(0, Int(date.timeIntervalSinceNow / 3600))
    }

    @ViewBuilder
    private func rfpFullRow(_ rfp: RFPManagerAPI.RFP, canon: CanonStatus) -> some View {
        Button(action: { tapRow(rfp) }) {
            HStack(spacing: 0) {
                tierRimShape(canon.tier)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text(rfpDisplayId(rfp.id))
                            .font(EType.mono(.micro))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                        statusPillView(kind: canon.pillKind, legend: canon.pillLegend, width: canon.pillWidth)
                    }
                    .padding(.top, Space.s4)

                    Text(laneTitle(rfp))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .padding(.top, Space.s2 + 2)

                    Text(specLine(rfp))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 4)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        statCell(value: "\(rfp.responsesReceived)", unit: "bids", color: palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // EUSO-2117 — low/high bid range pending.
                        statCell(value: "—", unit: "low", color: palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        statCell(value: "—", unit: "high", color: palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, Space.s2 + 2)

                    LifecycleStrip4(activeStage: canon.stage)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(RFPRowStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibility(rfp, canon: canon))
    }

    @ViewBuilder
    private func rfpCompactRow(_ rfp: RFPManagerAPI.RFP) -> some View {
        Button(action: { tapRow(rfp) }) {
            HStack(spacing: 0) {
                tierRimShape(.neutral)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text(rfpDisplayId(rfp.id))
                            .font(EType.mono(.micro))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                        statusPillView(kind: .closed, legend: "CLOSED", width: 84)
                    }
                    .padding(.top, Space.s3 + 2)

                    Text(laneTitle(rfp))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .padding(.top, Space.s2 + 2)

                    Text(closedSubline(rfp))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 4)
                        .padding(.bottom, Space.s3 + 2)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(RFPRowStyle())
        .accessibilityLabel("\(rfpDisplayId(rfp.id)), Closed, \(laneTitle(rfp)), \(closedSubline(rfp))")
    }

    private func rfpDisplayId(_ id: String) -> String {
        // If backend returns a bare RFP id, display as-is. Wireframe
        // canon prefers the `RFP-260427-XXXXXXXXXX` form per §11.2.
        if id.uppercased().hasPrefix("RFP-") { return id }
        return "RFP-\(id)"
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
        guard let first = rfp.lanes.first else { return rfp.title }
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

    private func closedSubline(_ rfp: RFPManagerAPI.RFP) -> String {
        var parts: [String] = []
        parts.append("\(rfp.responsesReceived) bids")
        if let comp = rfp.companyName, !comp.isEmpty {
            parts.append(comp)
        }
        if let pub = rfp.publishedAt {
            parts.append("closed \(shortDate(pub))")
        }
        return parts.joined(separator: " · ")
    }

    private func rowAccessibility(_ rfp: RFPManagerAPI.RFP, canon: CanonStatus) -> String {
        let pill = canon.pillLegend.replacingOccurrences(of: "·", with: ",")
        return "\(rfpDisplayId(rfp.id)), \(pill), \(laneTitle(rfp)), \(specLine(rfp)), \(rfp.responsesReceived) bids"
    }

    @ViewBuilder
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

    @ViewBuilder
    private func tierRimShape(_ kind: TierRim) -> some View {
        switch kind {
        case .gradient:
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.diagonal)
        case .warn:
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.warnGrad)
        case .success:
            RoundedRectangle(cornerRadius: 1.5).fill(Brand.success)
        case .neutral:
            RoundedRectangle(cornerRadius: 1.5).fill(palette.textTertiary)
        }
    }

    // MARK: Status pills (§17.2)

    @ViewBuilder
    private func statusPillView(kind: CanonStatus.PillKind, legend: String, width: CGFloat) -> some View {
        switch kind {
        case .closingSoon:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: width, height: 20)
                .background(Capsule().fill(LinearGradient.warnGrad))
        case .activeOutlined:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(LinearGradient.primary)
                .frame(width: width, height: 20)
                .overlay(Capsule().strokeBorder(LinearGradient.primary, lineWidth: 1))
                .background(Capsule().fill(palette.bgCard))
        case .awarded:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: width, height: 20)
                .background(Capsule().fill(Brand.success))
        case .closed:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textSecondary)
                .frame(width: width, height: 20)
                .overlay(Capsule().strokeBorder(palette.textTertiary, lineWidth: 1))
                .background(Capsule().fill(palette.bgCard))
        case .draft:
            Text(legend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textSecondary)
                .frame(width: width, height: 20)
                .overlay(Capsule().strokeBorder(palette.textTertiary, lineWidth: 1))
                .background(Capsule().fill(palette.bgCardSoft))
        }
    }

    // MARK: "+ New RFP" gradient ribbon CTA

    private var newRFPButton: some View {
        Button(action: tapNewRFP) {
            Text("+ New RFP")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(LinearGradient.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create a new RFP")
    }

    // MARK: Inline detail (lanes + bids + scoring)

    @ViewBuilder
    private func rfpDetailBlock(_ rfp: RFPManagerAPI.RFP) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Detail header (publish CTA on draft)
            HStack(spacing: 8) {
                Text("RFP DETAIL")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if rfp.status.lowercased() == "draft" {
                    publishButton(rfp)
                }
            }
            if let desc = rfp.description, !desc.isEmpty {
                Text(desc)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            detailStatsGrid(rfp)
            laneListCard(rfp)
            if !store.bids.isEmpty {
                bidListCard(rfp)
            }
            if !store.scorecards.isEmpty {
                scoringSection(rfp)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func detailStatsGrid(_ rfp: RFPManagerAPI.RFP) -> some View {
        let req = rfp.carrierRequirements
        return HStack(spacing: Space.s2) {
            statTile(label: "DEADLINE",   value: shortDate(rfp.responseDeadline))
            statTile(label: "CONTRACT",   value: shortDate(rfp.contractStartDate))
            statTile(label: "MIN SAFETY", value: req?.minSafetyScore.map { "\($0)%" } ?? "—", tint: Brand.success)
            statTile(label: "MIN ON-TIME", value: req?.minOnTimeRate.map { "\($0)%" } ?? "—", tint: Brand.info)
        }
    }

    private func statTile(label: String, value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(tint ?? palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func publishButton(_ rfp: RFPManagerAPI.RFP) -> some View {
        let busy = (store.mutatingRfpId == rfp.id)
        return Button {
            Task {
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                _ = await store.publish(rfpId: rfp.id)
            }
        } label: {
            HStack(spacing: 4) {
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11, weight: .heavy))
                }
                Text("Publish")
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 6)
            .background(Capsule().fill(LinearGradient.diagonal))
        }
        .buttonStyle(RFPRowStyle())
        .disabled(busy)
    }

    private func laneListCard(_ rfp: RFPManagerAPI.RFP) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("LANES")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(rfp.lanes.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 4) {
                ForEach(rfp.lanes) { lane in
                    laneRow(lane)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func laneRow(_ lane: RFPManagerAPI.Lane) -> some View {
        HStack(spacing: 6) {
            Text(lane.id)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 48, alignment: .leading)
            HStack(spacing: 4) {
                Text("\(lane.origin.city), \(lane.origin.state)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text("\(lane.destination.city), \(lane.destination.state)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(lane.estimatedDistance) mi")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
            Text(lane.equipmentRequired.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.info)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(Brand.info.opacity(0.15)))
            if lane.hazmat == true {
                Text("HZM")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.danger)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Brand.danger.opacity(0.15)))
            }
            if let target = lane.targetRate {
                Text("$\(formatThousands(target))")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Brand.success)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(palette.bgCardSoft.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func bidListCard(_ rfp: RFPManagerAPI.RFP) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text("BID RESPONSES")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(store.bids.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: Space.s2) {
                ForEach(store.bids) { bid in
                    bidRow(bid, rfp: rfp)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func bidRow(_ bid: RFPManagerAPI.BidResponse, rfp: RFPManagerAPI.RFP) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "truck.box.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textSecondary)
                Text(bid.carrierName)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                if let tier = bid.carrierTier {
                    Text(tier.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(tierColor(tier, palette: palette))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().strokeBorder(tierColor(tier, palette: palette).opacity(0.5), lineWidth: 0.75))
                }
                Spacer(minLength: 0)
                bidMeta(bid)
            }
            HStack(spacing: 4) {
                ForEach(bid.laneBids.prefix(3)) { lb in
                    laneBidChip(lb)
                }
                if bid.laneBids.count > 3 {
                    Text("+\(bid.laneBids.count - 3)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s2)
        .background(palette.bgCardSoft.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func bidMeta(_ bid: RFPManagerAPI.BidResponse) -> some View {
        HStack(spacing: 6) {
            if let s = bid.safetyScore {
                bidMetaChip(icon: "shield.fill", value: "\(s)")
            }
            if let o = bid.onTimeRate {
                bidMetaChip(icon: "clock.fill", value: "\(o)%")
            }
            if let f = bid.fleetSize {
                bidMetaChip(icon: "truck.box", value: "\(f)")
            }
        }
    }

    private func bidMetaChip(icon: String, value: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 8, weight: .heavy))
            Text(value).font(.system(size: 9, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(palette.textSecondary)
    }

    private func laneBidChip(_ lb: RFPManagerAPI.LaneBid) -> some View {
        VStack(spacing: 1) {
            Text(lb.laneId)
                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            Text("$\(formatThousands(lb.bidRate))")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Brand.success)
            HStack(spacing: 3) {
                if let d = lb.transitDays {
                    Text("\(d)d")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
                if let c = lb.capacityPerWeek {
                    Text("\(c)/wk")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(minWidth: 56)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func scoringSection(_ rfp: RFPManagerAPI.RFP) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SCORING & AWARDS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(store.scorecards.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: Space.s2) {
                ForEach(Array(store.scorecards.enumerated()), id: \.element.id) { idx, sc in
                    scorecardRow(rank: idx + 1, scorecard: sc, rfp: rfp)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func scorecardRow(rank: Int, scorecard sc: RFPManagerAPI.Scorecard, rfp: RFPManagerAPI.RFP) -> some View {
        let rec = recommendationStyle(sc.recommendation)
        let isWinner = (rank == 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Space.s3) {
                rankBadge(rank: rank, isWinner: isWinner)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(sc.carrierName)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        if let tier = sc.carrierTier {
                            Text(tier.uppercased())
                                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(tierColor(tier, palette: palette))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().strokeBorder(tierColor(tier, palette: palette).opacity(0.5), lineWidth: 0.75))
                        }
                    }
                    HStack(spacing: 3) {
                        Image(systemName: rec.icon)
                            .font(.system(size: 10, weight: .heavy))
                        Text(rec.label)
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    }
                    .foregroundStyle(rec.color)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(sc.overallScore)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text("OVERALL")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                if sc.recommendation.lowercased() == "award" {
                    awardButton(scorecard: sc, rfpId: rfp.id)
                }
            }
            HStack(spacing: 4) {
                scoreDim(label: "RATE",  value: sc.rateScore,         tint: Brand.success)
                scoreDim(label: "SVC",   value: sc.serviceLevelScore, tint: Brand.info)
                scoreDim(label: "SAFETY", value: sc.safetyScore,       tint: .purple)
                scoreDim(label: "CAP",   value: sc.capacityScore,     tint: Brand.info)
                scoreDim(label: "EXP",   value: sc.experienceScore,   tint: Brand.warning)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isWinner
                ? AnyShapeStyle(LinearGradient(
                    colors: [Brand.success.opacity(0.18), Brand.blue.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
                : AnyShapeStyle(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    isWinner
                        ? Brand.success.opacity(0.55)
                        : palette.borderFaint,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func rankBadge(rank: Int, isWinner: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isWinner
                      ? AnyShapeStyle(LinearGradient.diagonal)
                      : AnyShapeStyle(palette.bgCardSoft))
            Text("#\(rank)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(isWinner ? .white : palette.textPrimary)
        }
        .frame(width: 32, height: 32)
    }

    private func awardButton(scorecard sc: RFPManagerAPI.Scorecard, rfpId: String) -> some View {
        Button {
            Task {
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                _ = await store.award(rfpId: rfpId, laneId: "ALL", carrierId: sc.carrierId)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 11, weight: .heavy))
                Text("Award")
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 6)
            .background(Capsule().fill(LinearGradient.diagonal))
        }
        .buttonStyle(RFPRowStyle())
    }

    private func scoreDim(label: String, value: Int, tint: Color) -> some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.borderFaint.opacity(0.5)).frame(height: 4)
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(100, max(0, value))) / 100, height: 4)
                }
            }
            .frame(height: 4)
            Text(label)
                .font(.system(size: 7, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text("\(value)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Empty + error states

    private var emptyHero: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(LinearGradient.diagonal)
            Text("No active RFPs")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text("Create your first lane RFP and distribute it to your carrier panel — bids land here for review and award.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s4)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: tapNewRFP) {
                Text("+ New RFP")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s5)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorBanner(_ msg: String) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("RFP service offline")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Notification posts (§20.4)

    private func tapFilter(_ f: RFPFilter) {
        withAnimation(.easeOut(duration: 0.18)) { filter = f }
        NotificationCenter.default.post(
            name: .eusoShipperRfpFilter,
            object: nil,
            userInfo: [
                "source": "215_ShipperRFP",
                "filter": f.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapRow(_ rfp: RFPManagerAPI.RFP) {
        let isOpen = (selectedRfpId == rfp.id)
        selectedRfpId = isOpen ? nil : rfp.id
        NotificationCenter.default.post(
            name: .eusoShipperRfpRow,
            object: nil,
            userInfo: [
                "source": "215_ShipperRFP",
                "rfpId": rfp.id,
                "expanded": !isOpen,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapNewRFP() {
        // Founder doctrine 2026-05-07: keep the RFP composer
        // IN-APP. The mailto:bids@eusotrip.com hand-off is gone.
        // The composer sheet (`showNewRFPComposer`) collects
        // lanes / equipment / volume / award date and submits
        // to `rfp.create` server-side.
        NotificationCenter.default.post(
            name: .eusoShipperRfpCreate,
            object: nil,
            userInfo: [
                "source": "215_ShipperRFP",
                "shipperCompanyId": 1
            ]
        )
        showNewRFPComposer = true
    }

    // MARK: Helpers

    private func shortDate(_ iso: String?) -> String {
        guard let s = iso, !s.isEmpty else { return "—" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        guard let date else { return s }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: date)
    }

    private func formatThousands(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "%.0fk", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - 4-stage RFP lifecycle strip (§15.2 · file-scoped per §19.2)

private struct LifecycleStrip4: View {
    let activeStage: RFPStage
    @Environment(\.palette) var palette

    private let stages: [(key: RFPStage, label: String)] = [
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

// MARK: - Warn gradient (§19.2 file-scoped)

private extension LinearGradient {
    static let warnGrad = LinearGradient(
        colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - RFP row press feedback

private struct RFPRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Filter chip tap — All / Active / Awarded / Closed / Drafts.
    static let eusoShipperRfpFilter = Notification.Name("eusoShipperRfpFilter")
    /// RFP row tap — toggles inline detail expansion.
    static let eusoShipperRfpRow    = Notification.Name("eusoShipperRfpRow")
    /// "+ New RFP" gradient ribbon tap.
    static let eusoShipperRfpCreate = Notification.Name("eusoShipperRfpCreate")
}

// MARK: - Previews

#Preview("215 · Shipper RFP · Dark") {
    ShipperRFP()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("215 · Shipper RFP · Light") {
    ShipperRFP()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}

// MARK: - In-app RFP composer (founder doctrine 2026-05-07)
//
// Replaces the prior `mailto:bids@eusotrip.com` hand-off. Collects
// the canonical RFP fields (origin / destination / equipment /
// volume / start date / award date / notes) and submits via the
// shippers / RFP routers. When the dedicated `rfp.create` endpoint
// ships server-side, swap the mutation key here; until then we
// fall through to a NotificationCenter post the web platform's
// existing inbox listener picks up.

struct NewRFPComposerSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let onClose: (Bool) -> Void

    @State private var origin: String = ""
    @State private var destination: String = ""
    @State private var equipment: String = "Dry van"
    @State private var monthlyVolume: String = ""
    @State private var startDate: Date = Date()
    @State private var awardDate: Date = Date().addingTimeInterval(7 * 24 * 3600)
    @State private var notes: String = ""
    @State private var submitting: Bool = false
    @State private var submitError: String? = nil

    private let equipmentOptions = ["Dry van", "Reefer", "Flatbed", "Step deck", "Container", "Tanker", "Power-only"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New RFP")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Lanes · Equipment · Volume · Award date")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Button { onClose(false) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(Space.s5)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    laneSection
                    equipmentSection
                    volumeSection
                    scheduleSection
                    notesSection
                    if let err = submitError {
                        Text(err)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    submitButton
                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, Space.s5)
            }
        }
        .background(palette.bgPrimary)
    }

    private var laneSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LANE").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 0) {
                composerField(label: "ORIGIN", text: $origin, placeholder: "City, ST")
                Divider().background(palette.borderFaint)
                composerField(label: "DESTINATION", text: $destination, placeholder: "City, ST")
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EQUIPMENT").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(equipmentOptions, id: \.self) { opt in
                        Button { equipment = opt } label: {
                            Text(opt)
                                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(equipment == opt ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textSecondary))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Capsule().fill(equipment == opt ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)))
                                .overlay(Capsule().strokeBorder(equipment == opt ? AnyShapeStyle(.clear) : AnyShapeStyle(palette.borderFaint)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MONTHLY VOLUME").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(LinearGradient.diagonal)
                TextField("Loads / month", text: $monthlyVolume)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .keyboardType(.numberPad)
                    .tint(LinearGradient.diagonal)
                Text("loads/mo").font(EType.caption).foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SCHEDULE").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            HStack(spacing: 10) {
                DatePicker("Start", selection: $startDate, displayedComponents: [.date])
                    .datePickerStyle(.compact)
                    .tint(LinearGradient.diagonal)
                DatePicker("Award", selection: $awardDate, in: startDate..., displayedComponents: [.date])
                    .datePickerStyle(.compact)
                    .tint(LinearGradient.diagonal)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES (OPTIONAL)").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            TextEditor(text: $notes)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .frame(minHeight: 90)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if submitting { ProgressView().tint(.white).scaleEffect(0.85) }
                Image(systemName: "paperplane.fill").font(.system(size: 12, weight: .heavy))
                Text(submitting ? "Submitting…" : "Submit RFP")
                    .font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(LinearGradient.diagonal)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(submitting || origin.isEmpty || destination.isEmpty || monthlyVolume.isEmpty)
    }

    private func composerField(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label).font(EType.micro).tracking(0.4).foregroundStyle(palette.textTertiary).frame(width: 96, alignment: .leading)
            TextField(placeholder, text: text)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .tint(LinearGradient.diagonal)
        }
        .padding(Space.s3)
    }

    private func submit() async {
        submitting = true
        submitError = nil
        defer { submitting = false }
        // Server-side `rfp.create` is the canonical mutation; until
        // it lands in iOS API, post via NotificationCenter so the
        // web platform's RFP inbox listener picks it up via the
        // shared session cookie. Doctrine: never mailto.
        struct In: Encodable {
            let origin: String
            let destination: String
            let equipmentType: String
            let monthlyVolume: Int
            let startDate: String
            let awardDate: String
            let notes: String?
        }
        struct Out: Decodable { let id: Int? }
        let iso = ISO8601DateFormatter()
        let input = In(
            origin: origin,
            destination: destination,
            equipmentType: equipment,
            monthlyVolume: Int(monthlyVolume) ?? 0,
            startDate: iso.string(from: startDate),
            awardDate: iso.string(from: awardDate),
            notes: notes.isEmpty ? nil : notes
        )
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("rfp.create", input: input)
            onClose(true)
        } catch {
            submitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
