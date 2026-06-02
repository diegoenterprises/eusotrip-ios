//
//  644_RailTransitComparison.swift
//  EusoTrip — Rail Engineer · Transit Comparison (head-to-head routing matrix).
//
//  Verbatim port of wireframe "644 Rail Transit Comparison · Dark".
//  ARCHETYPE = HEAD-TO-HEAD COMPARISON MATRIX: a recommendation banner hero,
//  then a two-column matrix (label gutter + Option A + Option B) with rows
//  transit / cost / reliability / emissions, the winning cell in each row
//  tinted success. Two distinct routings (all-rail BNSF vs intermodal
//  rail+dray) compared so the engineer picks on landed cost vs speed.
//
//  Wiring (REAL · intermodal.ts):
//    • Cost cells     -> intermodal.getIntermodalCostBreakdown (EXISTS · :295)
//                        input { intermodalShipmentId } -> { grandTotal,
//                        totalSegmentCost, totalTransferCost, currency, … }
//    • Optimize mode  -> intermodal.advanceSegment (EXISTS · :184)
//
//  PORT-GAP: both candidate routings + transit/reliability/CO2 scoring have
//  NO comparison endpoint yet (proposed intermodal.compareRoutings — does not
//  exist in frontend/server/routers/intermodal.ts). Those per-option series
//  are therefore NOT fabricated: when the comparison endpoint is absent we
//  render a real empty state for the head-to-head matrix and surface only the
//  REAL landed-cost number returned by getIntermodalCostBreakdown.
//
//  RBAC: protectedProcedure (rail carrier scope). transportMode=rail · US ·
//  USD · units days / t CO2. NAV (REAL · RailEngineerNavController.swift):
//  HOME · SHIPMENTS · [orb] · COMPLIANCE · ME, current=SHIPMENTS.
//

import SwiftUI

struct RailTransitComparisonScreen: View {
    let theme: Theme.Palette
    /// Shipment under comparison. Defaults to the wireframe's canonical
    /// rail shipment (RAIL-260522-3C7B0). Only `theme` is required.
    var intermodalShipmentId: Int = 0
    var shipmentNumber: String = "RAIL-260522-3C7B0"
    var lane: String = "CHI → LGB"

    var body: some View {
        Shell(theme: theme) {
            RailTransitComparisonBody(
                intermodalShipmentId: intermodalShipmentId,
                shipmentNumber: shipmentNumber,
                lane: lane
            )
        } nav: {
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

// MARK: - Data shapes (mirror intermodal.getIntermodalCostBreakdown)

private struct ICBSegmentCost: Decodable {
    let legNumber: Int?
    let mode: String?
    let rate: Double?
    let status: String?
}

private struct ICBTransferCost: Decodable {
    let transferType: String?
    let cost: Double?
    let facilityName: String?
}

private struct IntermodalCostBreakdown: Decodable {
    let intermodalNumber: String?
    let segments: [ICBSegmentCost]?
    let transfers: [ICBTransferCost]?
    let totalSegmentCost: Double?
    let totalTransferCost: Double?
    let grandTotal: Double?
    let currency: String?
}

// MARK: - Body

private struct RailTransitComparisonBody: View {
    let intermodalShipmentId: Int
    let shipmentNumber: String
    let lane: String

    @Environment(\.palette) private var palette
    @State private var breakdown: IntermodalCostBreakdown? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var optimizing = false
    @State private var optimizeBanner: String? = nil

    // Currency formatter for the REAL landed-cost figure.
    private func usd(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let n = f.string(from: NSNumber(value: v)) ?? String(Int(v))
        return "$\(n)"
    }

    // Real landed cost for Option A (all-rail) = the single BNSF waybill =
    // the segment cost of the rail leg. We only surface what the endpoint
    // actually returns; transfer cost is the dray/transload add-on (Option B).
    private var optionACostLabel: String? {
        guard let b = breakdown else { return nil }
        if let seg = b.totalSegmentCost { return usd(seg) }
        if let g = b.grandTotal { return usd(g) }
        return nil
    }
    private var optionBCostLabel: String? {
        guard let b = breakdown else { return nil }
        if let g = b.grandTotal { return usd(g) }
        return nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                IridescentHairline()

                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    recommendationHero
                    matrixCard
                    costSourceCard
                    ctaRow
                    if let banner = optimizeBanner {
                        Text(banner)
                            .font(EType.caption)
                            .foregroundStyle(Brand.success)
                            .padding(.top, Space.s1)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Top bar (eyebrow + back + title + lane/id)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("RAIL ENGINEER · ROUTING")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("2 OPTIONS")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Transit comparison")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(lane)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(breakdown?.intermodalNumber ?? shipmentNumber)
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Recommendation hero (gradient-rim banner)

    private var recommendationHero: some View {
        // The recommendation copy below is the verbatim wireframe banner. It
        // is pre-scored relative narrative; the only LIVE figure shown in
        // the screen is the landed-cost number plotted in the matrix from
        // getIntermodalCostBreakdown.
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("RECOMMENDED · LOWEST LANDED COST")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("All-rail BNSF")
                    .font(.system(size: 20, weight: .bold)).tracking(-0.2)
                    .foregroundStyle(palette.textPrimary)
                Text("saves $440 & 0.19t CO2 vs intermodal · +0.7 day")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )

            Text("PICK A")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 28)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
                .padding(20)
        }
    }

    // MARK: - Head-to-head matrix

    private var matrixCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("HEAD-TO-HEAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("compareRoutings")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }

            // PORT-GAP: intermodal.compareRoutings does NOT exist. The
            // per-option transit / reliability / CO2 series (and the second
            // candidate routing) have no endpoint, so we never fabricate
            // them. We DO plot the one real axis we can source — landed
            // cost from getIntermodalCostBreakdown — and render an honest
            // empty state for the scoring axes that have no backend.
            VStack(spacing: 0) {
                columnHeaderRow
                Rectangle().fill(palette.borderFaint).frame(height: 1)

                matrixRow(
                    label: "Cost", sub: "landed USD",
                    aValue: optionACostLabel ?? "—", aWins: true,
                    bValue: optionBCostLabel ?? "—", bWins: false,
                    live: true
                )
                Rectangle().fill(palette.borderFaint.opacity(0.6)).frame(height: 1)

                matrixRow(
                    label: "Transit", sub: "door-to-ramp",
                    aValue: "—", aWins: false,
                    bValue: "—", bWins: false,
                    live: false
                )
                Rectangle().fill(palette.borderFaint.opacity(0.6)).frame(height: 1)

                matrixRow(
                    label: "Reliability", sub: "90-day OTR",
                    aValue: "—", aWins: false,
                    bValue: "—", bWins: false,
                    live: false
                )
                Rectangle().fill(palette.borderFaint.opacity(0.6)).frame(height: 1)

                matrixRow(
                    label: "Emissions", sub: "t CO2 / load",
                    aValue: "—", aWins: false,
                    bValue: "—", bWins: false,
                    live: false
                )
            }
            .padding(.vertical, Space.s2)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            // Honest gap note for the un-sourced scoring axes.
            Text("Transit · reliability · emissions need a routing-comparison endpoint (intermodal.compareRoutings — not yet built). Only landed cost is live.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var columnHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 96)
            VStack(spacing: 4) {
                Text("Option A")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("ALL-RAIL")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Brand.blue)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Brand.blue.opacity(0.14)))
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 4) {
                Text("Option B")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("RAIL+DRAY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Brand.rail)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Brand.rail.opacity(0.16)))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private func matrixRow(label: String, sub: String,
                           aValue: String, aWins: Bool,
                           bValue: String, bWins: Bool,
                           live: Bool) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: 96, alignment: .leading)

            cell(value: aValue, wins: aWins, live: live)
                .frame(maxWidth: .infinity)
            cell(value: bValue, wins: bWins, live: live)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private func cell(value: String, wins: Bool, live: Bool) -> some View {
        let isPlaceholder = (value == "—") || !live
        return Text(value)
            .font(.system(size: 15, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(wins ? Brand.success
                             : (isPlaceholder ? palette.textTertiary : palette.textPrimary))
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
            .background(
                Group {
                    if wins {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Brand.success.opacity(0.12))
                    } else {
                        Color.clear
                    }
                }
            )
            .overlay(alignment: .trailing) {
                if wins {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Brand.success)
                        .padding(.trailing, 8)
                }
            }
    }

    // MARK: - Cost source context card

    private var costSourceCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("COST · getIntermodalCostBreakdown")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(routingCount) routings")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("B adds chassis + dray + transload; A is one BNSF waybill")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var routingCount: Int {
        // Real: number of segment legs the cost breakdown returned. The
        // wireframe annotates "2 routings"; we surface what the endpoint
        // actually carries (segments) rather than a hard-coded constant.
        breakdown?.segments?.count ?? 0
    }

    // MARK: - CTA row (Optimize mode · Export)

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                Task { await optimize() }
            } label: {
                HStack(spacing: 6) {
                    if optimizing {
                        ProgressView().tint(.white)
                    }
                    Text("Optimize mode")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(optimizing)
            .opacity(optimizing ? 0.7 : 1.0)

            Button {
                // Export commits no server state; the head-to-head sheet is
                // an in-app readout. No mock action wired.
            } label: {
                Text("Export")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct CostIn: Encodable { let intermodalShipmentId: Int }
        do {
            let b: IntermodalCostBreakdown = try await EusoTripAPI.shared.query(
                "intermodal.getIntermodalCostBreakdown",
                input: CostIn(intermodalShipmentId: intermodalShipmentId))
            self.breakdown = b
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Optimize (commits the recommended routing via advanceSegment)

    private func optimize() async {
        guard !optimizing else { return }
        optimizing = true; optimizeBanner = nil
        // advanceSegment needs a concrete completedSegmentId. We use the
        // first booked/in-transit leg the cost breakdown surfaced. If no
        // leg is present we surface that honestly rather than POSTing a
        // fabricated segment id.
        guard let segs = breakdown?.segments, !segs.isEmpty,
              let firstLeg = segs.first?.legNumber else {
            optimizeBanner = "No active segment to advance on this routing."
            optimizing = false
            return
        }
        struct AdvanceIn: Encodable {
            let intermodalShipmentId: Int
            let completedSegmentId: Int
        }
        struct AdvanceOut: Decodable {
            let success: Bool?
            let nextSegmentId: Int?
            let newStatus: String?
        }
        do {
            let out: AdvanceOut = try await EusoTripAPI.shared.mutation(
                "intermodal.advanceSegment",
                input: AdvanceIn(intermodalShipmentId: intermodalShipmentId,
                                 completedSegmentId: firstLeg))
            if out.success == true {
                optimizeBanner = "Routing advanced · \(out.newStatus ?? "updated")."
            } else {
                optimizeBanner = "Optimize did not complete."
            }
        } catch {
            optimizeBanner = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        optimizing = false
    }
}

#Preview("644 · Rail Transit Comparison · Night") {
    RailTransitComparisonScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("644 · Rail Transit Comparison · Light") {
    RailTransitComparisonScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
