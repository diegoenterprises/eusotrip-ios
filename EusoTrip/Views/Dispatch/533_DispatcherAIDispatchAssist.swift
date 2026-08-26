//
//  533_DispatcherAIDispatchAssist.swift
//  EusoTrip — Dispatcher · Dispatch Autopilot.
//
//  Verbatim SwiftUI port of:
//    `04 Dispatcher/Dark-SVG/533 Dispatcher AI Dispatch Assist.svg`
//
//  THE DISPATCH AUTOPILOT BOARD — ESANG ranks every unassigned load against the
//  available driver pool (HOS clock, lane fit, equipment match, deadhead)
//  and presents the dispatcher a single decisive surface: a confidence
//  hero, a RECOMMENDED / AUTO-MATCH / NEEDS-REVIEW triplet, the ranked TOP
//  RECOMMENDATIONS rows, and a one-pass BULK apply for the HOS-safe
//  auto-matches. Reached from the Board (401) as the Autopilot surface.
//
//  Reads ONE real server endpoint — no stubs, no mock data:
//    aiDispatchAssist.getBoardRecommendations   (added in the §44 fire —
//    see INTEGRATION.md in this staging folder). Returns the KPI summary,
//    the ranked recommendation rows (each pending load + its BEST driver
//    match + score + auto/review classification + HOS state + rate), and a
//    bulk-apply manifest. RBAC-gated with `dispatchProcedure`.
//    Distinct from recommendAssignments (per-load) and bulkRecommend
//    (loads with no driver match) — neither could feed a board. Replaces a
//    reliance on the empty dispatchRole.getAIRecommendations stub.
//
//  Honest-wire policy:
//    • the read flows through a real do/catch with a surfaced
//      `actionError`; if the procedure is not yet deployed the screen shows
//      the error state, never a fake "success" with mock rows.
//    • APPLY RECOMMENDATIONS sends one `dispatch.smartBulkAssign` intent.
//      The server recomputes tenant, HOS, location, equipment, and HERE
//      evidence immediately before each commit and returns a result per load.
//    • a single row taps into the per-load assign flow (532 Assign Driver
//      M05) via the real `.eusoDispatchNavSwap` event RoleSurfaceRouter
//      observes. REVIEW routes to the board (401). No dead taps.
//    • match score, classification, HOS label, and rate are all server
//      values — never fabricated client-side.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: ─────────────────────────────────────────────────────────
// MARK: Decoders — field-for-field match to aiDispatchAssist.getBoardRecommendations
// MARK: ─────────────────────────────────────────────────────────

private struct AIRec: Decodable, Hashable, Identifiable {
    let id: String
    let loadId: Int
    let loadNumber: String?
    let driverId: Int?           // drivers.id → dispatch.smartBulkAssign
    let driverUserId: Int?       // users.id (display / HOS only)
    let driverName: String?
    let initials: String?
    let lane: String?            // "LA → PHX"
    let equipment: String?       // "reefer" / "53′ Dry" / cargo
    let vehicleId: Int?
    let vehicleUnit: String?     // real plate or "Unit <id>"; nil when none
    let matchScore: Int?         // 0–100; nil when no eligible match exists
    let classification: String   // "auto" | "review" | "unavailable"
    let hosState: String         // "safe" | "tight" | "unknown"
    let hosLabel: String?        // "HOS-safe" | "HOS tight" | nil
    let hosFreshness: String?
    let locationFreshness: String?
    let rate: String?            // "$2,200"
    let transportMode: String?
    let suggestionState: String
    let unavailableReason: String?
    let routeSource: String?

    func hasReadyEvidence(now: Date = Date()) -> Bool {
        guard suggestionState == "ready",
              classification == "auto" || classification == "review",
              let driverId, driverId > 0,
              let vehicleId, vehicleId > 0,
              let matchScore, (0...100).contains(matchScore),
              hosState == "safe",
              routeSource?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              HOSObservationClock.freshness(hosFreshness, now: now).isCurrent,
              HOSObservationClock.freshness(
                locationFreshness,
                now: now,
                maximumAge: 30 * 60
              ).isCurrent else {
            return false
        }
        return true
    }
}

private struct AISummary: Decodable, Hashable {
    let loadsToAssign: Int
    let autoMatched: Int
    let needsReview: Int
    let unavailable: Int?
    let avgConfidence: Int?
}

private struct AIBulk: Decodable, Hashable {
    let autoCount: Int
    let reviewCount: Int
    let eligibleLoadIds: [Int]
}

private struct AIBoardResponse: Decodable {
    let state: String
    let source: String
    let freshness: String?
    let summary: AISummary
    let recommendations: [AIRec]
    let bulk: AIBulk
    let generatedAt: String?

    func hasCurrentEvidence(now: Date = Date()) -> Bool {
        state == "current"
            && source == "smart_assign"
            && HOSObservationClock.freshness(freshness, now: now).isCurrent
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Screen
// MARK: ─────────────────────────────────────────────────────────

struct DispatcherAIDispatchAssistScreen: View {
    let theme: Theme.Palette
    var body: some View {
        // Per the wireframe <desc>: BOARD is the current bottom-nav tab.
        Shell(theme: theme) { DispatcherAIDispatchAssistBody() } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

private struct DispatcherAIDispatchAssistBody: View {
    @Environment(\.palette) private var palette

    @State private var response: AIBoardResponse?

    @State private var loading: Bool = true
    @State private var actionError: String?
    @State private var applying: Bool = false
    @State private var applyNote: String?       // honest result of the bulk apply

    private var summary: AISummary? { response?.summary }
    private var recs: [AIRec] { response?.recommendations ?? [] }
    private var bulk: AIBulk? { response?.bulk }
    private var boardEvidenceIsCurrent: Bool { response?.hasCurrentEvidence() == true }

    /// The server's eligible IDs are necessary but not sufficient at display
    /// time. Recheck every surfaced evidence timestamp and keep driver IDs
    /// unique so the batch cannot fail schema validation before revalidation.
    private var actionableAutos: [AIRec] {
        guard boardEvidenceIsCurrent, let eligible = bulk?.eligibleLoadIds else { return [] }
        let eligibleIds = Set(eligible)
        var seenDriverIds = Set<Int>()
        return recs.filter { rec in
            guard rec.classification == "auto",
                  eligibleIds.contains(rec.loadId),
                  rec.hasReadyEvidence(),
                  let driverId = rec.driverId,
                  seenDriverIds.insert(driverId).inserted else {
                return false
            }
            return true
        }
    }

    // The card shows the first 3 ranked rows; the rest are summarized as "+ N more".
    private var topRows: [AIRec] { Array(recs.prefix(3)) }
    private var moreCount: Int { max(0, recs.count - topRows.count) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline().padding(.top, Space.s3)

                if loading {
                    loadingState
                } else if let err = actionError {
                    errorState(err)
                } else {
                    heroCard
                    kpiTriplet
                    topRecommendations
                    bulkStrip
                    if let note = applyNote { applyResult(note) }
                    ctaPair
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .eusoRefreshTask { await load() }
    }

    // MARK: Top bar (back chevron + eyebrow + mono caption + title + kebab)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                EusoTripEyebrow(verbatim: "DISPATCHER · AUTOPILOT")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text(summary.map { "\($0.loadsToAssign) OPEN" } ?? "— OPEN")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textSecondary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Text("Dispatch Autopilot")
                    .font(EType.h1).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: Hero — confidence card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                chip(boardEvidenceIsCurrent ? "current evidence" : "evidence unavailable")
                chip(response?.source ?? "source unavailable")
                Spacer(minLength: 0)
            }
            HStack(alignment: .top) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(summary.map { String($0.loadsToAssign) } ?? "—")
                        .font(.system(size: 30, weight: .bold, design: .default).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("loads to assign")
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text(summary.map {
                            "\($0.autoMatched) auto-matched · \($0.needsReview) review"
                        } ?? "Recommendation counts unavailable")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: Space.s3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONFIDENCE")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                    Text(summary?.avgConfidence.map { "\($0)%" } ?? "—")
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text("avg match")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20).fill(palette.bgCardSoft)
        )
        .overlay(
            // cardRim gradient rim (0.85 opacity gradient hairline).
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(LinearGradient.diagonal.opacity(0.85), lineWidth: 1.5)
        )
        .padding(.top, Space.s5)
    }

    private func chip(_ label: String) -> some View {
        Text(label)
            .font(EType.micro).tracking(0.5)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, Space.s3).frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    // MARK: KPI triplet

    private var kpiTriplet: some View {
        HStack(spacing: Space.s3) {
            kpiCell("RECOMMENDED", response.map { $0.recommendations.count }, tint: palette.textOnGradient, filled: true)
            kpiCell("AUTO-MATCH", summary?.autoMatched, tint: Brand.success, filled: false)
            kpiCell("NEEDS REVIEW", summary?.needsReview, tint: Brand.warning, filled: false)
        }
        .padding(.top, Space.s4)
    }

    private func kpiCell(_ label: String, _ value: Int?, tint: Color, filled: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(label)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(filled ? palette.textOnGradient.opacity(0.85) : palette.textSecondary)
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .frame(height: 72)
        .background {
            if filled {
                RoundedRectangle(cornerRadius: 16).fill(LinearGradient.diagonal)
            } else {
                RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft)
                RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1)
            }
        }
    }

    // MARK: Top recommendations

    private var topRecommendations: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TOP RECOMMENDATIONS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("\(recs.count) ranked")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s2)

            VStack(spacing: 0) {
                if topRows.isEmpty {
                    emptyRows
                } else {
                    ForEach(Array(topRows.enumerated()), id: \.element.id) { idx, r in
                        RecommendationRow(
                            rec: r,
                            isActionable: boardEvidenceIsCurrent && r.hasReadyEvidence()
                        ) { tapRow(r) }
                        if idx < topRows.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                    Text("+ \(moreCount) more · ranked from sourced HOS, location, equipment, and route evidence")
                        .font(EType.micro)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.s4)
                }
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
        .padding(.top, Space.s5)
    }

    private var emptyRows: some View {
        VStack(spacing: Space.s2) {
            Text("No loads waiting on a driver")
                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("The board is fully assigned. ESANG will surface new loads as they post.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s6)
        .padding(.horizontal, Space.s4)
    }

    // MARK: Bulk strip

    private var bulkStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("BULK RECOMMEND")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("\(actionableAutos.count) ready")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("Apply \(actionableAutos.count) evidence-backed auto-matches in one request")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(max(0, recs.count - actionableAutos.count)) held · eligibility is revalidated at commit")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1))
        .padding(.top, Space.s4)
    }

    private func applyResult(_ note: String) -> some View {
        Text(note)
            .font(EType.caption)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Space.s3)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await applyAll() } } label: {
                HStack(spacing: Space.s2) {
                    if applying { ProgressView().tint(palette.textOnGradient) }
                    Text(applying ? "Applying…" : "Apply recommendations")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textOnGradient)
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(applying || actionableAutos.isEmpty)
            .opacity(actionableAutos.isEmpty ? 0.5 : 1)

            Button { review() } label: {
                Text("Review")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Color(hex: 0x232932)))
            }
            .buttonStyle(.plain)
            .disabled(applying)
        }
        .padding(.top, Space.s5)
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 20).fill(palette.bgCardSoft).frame(height: 116)
            HStack(spacing: Space.s3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft).frame(height: 72)
                }
            }
            RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft).frame(height: 252)
        }
        .redacted(reason: .placeholder)
        .padding(.top, Space.s5)
    }

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Couldn't load Autopilot recommendations").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            Button { Task { await load() } } label: {
                Text("Retry").font(EType.caption.weight(.heavy))
                    .foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, Space.s4).frame(height: 32)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .padding(.top, Space.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .padding(.top, Space.s5)
    }

    // MARK: Data + actions

    private func load(preserveApplyNote: Bool = false) async {
        loading = true
        actionError = nil
        if !preserveApplyNote { applyNote = nil }
        do {
            let r: AIBoardResponse = try await EusoTripAPI.shared.queryNoInput("aiDispatchAssist.getBoardRecommendations")
            response = r
        } catch {
            actionError = "Recommendations could not refresh. Retry from this screen or open the dispatch board."
        }
        loading = false
    }

    // Submit one intent batch. The authoritative mutation recomputes all
    // mutable evidence before each write and returns a result for every load.
    private func applyAll() async {
        let autos = actionableAutos
        guard !autos.isEmpty else { return }
        applying = true
        defer { applying = false }
        applyNote = nil

        struct Assignment: Encodable {
            let loadId: Int
            let driverId: Int
        }
        struct Input: Encodable { let assignments: [Assignment] }
        struct Result: Decodable {
            let loadId: Int
            let success: Bool
            let error: String?
        }
        struct Output: Decodable {
            let assigned: Int
            let failed: Int
            let results: [Result]
        }

        let assignments = autos.compactMap { rec -> Assignment? in
            guard let driverId = rec.driverId else { return nil }
            return Assignment(loadId: rec.loadId, driverId: driverId)
        }
        guard assignments.count == autos.count else {
            applyNote = "Assignment evidence changed before submission. Refresh Autopilot and review the batch."
            return
        }

        do {
            let output: Output = try await EusoTripAPI.shared.mutation(
                "dispatch.smartBulkAssign",
                input: Input(assignments: assignments)
            )
            let requestedIds = Set(autos.map(\.loadId))
            var resultByLoad: [Int: Result] = [:]
            for result in output.results where requestedIds.contains(result.loadId) {
                resultByLoad[result.loadId] = result
            }

            let confirmed = autos.filter { resultByLoad[$0.loadId]?.success == true }
            let held: [String] = autos.compactMap { rec in
                guard let result = resultByLoad[rec.loadId] else {
                    return "\(rec.loadNumber ?? "Load \(rec.loadId)"): no result returned"
                }
                guard !result.success else { return nil }
                let reason = result.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                let detailReason: String
                if let reason, !reason.isEmpty {
                    detailReason = reason
                } else {
                    detailReason = "evidence changed"
                }
                return "\(rec.loadNumber ?? "Load \(rec.loadId)"): \(detailReason)"
            }
            let countMismatch = output.assigned != confirmed.count
                || output.failed != held.count
                || output.results.count != autos.count
            let resultNote: String
            if held.isEmpty && !countMismatch {
                resultNote = "Confirmed \(confirmed.count) assignment\(confirmed.count == 1 ? "" : "s") after server evidence revalidation."
            } else {
                let detail = held.prefix(2).joined(separator: " · ")
                let suffix = countMismatch ? " · response totals require review" : ""
                resultNote = "Confirmed \(confirmed.count); \(held.count) held\(detail.isEmpty ? "" : " · \(detail)")\(suffix)"
            }
            await load(preserveApplyNote: true)
            applyNote = resultNote
        } catch {
            applyNote = "The batch result is unavailable. Refresh before retrying so no assignment is submitted twice."
        }
    }

    private func tapRow(_ r: AIRec) {
        guard boardEvidenceIsCurrent,
              r.hasReadyEvidence(),
              let driverId = r.driverId else {
            applyNote = r.unavailableReason ?? "Current assignment evidence is unavailable."
            return
        }
        // Open the per-load assign flow (532 Assign Driver M05) with context.
        NotificationCenter.default.post(
            name: .eusoDispatchNavSwap, object: nil,
            userInfo: [
                "screenId": "532",
                "loadId": r.loadId,
                "loadNumber": r.loadNumber ?? "",
                "driverId": driverId,
                "classification": r.classification,
            ]
        )
    }

    private func review() {
        // Route to the dispatch board to review the held-for-manual set.
        // 2026-06-09 nav repair: "401" is a BROKER registry id — the
        // dispatch RBAC guard bounced it to Home. Canonical dispatch
        // board = "Disp401". The former "filter": "needs_review" key was
        // dropped: no receiver reads "filter" and the kanban has no
        // needs_review lens (it filters by cargo class only) — carrying
        // a dead key would fabricate an affordance that doesn't exist.
        NotificationCenter.default.post(
            name: .eusoDispatchNavSwap, object: nil,
            userInfo: ["screenId": "Disp401"]
        )
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Recommendation row
// MARK: ─────────────────────────────────────────────────────────

private struct RecommendationRow: View {
    @Environment(\.palette) private var palette
    let rec: AIRec
    let isActionable: Bool
    let onTap: () -> Void

    private var isAuto: Bool { rec.classification == "auto" }
    private var accent: Color {
        guard isActionable else { return palette.textTertiary }
        return isAuto ? Brand.success : Brand.warning
    }

    // "ME · LA → PHX reefer"  /  "Unit 214 · HOU → DAL"
    private var headline: String {
        let lead = rec.initials ?? rec.vehicleUnit ?? "Match"
        var tail: [String] = []
        if let lane = rec.lane { tail.append(lane) }
        if let eq = rec.equipment { tail.append(eq) }
        let tailStr = tail.joined(separator: " ")
        return tailStr.isEmpty ? lead : "\(lead) · \(tailStr)"
    }

    // "LD-… · HOS-safe"  /  "LD-… · HOS tight"
    private var subLine: String {
        var parts: [String] = []
        if let ln = rec.loadNumber { parts.append(ln) }
        if let hl = rec.hosLabel { parts.append(hl) }
        if !isActionable, let reason = rec.unavailableReason, !reason.isEmpty {
            parts.append(reason)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Space.s3) {
                // icon-chip (truck glyph, tinted by classification)
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.16))
                    Image(systemName: "box.truck.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(subLine)
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Space.s2)

                VStack(alignment: .trailing, spacing: 6) {
                    matchPill
                    if let rate = rec.rate {
                        Text(rate)
                            .font(EType.caption.weight(.heavy).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
            .padding(Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isActionable)
        .accessibilityHint(
            isActionable
                ? "Open this evidence-backed recommendation"
                : "Assignment evidence is unavailable or stale"
        )
    }

    private var matchPill: some View {
        Text(matchLabel)
            .font(EType.micro).tracking(0.5)
            .foregroundStyle(accent)
            .padding(.horizontal, 10).frame(height: 24)
            .background(Capsule().fill(accent.opacity(0.18)))
    }

    private var matchLabel: String {
        guard let score = rec.matchScore else { return "UNTRACKED" }
        if !isActionable { return "\(score)% · HELD" }
        return isAuto ? "\(score)% MATCH" : "\(score)% REVIEW"
    }
}

#if DEBUG
#Preview("533 · Dispatcher AI Dispatch Assist · Dark") {
    DispatcherAIDispatchAssistScreen(theme: Theme.dark)
        .environment(\.palette, Theme.dark)
}
#endif
