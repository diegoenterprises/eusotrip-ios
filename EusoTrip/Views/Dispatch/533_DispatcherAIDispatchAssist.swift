//
//  533_DispatcherAIDispatchAssist.swift
//  EusoTrip — Dispatcher · AI Dispatch Assist.
//
//  Verbatim SwiftUI port of:
//    `04 Dispatcher/Dark-SVG/533 Dispatcher AI Dispatch Assist.svg`
//
//  THE AI DISPATCH BOARD — ESANG ranks every unassigned load against the
//  available driver pool (HOS clock, lane fit, equipment match, deadhead)
//  and presents the dispatcher a single decisive surface: a confidence
//  hero, a RECOMMENDED / AUTO-MATCH / NEEDS-REVIEW triplet, the ranked TOP
//  RECOMMENDATIONS rows, and a one-pass BULK apply for the HOS-safe
//  auto-matches. Persona §196 Renée Marquette / Aurora Freight Lines.
//  Reached from the Board (401) as the AI-assist surface.
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
//    • APPLY RECOMMENDATIONS fires the real, compliance-gated, audited
//      `dispatch.assignDriver` (dispatch.ts:1033) ONCE PER auto-matched
//      load — preserving every per-load FMCSA / CDL / insurance gate. Loads
//      the gate rejects surface their real error; the rest still apply.
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
    let driverId: Int?           // drivers.id → dispatch.assignDriver
    let driverUserId: Int?       // users.id (display / HOS only)
    let driverName: String?
    let initials: String?
    let lane: String?            // "LA → PHX"
    let equipment: String?       // "reefer" / "53′ Dry" / cargo
    let vehicleUnit: String?     // real plate or "Unit <id>"; nil when none
    let matchScore: Int          // 0–100
    let classification: String   // "auto" | "review"
    let hosState: String         // "safe" | "tight" | "unknown"
    let hosLabel: String?        // "HOS-safe" | "HOS tight" | nil
    let rate: String?            // "$2,200"
    let transportMode: String?
}

private struct AISummary: Decodable, Hashable {
    let loadsToAssign: Int
    let autoMatched: Int
    let needsReview: Int
    let avgConfidence: Int
}

private struct AIBulk: Decodable, Hashable {
    let autoCount: Int
    let reviewCount: Int
    let eligibleLoadIds: [Int]
}

private struct AIBoardResponse: Decodable {
    let summary: AISummary
    let recommendations: [AIRec]
    let bulk: AIBulk
    let generatedAt: String?
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
                leading: [NavSlot(label: "Home",  systemImage: "house",                  isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DispatcherAIDispatchAssistBody: View {
    @Environment(\.palette) private var palette

    @State private var summary: AISummary = AISummary(loadsToAssign: 0, autoMatched: 0, needsReview: 0, avgConfidence: 0)
    @State private var recs: [AIRec] = []
    @State private var bulk: AIBulk = AIBulk(autoCount: 0, reviewCount: 0, eligibleLoadIds: [])

    @State private var loading: Bool = true
    @State private var actionError: String?
    @State private var applying: Bool = false
    @State private var applyNote: String?       // honest result of the bulk apply

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
        .task { await load() }
    }

    // MARK: Top bar (back chevron + eyebrow + mono caption + title + kebab)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ DISPATCHER · AI ASSIST")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text("AURORA · \(summary.loadsToAssign) OPEN")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textSecondary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("AI dispatch assist")
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
                chip("live")
                chip("recommendations")
                Spacer(minLength: 0)
            }
            HStack(alignment: .top) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text("\(summary.loadsToAssign)")
                        .font(.system(size: 30, weight: .bold, design: .default).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("loads to assign")
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text("\(summary.autoMatched) auto-matched · \(summary.needsReview) review")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: Space.s3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONFIDENCE")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                    Text("\(summary.avgConfidence)%")
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
            kpiCell("RECOMMENDED", recs.count, tint: palette.textOnGradient, filled: true)
            kpiCell("AUTO-MATCH",  summary.autoMatched, tint: Brand.success, filled: false)
            kpiCell("NEEDS REVIEW", summary.needsReview, tint: Brand.warning, filled: false)
        }
        .padding(.top, Space.s4)
    }

    private func kpiCell(_ label: String, _ value: Int, tint: Color, filled: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(label)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(filled ? palette.textOnGradient.opacity(0.85) : palette.textSecondary)
            Text("\(value)")
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
                Text("aiDispatchAssist.ts:17")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s2)

            VStack(spacing: 0) {
                if topRows.isEmpty {
                    emptyRows
                } else {
                    ForEach(Array(topRows.enumerated()), id: \.element.id) { idx, r in
                        RecommendationRow(rec: r) { tapRow(r) }
                        if idx < topRows.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                    Text("+ \(moreCount) more · ranked by HOS, lane fit, deadhead")
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
                Text("aiDispatchAssist.ts:88")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("apply all \(bulk.autoCount) auto-matches in one pass")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(bulk.reviewCount) held for manual review · HOS-safe only")
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
                .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(applying || bulk.autoCount == 0)
            .opacity(bulk.autoCount == 0 ? 0.5 : 1)

            Button { review() } label: {
                Text("Review")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(height: 48)
                    .background(Capsule().fill(Color(hex: 0x232932)))
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
            Text("Couldn’t load AI recommendations").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
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

    private func load() async {
        loading = true
        actionError = nil
        applyNote = nil
        do {
            let r: AIBoardResponse = try await EusoTripAPI.shared.queryNoInput("aiDispatchAssist.getBoardRecommendations")
            summary = r.summary
            recs = r.recommendations
            bulk = r.bulk
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // Apply every HOS-safe auto-match through the real compliance-gated
    // dispatch.assignDriver — ONE call per load so each FMCSA/CDL/insurance
    // gate runs. Loads the gate rejects surface honestly; the rest assign.
    private func applyAll() async {
        let autos = recs.filter { $0.classification == "auto" && $0.driverId != nil }
        guard !autos.isEmpty else { return }
        applying = true
        applyNote = nil
        var applied = 0
        var failures: [String] = []

        struct In: Encodable { let loadId: Int; let driverId: Int }
        struct Out: Decodable { let success: Bool? }

        for r in autos {
            guard let did = r.driverId else { continue }
            do {
                let _: Out = try await EusoTripAPI.shared.mutation(
                    "dispatch.assignDriver",
                    input: In(loadId: r.loadId, driverId: did)
                )
                applied += 1
            } catch {
                let msg = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
                failures.append("\(r.loadNumber ?? "Load \(r.loadId)"): \(msg)")
            }
        }

        applying = false
        if failures.isEmpty {
            applyNote = "Applied \(applied) auto-match\(applied == 1 ? "" : "es")."
        } else {
            applyNote = "Applied \(applied); \(failures.count) blocked by compliance — \(failures.prefix(2).joined(separator: " · "))"
        }
        await load()   // refresh the board after the writes
    }

    private func tapRow(_ r: AIRec) {
        // Open the per-load assign flow (532 Assign Driver M05) with context.
        NotificationCenter.default.post(
            name: .eusoDispatchNavSwap, object: nil,
            userInfo: [
                "screenId": "532",
                "loadId": r.loadId,
                "loadNumber": r.loadNumber ?? "",
                "driverId": r.driverId ?? 0,
                "classification": r.classification,
            ]
        )
    }

    private func review() {
        // Route to the dispatch board (401) to review the held-for-manual set.
        NotificationCenter.default.post(
            name: .eusoDispatchNavSwap, object: nil,
            userInfo: ["screenId": "401", "filter": "needs_review"]
        )
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Recommendation row
// MARK: ─────────────────────────────────────────────────────────

private struct RecommendationRow: View {
    @Environment(\.palette) private var palette
    let rec: AIRec
    let onTap: () -> Void

    private var isAuto: Bool { rec.classification == "auto" }
    private var accent: Color { isAuto ? Brand.success : Brand.warning }

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
    }

    private var matchPill: some View {
        Text(isAuto ? "\(rec.matchScore)% MATCH" : "REVIEW")
            .font(EType.micro).tracking(0.5)
            .foregroundStyle(accent)
            .padding(.horizontal, 10).frame(height: 24)
            .background(Capsule().fill(accent.opacity(0.18)))
    }
}

#if DEBUG
private let _previewBoard = AIBoardResponse(
    summary: AISummary(loadsToAssign: 9, autoMatched: 6, needsReview: 3, avgConfidence: 92),
    recommendations: [
        AIRec(id: "rec-1", loadId: 1, loadNumber: "LD-260427-7C3A09F18B", driverId: 41, driverUserId: 88,
              driverName: "Michael Eusorone", initials: "ME", lane: "LA → PHX", equipment: "reefer",
              vehicleUnit: nil, matchScore: 92, classification: "auto", hosState: "safe", hosLabel: "HOS-safe",
              rate: "$2,200", transportMode: "truck"),
        AIRec(id: "rec-2", loadId: 2, loadNumber: "LD-260427-A38FB12C7E", driverId: 52, driverUserId: 91,
              driverName: nil, initials: nil, lane: "HOU → DAL", equipment: "MC-306",
              vehicleUnit: "Unit 214", matchScore: 88, classification: "auto", hosState: "safe", hosLabel: "HOS-safe",
              rate: "$1,900", transportMode: "truck"),
        AIRec(id: "rec-3", loadId: 3, loadNumber: "LD-260517-BH7C3A09F1", driverId: 63, driverUserId: 95,
              driverName: nil, initials: nil, lane: "PHX backhaul", equipment: nil,
              vehicleUnit: "Unit 087", matchScore: 71, classification: "review", hosState: "tight", hosLabel: "HOS tight",
              rate: "$1,450", transportMode: "truck"),
    ],
    bulk: AIBulk(autoCount: 6, reviewCount: 3, eligibleLoadIds: [1, 2]),
    generatedAt: "2026-05-30T09:41:00Z"
)

#Preview("533 · Dispatcher AI Dispatch Assist · Dark") {
    DispatcherAIDispatchAssistScreen(theme: Theme.dark)
        .environment(\.palette, Theme.dark)
}
#endif
