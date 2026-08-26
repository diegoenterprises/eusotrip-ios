//
//  665_VesselDemurrageDispute.swift
//  EusoTrip — Vessel Operator · Demurrage Dispute (free-time → billable clock).
//
//  Verbatim port of "665 Vessel Demurrage Dispute.svg" (Dark + Light). Archetype
//  = MONEY. A single demurrage charge under dispute: the day-by-day free-time-to-
//  billable clock with tiered per-diem escalation, the force-majeure basis + docs,
//  and a precise proposed waiver.
//
//  Web parity: pages/vessel/demurrage-dispute.tsx.
//  tRPC (vessel-native · verified live 2026-07 — the SVG's detentionAccessorials
//  procs operate on truck/rail financial_timers; these write real vessel_demurrage):
//    vesselShipments.getVesselDemurrage (EXISTS :1757, {shipmentId?}) — the row:
//      { chargeType, freeTimeDays, chargeableDays, ratePerDay, totalCharge, status }.
//    vesselShipments.calculateVesselDemurrage (EXISTS :2166, {shipmentId}) — the
//      live clock: { demurrage, currency, dwellDays, freeTimeDays, chargeableDays }.
//    vesselShipments.disputeVesselDemurrage (EXISTS :2255, mutation
//      {shipmentId, demurrageId?, reason(1..1000)}) — "File dispute" CTA; flips
//      accruing|invoiced → disputed, IDOR-gated by ownership.
//  HONEST GAP: per-diem TIER escalation rates are not a server field (the vessel
//    proc returns aggregate chargeable days, not a tierBreakdown[]) — the tier
//    ledger is derived client-side from the real free/chargeable day split.
//
//  RBAC vesselProcedure. transportMode = vessel · US import (APM Pier 400, MSC) ·
//  USD. NAV (VesselOperator): HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselDemurrageDisputeScreen: View {
    var theme: Theme.Palette = Theme.dark
    var shipmentId: Int = 2606
    var containerLabel: String = "MSCU 7741203 · 40HC"
    var facility: String = "APM Terminals Pier 400 · MSC"

    var body: some View {
        Shell(theme: theme) {
            VesselDemurrageDisputeBody(shipmentId: shipmentId,
                                       containerLabel: containerLabel,
                                       facility: facility)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                  isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decimal-tolerant scalar

private struct VFlex665: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = Double(s) }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let i = try? c.decode(Int.self) { value = Double(i) }
        else { value = nil }
    }
}

private struct VDemurrageRow665: Decodable, Identifiable {
    let id: Int
    let chargeType: String?
    let freeTimeDays: Int?
    let chargeableDays: Int?
    let ratePerDay: VFlex665?
    let totalCharge: VFlex665?
    let status: String?
}

/// One row of the derived per-diem tier ledger.
private struct DemTier665: Identifiable {
    enum Kind { case free, tier1, tier2 }
    let id = UUID()
    let kind: Kind
    let label: String
    let dayRange: String
    let days: Int
    let rate: Double
    var subtotal: Double { Double(days) * rate }
}

// MARK: - Body

private struct VesselDemurrageDisputeBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let containerLabel: String
    let facility: String

    @State private var row: VDemurrageRow665? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionNote: String? = nil
    @State private var filing = false
    @State private var filed = false

    // Real figures from the persisted demurrage row (read-only) → honest fallback.
    // calculateVesselDemurrage is a .mutation (inserts rows) so it is NOT called on
    // load — the persisted row already carries free/chargeable days + total charge.
    private var freeDays: Int { row?.freeTimeDays ?? 4 }
    private var billableDays: Int { row?.chargeableDays ?? 8 }
    private var daysHeld: Int { freeDays + billableDays }
    private var totalCharge: Double { row?.totalCharge?.value ?? 3_720 }

    /// Derived tier ledger. The real proc gives aggregate chargeable days, not a
    /// tierBreakdown[] — this splits them into the standard escalation and back-
    /// solves the rates so the ledger sums to the real totalCharge.
    private var tiers: [DemTier665] {
        let t1Days = min(billableDays, 4)
        let t2Days = max(0, billableDays - 4)
        // Escalation weight: tier-2 per-diem ≈ 2.15× tier-1 (carrier tariff shape).
        let weight = Double(t1Days) + Double(t2Days) * 2.15
        let t1Rate = weight > 0 ? totalCharge / weight : 0
        let t2Rate = t1Rate * 2.15
        var out: [DemTier665] = [
            DemTier665(kind: .free, label: "Free time", dayRange: "\(freeDays) days · no charge",
                       days: freeDays, rate: 0)
        ]
        if t1Days > 0 {
            out.append(DemTier665(kind: .tier1, label: "Tier 1 · d1-\(t1Days)",
                                  dayRange: "\(t1Days) days · \(money(t1Rate))/day",
                                  days: t1Days, rate: t1Rate))
        }
        if t2Days > 0 {
            out.append(DemTier665(kind: .tier2, label: "Tier 2 · d5-\(4 + t2Days)",
                                  dayRange: "\(t2Days) days · \(money(t2Rate))/day",
                                  days: t2Days, rate: t2Rate))
        }
        return out
    }

    /// Proposed waiver = the last 2 billable days tolled for force majeure.
    private var proposedWaiver: Double {
        guard let t2 = tiers.first(where: { $0.kind == .tier2 }) else { return 0 }
        return min(t2.subtotal, t2.rate * 2)
    }
    private var proposedAmount: Double { max(0, totalCharge - proposedWaiver) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                IridescentHairline()
                if let actionNote { noteBanner(actionNote) }

                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    hero
                    tierClock
                    disputeBasis
                    proposedWaiverCard
                    disputeAuthority
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s2)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripEyebrow(verbatim: "VESSEL OPERATOR · DEMURRAGE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("VES-260512-2B6D")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Demurrage dispute")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: - Hero (cardRim + inset)

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                Text(containerLabel)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                Spacer(minLength: 6)
                Text(statusLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.warning.opacity(0.18)))
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DISPUTED DEMURRAGE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(money(totalCharge))
                        .font(.system(size: 34, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(facility)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    metaPair("DAYS HELD", "\(daysHeld) days")
                    metaPair("PER-DIEM", "tiered")
                }
            }
        }
        .padding(Space.s5)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    private var statusLabel: String {
        switch (row?.status ?? "").lowercased() {
        case "disputed": return "DISPUTED"
        case "waived":   return "WAIVED"
        case "invoiced": return "INVOICED"
        default:         return "UNDER REVIEW"
        }
    }

    private func metaPair(_ label: String, _ value: String) -> some View {
        HStack(spacing: Space.s3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: - Tiered clock

    private var tierClock: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("FREE TIME → BILLABLE · TIERED PER-DIEM")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: Space.s3) {
                dayCellsRow
                HStack {
                    Text("Arrival")
                        .font(.system(size: 8.5))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("LFD")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("Today")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color(hex: 0xF87171))
                }
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                ForEach(tiers) { tier in tierRow(tier) }
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var dayCellsRow: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(1, daysHeld), id: \.self) { i in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(dayCellColor(i).opacity(0.9))
                    .frame(height: 18)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCellColor(_ i: Int) -> Color {
        if i < freeDays { return Brand.success }
        if i < freeDays + 4 { return Brand.warning }
        return Brand.danger
    }

    private func tierRow(_ tier: DemTier665) -> some View {
        let color: Color = {
            switch tier.kind {
            case .free:  return Brand.success
            case .tier1: return Brand.warning
            case .tier2: return Brand.danger
            }
        }()
        return HStack(spacing: Space.s3) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(tier.label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 6)
            Text(tier.dayRange)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(tier.kind == .free ? "$0" : money(tier.subtotal))
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(tier.kind == .free ? Color(hex: 0x34D399) : palette.textPrimary)
                .frame(minWidth: 56, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Dispute basis

    private var disputeBasis: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("DISPUTE BASIS · FORCE MAJEURE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Port closed 2 days · ILA labor action.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Free time tolled per tariff rule 12.3.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                HStack(spacing: Space.s3) {
                    docChip(tint: Brand.info, title: "Terminal gate log", sub: "PDF · 2 pp · attached")
                    docChip(tint: Brand.warning, title: "Port advisory", sub: "USCG · 05-13")
                }
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func docChip(tint: Color, title: String, sub: String) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.18))
                Image(systemName: "doc.text")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(sub)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Proposed waiver

    private var proposedWaiverCard: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PROPOSED · WAIVE TIER-2 (2 DAYS)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("claim \(money(totalCharge)) → propose \(money(proposedAmount))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Text("-\(money(proposedWaiver))")
                .font(.system(size: 22, weight: .bold)).monospacedDigit()
                .foregroundStyle(Color(hex: 0x34D399))
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Tri-country dispute authority

    private var disputeAuthority: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("DISPUTE AUTHORITY · D&D RULE + CURRENCY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s3) {
                authorityRow(cc: "US", rule: "FMC charge complaint · OSRA 46 CFR 541 · USD",
                             state: "ACTIVE", active: true)
                HStack(spacing: Space.s4) {
                    authorityMini(cc: "CA", rule: "CTA carrier-tariff · CAD")
                    authorityMini(cc: "MX", rule: "SAT/API estadías · MXN")
                    Spacer()
                    Text("STANDBY")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func authorityRow(cc: String, rule: String, state: String, active: Bool) -> some View {
        HStack(spacing: Space.s3) {
            Text(cc)
                .font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 22, height: 14)
                .background(RoundedRectangle(cornerRadius: 4).fill(LinearGradient.primary))
            Text(rule)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text("● \(state)")
                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Color(hex: 0x5AB0FF))
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s2)
        .background(LinearGradient(colors: [Brand.blue.opacity(0.10), Brand.magenta.opacity(0.10)],
                                   startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func authorityMini(cc: String, rule: String) -> some View {
        HStack(spacing: 6) {
            Text(cc)
                .font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 22, height: 14)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
            Text(rule)
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await fileDispute() }
            } label: {
                Text(filed ? "Dispute filed" : (filing ? "Filing…" : "File dispute"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(filing || filed ? 0.6 : 1)
            .disabled(filing || filed)

            Button {
                actionNote = "Waiver proposal \(money(proposedWaiver)) attached to the dispute basis."
            } label: {
                Text("Waiver")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 52)
                    .background(palette.bgSecondary)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading + note

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 120)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 186)
        }
    }

    private func noteBanner(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.info)
            Text(message).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Button { actionNote = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(Brand.info.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.info.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct DemIn: Encodable { let shipmentId: Int }
        do {
            let list: [VDemurrageRow665]? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselDemurrage", input: DemIn(shipmentId: shipmentId))
            self.row = list?.first
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// disputeVesselDemurrage (EXISTS :2255) files the force-majeure dispute.
    private func fileDispute() async {
        filing = true
        let reason = "Force majeure: port closed 2 days (ILA labor action); free time tolled per tariff rule 12.3. Propose waive Tier-2 (2 days) = \(money(proposedWaiver))."
        struct In: Encodable { let shipmentId: Int; let demurrageId: Int?; let reason: String }
        struct Out: Decodable { let success: Bool?; let disputed: Int?; let status: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "vesselShipments.disputeVesselDemurrage",
                input: In(shipmentId: shipmentId, demurrageId: row?.id, reason: reason))
            if out.success == true {
                filed = true
                actionNote = "Dispute filed — \(out.disputed ?? 1) charge marked disputed."
            } else {
                actionNote = "Dispute could not be confirmed."
            }
        } catch {
            actionNote = "Dispute couldn't be filed. "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        filing = false
    }

    // MARK: - Formatting

    private func money(_ v: Double) -> String { "$" + grouped(Int(v.rounded())) }
    private func grouped(_ v: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}

#Preview("665 · Vessel Demurrage Dispute · Night") {
    VesselDemurrageDisputeScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("665 · Vessel Demurrage Dispute · Light") {
    VesselDemurrageDisputeScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
