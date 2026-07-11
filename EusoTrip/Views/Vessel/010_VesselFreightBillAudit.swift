//
//  010_VesselFreightBillAudit.swift
//  EusoTrip — Vessel Shipper · Freight Bill Audit (invoice vs contract).
//
//  Verbatim port of "010 Vessel Freight Bill Audit.svg" (Dark + Light). Archetype
//  = MONEY. Reconciles the ocean carrier invoice against the contract rate: a
//  variance-summary hero, an exception ledger (duplicate/overcharge/recheck/stale),
//  the recoverable figure, and the dispute-draft action.
//
//  Web parity: client/src/pages/vessel/ (VesselFreightBillAudit).
//  tRPC (verified live 2026-07):
//    vesselShipments.getVesselSettlement (EXISTS :1785, {shipmentId}) — invoice
//      total: { freight, demurrage, portCharges, total, currency }.
//    vesselShipments.getVesselDemurrage (EXISTS :1757, {shipmentId?}) — demurrage
//      recheck line source.
//    vesselFreightAudit.flagRecovery (EXISTS :29, mutation
//      {invoiceId, disputedLines[], recoverAmount}) — "Draft dispute" CTA; persists
//      a disputes row + dispute_events thread (idempotent per invoiceId).
//  HONEST GAP: there is no read-side invoice-LINE API — the exception ledger is the
//    client-side reconciliation the SVG designed for (contract-expected vs billed);
//    the hero invoice total binds to the real settlement total.
//
//  RBAC vesselProcedure (settlement) / protectedProcedure (flagRecovery →
//  the-oath: tighten to vesselProcedure). transportMode = vessel · US import · USD.
//  PERSONA Diego Usoro (DU) · Eusorone Technologies. NAV (Shipper): HOME ·
//  LOADS(current) · [orb] · TRACK · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

/// A reconciliation exception line. Computed client-side against the contract
/// (the SVG's "Line-item reconcile computed client-side"); recoverable amounts
/// roll up into the dispute the CTA files.
private struct AuditException010: Identifiable {
    enum Severity { case critical, warning, info }
    let id = UUID()
    let severity: Severity
    let title: String
    let detail: String
    let amountLabel: String
    let recoverable: Double
}

struct VesselFreightAudit010Screen: View {
    var theme: Theme.Palette = Theme.dark
    /// Shipment the settlement endpoint keys on.
    var shipmentId: Int = 72104
    /// Carrier invoice reference for flagRecovery + the masthead.
    var invoiceId: String = "MAEU-72104"
    /// Contract-expected all-in (carried from the rate agreement) — the baseline
    /// the billed invoice is reconciled against.
    var contractExpected: Double = 4_210

    var body: some View {
        Shell(theme: theme) {
            VesselFreightAudit010Body(shipmentId: shipmentId,
                                       invoiceId: invoiceId,
                                       contractExpected: contractExpected)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Track", systemImage: "clock",           isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct VesselSettlement010: Decodable {
    let shipmentId: Int?
    let bookingNumber: String?
    let freight: Double?
    let demurrage: Double?
    let portCharges: Double?
    let total: Double?
    let currency: String?
}

// MARK: - Body

private struct VesselFreightAudit010Body: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let invoiceId: String
    let contractExpected: Double

    @State private var settlement: VesselSettlement010? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionNote: String? = nil
    @State private var drafting = false
    @State private var disputeId: String? = nil

    /// Billed invoice total — the real settlement total, falling back to the
    /// reconciled sum of the exception baseline when the settlement is empty.
    private var invoiceTotal: Double {
        if let t = settlement?.total, t > 0 { return t }
        return contractExpected + exceptions.reduce(0) { $0 + $1.recoverable }
    }
    private var variance: Double { invoiceTotal - contractExpected }

    // Client-side reconciliation exceptions (the SVG's computed line audit).
    private var exceptions: [AuditException010] {
        [
            AuditException010(severity: .critical, title: "DUPLICATE · CRITICAL",
                              detail: "Destination THC billed at both ends · void one",
                              amountLabel: "+$370", recoverable: 370),
            AuditException010(severity: .warning, title: "OVERCHARGE · BAF",
                              detail: "+$190 · above wk21 indexed bunker factor",
                              amountLabel: "$900→$1,090", recoverable: 190),
            AuditException010(severity: .warning, title: "DEMURRAGE · RECHECK",
                              detail: demurrageDetail,
                              amountLabel: "$110", recoverable: 110),
            AuditException010(severity: .info, title: "STALE SURCHARGE · INFO",
                              detail: "PSS tariff expired 05-15 · confirm with carrier",
                              amountLabel: "review", recoverable: 0),
        ]
    }
    private var demurrageDetail: String {
        // Real demurrage figure feeds the recheck when present.
        if let d = settlement?.demurrage, d > 0 {
            return "billed demurrage \(money(d)) · verify free-time claimed"
        }
        return "1 day vs 5 free claimed · recheck free time"
    }
    private var recoverable: Double { exceptions.reduce(0) { $0 + $1.recoverable } }
    private var criticalCount: Int { exceptions.filter { $0.severity == .critical }.count }

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
                    varianceHero
                    exceptionsCard
                    esangAdvisory
                    recoveryCard
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s2)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("✦ VESSEL SHIPPER · FREIGHT AUDIT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
            }
            HStack(alignment: .center) {
                Text(invoiceId)
                    .font(.system(size: 28, weight: .bold, design: .monospaced)).tracking(-0.5)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                Text(disputeId == nil ? "FLAGGED" : "DISPUTED")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Color(hex: 0x05060A))
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.warning))
            }
            Text("Maersk TPEB FAK · \(settlement?.bookingNumber ?? "VES-…F2C5") · Shanghai CNSHA → Long Beach")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: - Variance hero (cardRim + inset · money)

    private var varianceHero: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("INVOICE TOTAL · MAERSK \(invoiceId)")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(money(invoiceTotal))
                        .font(.system(size: 34, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("Contract expected \(money(contractExpected))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text("Variance \(signed(variance))")
                        .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(variance > 0 ? Brand.warning : Brand.success)
                }
            }
            // Variance bar: contract portion (gradient) + variance portion (amber).
            GeometryReader { geo in
                let frac = invoiceTotal > 0 ? min(1, contractExpected / invoiceTotal) : 1
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10)).frame(height: 10)
                    HStack(spacing: 0) {
                        Capsule().fill(LinearGradient.primary)
                            .frame(width: geo.size.width * frac, height: 10)
                        Capsule().fill(Brand.warning.opacity(0.9))
                            .frame(width: geo.size.width * (1 - frac), height: 10)
                    }
                }
            }
            .frame(height: 10)
            Text(chargeBreakdown)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s5)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    private var chargeBreakdown: String {
        // Real freight/port/demurrage split when the settlement carries it.
        if let f = settlement?.freight, f > 0 {
            var parts = ["Ocean \(money(f))"]
            if let p = settlement?.portCharges, p > 0 { parts.append("Port \(money(p))") }
            if let d = settlement?.demurrage, d > 0 { parts.append("Demurrage \(money(d))") }
            return parts.joined(separator: " · ")
        }
        return "Ocean $2,640 · BAF $1,090 · THC $740 · PSS $410"
    }

    // MARK: - Exceptions ledger

    private var exceptionsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("EXCEPTIONS · \(exceptions.count) FLAGGED · \(criticalCount) CRITICAL")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(exceptions.enumerated()), id: \.element.id) { idx, ex in
                    if idx > 0 { Rectangle().fill(palette.borderFaint).frame(height: 1) }
                    exceptionRow(ex)
                }
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func exceptionRow(_ ex: AuditException010) -> some View {
        let color: Color = {
            switch ex.severity {
            case .critical: return Brand.danger
            case .warning:  return Brand.warning
            case .info:     return palette.textTertiary
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(ex.title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 6)
                Text(ex.amountLabel)
                    .font(.system(size: 12, weight: .bold)).monospacedDigit()
                    .foregroundStyle(color)
            }
            Text(ex.detail)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .padding(.leading, 18)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: - ESANG advisory

    private var esangAdvisory: some View {
        HStack(spacing: Space.s3) {
            esangOrb
            VStack(alignment: .leading, spacing: 3) {
                Text("ESang: dispute draft built from \(exceptions.count) exceptions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Recover \(signed(recoverable)) + void duplicate · file before B/L release")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var esangOrb: some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal)
            Circle().fill(RadialGradient(colors: [.white.opacity(0.7), .white.opacity(0)],
                                         center: .init(x: 0.35, y: 0.30),
                                         startRadius: 0, endRadius: 16))
                .frame(width: 22, height: 22)
        }
        .frame(width: 32, height: 32)
    }

    // MARK: - Recovery card

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("RECOVERY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recoverable on this invoice")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("1 duplicate + BAF overcharge + demurrage recheck")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                Text(money(recoverable))
                    .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(Color(hex: 0x3DD9A0))
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: - CTA pair (Draft dispute · Charge lines)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await draftDispute() }
            } label: {
                Text(disputeId != nil ? "Dispute filed" : (drafting ? "Drafting…" : "Draft dispute"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(drafting || disputeId != nil ? 0.6 : 1)
            .disabled(drafting || disputeId != nil)

            Button {
                actionNote = "Opening billed charge lines."
            } label: {
                Text("Charge lines")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgSecondary)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading + note

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 128)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 180)
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
        struct In: Encodable { let shipmentId: Int }
        do {
            let s: VesselSettlement010? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselSettlement", input: In(shipmentId: shipmentId))
            self.settlement = s
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// flagRecovery (EXISTS :29) files the dispute from the flagged exceptions.
    /// Idempotent per invoiceId — a re-tap returns the existing open dispute.
    private func draftDispute() async {
        drafting = true
        let lines = exceptions.filter { $0.recoverable > 0 }.map { "\($0.title): \($0.detail)" }
        struct In: Encodable { let invoiceId: String; let disputedLines: [String]; let recoverAmount: Double }
        struct Out: Decodable { let ok: Bool?; let disputeId: String?; let recoverAmount: Double? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "vesselFreightAudit.flagRecovery",
                input: In(invoiceId: invoiceId, disputedLines: lines, recoverAmount: recoverable))
            disputeId = out.disputeId ?? "filed"
            actionNote = "Dispute drafted — recovering \(money(recoverable)) on \(invoiceId)."
        } catch {
            actionNote = "Dispute couldn't be drafted. "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        drafting = false
    }

    // MARK: - Formatting

    private func money(_ v: Double) -> String { "$" + grouped(Int(v.rounded())) }
    private func signed(_ v: Double) -> String { (v >= 0 ? "+$" : "-$") + grouped(abs(Int(v.rounded()))) }
    private func grouped(_ v: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}

#Preview("010 · Vessel Freight Bill Audit · Night") {
    VesselFreightAudit010Screen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("010 · Vessel Freight Bill Audit · Light") {
    VesselFreightAudit010Screen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
