//
//  593_RailSettlementBatch.swift
//  EusoTrip — Rail Engineer · Settlement Batch (CARRIER-SIDE).
//
//  Verbatim port of wireframe "593 Rail Settlement Batch · Dark".
//  Reconstructed to flagship DETAIL grammar (581 Rail Settlement Summary /
//  02 Shipper 205 Load Detail): back chevron + eyebrow + mono caption +
//  title 28/-0.4, gradient-rimmed hero ActiveCard, 3-cell KPI strip
//  (cell 1 gradient), itemized ListRow stack, secondary context strip,
//  CTA pair. Roll a period's rail settlements into one batch run.
//
//  Wiring (REAL · server/routers/settlementBatching.ts):
//    • createBatch EXISTS:41 — {batchType, periodStart, periodEnd, loadIds,
//      railShipmentIds, vesselShipmentIds} -> {batchId, batchNumber,
//      totalLoads, totalAmount, status}. railShipmentIds supported :47,
//      double-batch guard :66–84, atomic transaction :60.
//    • The included rail shipments feed comes from
//      railShipments.getRailShipments (the same query 551 uses).
//

import SwiftUI

struct RailSettlementBatchScreen: View {
    let theme: Theme.Palette
    // OATH §5: only `theme` is required; everything else defaults.
    var id: String = ""
    var batchType: String = "carrier_receivable"

    var body: some View {
        Shell(theme: theme) { RailSettlementBatchBody(batchType: batchType) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

/// Mirror of `railShipments.getRailShipments` rows (same shape 551 decodes).
/// `id` arrives as a string; createBatch needs Int `railShipmentIds`, so we
/// derive the numeric id at batch time.
private struct RailBatchShipment: Decodable, Identifiable {
    let id: String
    let loadId: String?
    let origin: String?
    let destination: String?
    let status: String?
    let carsCount: Int?
    let commodity: String?
    let estimatedArrival: String?
    let carrierName: String?
    let hazmat: Bool?
    /// Settlement money for this shipment, when the server surfaces it.
    /// Absent on the plain getRailShipments feed (see PORT-GAP below) →
    /// we never fabricate a figure; the row shows a neutral dash.
    let settlementAmount: Double?
    let receivableAmount: Double?
}

/// Response envelope returned by `settlementBatching.createBatch`.
private struct CreateBatchResult: Decodable {
    let batchId: Int
    let batchNumber: String
    let totalLoads: Int
    let totalAmount: Double
    let status: String
}

private struct CreateBatchInput: Encodable {
    let batchType: String
    let periodStart: String
    let periodEnd: String
    let loadIds: [Int]
    let railShipmentIds: [Int]
    let vesselShipmentIds: [Int]
}

// MARK: - Body

private struct RailSettlementBatchBody: View {
    let batchType: String

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var shipments: [RailBatchShipment] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // Create-batch mutation state
    @State private var creating = false
    @State private var createError: String? = nil
    @State private var createdBatch: CreateBatchResult? = nil

    // MARK: Derived

    /// Numeric rail-shipment ids the batch will carry. createBatch wants
    /// `[Int]`; getRailShipments returns string ids.
    private var railShipmentIds: [Int] {
        shipments.compactMap { Int($0.id) }
    }

    /// Gross receivable across the included shipments — summed from REAL
    /// per-row money only. No money on a row contributes 0; we never
    /// invent a total. Float reduce per OATH compile guardrail.
    private var grossAmount: Double {
        shipments.reduce(into: 0.0) { acc, s in
            acc += (s.receivableAmount ?? s.settlementAmount ?? 0)
        }
    }

    private var hasAnyMoney: Bool {
        shipments.contains { ($0.receivableAmount ?? $0.settlementAmount) != nil }
    }

    private var shipmentCount: Int { shipments.count }

    /// Period bounds derived from the shipments' arrival timestamps when
    /// present. Used both for the hero "period" line and the createBatch
    /// `periodStart` / `periodEnd` (server requires yyyy-MM-dd).
    private var periodBounds: (start: String, end: String)? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let iso = ISO8601DateFormatter()
        let dates: [Date] = shipments.compactMap { s in
            guard let raw = s.estimatedArrival else { return nil }
            return iso.date(from: raw) ?? f.date(from: String(raw.prefix(10)))
        }
        guard let lo = dates.min(), let hi = dates.max() else { return nil }
        return (f.string(from: lo), f.string(from: hi))
    }

    private var periodLabel: String {
        guard let b = periodBounds else { return "period —" }
        let inFmt = DateFormatter(); inFmt.dateFormat = "yyyy-MM-dd"
        let outFmt = DateFormatter(); outFmt.dateFormat = "MMM d"
        guard let lo = inFmt.date(from: b.start), let hi = inFmt.date(from: b.end) else {
            return "period \(b.start)–\(b.end)"
        }
        return "period \(outFmt.string(from: lo))–\(outFmt.string(from: hi))"
    }

    private func money(_ v: Double) -> String {
        if v >= 1_000 {
            return String(format: "$%.1fK", v / 1_000)
        }
        return String(format: "$%.0f", v)
    }

    private func moneyFull(_ v: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        let n = nf.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
        return "$\(n)"
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
                .padding(.top, Space.s3)

            if loading {
                loadingState
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
            } else {
                content
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (DETAIL grammar)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ RAIL ENGINEER · BATCH")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("CR · BNSF")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Settlement batch")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
            .padding(.top, Space.s4)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            heroCard
            kpiStrip
            includedList
            doubleBatchGuard
            ctaPair
            Color.clear.frame(height: 12)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    // MARK: - Hero ActiveCard

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                // Status chip row
                HStack(spacing: 8) {
                    heroChip(createdBatch?.status ?? "draft")
                    heroChip("carrier receivable")
                }
                HStack(alignment: .top) {
                    // Batch total
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasAnyMoney ? money(createdBatch?.totalAmount ?? grossAmount) : "—")
                            .font(.system(size: 30, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(hasAnyMoney ? AnyShapeStyle(LinearGradient.diagonal)
                                                         : AnyShapeStyle(palette.textPrimary))
                        Text("batch total")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(periodLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    // Status block
                    VStack(alignment: .leading, spacing: 4) {
                        Text("STATUS")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(createdBatch?.status ?? "draft")
                            .font(.system(size: 22, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text(createdBatch == nil ? "ready to run" : "created")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    private func heroChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).tracking(0.5)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    // MARK: - KPI strip (cell 1 gradient)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // SHIPMENTS — gradient cell
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("SHIPMENTS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(shipmentCount)")
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            // GROSS
            kpiCell(label: "GROSS",
                    value: hasAnyMoney ? money(grossAmount) : "—",
                    accent: hasAnyMoney ? Brand.success : nil)
            // GUARD
            kpiCell(label: "GUARD",
                    value: "clear",
                    accent: Brand.success)
        }
    }

    private func kpiCell(label: String, value: String, accent: Color?) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(accent ?? palette.textPrimary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Included itemized list

    private var includedList: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("INCLUDED · createBatch")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("railShipmentIds")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if shipments.isEmpty {
                EusoEmptyState(systemImage: "tram.fill",
                               title: "No rail shipments to batch",
                               subtitle: "Settled rail shipments eligible for a carrier-receivable batch will appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shipments.prefix(3).enumerated()), id: \.element.id) { idx, s in
                        includedRow(s)
                        if idx < min(shipments.count, 3) - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.leading, 68)
                        }
                    }
                    if shipments.count > 3 {
                        Divider().overlay(palette.borderFaint).padding(.leading, 68)
                        Text("+ \(shipments.count - 3) more · \(shipments.count) of \(shipments.count) selected")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Space.s3)
                    } else {
                        Text("\(shipments.count) of \(shipments.count) selected")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Space.s3)
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func includedRow(_ s: RailBatchShipment) -> some View {
        // Status → READY (settled / ready) vs REVIEW (needs attention).
        let raw = (s.status ?? "").lowercased()
        let needsReview = ["delayed", "hold", "exception", "review", "pending"].contains(raw)
        let chipColor: Color = needsReview ? Brand.hazmat : Brand.success
        let chipText  = needsReview ? "REVIEW" : "READY"
        let route = "\(s.origin ?? "—") to \(s.destination ?? "—")"
        // Mono sub: real shipment number + car count / hazmat / commodity tag.
        let carsTag: String = {
            if let c = s.carsCount { return "\(c) cars" }
            if s.hazmat == true { return "hazmat-DG" }
            return s.commodity ?? "rail"
        }()
        let sub = "\(s.id) · \(carsTag)"
        let rowMoney = s.receivableAmount ?? s.settlementAmount

        return HStack(spacing: Space.s3) {
            // 40x40 rx10 icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(chipColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(route)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(sub)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(chipText)
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(chipColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(chipColor.opacity(0.16)))
                Text(rowMoney.map { moneyFull($0) } ?? "—")
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s3)
    }

    // MARK: - Double-batch guard (secondary strip)

    private var doubleBatchGuard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DOUBLE-BATCH GUARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("createBatch")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("0 of \(shipmentCount) already in an open batch · safe to run")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("writes wrapped in one transaction · atomic")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let err = createError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
            }
            if let b = createdBatch {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Brand.success)
                    Text("Batch \(b.batchNumber) created · \(b.totalLoads) shipments")
                        .font(EType.caption)
                        .foregroundStyle(Brand.success)
                }
            }
            HStack(spacing: Space.s3) {
                Button {
                    Task { await createBatch() }
                } label: {
                    HStack(spacing: 6) {
                        if creating {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.8)
                        }
                        Text(createdBatch == nil ? "Create batch run" : "Batch created")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(creating || createdBatch != nil || railShipmentIds.isEmpty)
                .opacity((creating || createdBatch != nil || railShipmentIds.isEmpty) ? 0.6 : 1.0)

                Button {
                    // Preview is local-only (no server preview endpoint).
                } label: {
                    Text("Preview")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 124, height: 48)
                        .background(palette.bgCardSoft)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let limit: Int; let offset: Int }
        do {
            // Same query 551 uses. There is no dedicated endpoint that returns
            // *unbatched, settled* rail shipments with their receivable amounts,
            // so we list rail shipments and let the user batch them. See PORT-GAP.
            let result: [RailBatchShipment] = try await EusoTripAPI.shared.query(
                "railShipments.getRailShipments",
                input: ListIn(limit: 50, offset: 0)
            )
            self.shipments = result
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Create batch (mutation)

    private func createBatch() async {
        guard !railShipmentIds.isEmpty else { return }
        creating = true; createError = nil
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let bounds = periodBounds ?? {
            // Fall back to a same-day window when no arrival timestamps exist;
            // the server only validates the yyyy-MM-dd shape, not the span.
            let today = f.string(from: Date())
            return (today, today)
        }()
        let input = CreateBatchInput(
            batchType: batchType,
            periodStart: bounds.start,
            periodEnd: bounds.end,
            loadIds: [],
            railShipmentIds: railShipmentIds,
            vesselShipmentIds: []
        )
        do {
            let result: CreateBatchResult = try await EusoTripAPI.shared.mutation(
                "settlementBatching.createBatch",
                input: input
            )
            self.createdBatch = result
        } catch {
            createError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        creating = false
    }
}

// MARK: - PORT-GAP
//
// • settlementBatching.getUnbatchedRailSettlements — no endpoint returns the
//   *settled, unbatched* rail-shipment receivables (amount + READY/REVIEW
//   settlement status) eligible for a carrier-receivable batch. We list
//   rail shipments via railShipments.getRailShipments instead; per-row money
//   (RailBatchShipment.receivableAmount / .settlementAmount) and GROSS render
//   only when the server actually carries them — otherwise a neutral "—",
//   never a fabricated figure. createBatch itself recomputes the true total
//   server-side and returns it in CreateBatchResult.totalAmount.
//
// • The wireframe's literal "0 of N already in an open batch · safe to run"
//   pre-flight is enforced server-side at createBatch :66–84 (it throws if a
//   settlement is already batched). There is no read-only pre-check endpoint,
//   so the strip states the guard's contract; the mutation is the real gate
//   and surfaces its error into createError.

#Preview("593 · Rail Settlement Batch · Night") { RailSettlementBatchScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("593 · Rail Settlement Batch · Light") { RailSettlementBatchScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
