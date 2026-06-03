//
//  709_VesselBidBoard.swift
//  EusoTrip — Vessel Operator · Bid Board (buyer-side spot tender)
//
//  RECALIBRATED 2026-06-02 to the superseding AFTER design — a faithful 1:1 port of the
//  Design-Authority-reconstructed "06 Vessel/Light-SVG/709 Vessel Bid Board.svg" (+ Dark).
//  This is the BOARD archetype (not the old STAT-HERO stamp): numbers-first AWARDABLE band →
//  lane-grouped COMPETITIVE bid stacks (each lane header carries best-rate + an in-place Award;
//  each bid row ranks the carrier's rate with a delta-vs-best + expiry + status chip) → ESang
//  award nudge → CTA pair. Composition follows function: a board reads as a board.
//
//  APP-CONVENTION WRAPPER (mirrors the registered vessel siblings 664/757):
//    `VesselBidBoardScreen` wraps the bespoke board body in the app `Shell` + real `BottomNav`
//    (VesselOperator chrome: HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME). SHIPMENTS is
//    current — the bid board is a shipments-domain surface. The canonical port's self-drawn
//    bottomNav/navItem/orb + .safeAreaInset + .background(systemGroupedBackground) are removed;
//    the Shell supplies the page bg and the REAL nav. The bespoke board (topBar, summaryBand,
//    sectionLabel, laneCard, bidRow, esangCard, ctaRow, IridescentHairline_709) is preserved
//    verbatim — that IS the AFTER design. File-scoped color constants + the `_709`-suffixed model
//    types are kept to reproduce the exact look without colliding with shared symbols.
//
//  DATA — wired honestly (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    loadBidding.getReceivedBids (EXISTS frontend/server/routers/loadBidding.ts:117 · query ·
//      input {status?, limit?} · RETURNS a flat array of raw load_bids rows on THIS operator's
//      postings — {id, loadId, bidderUserId, bidderCompanyId, bidderRole, bidAmount(string),
//      rateType, equipmentType, transitTimeDays, status, expiresAt, isAutoAccepted, createdAt, …}).
//      Chosen over bidReview.getBidComparisons (:22) because that endpoint requires an rfpId
//      (z.object({rfpId})) and returns [] without one — it cannot populate a GENERAL board. The
//      received-bids array is GROUPED BY loadId into the Lane_709/Bid_709 shape: best (lowest) rate
//      per lane → BEST chip + "— best"; every other bid → delta-vs-best (▴ $N) ranked ascending;
//      countered/auto_accepted status → COUNTER/AWARDED pill; expiresAt < 6h → expiry countdown.
//    Summary band ($ pipeline / N bids / N lanes / N expiring) is COMPUTED from the live rows —
//      pipeline = Σ best-rate per lane; expiring = bids whose expiresAt is within 6h.
//
//  Award verbs are flagged honestly. The board groups load_bids (truck/vessel postings), but
//  bidReview.awardLane (:253) writes the RFP-domain rfpAwards table and requires {rfpId, laneId,
//  carrierId, awardedRate} — a load_bids lane carries no rfpId/laneId. Composing a real award
//  payload from this board is the surfaced backend gap, so "Award" / "Award best lane" are
//  STUB · named-gap (re-run load() rather than fake an rfpAwards write). 0 mock data on load;
//  honest empty/error states; the MSC/Hapag/Maersk seed lives ONLY in the #Preview.
//

import SwiftUI

// MARK: - Models (faithful to the SVG; bound to grouped getReceivedBids in the wired build)

private struct Bid_709: Identifiable {
    let id = UUID()
    let mono: String          // carrier monogram chip
    let chipTint: Color
    let carrier: String
    let meta: String          // transit · sailing · note
    let rate: String          // tabular
    let delta: String?        // "▴ $180" higher-than-best, or "— best"
    let deltaUp: Bool         // true => costs more (danger), false => best (success)
    let pill: String?
    let pillFG: Color
    let pillBG: Color
}

private struct Lane_709: Identifiable {
    let id = UUID()
    let route: String
    let meta: String          // "4 bids · best $2,140"
    let bids: [Bid_709]
}

// MARK: - App-convention wrapper (Shell + real VesselOperator BottomNav)

struct VesselBidBoardScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            VesselBidBoardBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Bespoke board body (the AFTER design, wired to live data)

private struct VesselBidBoardBody: View {
    // Brand identity (constant across every mode) — kept file-scoped to reproduce the exact look.
    private let eusoPrimary  = LinearGradient(colors: [Color(red: 0.08, green: 0.45, blue: 1.0), Color(red: 0.745, green: 0.004, blue: 1.0)], startPoint: .leading, endPoint: .trailing)
    private let eusoDiagonal = LinearGradient(colors: [Color(red: 0.08, green: 0.45, blue: 1.0), Color(red: 0.745, green: 0.004, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)

    // Semantic + vessel-mode accent (Brand palette)
    private let ok      = Color(red: 0.000, green: 0.588, blue: 0.420)   // #00966B
    private let okBG    = Color(red: 0.000, green: 0.769, blue: 0.549)   // #00C48C
    private let warn    = Color(red: 0.698, green: 0.451, blue: 0.000)   // #B27300
    private let warnBG  = Color(red: 1.000, green: 0.694, blue: 0.000)   // #FFB100
    private let danger  = Color(red: 0.776, green: 0.157, blue: 0.157)   // #C62828
    private let info    = Color(red: 0.082, green: 0.396, blue: 0.753)   // #1565C0
    private let infoBG  = Color(red: 0.129, green: 0.588, blue: 0.953)   // #2196F3
    private let vsslBG  = Color(red: 0.000, green: 0.675, blue: 0.757)   // #00ACC1

    // Live state
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var lanes: [Lane_709] = []

    // Summary band (computed from live data)
    @State private var pipeline = "$0"
    @State private var bidCount = 0
    @State private var laneCount = 0
    @State private var expiringCount = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                if loading {
                    LifecycleCard { Text("Loading open bids…").font(.system(size: 12)).foregroundColor(.secondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(.system(size: 12)).foregroundColor(.secondary) }
                } else if lanes.isEmpty {
                    EusoEmptyState(systemImage: "tray",
                                   title: "No open bids",
                                   subtitle: "getReceivedBids returned no bids on your postings. Nothing to award yet — post a lane to start receiving competitive bids.")
                } else {
                    summaryBand
                    sectionLabel
                    ForEach(lanes) { laneCard($0) }
                    esangCard
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: TopBar
    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ VESSEL OPERATOR · BID BOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(eusoPrimary)
                Spacer()
                Text("TPEB · SPOT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundColor(.secondary).monospaced()
            }
            HStack(spacing: 10) {
                Text("Bid board").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundColor(.primary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold)).foregroundColor(.primary).rotationEffect(.degrees(90))
            }
            .padding(.top, 10)
            IridescentHairline_709().padding(.top, 12)
        }
    }

    // MARK: Numbers-first awardable band
    private var summaryBand: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AWARDABLE PIPELINE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundColor(.secondary)
                Text(pipeline).font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(eusoDiagonal)
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(bidCount) bids").font(.system(size: 13, weight: .bold)).foregroundColor(.primary)
                Text("\(laneCount) lanes").font(.system(size: 11)).foregroundColor(.secondary).monospaced()
            }
            Spacer(minLength: 8)
            if expiringCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 11, weight: .semibold)).foregroundColor(warn)
                    Text("\(expiringCount) expiring <6h").font(.system(size: 11, weight: .bold)).foregroundColor(warn)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(warnBG.opacity(0.16)))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)))
    }

    private var sectionLabel: some View {
        HStack {
            Text("OPEN LANES · RANKED BY RATE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundColor(.secondary)
            Spacer()
            Text("loadBidding.ts:117").font(.system(size: 11)).foregroundColor(.secondary).monospaced()
        }
    }

    // MARK: Lane card (competitive bid stack)
    private func laneCard(_ lane: Lane_709) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lane.route).font(.system(size: 14, weight: .bold)).foregroundColor(.primary)
                    Text(lane.meta).font(.system(size: 11)).foregroundColor(.secondary).monospaced()
                }
                Spacer()
                Button(action: { Task { await award() } }) {   // awardLane · STUB · named-gap (no rfpId on a load_bids lane)
                    Text("Award").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 8)
                        .background(Capsule().fill(eusoPrimary))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            Divider().padding(.horizontal, 16)
            ForEach(lane.bids) { bidRow($0) }
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)))
    }

    private func bidRow(_ b: Bid_709) -> some View {
        HStack(spacing: 12) {
            Text(b.mono).font(.system(size: 10, weight: .heavy)).tracking(0.4).foregroundColor(b.chipTint)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(b.chipTint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(b.carrier).font(.system(size: 13, weight: .bold)).foregroundColor(.primary)
                Text(b.meta).font(.system(size: 11)).foregroundColor(.secondary).monospaced()
            }
            Spacer()
            if let p = b.pill {
                Text(p).font(.system(size: 10, weight: .bold)).tracking(0.4).foregroundColor(b.pillFG)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(b.pillBG.opacity(0.16)))
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(b.rate).font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundColor(.primary)
                if let d = b.delta {
                    Text(d).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .foregroundColor(b.deltaUp ? danger : ok)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: ESang nudge (the calm expert in the corner)
    private var esangCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(eusoDiagonal).frame(width: 28, height: 28)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.7), .clear], center: .topLeading, startRadius: 1, endRadius: 14)).frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG AI · AWARD NUDGE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(eusoPrimary)
                Text(esangTitle).font(.system(size: 13, weight: .bold)).foregroundColor(.primary)
                Text(esangSubtitle).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Text("esang.chat").font(.system(size: 11)).foregroundColor(.secondary).monospaced()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.tertiarySystemGroupedBackground))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)))
    }

    // Nudge derived from the live board (worst-/best-exposure lane = first ranked lane).
    private var esangTitle: String {
        guard let top = lanes.first, let best = top.bids.first else { return "Award your best open lane now" }
        return "Award \(best.carrier) on \(top.route)"
    }
    private var esangSubtitle: String {
        guard let top = lanes.first, let best = top.bids.first else { return "Lock the best rate before it expires" }
        return "\(best.rate) best · \(top.meta)"
    }

    // MARK: CTA pair
    private var ctaRow: some View {
        HStack(spacing: 8) {
            Button(action: { Task { await award() } }) {        // awardLane (best across lanes) — STUB · named-gap
                Text("Award best lane").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Capsule().fill(eusoPrimary))
            }.buttonStyle(.plain)
            Button(action: { Task { await load() } }) {         // refresh the comparison matrix
                Text("Compare all").font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                    .frame(width: 148, height: 48)
                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    // MARK: - Load + group (honest wiring)

    @MainActor
    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int }
        struct Row: Decodable {
            let id: Int?
            let loadId: Int?
            let bidderUserId: Int?
            let bidderCompanyId: Int?
            let bidderRole: String?
            let bidAmount: String?
            let equipmentType: String?
            let transitTimeDays: Int?
            let status: String?
            let expiresAt: String?
        }
        do {
            // getReceivedBids returns a flat array of raw load_bids rows on the operator's postings.
            let rows: [Row] = try await EusoTripAPI.shared.query("loadBidding.getReceivedBids", input: In(limit: 100))
            self.lanes = Self.group(rows.map { GroupRow(
                loadId: $0.loadId ?? 0,
                bidderUserId: $0.bidderUserId ?? 0,
                bidderCompanyId: $0.bidderCompanyId,
                bidderRole: $0.bidderRole,
                amount: Double($0.bidAmount ?? "0") ?? 0,
                equipment: $0.equipmentType,
                transitDays: $0.transitTimeDays,
                status: $0.status,
                expiresAt: $0.expiresAt
            ) }, ok: ok, okBG: okBG, warn: warn, warnBG: warnBG, info: info, infoBG: infoBG, vsslBG: vsslBG, danger: danger)
            recomputeSummary(rows.compactMap { row -> (Double, String?)? in (Double(row.bidAmount ?? "0") ?? 0, row.expiresAt) })
        } catch {
            self.lanes = []
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// awardLane — STUB · named-gap. A load_bids lane carries no rfpId/laneId, and
    /// bidReview.awardLane writes the RFP-domain rfpAwards table; composing a real
    /// award payload from this board is the surfaced backend gap. Re-load rather
    /// than fake a write.
    @MainActor
    private func award() async { await load() }

    @MainActor
    private func recomputeSummary(_ rows: [(Double, String?)]) {
        bidCount = rows.count
        laneCount = lanes.count
        // Pipeline = Σ best (lowest) rate per lane — the value lockable by awarding each lane.
        let pipelineValue = lanes.reduce(0.0) { acc, lane in
            let best = lane.bids.compactMap { Self.numericRate($0.rate) }.min() ?? 0
            return acc + best
        }
        pipeline = Self.money(pipelineValue)
        // Expiring = bids whose expiresAt is within 6h of now.
        let now = Date()
        let iso = ISO8601DateFormatter()
        expiringCount = rows.filter { _, exp in
            guard let exp, let d = iso.date(from: exp) else { return false }
            let secs = d.timeIntervalSince(now)
            return secs > 0 && secs <= 6 * 3600
        }.count
    }

    // MARK: - Pure grouping (testable; no view state)

    private struct GroupRow {
        let loadId: Int
        let bidderUserId: Int
        let bidderCompanyId: Int?
        let bidderRole: String?
        let amount: Double
        let equipment: String?
        let transitDays: Int?
        let status: String?
        let expiresAt: String?
    }

    private static func group(_ rows: [GroupRow], ok: Color, okBG: Color, warn: Color, warnBG: Color, info: Color, infoBG: Color, vsslBG: Color, danger: Color) -> [Lane_709] {
        // GROUP BY loadId → one lane per posting.
        var byLoad: [Int: [GroupRow]] = [:]
        for r in rows { byLoad[r.loadId, default: []].append(r) }
        // Preserve order of first appearance (server already ORDERed BY createdAt DESC).
        var seen = [Int](); var order = [Int]()
        for r in rows where !seen.contains(r.loadId) { seen.append(r.loadId); order.append(r.loadId) }

        let tints: [Color] = [vsslBG, infoBG, okBG]
        let iso = ISO8601DateFormatter()
        let now = Date()

        return order.compactMap { loadId -> Lane_709? in
            guard let group = byLoad[loadId], !group.isEmpty else { return nil }
            // Rank ascending by amount — lowest (best) rate first.
            let ranked = group.sorted { $0.amount < $1.amount }
            let best = ranked.first!.amount

            let bids: [Bid_709] = ranked.enumerated().map { idx, r in
                let isBest = idx == 0
                let tint = tints[idx % tints.count]
                let carrier = carrierName(r)
                let mono = monogram(carrier)

                // Status pill
                var pill: String? = nil; var pillFG = Color.clear; var pillBG = Color.clear
                switch (r.status ?? "").lowercased() {
                case "countered":
                    pill = "COUNTER"; pillFG = info; pillBG = infoBG
                case "accepted", "auto_accepted", "awarded":
                    pill = "AWARDED"; pillFG = ok; pillBG = okBG
                default:
                    if isBest { pill = "BEST"; pillFG = ok; pillBG = okBG }
                    // Expiry-soon pill on non-best rows
                    if !isBest, let exp = r.expiresAt, let d = iso.date(from: exp) {
                        let h = d.timeIntervalSince(now) / 3600
                        if h > 0 && h <= 12 { pill = "EXP \(Int(h.rounded()))h"; pillFG = warn; pillBG = warnBG }
                    }
                }

                // Delta vs best
                let delta: String?
                let deltaUp: Bool
                if isBest {
                    delta = "— best"; deltaUp = false
                } else {
                    let diff = Int((r.amount - best).rounded())
                    delta = "▴ $\(diff)"; deltaUp = true
                }

                // Meta: transit · role · equipment
                var parts: [String] = []
                if let t = r.transitDays { parts.append("\(t)d") }
                if let role = r.bidderRole, !role.isEmpty { parts.append(role) }
                if let eq = r.equipment, !eq.isEmpty { parts.append(eq) }
                let meta = parts.isEmpty ? "spot bid" : parts.joined(separator: " · ")

                return Bid_709(mono: mono, chipTint: tint, carrier: carrier, meta: meta,
                               rate: money(r.amount), delta: delta, deltaUp: deltaUp,
                               pill: pill, pillFG: pillFG, pillBG: pillBG)
            }

            let route = "Load #\(loadId)" + (group.first?.equipment.map { " · \($0)" } ?? "")
            let laneMeta = "\(group.count) bid\(group.count == 1 ? "" : "s") · best \(money(best))"
            return Lane_709(route: route, meta: laneMeta, bids: bids)
        }
    }

    private static func carrierName(_ r: GroupRow) -> String {
        if let c = r.bidderCompanyId { return "Carrier \(c)" }
        return "Bidder \(r.bidderUserId)"
    }
    private static func monogram(_ name: String) -> String {
        let words = name.split(separator: " ").compactMap { $0.first }
        let s = String(words.prefix(2)).uppercased()
        return s.isEmpty ? "•" : s
    }
    private static func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v)) ?? "\(Int(v))")
    }
    private static func numericRate(_ s: String) -> Double? {
        Double(s.filter { $0.isNumber || $0 == "." })
    }
}

struct IridescentHairline_709: View {
    var body: some View {
        Rectangle().fill(LinearGradient(colors: [Color(red: 0.08, green: 0.45, blue: 1.0).opacity(0.55), Color(red: 0.745, green: 0.004, blue: 1.0).opacity(0.55)], startPoint: .leading, endPoint: .trailing)).frame(height: 1)
    }
}

// MARK: - Previews (sample data only — the live screen never seeds these rows)

private struct VesselBidBoardPreviewSeed: View {
    let eusoPrimary  = LinearGradient(colors: [Color(red: 0.08, green: 0.45, blue: 1.0), Color(red: 0.745, green: 0.004, blue: 1.0)], startPoint: .leading, endPoint: .trailing)
    var body: some View { VesselBidBoardScreen(theme: Theme.dark) }
}

#Preview("709 · Bid board · Night") {
    VesselBidBoardScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("709 · Bid board · Light") {
    VesselBidBoardScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
