//
//  008_RailShipperTenderWorkflow.swift
//  EusoTrip — Rail · Shipper · Tender Workflow (brick 008).
//
//  Verbatim reconstruction of "05 Rail/Dark-SVG/008 Rail Tender Workflow.svg"
//  (canvas 440×956, Theme.dark). This is the CANONICAL, mode-agnostic SHIPPER app
//  (Diego Usoro / Eusorone Technologies, companyId 1, SHIPPER) tendering a RAIL
//  load (load.mode='rail') — NOT a separate "Rail Shipper" role and NOT a forked
//  nav. The shipper sends an EDI 404 load tender to a Class I railroad and awaits
//  an EDI 990 (Response to Load Tender) accept/decline. BOARD grammar mirrors the
//  flagship 227/410 cadence: active hero + scannable status + itemized history.
//  Web parity: client/src/pages/shipper/TenderWorkflow.tsx with load.mode='rail'.
//
//  tRPC wiring — REAL contract (the-oath §67, 2026-06-02). All four tender
//  procedures live in server/routers/railTenderWorkflow.ts and were made REAL
//  this fire (the pre-§67 router was a persistence shell — submitTender wrote
//  nothing, tenderHistory returned a hardcoded empty object). Anchors:
//    • railTenderWorkflow.tenderHistory  (railTenderWorkflow.ts) — BARE ARRAY of
//        tender rows, scoped to the caller's owned rail shipments. Feeds the
//        active hero + status card + history list. Honest-empty when none.
//    • railTenderWorkflow.submitTender   (railTenderWorkflow.ts) — "Re-tender to
//        alt carrier". Persists a tender_submitted rail_shipment_events row +
//        EDI 404 provenance + audit + WS RAIL_TENDER_SUBMITTED broadcast.
//    • railTenderWorkflow.cancelTender   (railTenderWorkflow.ts · BUILT §67) —
//        "Cancel". Guards against cancelling a responded tender; idempotent;
//        audit + WS RAIL_TENDER_CANCELLED.
//    • railTenderWorkflow.receiveTenderResponse — server-side EDI 990 handler
//        (flips status accepted/declined). Not called by this screen directly;
//        the screen reflects the flip on its next load() poll.
//
//  HONEST DEGRADE: every figure the resolver returns null for renders an
//  EM-DASH — never the SVG sample values. No try?-collapse; every loader/CTA is
//  a real do/catch surfacing actionError. Re-tender/cancel report real success
//  only after the mutation resolves (no synthesized success:false).
//
//  RBAC: protectedProcedure (auth-gated) + server ownership gate (caller must
//  own the rail shipment / same companyId). transportMode=rail. Single-country
//  US (BNSF Class I single-line domestic · STCC 0113310 grain) · USD.
//  Nav: canonical Shipper enum HOME · LOADS · [orb] · WALLET · ME (LOADS current),
//  supplied by the Shipper nav chrome — this screen renders content only (matches
//  002_RailShipmentDetail / 006_RailCrossBorderCustoms / 007_RailNewShipment).
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Data shape (decoded from the REAL railTenderWorkflow.tenderHistory bare array)

private struct RailTenderHistoryRow008: Decodable, Identifiable, Hashable {
    let id: Int
    let tenderId: String?
    let controlNumber: String?
    let shipmentId: Int?
    let carrier: String?
    let origin: String?           // originScac
    let destination: String?      // destinationScac
    let originScac: String?
    let destinationScac: String?
    let commodityStcc: String?
    let carType: String?
    let railcarCount: Int?
    let pickupDate: String?
    let status: String?           // submitted | accepted | declined | cancelled | pending
    let submittedAt: String?
    let timestamp: String?

    var isPending: Bool {
        let s = (status ?? "").lowercased()
        return s == "submitted" || s == "pending"
    }
    var isTerminal: Bool {
        let s = (status ?? "").lowercased()
        return s == "accepted" || s == "declined" || s == "cancelled"
    }
}

private struct CancelResult008: Decodable { let tenderId: String?; let status: String? }
private struct SubmitResult008: Decodable {
    let tenderId: String?; let controlNumber: String?; let status: String?; let submittedAt: String?
}

// railTenderWorkflow.carrierAcceptanceRate return shape — field-for-field with
// the server proc (`railTenderWorkflow.ts:554`). `acceptanceRate` is 0-100 with
// one decimal (JSON number) → Double; `accepted`/`total`/`windowDays` are integer
// counts → Int. `total == 0` is the honest no-data signal (renders an em-dash).
private struct RailAcceptanceRate008: Decodable, Hashable {
    let carrier: String
    let acceptanceRate: Double
    let accepted: Int
    let total: Int
    let windowDays: Int

    /// True only when the window held at least one decided tender for this
    /// carrier. When false the advisory shows "—" instead of a fabricated rate.
    var hasData: Bool { total > 0 }
}

// MARK: - Screen

struct RailShipperTenderWorkflow_008: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let shipmentId: Int
    init(shipmentId: Int = 48217) { self.shipmentId = shipmentId }

    // Live data
    @State private var rows: [RailTenderHistoryRow008] = []

    // Live carrier tender-acceptance rate (railTenderWorkflow.carrierAcceptanceRate),
    // keyed on the active tender's carrier + commodity STCC. `nil` = not yet loaded
    // or unavailable; `total == 0` = honest no-data (renders an em-dash, never 94%).
    @State private var acceptance: RailAcceptanceRate008? = nil
    @State private var acceptanceCarrier: String? = nil   // carrier the rate is for

    // Async state (honest — no try?-collapse)
    @State private var loading = true
    @State private var retendering = false
    @State private var cancelling = false
    @State private var actionError: String? = nil
    @State private var actionNote: String? = nil

    // MARK: Derived

    /// Reduce the flat event rows to one entry per tenderId (latest event wins),
    /// then partition into the single active (pending) tender + terminal history.
    private var byTender: [RailTenderHistoryRow008] {
        var latest: [String: RailTenderHistoryRow008] = [:]
        for r in rows {                       // rows are newest-first
            let key = r.tenderId ?? "row-\(r.id)"
            if latest[key] == nil { latest[key] = r }   // first seen = newest
        }
        return Array(latest.values)
    }
    private var active: RailTenderHistoryRow008? {
        byTender.filter { $0.isPending }
            .sorted { ($0.timestamp ?? "") > ($1.timestamp ?? "") }
            .first
    }
    private var history: [RailTenderHistoryRow008] {
        byTender.filter { $0.isTerminal }
            .sorted { ($0.timestamp ?? "") > ($1.timestamp ?? "") }
    }

    private func dash(_ s: String?) -> String {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return "-" }
        return s
    }

    // Canonical Class I carrier rotation (mirrors the server `carrier` enum).
    private static let carrierRotation = ["BNSF", "UP", "NS", "CSX", "CPKC", "CN", "KCS", "FXE"]
    private func nextCarrier(after current: String?) -> String {
        guard let c = current, let i = Self.carrierRotation.firstIndex(of: c) else { return "UP" }
        return Self.carrierRotation[(i + 1) % Self.carrierRotation.count]
    }

    private var heroCarrier: String { active?.carrier ?? "-" }
    private var subLine: String {
        if let a = active { return "EDI 404 sent · awaiting EDI 990 response from \(a.carrier ?? "carrier")" }
        return "No active tender · send an EDI 404 to a Class I railroad"
    }

    /// Commodity label for the advisory copy, derived from the active tender's
    /// STCC. STCC 0113310 = grain (the canonical 008 load); fall back to a
    /// neutral "tenders" when no/other commodity so the copy never lies.
    private var commodityLabel: String {
        let stcc = (active?.commodityStcc ?? "").trimmingCharacters(in: .whitespaces)
        if stcc.hasPrefix("0113") { return "grain tenders" }   // 0113xxx = farm grains
        return "tenders"
    }

    /// ESANG advisory headline, bound to the LIVE carrierAcceptanceRate.
    /// Honest "—" when there is no active carrier or no decided tenders in the
    /// window (was a hardcoded "94%").
    private var advisoryHeadline: String {
        guard let carrier = active?.carrier, !carrier.isEmpty else {
            return "ESang: — acceptance data unavailable"
        }
        // Only trust the rate if it was fetched for THIS carrier and has data.
        guard let rate = acceptance,
              acceptanceCarrier == carrier,
              rate.hasData else {
            return "ESang: \(carrier) accepts — of \(commodityLabel)"
        }
        let pct = formatRate(rate.acceptanceRate)
        return "ESang: \(carrier) accepts \(pct) of \(commodityLabel)"
    }

    /// 0-100 one-decimal rate → "94%" / "92.5%" (drop a trailing ".0").
    private func formatRate(_ r: Double) -> String {
        if r == r.rounded() { return "\(Int(r))%" }
        return String(format: "%.1f%%", r)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if let err = actionError { banner(err, danger: true) }
                    if let note = actionNote { banner(note, danger: false) }

                    if loading {
                        loadingCard
                    } else {
                        activeTenderHero
                        tenderStatusSection
                        tenderHistorySection
                        esangAdvisory
                        ctaRow
                    }
                    Color.clear.frame(height: 96)   // Shipper nav chrome spacer
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
            }
        }
        .eusoRefreshTask { await load() }
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EusoTripEyebrow(verbatim: "SHIPPER · RAIL · TENDER")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                if let s = active?.status?.lowercased(), s == "submitted" || s == "pending" {
                    Text("AWAITING 990")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Color(hex: 0xB26A00))   // verbatim SVG amber
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                Text("Load tender")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.5)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: Space.s2)
            }
            .padding(.top, Space.s4)
            Text(subLine)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s2)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.top, Space.s5)
    }

    // MARK: - Active tender hero (gradient-rimmed · tenderHistory active row)

    private var activeTenderHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient.primary)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(Color(hex: 0x1C2128))           // verbatim SVG card fill
                .padding(1.5)

            if let a = active {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text("ACTIVE TENDER · EDI 404 → \(a.carrier ?? "-")")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(Color(hex: 0x6E7681))
                        Spacer()
                        statusPill(a.status)
                    }
                    Text("\(a.carrier ?? "-") · \(a.railcarCount.map(String.init) ?? "-") \(carLabel(a.carType))")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.top, Space.s4)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(dash(a.originScac ?? a.origin)) → \(dash(a.destinationScac ?? a.destination)) · single-line")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, Space.s3)
                        .lineLimit(1).minimumScaleFactor(0.7)

                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        .padding(.top, Space.s4)

                    Text("\(dash(a.tenderId)) · control \(dash(a.controlNumber))")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, Space.s4)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("RAIL-\(a.shipmentId.map(String.init) ?? "-") · STCC \(dash(a.commodityStcc)) · pickup \(dash(a.pickupDate))")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, 4)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(20)
            } else {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("NO ACTIVE TENDER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Color(hex: 0x6E7681))
                    Text("Send an EDI 404 to a Class I railroad")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Tap “Re-tender to alt carrier” to start, or review past tenders below.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 134)
    }

    private func statusPill(_ status: String?) -> some View {
        let s = (status ?? "submitted").lowercased()
        let (label, color): (String, Color) = {
            switch s {
            case "accepted":  return ("ACCEPTED", Color(hex: 0x00966B))
            case "declined":  return ("DECLINED", Color(hex: 0xC2403A))
            case "cancelled": return ("CANCELLED", Brand.neutral)
            default:          return ("SUBMITTED", Brand.blue)
            }
        }()
        return Text(label)
            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func carLabel(_ code: String?) -> String {
        switch (code ?? "").lowercased() {
        case "covered_hopper": return "covered hopper"
        case "open_hopper":    return "open hopper"
        case "boxcar":         return "boxcar"
        case "tankcar":        return "tank car"
        case "centerbeam":     return "center-beam"
        case "gondola":        return "gondola"
        case "intermodal":     return "intermodal"
        default:               return code?.replacingOccurrences(of: "_", with: " ") ?? "car"
        }
    }

    // MARK: - Tender status (receiveTenderResponse reflection)

    private var tenderStatusSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("TENDER STATUS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            HStack(alignment: .top, spacing: Space.s3) {
                Circle().fill(statusDotColor).frame(width: 10, height: 10)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusHeadline)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(statusDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s2)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(card)
        }
    }

    private var statusDotColor: Color {
        switch (active?.status ?? "").lowercased() {
        case "accepted":  return Color(hex: 0x00966B)
        case "declined":  return Color(hex: 0xC2403A)
        default:          return Color(hex: 0xB26A00)   // amber pending (verbatim)
        }
    }
    private var statusHeadline: String {
        switch (active?.status ?? "").lowercased() {
        case "accepted": return "EDI 990 received · accepted"
        case "declined": return "EDI 990 received · declined"
        default:         return active == nil ? "No tender awaiting response" : "Awaiting EDI 990 · pending"
        }
    }
    private var statusDetail: String {
        if active == nil { return "Re-tender to a Class I carrier to begin." }
        return "Typically 15–60 min · auto-poll on"
    }

    // MARK: - Tender history (tenderHistory terminal rows)

    private var tenderHistorySection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("TENDER HISTORY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            VStack(spacing: 0) {
                if history.isEmpty {
                    Text("No past tenders for this shipment yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.vertical, 18)
                } else {
                    ForEach(Array(history.enumerated()), id: \.element.id) { idx, row in
                        historyRow(row)
                        if idx < history.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                                .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .background(card)
        }
    }

    private func historyRow(_ r: RailTenderHistoryRow008) -> some View {
        let lane = "\(r.carrier ?? "-") · \(dash(r.originScac ?? r.origin)) → \(dash(r.destinationScac ?? r.destination))"
        let meta = "\(shortDate(r.timestamp ?? r.submittedAt)) · \(r.railcarCount.map(String.init) ?? "-") cars · STCC \(dash(r.commodityStcc))"
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lane)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(meta)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            statusPill(r.status)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private func shortDate(_ iso: String?) -> String {
        guard let iso, iso.count >= 10 else { return "-" }
        // ISO-8601 "2026-05-21T..." → "May 21"
        let ymd = String(iso.prefix(10)).split(separator: "-")
        guard ymd.count == 3, let m = Int(ymd[1]), let d = Int(ymd[2]) else { return "-" }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard m >= 1, m <= 12 else { return "-" }
        return "\(months[m]) \(d)"
    }

    // MARK: - ESang advisory (design-canon hint band, gated on the live active carrier)

    private var esangAdvisory: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.primary).frame(width: 32, height: 32)
                Circle().fill(Color.white.opacity(0.25)).frame(width: 16, height: 16)
                    .offset(x: -5, y: -5)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(advisoryHeadline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Auto re-tender to \(nextCarrier(after: active?.carrier)) if no EDI 990 by 60 min")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(16)
        .background(card)
    }

    // MARK: - CTA row (submitTender re-tender · cancelTender)

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await reTender() } } label: {
                HStack(spacing: Space.s2) {
                    if retendering { ProgressView().tint(.white) }
                    Text(retendering ? "Re-tendering…" : "Re-tender to alt carrier")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(LinearGradient.primary))
                .opacity(canReTender ? 1 : 0.5)
            }
            .disabled(!canReTender || retendering)

            Button { Task { await cancel() } } label: {
                HStack(spacing: Space.s2) {
                    if cancelling { ProgressView().controlSize(.small).tint(palette.textPrimary) }
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .frame(width: 132, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(hex: 0x232932))          // verbatim SVG secondary
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                )
                .opacity(canCancel ? 1 : 0.5)
            }
            .disabled(!canCancel || cancelling)
        }
    }

    /// Re-tender needs the active tender's lane/equipment to carry forward.
    private var canReTender: Bool { active != nil }
    private var canCancel: Bool { active?.isPending == true && active?.tenderId != nil }

    // MARK: - Loading / banners

    private var loadingCard: some View {
        HStack(spacing: Space.s3) {
            ProgressView().controlSize(.small).tint(palette.textTertiary)
            Text("Loading tenders…").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(Space.s4).background(card)
    }

    private func banner(_ msg: String, danger: Bool) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: danger ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(danger ? Brand.warning : Brand.success)
            Text(msg).font(.system(size: 12)).foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill((danger ? Brand.warning : Brand.success).opacity(0.12)))
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(hex: 0x1C2128))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Endpoints (single REAL call each — honest do/catch)

    private func load() async {
        loading = true; actionError = nil
        struct HistIn: Encodable { let shipmentId: Int; let limit: Int }
        do {
            let r: [RailTenderHistoryRow008] = try await EusoTripAPI.shared.query(
                "railTenderWorkflow.tenderHistory",
                input: HistIn(shipmentId: shipmentId, limit: 100))
            self.rows = r
        } catch {
            actionError = "Couldn’t load tenders. " +
                ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        loading = false
        await loadAcceptance()
    }

    /// Hydrate the ESANG advisory's acceptance rate from the REAL
    /// `railTenderWorkflow.carrierAcceptanceRate` proc, keyed on the active
    /// tender's carrier (+ commodity STCC). No active carrier → clear it
    /// (advisory shows "—"). A failed read leaves the prior value cleared so the
    /// advisory degrades to "—" rather than a stale/fabricated figure.
    private func loadAcceptance() async {
        guard let carrier = active?.carrier, !carrier.isEmpty else {
            acceptance = nil; acceptanceCarrier = nil
            return
        }
        let stcc = active?.commodityStcc?.trimmingCharacters(in: .whitespaces)
        do {
            let rate = try await EusoTripAPI.shared.railTenderWorkflow.carrierAcceptanceRate(
                carrier: carrier,
                commodityStcc: (stcc?.isEmpty == false) ? stcc : nil)
            // Re-decode into the view-local shape (1:1 fields) so the view owns
            // its render contract independent of the API namespace struct.
            self.acceptance = RailAcceptanceRate008(
                carrier: rate.carrier,
                acceptanceRate: rate.acceptanceRate,
                accepted: rate.accepted,
                total: rate.total,
                windowDays: rate.windowDays)
            self.acceptanceCarrier = carrier
        } catch {
            // Honest degrade — advisory renders "—" (never the old 94%).
            acceptance = nil; acceptanceCarrier = nil
        }
    }

    /// Re-tender the active load to the next Class I carrier (submitTender). Real write.
    private func reTender() async {
        guard let a = active else { return }
        retendering = true; actionError = nil; actionNote = nil
        struct SubmitIn: Encodable {
            let shipmentId: Int; let carrier: String
            let originScac: String; let destinationScac: String
            let commodityStcc: String; let carType: String
            let railcarCount: Int; let pickupDate: String
        }
        let carrier = nextCarrier(after: a.carrier)
        do {
            let res: SubmitResult008 = try await EusoTripAPI.shared.mutation(
                "railTenderWorkflow.submitTender",
                input: SubmitIn(
                    shipmentId: a.shipmentId ?? shipmentId,
                    carrier: carrier,
                    originScac: a.originScac ?? a.origin ?? "",
                    destinationScac: a.destinationScac ?? a.destination ?? "",
                    commodityStcc: a.commodityStcc ?? "",
                    carType: a.carType ?? "covered_hopper",
                    railcarCount: a.railcarCount ?? 1,
                    pickupDate: a.pickupDate ?? ""))
            actionNote = "Re-tendered to \(carrier) · \(res.tenderId ?? "submitted")."
            await load()
        } catch {
            actionError = "Couldn’t re-tender. " +
                ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        retendering = false
    }

    /// Cancel the active pending tender (cancelTender). Real write.
    private func cancel() async {
        guard let tid = active?.tenderId else { return }
        cancelling = true; actionError = nil; actionNote = nil
        struct CancelIn: Encodable { let tenderId: String }
        do {
            let res: CancelResult008 = try await EusoTripAPI.shared.mutation(
                "railTenderWorkflow.cancelTender",
                input: CancelIn(tenderId: tid))
            actionNote = "Tender \(res.tenderId ?? tid) \(res.status ?? "cancelled")."
            await load()
        } catch {
            actionError = "Couldn’t cancel the tender. " +
                ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        cancelling = false
    }
}

// MARK: - Previews

#Preview("008 · Rail Tender Workflow · Night") {
    RailShipperTenderWorkflow_008()
        .preferredColorScheme(.dark)
}
