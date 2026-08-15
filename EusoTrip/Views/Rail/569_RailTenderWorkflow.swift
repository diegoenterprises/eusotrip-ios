//
//  569_RailTenderWorkflow.swift
//  EusoTrip — Rail Engineer · Tender Workflow (carrier-side load-tender inbox).
//
//  Verbatim port of "569 Rail Tender Workflow.svg" (Light + Dark).
//  Incoming tender offer with rate, countdown, and tender history.
//  Nav anchored to RailEngineerNavController (HOME[current] · SHIPMENTS · [orb] · COMPLIANCE · ME).
//
//  Data:
//    railTenderWorkflow.submitTender         (EXISTS railTenderWorkflow.ts:16)  → active tender hero
//    railTenderWorkflow.receiveTenderResponse(EXISTS railTenderWorkflow.ts:57)  → Accept/Decline action
//    railTenderWorkflow.tenderHistory        (EXISTS railTenderWorkflow.ts:80)  → history rows
//

import SwiftUI

/// Strip machine tokens (bracketed enum keys, key=value pairs) that
/// occasionally bleed into server equipment/cargo display strings, e.g.
/// the entire 204-machine block "Mode:… Equipment:… [rawValue]·key=value".
/// Display-layer only — never apply to values used as lexicon keys or sent
/// to the server. Mirrors cleanLabel in 205_ShipperLoadDetail.swift.
/// Returns "—" for nil/empty; never returns empty for a non-empty input.
fileprivate func cleanEquipLabel(_ s: String?) -> String {
    guard let s = s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "—" }
    var out = s
    // remove "[anything]" bracket tokens (with any leading whitespace)
    out = out.replacingOccurrences(
        of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
    // remove "key=value" tokens (vertical=truck, rate-unit=per_mile, …),
    // dropping any leading separator/bullet too
    out = out.replacingOccurrences(
        of: #"\s*[·•]?\s*[A-Za-z_-]+=\S+"#, with: "", options: .regularExpression)
    // collapse doubled separators left behind by the removals
    out = out.replacingOccurrences(
        of: #"\s*·\s*·\s*"#, with: " · ", options: .regularExpression)
    let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: " ·•\n\r\t"))
    // Guard: never return empty for a non-empty input.
    if trimmed.isEmpty {
        let fallback = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "—" : fallback
    }
    return trimmed
}

struct RailTenderWorkflowScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailTenderWorkflowBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: true),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct ActiveTender569: Decodable {
    // D5 cure 2026-08-10: no longer decoded from a GET of the submitTender
    // MUTATION (dead read, 405 forever) — constructed from the newest
    // undecided row of the real tenderHistory read. Stored props keep the
    // server-row names; decode synthesis stays tolerant (all optional).
    let tenderId: String?
    let controlNumber: String?
    let ediDocument: String?
    let status: String?
    let submittedAt: String?
    let awaiting: String?
    let shipmentId: Int?
    let laneOrigin: String?
    let laneDestination: String?

    var id: String? { tenderId }
    var origin: String? { laneOrigin }
    var destination: String? { laneDestination }
    var rateUsd: Double? { nil }        // no rate stored on a tender event (honest — railTenderWorkflow.ts:492)
    var ratePerMile: Double? { nil }
    var railroad: String? { nil }
    var equipmentType: String? { nil }
    var note: String? { nil }
    var respondByMinutes: Int? { nil }
    var respondByIso: String? { nil }
}

private struct TenderStats569: Decodable {
    // Derived client-side from real tenderHistory rows since the D5 cure —
    // same arithmetic carrierAcceptanceRate applies server-side (:514).
    let pendingCount: Int?
    let acceptRatePct: Double?
    let avgReplyMinutes: Double?
}

private struct TenderHistoryItem569: Decodable, Identifiable {
    let id: Int
    let origin: String?
    let destination: String?
    let railId: String?
    let outcome: String?        // "accepted" | "declined" | "counter"
    let outcomeNote: String?
    let rateUsd: Double?
    // D5 cure 2026-08-10 — the server row (railTenderWorkflow.ts:470-495
    // mapped shape) has always carried these; decoding them lets the screen
    // derive its active tender + stats from the ONE real read instead of
    // GET-calling the submitTender mutation (which returned 405 forever).
    let tenderId: String?
    let controlNumber: String?
    let shipmentId: Int?
    let submittedAt: String?
    let timestamp: String?
    let status: String?         // "pending" | "accepted" | "declined" | "cancelled"
}

// Envelope wrapper that tolerates server's {tenders:[], total:, note:} shape
private struct TenderHistoryResponse: Decodable {
    let items: [TenderHistoryItem569]
    
    init(from decoder: Decoder) throws {
        // Try bare-array shape first
        if let single = try? decoder.singleValueContainer(),
           let bare = try? single.decode([TenderHistoryItem569].self) {
            self.items = bare
            return
        }
        // Fall back to envelope shape {tenders, total, note}
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try container.decode([TenderHistoryItem569].self, forKey: .tenders)
    }
    
    enum CodingKeys: String, CodingKey {
        case tenders, total, note
    }
}

// MARK: - Body

private struct RailTenderWorkflowBody: View {
    @Environment(\.palette) private var palette

    @State private var activeTender: ActiveTender569? = nil
    @State private var stats: TenderStats569? = nil
    @State private var history: [TenderHistoryItem569] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isAccepting = false
    @State private var isDeclining = false

    // MARK: Derived

    private var tenderRateLabel: String {
        activeTender?.rateUsd.map { "$\(Int($0))" } ?? "-"
    }
    private var rateMileLabel: String {
        activeTender?.ratePerMile.map { "$\(String(format: "%.2f", $0))/mi" } ?? "-"
    }
    private var laneLabel: String {
        let o = activeTender?.origin ?? "-"
        let d = activeTender?.destination ?? "-"
        return "\(shortName(o)) → \(shortName(d))"
    }
    private var tenderIdCaption: String { activeTender?.id ?? "-" }
    private var respondLabel: String {
        activeTender?.respondByMinutes.map { "\($0)m" } ?? "-"
    }
    private var pendingCount: Int  { stats?.pendingCount ?? 0 }
    private var acceptRateLabel: String {
        stats?.acceptRatePct.map { "\(Int($0))%" } ?? "-"
    }
    private var avgReplyLabel: String {
        stats?.avgReplyMinutes.map { "\(Int($0))m" } ?? "-"
    }

    private func shortName(_ s: String) -> String {
        let parts = s.split(separator: " ")
        if parts.count >= 2 { return "\(parts[0]) \(parts[1])" }
        return s
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading tenders…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    tenderHistoryList
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
                    Text("RAIL ENGINEER · TENDERS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(tenderIdCaption)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Tender workflow")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("INCOMING TENDER")
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.16)))
                Text(laneLabel)
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(tenderRateLabel)
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Text("all-in tender · \(rateMileLabel)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(cleanEquipLabel(activeTender?.note ?? activeTender?.equipmentType))
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("RESPOND IN")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(respondLabel)
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Brand.warning)
                    Text("to lock rate")
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
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "PENDING",     value: "\(pendingCount)",  accent: pendingCount > 0 ? Brand.warning : nil)
            MetricTile(label: "ACCEPT RATE", value: acceptRateLabel,   gradientNumeral: true)
            MetricTile(label: "AVG REPLY",   value: avgReplyLabel)
        }
    }

    // MARK: - Tender history

    private var tenderHistoryList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TENDER HISTORY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("tenderHistory")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if history.isEmpty {
                EusoEmptyState(
                    systemImage: "tray.fill",
                    title: "No tender history",
                    subtitle: "Past tender responses will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.enumerated()), id: \.element.id) { idx, item in
                        historyRow(item)
                        if idx < history.count - 1 {
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

    private enum TenderOutcome { case accepted, declined, counter }
    private func outcome(_ item: TenderHistoryItem569) -> TenderOutcome {
        switch (item.outcome ?? "").lowercased() {
        case "accepted":         return .accepted
        case "declined", "deny": return .declined
        default:                 return .counter
        }
    }
    private func chipColor(_ o: TenderOutcome) -> Color {
        switch o { case .accepted: return Brand.success; case .declined: return Brand.danger; case .counter: return Brand.rail }
    }
    private func pillLabel(_ o: TenderOutcome) -> String {
        switch o { case .accepted: return "ACCEPTED"; case .declined: return "DECLINED"; case .counter: return "COUNTER" }
    }

    private func historyRow(_ item: TenderHistoryItem569) -> some View {
        let o = outcome(item)
        let color = chipColor(o)
        let lane = "\(item.origin ?? "-") → \(item.destination ?? "-")"
        let sub = [item.railId, item.outcomeNote].compactMap { $0 }.joined(separator: " · ")
        let rateLabel = item.rateUsd.map { "$\(Int($0))" } ?? "-"

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "tram.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(lane)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(sub.isEmpty ? "-" : sub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(pillLabel(o))
                    .font(.system(size: 10, weight: .bold)).kerning(0.4)
                    .foregroundStyle(color)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(color.opacity(0.12)))
                Text(rateLabel)
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(
                title: "Accept tender",
                action: { Task { await respond(accept: true) } },
                leadingIcon: "checkmark",
                isLoading: isAccepting
            )
            Button { Task { await respond(accept: false) } } label: {
                Group {
                    if isDeclining {
                        ProgressView().scaleEffect(0.85).tint(Brand.danger)
                    } else {
                        Text("Decline")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Brand.danger)
                    }
                }
                .frame(width: 148, height: 48)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.40)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        // D5 cure 2026-08-10 (fresh-context evaluator finding, same class as
        // the S4 respond() cure): the two removed reads GET-`query()`ed
        // `railTenderWorkflow.submitTender` — a MUTATION (railTenderWorkflow
        // .ts:85) — so they 405'd on every launch, activeTender stayed nil,
        // and the Accept/Decline CTA (which guards on activeTender?.id) could
        // never fire even after its own method-seam cure. The router has no
        // active-tender or stats READ (named gap: `getActiveTender` —
        // RAIL-S4-569-DEAD-READS carries the proposed shape). Until it lands,
        // everything derives from the ONE real read, tenderHistory
        // (railTenderWorkflow.ts:435 .query): active = newest pending row
        // with no later decided event for the same tenderId; stats = the
        // same arithmetic carrierAcceptanceRate (:514) applies server-side,
        // computed over the fetched window. Real rows only — nothing invented.
        struct HistIn: Encodable { let limit: Int }
        do {
            let h: [TenderHistoryItem569] = try await EusoTripAPI.shared.query(
                "railTenderWorkflow.tenderHistory", input: HistIn(limit: 50))
            self.history = h

            let decided = Set(["accepted", "declined", "cancelled"])
            let decidedTenderIds = Set(h.filter { decided.contains(($0.status ?? $0.outcome ?? "").lowercased()) }
                                        .compactMap { $0.tenderId })
            let pending = h.filter {
                let s = ($0.status ?? $0.outcome ?? "").lowercased()
                guard s == "pending" || s == "submitted" else { return false }
                guard let tid = $0.tenderId else { return true }
                return !decidedTenderIds.contains(tid)
            }
            self.activeTender = pending.first.map { row in
                ActiveTender569(tenderId: row.tenderId, controlNumber: row.controlNumber,
                                ediDocument: nil, status: row.status ?? "pending",
                                submittedAt: row.submittedAt ?? row.timestamp,
                                awaiting: nil, shipmentId: row.shipmentId,
                                laneOrigin: row.origin, laneDestination: row.destination)
            }

            let decidedRows = h.filter { decided.contains(($0.status ?? $0.outcome ?? "").lowercased()) }
            let accepted = decidedRows.filter { (($0.status ?? $0.outcome ?? "").lowercased()) == "accepted" }.count
            self.stats = TenderStats569(
                pendingCount: pending.count,
                acceptRatePct: decidedRows.isEmpty ? nil : (Double(accepted) / Double(decidedRows.count)) * 100.0,
                avgReplyMinutes: nil)  // reply latency needs paired submit/decide stamps — nil renders "—", never a fabricated number
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func respond(accept: Bool) async {
        // tenderId is the primary correlation key; shipmentId is the server's
        // sanctioned fallback (receiveTenderResponse input, railTenderWorkflow
        // .ts:220-225). Either being present makes the reply routable.
        guard activeTender?.id != nil || activeTender?.shipmentId != nil else { return }
        let tid = activeTender?.id
        if accept { isAccepting = true } else { isDeclining = true }
        struct RespondIn: Encodable { let tenderId: String?; let response: String; let shipmentId: Int? }
        struct RespondOut: Decodable {}
        do {
            // S4 cure 2026-08-10: receiveTenderResponse is a MUTATION
            // (railTenderWorkflow.ts:220 .mutation — persists the EDI-990
            // outcome). query() GET-called it, so Accept/Decline was dead on
            // iOS while working on web — PARITY_AND_CHAINS.md §2·S4.
            let _: RespondOut = try await EusoTripAPI.shared.mutation(
                "railTenderWorkflow.receiveTenderResponse",
                input: RespondIn(tenderId: tid, response: accept ? "accept" : "decline",
                                 shipmentId: activeTender?.shipmentId))
            await load()
        } catch { /* surface error silently; keep tender displayed */ }
        isAccepting = false; isDeclining = false
    }
}

#Preview("569 · Rail Tender Workflow · Night") { RailTenderWorkflowScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("569 · Rail Tender Workflow · Light") { RailTenderWorkflowScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
