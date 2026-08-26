//
//  594_RailCostBreakdown.swift
//  EusoTrip — Rail Engineer · Cost Breakdown (intermodal all-in landed cost).
//
//  CARRIER-SIDE (RAIL_ENGINEER vantage). Money-ledger grammar (227 Settlement-
//  Detail): big gradient figure + subline + hero card + colored-dot breakdown
//  ledger + TOTAL strip + margin card + CTA pair. Rolls the per-leg economics
//  of an intermodal rail move (segment line-haul rates + inter-leg transfer
//  costs) into one all-in landed cost.
//
//  Web parity: client/src/pages/rail/IntermodalCost.tsx (/rail/intermodal/:id/cost).
//  tRPC (server/routers/intermodal.ts), bound to the REAL return shapes:
//    per-leg ledger → intermodal.getIntermodalCostBreakdown (EXISTS · :295)
//        input  { intermodalShipmentId: number }
//        output { intermodalNumber, segments[{legNumber,mode,rate,status}],
//                 transfers[{transferType,cost,facilityName}],
//                 totalSegmentCost, totalTransferCost, grandTotal, currency }
//    Export cost sheet → STUB·named-gap rail.exportCostSheet (PORT-GAP).
//
//  HONESTY NOTE — there is NO margin/benchmark/shipper-charge endpoint in
//  intermodal.ts. `getIntermodalDashboard` takes no input and returns only
//  { activeShipments, avgTransitDays, modeSplit, totalRevenue } — it carries
//  NO per-shipment margin, lane benchmark, or shipper charge. So the
//  margin-vs-benchmark card renders an honest "unavailable" state rather than
//  fabricating margin %, benchmark $, or a shipper persona. The shipper line
//  on the hero card binds to the SESSION user (or "—"), never a hardcoded
//  founder company.
//
//  RBAC railProcedure (RAIL_ENGINEER|CATALYST). The persisted shipment
//  currency qualifies every displayed amount; this surface never assumes USD.
//

import SwiftUI

struct RailCostBreakdownScreen: View {
    let theme: Theme.Palette
    /// Intermodal shipment whose per-leg economics we roll up. Defaulted to 0
    /// so the top-level struct only requires `theme` (router supplies the real
    /// id when one is in scope). The server proc input is `z.number()`, so this
    /// is an Int — matching every sibling intermodal screen. With no real id
    /// selected the proc returns nothing and we render the honest empty state.
    var intermodalShipmentId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            RailCostBreakdownBody(intermodalShipmentId: intermodalShipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (REAL return shapes from intermodal.getIntermodalCostBreakdown)

/// One rail/dray segment of the move. Server: `segments[]` in the cost
/// breakdown (legNumber · mode · rate · status).
private struct ICBSegmentCost: Decodable {
    struct MetricStates: Decodable {
        let rate: FreightClaimsAPI.MetricTruth
    }

    let legNumber: Int?
    let mode: String?       // RAIL · TRUCK · VESSEL
    let rate: Double?
    let currency: FreightClaimsAPI.CurrencyCode?
    let status: String?     // booked · in_transit · completed · pending
    let metricStates: MetricStates?
}

/// One inter-leg transfer (ramp lift / transload / dray hand-off). Server:
/// `transfers[]` in the cost breakdown (transferType · cost · facilityName).
private struct ICBTransferCost: Decodable {
    struct MetricStates: Decodable {
        let cost: FreightClaimsAPI.MetricTruth
    }

    let transferType: String?   // rail_to_truck · truck_to_rail · …
    let cost: Double?
    let currency: FreightClaimsAPI.CurrencyCode?
    let facilityName: String?   // ramp / terminal name (may be absent)
    let metricStates: MetricStates?
}

/// Whole roll-up returned by `intermodal.getIntermodalCostBreakdown`.
/// Every field is exactly what the proc emits — nothing invented.
private struct IntermodalCostBreakdown: Decodable {
    struct MetricStates: Decodable {
        let totalSegmentCost: FreightClaimsAPI.MetricTruth
        let totalTransferCost: FreightClaimsAPI.MetricTruth
        let grandTotal: FreightClaimsAPI.MetricTruth
    }

    let intermodalNumber: String?
    let segments: [ICBSegmentCost]?
    let transfers: [ICBTransferCost]?
    let totalSegmentCost: Double?
    let totalTransferCost: Double?
    let grandTotal: Double?
    let currency: FreightClaimsAPI.CurrencyCode?
    let metricStates: MetricStates?
}

/// A single rendered ledger line, derived locally from the REAL segments +
/// transfers (NOT decoded from an invented `legs[]` the proc never returns).
private struct LedgerLine: Identifiable {
    let id: String
    let label: String
    let detail: String?
    let amount: Double?
    let currency: FreightClaimsAPI.CurrencyCode?
    let formattedAmount: String?
}

// MARK: - Body

private struct RailCostBreakdownBody: View {
    let intermodalShipmentId: Int

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @State private var breakdown: IntermodalCostBreakdown? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var exporting = false
    @State private var exportError: String? = nil
    @State private var exportNotice: String? = nil

    // Leg-color palette — matches the quad-color breakdown bar order in the
    // wireframe: leg 0 (gradient/blue), 1 (escort purple), 2 (hazmat amber),
    // 3+ (success green). Driven by ledger-line index, not by a fabricated
    // legType enum.
    private func legColor(_ index: Int) -> Color {
        switch index {
        case 0:  return Brand.blue
        case 1:  return Brand.escort   // 0x9C27B0
        case 2:  return Brand.hazmat   // 0xFFB100
        default: return Brand.success  // 0x00C48C
        }
    }

    private func qualifiedMoney(
        _ value: Double?,
        currency: FreightClaimsAPI.CurrencyCode?,
        truth: FreightClaimsAPI.MetricTruth?,
        source: String
    ) -> Double? {
        guard let value,
              value.isFinite,
              value >= 0,
              currency != nil,
              let truth,
              truth.valueState == .measured,
              truth.accessState == .granted,
              truth.trackingState == .tracked,
              truth.provenance.source == source,
              truth.provenance.observedAt != nil,
              truth.provenance.computedAt != nil else {
            return nil
        }
        return value
    }

    private func formattedMoney(
        _ value: Double?,
        currency: FreightClaimsAPI.CurrencyCode?,
        truth: FreightClaimsAPI.MetricTruth?,
        source: String,
        whole: Bool = false
    ) -> String? {
        guard let value = qualifiedMoney(value, currency: currency, truth: truth, source: source),
              let currency else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.minimumFractionDigits = whole ? 0 : 2
        formatter.maximumFractionDigits = whole ? 0 : 2
        return formatter.string(from: NSNumber(value: value))
            ?? "\(currency.rawValue) \(value.formatted(.number.precision(.fractionLength(whole ? 0 : 2))))"
    }

    // Human label for a transport mode token returned by the proc.
    private func modeWord(_ mode: String?) -> String {
        switch (mode ?? "").uppercased() {
        case "RAIL":   return "Rail"
        case "TRUCK":  return "Drayage"
        case "VESSEL": return "Vessel"
        default:       return (mode ?? "Leg").capitalized
        }
    }

    // Human label for a transfer-type token (e.g. "rail_to_truck" → "Rail → drayage").
    private func transferWord(_ t: String?) -> String {
        guard let raw = t, !raw.isEmpty else { return "Transfer" }
        let parts = raw.lowercased().split(separator: "_")
        func word(_ s: Substring) -> String {
            switch s {
            case "rail":   return "rail"
            case "truck":  return "drayage"
            case "vessel": return "vessel"
            default:       return String(s)
            }
        }
        // pattern: <mode>_to_<mode>
        if parts.count == 3, parts[1] == "to" {
            return "\(word(parts[0]).capitalized) → \(word(parts[2]))"
        }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Real ledger lines: one per segment (line-haul by mode) + one per
    /// transfer (ramp/transload/dray hand-off). Derived from what the proc
    /// actually returns; no invented leg labels, carriers, or mileage.
    private var ledgerLines: [LedgerLine] {
        guard let b = breakdown else { return [] }
        var lines: [LedgerLine] = []
        for seg in (b.segments ?? []) {
            let legNo = seg.legNumber.map(String.init) ?? "—"
            let statusDetail = (seg.status?.isEmpty == false)
                ? "Status \(seg.status!)" : nil
            let amount = qualifiedMoney(
                seg.rate,
                currency: seg.currency,
                truth: seg.metricStates?.rate,
                source: "intermodal_segments.rate+intermodal_shipments.currency"
            )
            lines.append(LedgerLine(
                id: "seg-\(legNo)-\(seg.mode ?? "")",
                label: "\(modeWord(seg.mode)) · leg \(legNo)",
                detail: statusDetail,
                amount: amount,
                currency: seg.currency,
                formattedAmount: formattedMoney(
                    seg.rate,
                    currency: seg.currency,
                    truth: seg.metricStates?.rate,
                    source: "intermodal_segments.rate+intermodal_shipments.currency"
                )))
        }
        for (i, t) in (b.transfers ?? []).enumerated() {
            let facility = (t.facilityName?.isEmpty == false) ? t.facilityName : nil
            let amount = qualifiedMoney(
                t.cost,
                currency: t.currency,
                truth: t.metricStates?.cost,
                source: "intermodal_transfers.transferCost+intermodal_shipments.currency"
            )
            lines.append(LedgerLine(
                id: "xfer-\(i)",
                label: "Transfer · \(transferWord(t.transferType))",
                detail: facility,
                amount: amount,
                currency: t.currency,
                formattedAmount: formattedMoney(
                    t.cost,
                    currency: t.currency,
                    truth: t.metricStates?.cost,
                    source: "intermodal_transfers.transferCost+intermodal_shipments.currency"
                )))
        }
        return lines
    }

    /// All-in landed cost exactly as the proc qualifies it. A missing or
    /// partial source remains nil; the client never manufactures a total.
    private var landedTotal: Double? {
        guard let b = breakdown else { return nil }
        return qualifiedMoney(
            b.grandTotal,
            currency: b.currency,
            truth: b.metricStates?.grandTotal,
            source: "intermodal_segments.rate+intermodal_transfers.transferCost+intermodal_shipments.currency"
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                backRow
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else if let b = breakdown, hasContent(b) {
                    hero(b)
                    IridescentHairline().padding(.vertical, Space.s4)
                    heroCard(b)
                    legLedger()
                    totalStrip()
                    marginCard()
                    ctaPair(b)
                } else {
                    emptyState
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    /// The proc can return a non-nil object with no segments/transfers/total
    /// (e.g. a planned shipment that isn't priced). Treat that as empty so we
    /// show the honest EusoEmptyState rather than a $0 ledger.
    private func hasContent(_ b: IntermodalCostBreakdown) -> Bool {
        let hasLines = !((b.segments ?? []).isEmpty && (b.transfers ?? []).isEmpty)
        return hasLines || landedTotal != nil
    }

    // MARK: - Top bar (eyebrow + reference caption)

    private var topBar: some View {
        HStack {
            EusoTripEyebrow(verbatim: "RAIL ENGINEER · COST BREAKDOWN")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(refTail)
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.bottom, Space.s3)
    }

    private var refTail: String {
        // Last visible shard of the REAL intermodal number (e.g. "IM-48213").
        // No invented "RAIL · 7C3A" fallback — em-dash when absent.
        guard let ref = breakdown?.intermodalNumber, !ref.isEmpty else { return "—" }
        return ref
    }

    // MARK: - Back chevron + breadcrumb

    private var backRow: some View {
        HStack(spacing: 8) {
            Text("Shipment")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(.bottom, Space.s3)
    }

    // MARK: - Hero figure + subline

    private func hero(_ b: IntermodalCostBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedMoney(
                b.grandTotal,
                currency: b.currency,
                truth: b.metricStates?.grandTotal,
                source: "intermodal_segments.rate+intermodal_transfers.transferCost+intermodal_shipments.currency",
                whole: true
            ).map { "\($0) landed" } ?? "Landed cost unavailable")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(heroSubline(b))
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heroSubline(_ b: IntermodalCostBreakdown) -> String {
        // Bind to the SESSION user + REAL intermodal number. No founder company,
        // no invented origin/destination — the cost-breakdown proc carries no
        // lane/origin/destination, so we show only what we honestly have.
        let shipper = session.user?.name ?? "—"
        let ref = (b.intermodalNumber?.isEmpty == false) ? b.intermodalNumber! : "—"
        return "\(shipper) · \(ref)"
    }

    // MARK: - Hero intermodal card

    private func heroCard(_ b: IntermodalCostBreakdown) -> some View {
        HStack(spacing: 0) {
            // Gradient left rail (3pt).
            LinearGradient.diagonal.frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                // Reference + leg-count badge (real segment count).
                HStack {
                    Text(b.intermodalNumber ?? "—")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .monospacedDigit()
                    Spacer()
                    Text("\(legCount) LEGS")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(LinearGradient.primary)
                        .clipShape(Capsule())
                }
                Text(laneLine(b))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 12)
                Text(equipmentLine(b))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 4)
                // Shipper footer row (session user; no founder persona).
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 12, height: 12)
                        Text(shipperMonogram)
                            .font(.system(size: 6, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    (Text("Shipper ")
                        .foregroundStyle(palette.textSecondary)
                     + Text(session.user?.name ?? "—")
                        .foregroundStyle(palette.textPrimary).bold())
                        .font(.system(size: 10.5))
                    Spacer()
                }
                .padding(.top, 14)
            }
            .padding(16)
        }
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var legCount: Int {
        (breakdown?.segments?.count ?? 0)
    }

    // Two-letter monogram from the session user's name; "—" placeholder glyph
    // when unknown. Never the hardcoded founder "DU".
    private var shipperMonogram: String {
        guard let name = session.user?.name, !name.isEmpty else { return "—" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // Lane line: the cost-breakdown proc carries NO origin/destination/lane.
    // We render the modal composition it DOES carry (rail/dray legs), or an
    // em-dash — never an invented "Long Beach → Joliet".
    private func laneLine(_ b: IntermodalCostBreakdown) -> String {
        let modes = (b.segments ?? [])
            .compactMap { $0.mode }
            .map { modeWord($0) }
        guard !modes.isEmpty else { return "—" }
        return modes.joined(separator: " → ")
    }

    // Equipment line: the proc carries no equipment / mileage / line-haul
    // carrier. Show the real composition counts (segments + transfers) instead
    // of fabricating "53′ domestic · 4 legs · 2,176 mi · BNSF".
    private func equipmentLine(_ b: IntermodalCostBreakdown) -> String {
        let segs = b.segments?.count ?? 0
        let xfers = b.transfers?.count ?? 0
        let segPart = "\(segs) \(segs == 1 ? "segment" : "segments")"
        let xferPart = xfers > 0 ? " · \(xfers) \(xfers == 1 ? "transfer" : "transfers")" : ""
        let curr = b.currency.map { " · \($0.rawValue)" } ?? ""
        return segPart + xferPart + curr
    }

    // MARK: - Cost-by-leg breakdown ledger

    private func legLedger() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("COST BY LEG")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("per-leg · all-in")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s2)

            let lines = ledgerLines
            let values = lines.compactMap(\.amount)
            let total = values.isEmpty ? nil : values.reduce(0, +)

            VStack(alignment: .leading, spacing: 0) {
                breakdownBar(lines: lines, total: total)
                    .padding(.bottom, 18)
                ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                    legRow(line, color: legColor(idx))
                    if idx < lines.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                            .padding(.vertical, 10)
                    }
                }
            }
            .padding(16)
            .background(palette.bgCardSoft)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func breakdownBar(lines: [LedgerLine], total: Double?) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                    if let amount = line.amount, let total, total > 0 {
                        Rectangle()
                            .fill(idx == 0 ? AnyShapeStyle(LinearGradient.primary)
                                           : AnyShapeStyle(legColor(idx)))
                            .frame(width: max(0, w * amount / total))
                    }
                }
            }
            .frame(height: 8)
            .background(Color(hex: 0x05060A))
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }

    private func legRow(_ line: LedgerLine, color: Color) -> some View {
        // Percent-of-total is computed locally from real amounts (the proc
        // returns no pctOfTotal field), and only shown when a positive total
        // exists so we never print a fabricated share.
        let values = ledgerLines.compactMap(\.amount)
        let total = values.isEmpty ? nil : values.reduce(0, +)
        let pct: Double? = line.amount.flatMap { amount in
            guard let total, total > 0 else { return nil }
            return (amount / total) * 100
        }
        return HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color == Brand.blue ? AnyShapeStyle(LinearGradient.diagonal)
                                          : AnyShapeStyle(color))
                .frame(width: 10, height: 10)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(line.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                if let detail = line.detail, !detail.isEmpty {
                    Text(detail)
                        .font(EType.mono(.caption)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(line.formattedAmount ?? "—")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                if let pct {
                    Text(String(format: "%.1f%%", pct))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color == Brand.blue ? palette.textSecondary : color)
                }
            }
        }
    }

    // MARK: - TOTAL strip

    private func totalStrip() -> some View {
        HStack {
            Text("TOTAL · LANDED")
                .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(breakdown.flatMap { b in
                formattedMoney(
                    b.grandTotal,
                    currency: b.currency,
                    truth: b.metricStates?.grandTotal,
                    source: "intermodal_segments.rate+intermodal_transfers.transferCost+intermodal_shipments.currency"
                )
            } ?? "—")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(palette.textPrimary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .padding(.top, Space.s4)
    }

    // MARK: - Margin vs lane benchmark card (HONEST: no source endpoint)

    private func marginCard() -> some View {
        // There is NO intermodal margin / lane-benchmark / shipper-charge proc.
        // `getIntermodalDashboard` (no input) returns only platform-wide
        // counters — nothing per-shipment. We refuse to fabricate margin %,
        // benchmark $, or shipper charge: surface the real subtotals the cost
        // breakdown DOES carry, and state plainly that margin is unavailable.
        VStack(alignment: .leading, spacing: 0) {
            Text("MARGIN VS LANE BENCHMARK")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s2)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Line-haul (segments)")
                            .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                        Text(breakdown.flatMap { b in
                            formattedMoney(
                                b.totalSegmentCost,
                                currency: b.currency,
                                truth: b.metricStates?.totalSegmentCost,
                                source: "intermodal_segments.rate+intermodal_shipments.currency",
                                whole: true
                            )
                        } ?? "—")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                    }
                    Spacer().frame(width: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transfers")
                            .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                        Text(breakdown.flatMap { b in
                            formattedMoney(
                                b.totalTransferCost,
                                currency: b.currency,
                                truth: b.metricStates?.totalTransferCost,
                                source: "intermodal_transfers.transferCost+intermodal_shipments.currency",
                                whole: true
                            )
                        } ?? "—")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                    }
                    Spacer()
                }
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                    .padding(.vertical, 12)
                Text("Margin vs lane benchmark unavailable — no per-shipment benchmark or shipper-charge source for this lane.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(palette.bgCardSoft)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: - CTA pair

    private func ctaPair(_ b: IntermodalCostBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = exportNotice {
                Text(notice).font(EType.caption).foregroundStyle(Brand.success)
            }
            if let err = exportError {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
            HStack(spacing: 8) {
                Button {
                    Task { await exportSheet(b) }
                } label: {
                    Text(exporting ? "Exporting…" : "Export cost sheet")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(LinearGradient.primary)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(exporting ? 0.6 : 1.0)
                .disabled(exporting)

                Button {
                    Task { await dispute(b) }
                } label: {
                    Text("Dispute")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 148, height: 48)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Space.s5)
    }

    // MARK: - Lifecycle states

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
        .padding(.top, Space.s4)
    }

    private func errorState(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
        .padding(.top, Space.s4)
    }

    private var emptyState: some View {
        EusoEmptyState(
            systemImage: "dollarsign.square",
            title: "No cost breakdown",
            subtitle: "Per-leg intermodal economics will appear here once the lane is priced."
        )
        .padding(.top, Space.s4)
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct CostIn: Encodable { let intermodalShipmentId: Int }
        let input = CostIn(intermodalShipmentId: intermodalShipmentId)
        do {
            // per-leg ledger → intermodal.getIntermodalCostBreakdown EXISTS·intermodal.ts:295
            // (input is z.number(); we send Int). The proc returns null for an
            // unknown id — query() decodes that to a nil/empty object and we
            // fall through to the honest empty state.
            let bd: IntermodalCostBreakdown = try await EusoTripAPI.shared.query(
                "intermodal.getIntermodalCostBreakdown", input: input)
            self.breakdown = bd
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Export cost sheet (PORT-GAP)

    private func exportSheet(_ b: IntermodalCostBreakdown) async {
        exporting = true; exportError = nil; exportNotice = nil
        struct ExportIn: Encodable { let intermodalShipmentId: Int }
        struct ExportOut: Decodable { let url: String?; let format: String? }
        do {
            // PORT-GAP: rail.exportCostSheet — STUB·named-gap on the server.
            // Proposed: railCost.exportSheet({intermodalShipmentId})->{url,format}
            // (writes documents row + blockchainAuditTrail entry; broadcasts
            // WS_CHANNELS.SHIPMENT/WS_EVENTS.DOC_GENERATED). Wired through the
            // generic mutate path so it activates the moment the route lands
            // server-side; surfaces a real error until then.
            let out: ExportOut = try await EusoTripAPI.shared.mutation(
                "rail.exportCostSheet",
                input: ExportIn(intermodalShipmentId: intermodalShipmentId))
            if let fmt = out.format {
                exportNotice = "Cost sheet exported (\(fmt.uppercased()))."
            } else {
                exportNotice = "Cost sheet exported."
            }
        } catch {
            exportError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        exporting = false
    }

    // MARK: - Dispute

    private func dispute(_ b: IntermodalCostBreakdown) async {
        exportError = nil; exportNotice = nil
        struct DisputeIn: Encodable { let intermodalShipmentId: Int; let reason: String }
        struct AmountStates: Decodable { let amount: FreightClaimsAPI.MetricTruth }
        struct Provenance: Decodable { let source: String; let observedAt: String?; let computedAt: String? }
        struct DisputeOut: Decodable {
            let id: String?
            let status: String?
            let amount: Double?
            let currency: FreightClaimsAPI.CurrencyCode?
            let metricStates: AmountStates
            let provenance: Provenance
        }
        struct ReadbackInput: Encodable { let limit: Int; let offset: Int }
        struct Readback: Decodable {
            struct Row: Decodable {
                let id: String
                let status: String
                let amount: Double?
                let currency: FreightClaimsAPI.CurrencyCode?
                let metricStates: AmountStates
            }
            let disputes: [Row]
        }
        do {
            let out: DisputeOut = try await EusoTripAPI.shared.mutation(
                "freightClaims.createDispute",
                input: DisputeIn(intermodalShipmentId: intermodalShipmentId,
                                 reason: "Cost breakdown dispute"))
            guard let disputeId = out.id, !disputeId.isEmpty,
                  out.status?.lowercased() == "open",
                  out.provenance.source == "intermodal_shipments+disputes+dispute_events",
                  out.provenance.observedAt != nil,
                  out.provenance.computedAt != nil,
                  coherentDisputeMoney(amount: out.amount, currency: out.currency, truth: out.metricStates.amount) else {
                throw RailCostDisputeConfirmationError.invalidAcknowledgement
            }
            let readback: Readback = try await EusoTripAPI.shared.query(
                "freightClaims.getDisputeResolution",
                input: ReadbackInput(limit: 50, offset: 0)
            )
            guard readback.disputes.contains(where: {
                $0.id == disputeId
                    && $0.status.lowercased() == "filed"
                    && $0.currency == out.currency
                    && sameOptionalMoney($0.amount, out.amount)
                    && coherentDisputeMoney(amount: $0.amount, currency: $0.currency, truth: $0.metricStates.amount)
            }) else {
                throw RailCostDisputeConfirmationError.readbackMismatch
            }
            exportNotice = "Dispute \(disputeId) confirmed."
        } catch {
            exportError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func coherentDisputeMoney(
        amount: Double?,
        currency: FreightClaimsAPI.CurrencyCode?,
        truth: FreightClaimsAPI.MetricTruth
    ) -> Bool {
        if truth.valueState == .noObservations {
            return amount == nil
                && currency == nil
                && truth.accessState == .granted
                && truth.trackingState == .tracked
                && truth.provenance.source == "disputes.amountInDispute+baseCurrency"
                && truth.provenance.observedAt == nil
                && truth.provenance.computedAt != nil
        }
        return amount.map { $0 > 0 } == true
            && currency != nil
            && truth.valueState == .measured
            && truth.accessState == .granted
            && truth.trackingState == .tracked
            && truth.provenance.source == "disputes.amountInDispute+baseCurrency"
            && truth.provenance.observedAt != nil
            && truth.provenance.computedAt != nil
    }

    private func sameOptionalMoney(_ left: Double?, _ right: Double?) -> Bool {
        switch (left, right) {
        case (nil, nil): return true
        case let (left?, right?): return abs(left - right) < 0.005
        default: return false
        }
    }
}

private enum RailCostDisputeConfirmationError: LocalizedError {
    case invalidAcknowledgement
    case readbackMismatch

    var errorDescription: String? {
        switch self {
        case .invalidAcknowledgement:
            return "The dispute acknowledgement did not preserve its amount, currency, and provenance state."
        case .readbackMismatch:
            return "The dispute could not be confirmed in the live dispute ledger."
        }
    }
}

#Preview("594 · Rail Cost Breakdown · Night") { RailCostBreakdownScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("594 · Rail Cost Breakdown · Light") { RailCostBreakdownScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
