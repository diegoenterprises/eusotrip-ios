//
//  594_RailCostBreakdown.swift
//  EusoTrip — Rail Engineer · Cost Breakdown (intermodal all-in landed cost).
//
//  CARRIER-SIDE (RAIL_ENGINEER vantage). Money-ledger grammar (227 Settlement-
//  Detail): big gradient figure + subline + hero card + colored-dot breakdown
//  ledger + TOTAL strip + margin card + CTA pair. Rolls the per-leg economics
//  of an intermodal rail move (line-haul · ramp lift · drayage+fuel ·
//  accessorials) into one all-in landed cost with margin vs lane benchmark.
//
//  Web parity: client/src/pages/rail/IntermodalCost.tsx (/rail/intermodal/:id/cost).
//  tRPC (server/routers/intermodal.ts):
//    per-leg ledger → intermodal.getIntermodalCostBreakdown
//    margin/benchmark → intermodal.getIntermodalDashboard
//    lane legs → intermodal.getIntermodalTracking
//    Export cost sheet → STUB·named-gap rail.exportCostSheet (PORT-GAP).
//  RBAC railProcedure (RAIL_ENGINEER|CATALYST). transportMode=rail · US lane (USD).
//

import SwiftUI

struct RailCostBreakdownScreen: View {
    let theme: Theme.Palette
    /// Intermodal shipment whose per-leg economics we roll up. Defaulted so the
    /// top-level struct only requires `theme` (router supplies the real id).
    var intermodalShipmentId: String = ""

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

// MARK: - Data shapes (live return shapes from intermodal.ts)

/// One leg of the all-in cost roll-up. Returned by
/// `intermodal.getIntermodalCostBreakdown` ({intermodalShipmentId}->per-leg cost).
private struct IntermodalCostLeg: Decodable, Identifiable {
    let id: String
    let label: String?          // "Line-haul rail · BNSF"
    let detail: String?         // "Long Beach ICTF → Joliet · 2,054 mi"
    let carrier: String?        // "BNSF"
    let amountUsd: Double?
    let pctOfTotal: Double?     // 65.4
    let legType: String?        // line_haul · ramp_lift · drayage · accessorial
}

private struct IntermodalCostBreakdown: Decodable {
    let intermodalShipmentId: String?
    let referenceNumber: String?     // RAIL-260523-7C3A0B12D4
    let origin: String?              // LA Long Beach ICTF
    let destination: String?         // Joliet / Chicago Logistics Park
    let lane: String?                // "Long Beach → Joliet → consignee"
    let equipment: String?           // "53′ domestic"
    let legCount: Int?               // 4
    let mileage: Int?                // 2,176
    let lineHaulCarrier: String?     // BNSF
    let totalUsd: Double?            // 4820
    let legs: [IntermodalCostLeg]?
    let auditedLegCount: Int?        // 3
}

/// Margin vs lane benchmark. Returned by `intermodal.getIntermodalDashboard`.
private struct IntermodalMargin: Decodable {
    let shipperChargeUsd: Double?    // 5560
    let marginUsd: Double?           // 740
    let marginPct: Double?           // 13.3
    let laneBenchmarkUsd: Double?    // 5200
    let benchmarkDeltaPct: Double?   // +6.9
    let shipperName: String?         // Eusorone Technologies
}

// MARK: - Body

private struct RailCostBreakdownBody: View {
    let intermodalShipmentId: String

    @Environment(\.palette) private var palette
    @State private var breakdown: IntermodalCostBreakdown? = nil
    @State private var margin: IntermodalMargin? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var exporting = false
    @State private var exportError: String? = nil
    @State private var exportNotice: String? = nil

    // Leg-color palette — matches the quad-color breakdown bar order in the
    // wireframe: line-haul (gradient/blue), ramp lift (escort purple), drayage
    // (hazmat amber), accessorials (success green).
    private func legColor(_ index: Int) -> Color {
        switch index {
        case 0:  return Brand.blue
        case 1:  return Brand.escort   // 0x9C27B0
        case 2:  return Brand.hazmat   // 0xFFB100
        default: return Brand.success  // 0x00C48C
        }
    }

    private func usd(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return "$" + (f.string(from: n) ?? String(format: "%.2f", v))
    }

    private func usdWhole(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "$" + (f.string(from: n) ?? String(format: "%.0f", v))
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
                } else if let b = breakdown {
                    hero(b)
                    IridescentHairline().padding(.vertical, Space.s4)
                    heroCard(b)
                    legLedger(b)
                    totalStrip(b)
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
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + reference caption)

    private var topBar: some View {
        HStack {
            Text("✦ RAIL ENGINEER · COST BREAKDOWN")
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
        // "RAIL · 7C3A" — last visible reference shard.
        guard let ref = breakdown?.referenceNumber, !ref.isEmpty else { return "RAIL · 7C3A" }
        let shard = ref.replacingOccurrences(of: "RAIL-", with: "")
        let tail = String(shard.suffix(8)).prefix(4)
        return "RAIL · \(tail)"
    }

    // MARK: - Back chevron + breadcrumb

    private var backRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Shipment")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(.bottom, Space.s3)
    }

    // MARK: - Hero figure + lane subline

    private func hero(_ b: IntermodalCostBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(usdWhole(b.totalUsd ?? 0)) landed")
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
        let shipper = margin?.shipperName ?? "Eusorone Technologies"
        let ref = (breakdown?.referenceNumber.map { String($0.prefix(17)) }) ?? "RAIL-260523-7C3A"
        let origin = b.origin ?? "LA Long Beach ICTF"
        let dest = b.destination ?? "Joliet"
        return "\(shipper) · \(ref) · \(origin) → \(dest)"
    }

    // MARK: - Hero intermodal card

    private func heroCard(_ b: IntermodalCostBreakdown) -> some View {
        HStack(spacing: 0) {
            // Gradient left rail (3pt).
            LinearGradient.diagonal.frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                // Reference + audited badge.
                HStack {
                    Text(b.referenceNumber ?? "RAIL-260523-7C3A0B12D4")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .monospacedDigit()
                    Spacer()
                    Text("\(b.auditedLegCount ?? b.legCount ?? 0) LEGS · AUDITED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(LinearGradient.primary)
                        .clipShape(Capsule())
                }
                Text(b.lane ?? "Long Beach → Joliet → consignee")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 12)
                Text(equipmentLine(b))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 4)
                // Shipper + margin footer row.
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 12, height: 12)
                        Text("DU")
                            .font(.system(size: 6, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    (Text("Shipper ")
                        .foregroundStyle(palette.textSecondary)
                     + Text(margin?.shipperName ?? "Eusorone Technologies")
                        .foregroundStyle(palette.textPrimary).bold()
                     + Text(marginTail)
                        .foregroundStyle(palette.textSecondary))
                        .font(.system(size: 10.5))
                    Spacer()
                    if let m = margin?.marginUsd {
                        Text("+\(usdWhole(m))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: 0x00966B))
                            .monospacedDigit()
                    }
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

    private func equipmentLine(_ b: IntermodalCostBreakdown) -> String {
        let equip = b.equipment ?? "53′ domestic"
        let legs = b.legCount ?? 4
        let miStr: String = {
            guard let mi = b.mileage else { return "2,176 mi" }
            let f = NumberFormatter(); f.numberStyle = .decimal
            return (f.string(from: NSNumber(value: mi)) ?? "\(mi)") + " mi"
        }()
        let carrier = b.lineHaulCarrier ?? "BNSF"
        return "\(equip) · \(legs) legs · \(miStr) · \(carrier) line-haul"
    }

    private var marginTail: String {
        guard let pct = margin?.marginPct else { return "" }
        return " · margin \(String(format: "%.1f", pct))%"
    }

    // MARK: - Cost-by-leg breakdown ledger

    private func legLedger(_ b: IntermodalCostBreakdown) -> some View {
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

            let legs = b.legs ?? []
            let total = legs.reduce(into: 0.0) { acc, l in acc += (l.amountUsd ?? 0) }

            VStack(alignment: .leading, spacing: 0) {
                breakdownBar(legs: legs, total: total)
                    .padding(.bottom, 18)
                ForEach(Array(legs.enumerated()), id: \.element.id) { idx, leg in
                    legRow(leg, color: legColor(idx))
                    if idx < legs.count - 1 {
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

    private func breakdownBar(legs: [IntermodalCostLeg], total: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let safeTotal = total > 0 ? total : 1
            HStack(spacing: 0) {
                ForEach(Array(legs.enumerated()), id: \.element.id) { idx, leg in
                    let frac = (leg.amountUsd ?? 0) / safeTotal
                    Rectangle()
                        .fill(idx == 0 ? AnyShapeStyle(LinearGradient.primary)
                                       : AnyShapeStyle(legColor(idx)))
                        .frame(width: max(0, w * frac))
                }
            }
            .frame(height: 8)
            .background(Color(hex: 0x05060A))
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }

    private func legRow(_ leg: IntermodalCostLeg, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color == Brand.blue ? AnyShapeStyle(LinearGradient.diagonal)
                                          : AnyShapeStyle(color))
                .frame(width: 10, height: 10)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(leg.label ?? "Leg")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                if let detail = leg.detail, !detail.isEmpty {
                    Text(detail)
                        .font(EType.mono(.caption)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(usd(leg.amountUsd ?? 0))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                if let pct = leg.pctOfTotal {
                    Text(String(format: "%.1f%%", pct))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color == Brand.blue ? palette.textSecondary : color)
                }
            }
        }
    }

    // MARK: - TOTAL strip

    private func totalStrip(_ b: IntermodalCostBreakdown) -> some View {
        HStack {
            Text("TOTAL · LANDED")
                .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(usd(b.totalUsd ?? 0))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(palette.textPrimary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .padding(.top, Space.s4)
    }

    // MARK: - Margin vs lane benchmark card

    private func marginCard() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MARGIN VS LANE BENCHMARK")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s2)

            if let m = margin {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shipper charge")
                                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                            Text(usdWhole(m.shipperChargeUsd ?? 0))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                                .monospacedDigit()
                        }
                        Spacer().frame(width: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Margin")
                                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(usdWhole(m.marginUsd ?? 0))
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x00966B))
                                    .monospacedDigit()
                                if let pct = m.marginPct {
                                    Text(String(format: "%.1f%%", pct))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color(hex: 0x00966B))
                                }
                            }
                        }
                        Spacer()
                    }
                    Rectangle().fill(palette.borderFaint).frame(height: 1)
                        .padding(.vertical, 12)
                    benchmarkLine(m)
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
    }

    private func benchmarkLine(_ m: IntermodalMargin) -> some View {
        let bench = usdWhole(m.laneBenchmarkUsd ?? 0)
        let deltaStr: String = {
            guard let d = m.benchmarkDeltaPct else { return "" }
            return String(format: "%+.1f%%", d)
        }()
        return (Text("vs lane benchmark ")
                    .foregroundStyle(palette.textSecondary)
                + Text(bench)
                    .foregroundStyle(palette.textPrimary).bold()
                + Text(" · this lane prices ")
                    .foregroundStyle(palette.textSecondary)
                + Text(deltaStr)
                    .foregroundStyle(Color(hex: 0x00966B)).bold())
            .font(.system(size: 11))
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
                        .clipShape(Capsule())
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
                        .overlay(Capsule().strokeBorder(palette.borderSoft))
                        .clipShape(Capsule())
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
        struct CostIn: Encodable { let intermodalShipmentId: String }
        let input = CostIn(intermodalShipmentId: intermodalShipmentId)
        do {
            // per-leg ledger → intermodal.getIntermodalCostBreakdown EXISTS·intermodal.ts:295
            async let bd: IntermodalCostBreakdown = EusoTripAPI.shared.query(
                "intermodal.getIntermodalCostBreakdown", input: input)
            // margin/benchmark → intermodal.getIntermodalDashboard EXISTS·intermodal.ts:341
            async let mg: IntermodalMargin = EusoTripAPI.shared.query(
                "intermodal.getIntermodalDashboard", input: input)
            let (breakdownVal, marginVal) = try await (bd, mg)
            self.breakdown = breakdownVal
            self.margin = marginVal
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Export cost sheet (PORT-GAP)

    private func exportSheet(_ b: IntermodalCostBreakdown) async {
        exporting = true; exportError = nil; exportNotice = nil
        struct ExportIn: Encodable { let intermodalShipmentId: String }
        struct ExportOut: Decodable { let url: String?; let format: String? }
        do {
            // PORT-GAP: rail.exportCostSheet — STUB·named-gap on the server.
            // Proposed: railCost.exportSheet({intermodalShipmentId})->{url,format}
            // (writes documents row + blockchainAuditTrail entry; broadcasts
            // WS_CHANNELS.SHIPMENT/WS_EVENTS.DOC_GENERATED). Wired through the
            // generic mutate-style query path so it activates the moment the
            // route lands server-side; surfaces a real error until then.
            let out: ExportOut = try await EusoTripAPI.shared.query(
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

    // MARK: - Dispute (reuses freightClaims dispute path — UNVERIFIED)

    private func dispute(_ b: IntermodalCostBreakdown) async {
        exportError = nil; exportNotice = nil
        struct DisputeIn: Encodable { let intermodalShipmentId: String; let reason: String }
        struct DisputeOut: Decodable { let id: String? }
        do {
            // PORT-GAP: dispute reuses the freightClaims dispute path (UNVERIFIED
            // line per <desc>). Wired so it activates when confirmed server-side.
            let _: DisputeOut = try await EusoTripAPI.shared.query(
                "freightClaims.createDispute",
                input: DisputeIn(intermodalShipmentId: intermodalShipmentId,
                                 reason: "Cost breakdown dispute"))
            exportNotice = "Dispute filed."
        } catch {
            exportError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("594 · Rail Cost Breakdown · Night") { RailCostBreakdownScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("594 · Rail Cost Breakdown · Light") { RailCostBreakdownScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
