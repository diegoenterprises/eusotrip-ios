//
//  215_ShipperRFP.swift
//  EusoTrip 2027 UI — brick 215 (shipper · RFP / procurement)
//
//  Procurement workflow — list active RFPs, drill into one to view
//  lanes + bid responses + scored recommendations, publish drafts,
//  award lanes to winning carriers. Mirrors web `/rfp-manager`
//  (`RFPManagerPage.tsx`) 1:1, backed by `rfpManager.*` tRPC procs.
//
//  Cohort B day-1 — fully dynamic. No fixtures.
//
//    • RFP list                → `rfpManager.getRFPs`
//    • RFP detail (lanes)      → folded into `getRFPs` envelope
//    • Bid responses           → `rfpManager.getBidResponses(rfpId)`
//    • Scored recommendations  → `rfpManager.scoreResponses(rfpId)`
//    • Publish draft           → `rfpManager.publishRFP(rfpId)`
//    • Award lane              → `rfpManager.awardLane(rfpId, laneId, carrierId)`
//
//  Tab structure (matches web peer):
//    • RFPs & Bids   — list + detail + bid responses
//    • Scoring & Awards — ranked scorecards with award CTA
//
//  RFP CREATION is intentionally NOT wired on this brick — the
//  multi-lane wizard is a heavy form best done on web for now. iOS
//  surfaces a "Create on web" disclosure on the empty state. A
//  future brick (215b ShipperRFPCreate) can land the form when the
//  shipper-side iOS demand justifies the build.
//
//  Design doctrine (per Driver Figma 010-103):
//    §1   Status pills with color-keyed background + 1px tinted
//         stroke. Recommendation chips with leading icon.
//    §2   `.easeOut(0.12)` press scale on every CTA. Success haptic
//         on publish + award.
//    §4   Tokenized Space/Radius/EType.
//    §5   Palette semantic. Status colors:
//         draft→neutral, published→info, in_review→warning,
//         awarded→success, closed→neutral, cancelled→danger.
//    §10  Dark + Light previews compile in isolation under .empty.
//
//  Powered by ESANG AI™.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Status helpers (file-local so they don't pollute the ViewModel namespace)

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = ShipperRFPStore()

    @State private var selectedRfpId: String?
    @State private var tab: Tab = .rfps

    private enum Tab: String, CaseIterable, Identifiable {
        case rfps, scoring
        var id: String { rawValue }
        var label: String { self == .rfps ? "RFPs & Bids" : "Scoring & Awards" }
        var icon: String { self == .rfps ? "doc.text.fill" : "chart.bar.fill" }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                tabPicker
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
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
            value: tab
        )
        .onChange(of: selectedRfpId) { _, newId in
            guard let id = newId else { return }
            Task { await store.loadDetail(for: id) }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text.below.ecg.fill")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · RFP MANAGER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Procurement & awards")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("Distribute lane RFPs, collect bids, score carriers across rate · service · safety · capacity · experience.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: Tab picker

    private var tabPicker: some View {
        HStack(spacing: Space.s2) {
            ForEach(Tab.allCases) { t in
                tabButton(t)
            }
        }
    }

    private func tabButton(_ t: Tab) -> some View {
        let active = (tab == t)
        return Button {
            tab = t
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        } label: {
            HStack(spacing: 6) {
                Image(systemName: t.icon)
                    .font(.system(size: 11, weight: .heavy))
                Text(t.label)
                    .font(EType.bodyStrong)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity)
            .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(active
                          ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                          : AnyShapeStyle(palette.bgCard))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                        .frame(height: 88)
                }
            }
        case .empty:
            emptyHero
        case .error(let msg):
            errorBanner(msg)
        case .loaded(let rfps):
            switch tab {
            case .rfps:
                rfpsAndBidsTab(rfps: rfps)
            case .scoring:
                scoringTab(rfps: rfps)
            }
        }
    }

    private var emptyHero: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(LinearGradient.diagonal)
            Text("No active RFPs")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text("Create your first lane RFP on web and distribute it to your carrier panel — bids land here for review and award.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s4)
                .fixedSize(horizontal: false, vertical: true)
            Text("eusotrip.com/rfp-manager")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(LinearGradient.diagonal)
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

    // MARK: RFPs & Bids tab

    private func rfpsAndBidsTab(rfps: [RFPManagerAPI.RFP]) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("YOUR RFPS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                VStack(spacing: Space.s2) {
                    ForEach(rfps) { rfp in
                        rfpRow(rfp)
                    }
                }
            }

            if let active = rfps.first(where: { $0.id == selectedRfpId }) {
                rfpDetailBlock(active)
            }
        }
    }

    private func rfpRow(_ rfp: RFPManagerAPI.RFP) -> some View {
        let style = statusStyle(for: rfp.status, palette: palette)
        let isSelected = (selectedRfpId == rfp.id)
        return Button {
            selectedRfpId = isSelected ? nil : rfp.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(rfp.id)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 0)
                    statusPill(style)
                }
                Text(rfp.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    chipMini(icon: "mappin.and.ellipse", value: "\(rfp.lanes.count) lanes")
                    chipMini(icon: "person.2.fill",       value: "\(rfp.distributedTo) carriers")
                    chipMini(icon: "tray.full.fill",      value: "\(rfp.responsesReceived) bids")
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.10))
                    : AnyShapeStyle(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.55))
                            : AnyShapeStyle(palette.borderFaint),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(RFPRowStyle())
    }

    private func statusPill(_ s: StatusStyle) -> some View {
        Text(s.label.uppercased())
            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundStyle(s.color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(s.color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(s.color.opacity(0.4), lineWidth: 0.75))
    }

    private func chipMini(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
            Text(value)
                .font(.system(size: 10, weight: .heavy)).tracking(0.3)
        }
        .foregroundStyle(palette.textTertiary)
    }

    // MARK: RFP detail (when a row is selected)

    @ViewBuilder
    private func rfpDetailBlock(_ rfp: RFPManagerAPI.RFP) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Detail header — stats + publish CTA on draft RFPs.
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("RFP DETAIL")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    if rfp.status.lowercased() == "draft" {
                        publishButton(rfp)
                    }
                }
                Text(rfp.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                if let desc = rfp.description, !desc.isEmpty {
                    Text(desc)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                detailStatsGrid(rfp)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            // Lanes
            laneListCard(rfp)

            // Bids
            if !store.bids.isEmpty {
                bidListCard(rfp)
            }
        }
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
            // Per-lane bid rates
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

    // MARK: Scoring tab

    private func scoringTab(rfps: [RFPManagerAPI.RFP]) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            // RFP selector chips for the scoring tab.
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("SCORING FOR")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(rfps) { rfp in
                            scoringRfpChip(rfp)
                        }
                    }
                }
            }

            if selectedRfpId == nil {
                Text("Pick an RFP above to score its bids.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s3)
            } else if store.scorecards.isEmpty {
                noBidsCard
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(Array(store.scorecards.enumerated()), id: \.element.id) { idx, sc in
                        scorecardRow(rank: idx + 1, scorecard: sc)
                    }
                }
            }
        }
    }

    private func scoringRfpChip(_ rfp: RFPManagerAPI.RFP) -> some View {
        let active = (selectedRfpId == rfp.id)
        return Button {
            selectedRfpId = rfp.id
        } label: {
            Text(rfp.id)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .foregroundStyle(active ? .white : palette.textSecondary)
                .background(
                    Capsule().fill(active
                                   ? AnyShapeStyle(LinearGradient.diagonal)
                                   : AnyShapeStyle(palette.bgCard))
                )
                .overlay(
                    Capsule().strokeBorder(active ? Color.clear : palette.borderFaint, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var noBidsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(palette.textTertiary)
            Text("No bids to score yet")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("Once carriers respond to this RFP, their scorecards land here.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
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

    private func scorecardRow(rank: Int, scorecard sc: RFPManagerAPI.Scorecard) -> some View {
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
                    awardButton(scorecard: sc)
                }
            }
            // Score breakdown 5-dim row
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

    private func awardButton(scorecard sc: RFPManagerAPI.Scorecard) -> some View {
        Button {
            guard let rfpId = selectedRfpId else { return }
            // Award all lanes ("ALL" sentinel) — server interprets
            // this as a sweep; per-lane awards land via the iOS lane
            // detail flow once that's wired.
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

// MARK: - RFP row press feedback

private struct RFPRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("215 · Shipper RFP · Night") {
    ShipperRFP()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("215 · Shipper RFP · Afternoon") {
    ShipperRFP()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
