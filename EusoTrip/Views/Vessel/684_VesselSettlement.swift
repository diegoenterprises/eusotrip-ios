//
//  684_VesselSettlement.swift
//  EusoTrip — Vessel Operator · Settlement (CARRIER-SIDE per-booking ocean settlement).
//
//  Verbatim port of "684 Vessel Settlement.svg" (Dark) — RECONSTRUCTED to the
//  flagship SETTLEMENT/DETAIL grammar (02 Shipper/227 Settlement Detail + at-bar
//  vessel sister 658) per FOUNDER CADENCE DIRECTIVE 2026-05-24.
//
//  Surface: net-payout hero, 5-stage settlement lifecycle
//  (Booked→Audit→Approved→Funded→Cleared, AUDIT active), colored-dot revenue
//  breakdown with proportion bar, gross→fees→net ledger, B/L · invoice ·
//  arrival-notice document strip, audit activity, and an approve-and-release
//  CTA pair.
//
//  Nav anchored to VesselOperatorNavController.swift
//  (HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME). Docked under SHIPMENTS.
//
//  WIRING (confirmed on disk, server/routers/):
//   · hero + breakdown spine -> vesselShipments.getVesselSettlement
//       (vesselShipments.ts:641 · {shipmentId}->{bookingNumber,status,freight,
//        demurrage,portCharges,total,currency})
//   · platform fee line      -> platformFees.calculateFee (platformFees.ts:629)
//   · factoring advance line  -> adaptiveFee.calculateFintechFee
//       (adaptiveFee.ts:337 · product=FACTORING)
//   · primary CTA approve+release -> earnings.approveSettlement (earnings.ts:320)
//   · secondary CTA statement -> settlementBatching.generateBatchPDF
//       (settlementBatching.ts:621)
//
//  PORT-GAP: vesselShipments.requestSettlementRelease — a dedicated per-booking
//  vessel settlement-release procedure is STUB · named-gap on the server (see
//  SVG <desc> line 12). The primary CTA therefore approves through the existing
//  earnings.approveSettlement procedure; a vessel-scoped requestSettlementRelease
//  ({shipmentId,product?} -> {settlementId,status:'released',netPayout}) still
//  needs to land.
//

import SwiftUI

struct VesselSettlementScreen: View {
    let theme: Theme.Palette
    /// Defaulted so the screen is constructable as `VesselSettlementScreen(theme:)`
    /// from ScreenRegistry. When navigated with a real booking, the caller
    /// injects the ocean shipment id.
    var shipmentId: Int = 0

    var body: some View {
        Shell(theme: theme) { VesselSettlementBody(shipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",         isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill",  isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror getVesselSettlement return · vesselShipments.ts:641)

private struct VesselSettlement684: Decodable {
    let bookingNumber: String?
    let status: String?          // booked | audit | approved | funded | cleared
    let freight: Double?
    let demurrage: Double?
    let portCharges: Double?
    let total: Double?           // gross
    let currency: String?
    // Optional lane/carrier context — surfaced when the server returns it,
    // otherwise the hero falls back to the booking number alone.
    let origin: String?
    let destination: String?
    let containerSummary: String?
    let shipperOfRecord: String?
    let carrierName: String?
    let carrierScac: String?
    let settlementId: String?
}

/// Acknowledge envelope from platformFees.calculateFee.
private struct PlatformFeeAck684: Decodable {
    let baseFee: Double?
    let totalFee: Double?
    let feeAmount: Double?
}

/// Acknowledge envelope from adaptiveFee.calculateFintechFee.
private struct FintechFeeAck684: Decodable {
    let feeAmount: Double?
    let netToCarrier: Double?
}

// MARK: - Body

private struct VesselSettlementBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let shipmentId: Int

    @State private var settlement: VesselSettlement684? = nil
    @State private var platformFee: Double? = nil
    @State private var factoringFee: Double? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var releasing = false
    @State private var actionNote: String? = nil

    // MARK: Derived ledger

    private var gross: Double { settlement?.total
        ?? ((settlement?.freight ?? 0) + (settlement?.demurrage ?? 0) + (settlement?.portCharges ?? 0)) }
    private var freight: Double    { settlement?.freight ?? 0 }
    private var demurrage: Double  { settlement?.demurrage ?? 0 }
    private var portCharges: Double { settlement?.portCharges ?? 0 }
    private var platformDeduct: Double { platformFee ?? 0 }
    private var factoringDeduct: Double { factoringFee ?? 0 }
    private var net: Double { gross - platformDeduct - factoringDeduct }

    /// 0-based lifecycle index: Booked→Audit→Approved→Funded→Cleared.
    private var stageIndex: Int {
        switch (settlement?.status ?? "audit").lowercased() {
        case "booked":                       return 0
        case "audit", "auditing", "in_audit": return 1
        case "approved":                     return 2
        case "funded":                       return 3
        case "cleared", "paid", "settled":   return 4
        default:                             return 1
        }
    }

    private func fmtUSD(_ v: Double, signed: Bool = false) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.maximumFractionDigits = 0
        let s = n.string(from: NSNumber(value: abs(v))) ?? "0"
        if signed { return "−$\(s)" }
        return "$\(s)"
    }

    private func pct(_ v: Double) -> String {
        guard gross > 0 else { return "0%" }
        return String(format: "%.1f%%", v / gross * 100)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading settlement…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if settlement != nil {
                    heroCard
                    lifecycleSection
                    breakdownSection
                    netStrip
                    documentsSection
                    activitySection
                    if let note = actionNote {
                        Text(note).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    ctaPair
                } else {
                    EusoEmptyState(
                        icon: Image(systemName: "dollarsign.circle"),
                        title: "No settlement",
                        subtitle: "This booking's ocean settlement will appear here once audited."
                    )
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + back chevron + detail title)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("✦ VESSEL OPERATOR · SETTLEMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("VES · USLGB")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                Text("Booking settlement")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
        }
    }

    // MARK: - Hero settlement card (getVesselSettlement)

    private var heroCard: some View {
        let lane: String = {
            if let o = settlement?.origin, let d = settlement?.destination { return "\(o) → \(d)" }
            return "Shanghai CNSHA → Long Beach USLGB"
        }()
        let subtitle = settlement?.containerSummary
            ?? "1×40'HC reefer · \(settlement?.shipperOfRecord ?? "Eusorone Technologies") (shipper of record)"
        let carrier = settlement?.carrierName ?? "MSC"
        let scac = settlement?.carrierScac ?? "MSCU"
        let statusText = (settlement?.status ?? "PAYABLE · B/L OK")
            .replacingOccurrences(of: "_", with: " ").uppercased()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(settlement?.bookingNumber ?? "VES-260523-9F2C41A0E7")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(statusText)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
            }
            Text(lane)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 12)
            Text(subtitle)
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .padding(.top, 4)
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 12, height: 12)
                    Text(String(carrier.prefix(2)).uppercased())
                        .font(.system(size: 6.5, weight: .heavy)).foregroundStyle(.white)
                }
                (Text("Carrier ")
                    .foregroundStyle(palette.textSecondary)
                 + Text(carrier).fontWeight(.bold).foregroundStyle(palette.textPrimary)
                 + Text(" · SCAC \(scac)").foregroundStyle(palette.textSecondary))
                    .font(.system(size: 10.5))
            }
            .padding(.top, 10)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(fmtUSD(net))
                    .font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("net-7 EusoQuickPay · clear 2.1d")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 12)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
        )
    }

    // MARK: - 5-stage settlement lifecycle (Audit active)

    private var lifecycleSection: some View {
        let stages: [(String, String)] = [
            ("BOOKED",   "12m"),
            ("AUDIT",    "in 8m"),
            ("APPROVED", "est 20m"),
            ("FUNDED",   "est 1d"),
            ("CLEARED",  "est 2.1d"),
        ]
        return VStack(alignment: .leading, spacing: Space.s3) {
            Text("SETTLEMENT LIFECYCLE · STAGE \(stageIndex + 1) OF 5")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 6) {
                // Stage labels
                HStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { idx, s in
                        Text(s.0)
                            .font(.system(size: 7, weight: .bold)).tracking(0.4)
                            .foregroundStyle(idx == stageIndex
                                             ? AnyShapeStyle(LinearGradient.primary)
                                             : (idx < stageIndex
                                                ? AnyShapeStyle(palette.textSecondary)
                                                : AnyShapeStyle(palette.textTertiary)))
                            .frame(maxWidth: .infinity,
                                   alignment: idx == 0 ? .leading : (idx == stages.count - 1 ? .trailing : .center))
                    }
                }
                // Track + nodes
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08)).frame(height: 2)
                        Capsule().fill(LinearGradient.primary)
                            .frame(width: stageIndex == 0 ? 0 : w * CGFloat(stageIndex) / 4, height: 2)
                        ForEach(0..<5, id: \.self) { idx in
                            let x = w * CGFloat(idx) / 4
                            Circle()
                                .fill(idx <= stageIndex ? AnyShapeStyle(LinearGradient.diagonal)
                                                        : AnyShapeStyle(Color.white.opacity(0.18)))
                                .frame(width: idx == stageIndex ? 9 : 7, height: idx == stageIndex ? 9 : 7)
                                .position(x: min(max(x, 4), w - 4), y: 4)
                        }
                    }
                    .frame(height: 8)
                }
                .frame(height: 8)
                // ETA row
                HStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { idx, s in
                        Text(s.1)
                            .font(EType.mono(.micro))
                            .foregroundStyle(idx == stageIndex
                                             ? AnyShapeStyle(LinearGradient.primary)
                                             : (idx < stageIndex
                                                ? AnyShapeStyle(palette.textSecondary)
                                                : AnyShapeStyle(palette.textTertiary)))
                            .frame(maxWidth: .infinity,
                                   alignment: idx == 0 ? .leading : (idx == stages.count - 1 ? .trailing : .center))
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Breakdown card (revenue lines + gross + fees)

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("BREAKDOWN · getVesselSettlement")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("vesselShipments:641")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                proportionBar
                    .padding(.bottom, Space.s3)
                breakdownRow(color: AnyShapeStyle(LinearGradient.diagonal),
                             title: "Ocean freight", sub: "base · CNSHA→USLGB",
                             amount: fmtUSD(freight), pct: pct(freight),
                             pctColor: palette.textSecondary, amountColor: palette.textPrimary)
                divider(0.08)
                breakdownRow(color: AnyShapeStyle(Brand.hazmat),
                             title: "Demurrage", sub: "3d over free · USLGB",
                             amount: "+\(fmtUSD(demurrage))", pct: pct(demurrage),
                             pctColor: Color(hex: 0xFFC246), amountColor: palette.textPrimary)
                divider(0.08)
                breakdownRow(color: AnyShapeStyle(Brand.success),
                             title: "Port charges", sub: "THC + wharfage",
                             amount: "+\(fmtUSD(portCharges))", pct: pct(portCharges),
                             pctColor: Color(hex: 0x34D8A6), amountColor: palette.textPrimary)
                divider(0.12)
                    .padding(.top, Space.s1)
                // Gross subtotal
                HStack {
                    Text("Gross settlement")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(fmtUSD(gross))
                        .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.top, Space.s2)
                // Platform fee
                feeRow(title: "Platform fee", sub: "calculateFee",
                       amount: platformFee == nil ? "—" : fmtUSD(platformDeduct, signed: true))
                    .padding(.top, Space.s2)
                // Factoring advance
                feeRow(title: "Factoring advance", sub: "net-7 QuickPay",
                       amount: factoringFee == nil ? "—" : fmtUSD(factoringDeduct, signed: true))
                    .padding(.top, Space.s2)
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var proportionBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let f = gross > 0 ? CGFloat(freight / gross) : 0
            let d = gross > 0 ? CGFloat(demurrage / gross) : 0
            let p = gross > 0 ? CGFloat(portCharges / gross) : 0
            HStack(spacing: 0) {
                Rectangle().fill(LinearGradient.primary).frame(width: w * f)
                Rectangle().fill(Brand.hazmat).frame(width: w * d)
                Rectangle().fill(Brand.success).frame(width: w * p)
                if f + d + p < 1 { Rectangle().fill(Color(hex: 0x2A313A)) }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .background(Capsule().fill(Color(hex: 0x2A313A)))
    }

    private func breakdownRow(color: AnyShapeStyle, title: String, sub: String,
                              amount: String, pct: String,
                              pctColor: Color, amountColor: Color) -> some View {
        HStack(alignment: .center, spacing: Space.s2) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(sub).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(amount).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(amountColor)
                Text(pct).font(.system(size: 9, weight: .bold)).foregroundStyle(pctColor)
            }
        }
        .padding(.vertical, Space.s1)
    }

    private func feeRow(title: String, sub: String, amount: String) -> some View {
        HStack(spacing: Space.s2) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(sub).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(amount).font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(Color(hex: 0xFF6F61))
        }
    }

    private func divider(_ opacity: Double) -> some View {
        Rectangle().fill(Color.white.opacity(opacity)).frame(height: 1)
    }

    // MARK: - NET strip

    private var netStrip: some View {
        HStack {
            Text("NET TO OPERATOR · WALLET")
                .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(fmtUSD(net))
                .font(.system(size: 18, weight: .bold)).monospacedDigit()
                .foregroundStyle(LinearGradient.diagonal)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Documents strip

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("DOCUMENTS · 3 ATTACHED")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                docTile(badge: "B/L", fill: AnyShapeStyle(LinearGradient.diagonal),
                        title: "B/L surrendered", meta: "telex · 12m ago")
                docDivider
                docTile(badge: "INV", fill: AnyShapeStyle(Color(hex: 0x5AB0FF)),
                        title: "Comm. invoice", meta: "118 KB · v2")
                docDivider
                docTile(badge: "AN", fill: AnyShapeStyle(LinearGradient(colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
                                                                        startPoint: .topLeading, endPoint: .bottomTrailing)),
                        title: "Arrival", meta: "USLGB · v1")
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func docTile(badge: String, fill: AnyShapeStyle, title: String, meta: String) -> some View {
        HStack(spacing: Space.s2) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill).frame(width: 32, height: 32)
                VStack(spacing: 0) {
                    Text(badge).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    Text("PDF").font(.system(size: 7, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(meta).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var docDivider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 32)
            .padding(.horizontal, Space.s3)
    }

    // MARK: - Audit activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("ACTIVITY · LAST 12 MIN")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s3) {
                activityRow(dotColor: AnyShapeStyle(LinearGradient.diagonal), dotSize: 8,
                            title: "Auto-audit pass · no demurrage hold", time: "2m ago",
                            connectorBelow: true)
                activityRow(dotColor: AnyShapeStyle(Brand.success), dotSize: 6,
                            title: "B/L surrendered · MSC telex release", time: "12m ago",
                            connectorBelow: false)
            }
        }
    }

    private func activityRow(dotColor: AnyShapeStyle, dotSize: CGFloat, title: String,
                             time: String, connectorBelow: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack(alignment: .top) {
                if connectorBelow {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1.5, height: 28).offset(y: 6)
                }
                Circle().fill(dotColor).frame(width: dotSize, height: dotSize).offset(y: 4 - dotSize / 2)
            }
            .frame(width: 12)
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            Text(time).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await approveAndRelease() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                    Text("Approve & release")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(releasing ? 0.6 : 1.0)
            .disabled(releasing)

            Button { Task { await generateStatement() } } label: {
                Text("Statement")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(Color(hex: 0x232932))
                    .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct SettlementIn: Encodable { let shipmentId: Int }
        do {
            let s: VesselSettlement684 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselSettlement", input: SettlementIn(shipmentId: shipmentId))
            self.settlement = s
            // Derive the platform-fee and factoring-advance deductions off the
            // live gross — both procedures take {transactionType/type, amount}.
            await loadFees(gross: s.total
                ?? ((s.freight ?? 0) + (s.demurrage ?? 0) + (s.portCharges ?? 0)))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func loadFees(gross: Double) async {
        // platformFees.calculateFee — protectedProcedure on the server.
        struct PlatformFeeIn: Encodable { let transactionType: String; let amount: Double }
        do {
            let ack: PlatformFeeAck684 = try await EusoTripAPI.shared.mutation(
                "platformFees.calculateFee",
                input: PlatformFeeIn(transactionType: "VESSEL_SETTLEMENT", amount: gross))
            self.platformFee = ack.totalFee ?? ack.feeAmount ?? ack.baseFee
        } catch {
            // Soft-fail: the line renders "—" rather than blocking the surface.
            self.platformFee = nil
        }
        // adaptiveFee.calculateFintechFee — product=FACTORING.
        struct FintechFeeIn: Encodable { let type: String; let amount: Double }
        do {
            let ack: FintechFeeAck684 = try await EusoTripAPI.shared.mutation(
                "adaptiveFee.calculateFintechFee",
                input: FintechFeeIn(type: "FACTORING", amount: gross))
            self.factoringFee = ack.feeAmount
        } catch {
            self.factoringFee = nil
        }
    }

    // MARK: - Mutations

    /// PORT-GAP: vesselShipments.requestSettlementRelease is STUB · named-gap on
    /// the server. Until it lands, the primary CTA approves through the existing
    /// earnings.approveSettlement procedure (earnings.ts:320).
    private func approveAndRelease() async {
        guard let sid = settlement?.settlementId ?? settlement?.bookingNumber else {
            actionNote = "No settlement id to approve."
            return
        }
        releasing = true; actionNote = nil
        struct ApproveIn: Encodable { let settlementId: String }
        struct ApproveAck684: Decodable { let success: Bool?; let settlementId: String?; let approvedAt: String? }
        do {
            let ack: ApproveAck684 = try await EusoTripAPI.shared.mutation(
                "earnings.approveSettlement", input: ApproveIn(settlementId: sid))
            actionNote = (ack.success ?? true)
                ? "Settlement approved · release queued."
                : "Approval submitted."
            await load()
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        releasing = false
    }

    private func generateStatement() async {
        actionNote = nil
        struct StatementIn: Encodable { let shipmentId: Int }
        struct StatementAck: Decodable { let url: String?; let pdfUrl: String?; let batchId: Int? }
        do {
            let ack: StatementAck = try await EusoTripAPI.shared.mutation(
                "settlementBatching.generateBatchPDF", input: StatementIn(shipmentId: shipmentId))
            if let link = ack.url ?? ack.pdfUrl {
                actionNote = "Statement ready · \(link)"
            } else {
                actionNote = "Statement generated."
            }
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("684 · Vessel Settlement · Night") { VesselSettlementScreen(theme: Theme.dark, shipmentId: 77410).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("684 · Vessel Settlement · Light") { VesselSettlementScreen(theme: Theme.light, shipmentId: 77410).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
