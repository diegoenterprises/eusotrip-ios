//
//  010_VesselFreightBillAudit.swift
//  EusoTrip 2027 · 06 Vessel · 010 Freight Bill Audit — vessel mode-content of the ONE Shipper family.
//
//  REMEDIATED 2026-08-17 (fire §17, curing the DA_FAIL of 2026-08-17T18:55:04Z, which called this
//  the weakest row in the band and the cleanest failure). Archetype = MONEY-RECOVERY.
//
//  ───────── AXIS E · WRONG ROLE NAV (the hard fail) ─────────
//  The WALLET slot drew a clock glyph labelled "Track" — the vessel-OPERATOR enum — on a
//  SHIPPER-family screen, and the <desc> even self-documented the error. This band is vessel
//  mode-content of the ONE Shipper family; it must read as the same Shipper app as truck, never as
//  a separate product. The enum is HOME · LOADS · [orb] · WALLET · ME and it is now that, here and
//  in both SVG twins (Light:116, Dark:112 corrected alongside).
//
//  ───────── AXIS A · THE MONEY-ANCHOR LAW ─────────
//  The H1 was the invoice number and the hero figure was $4,880 — the CARRIER'S number, the one
//  figure on this screen the shipper cannot change — while the disputed delta of +$670, the entire
//  reason the screen exists, sat in a 13px secondary line. Golden anchor 227 Settlement Detail makes
//  the figure the H1. So: H1 = the recoverable delta, the invoice reference moves to the eyebrow
//  meta pair (where 227 keeps PAYABLE · POD), and billed-vs-contract drops to a compact strip below
//  the recovery decomposition.
//
//  ───────── THE INSTRUMENT BUG ─────────
//  The stacked bar had 2 segments against 3 dot colours, so the largest exception (+$370 duplicate
//  THC) had no segment at all. Segments and swatches are now generated from ONE ordered array
//  (`pricedExceptions`) — see `recoveryBar` and `exceptionLedger`, which both iterate it. The counts
//  cannot drift because there is only one count. Unpriced exceptions are EXCLUDED from the bar on
//  purpose and rendered with a dashed swatch and the words "no amount yet" — a stated exclusion,
//  not an accidental one.
//
//  ───────── THE RECEIVER WAS BUILT AND THE WIRE WAS NOT. NOW IT IS. ─────────
//  vesselFreightAudit.flagRecovery EXISTS at vesselFreightAudit.ts:29, mounted at routers.ts:3361.
//  Read first-hand this fire. Shape confirmed:
//    input  { invoiceId: string(1...120), disputedLines: string[](<=100, each <=300), recoverAmount: number>=0 }
//    writes one `disputes` row (subject "Vessel freight recovery — <invoiceId>", reason "rate",
//           status "open", amountInDispute = recoverAmount) at :77, plus the "created"
//           `disputeEvents` thread row at :90
//    IDEMPOTENT per invoice — a repeat tap returns the existing open dispute instead of spawning a
//           second one (:57-72), so the CTA is safe to re-tap and says so
//    output { ok, disputeId: "DSP-<n>" | null, recoverAmount, lineCount }
//  The old Swift:242 still called this a named gap and refused to fire. That refusal is deleted and
//  the CTA performs the write, sending the priced exception lines verbatim as `disputedLines`.
//  HONEST LIMITATION SURFACED ON SCREEN, not buried in a comment: the procedure sets
//  counterpartyUserId = 0 (:81-83) because the ocean carrier's platform account is not resolvable
//  from a bare bill reference, so the dispute opens UNASSIGNED. The DISPUTE STATE card says so
//  before the user taps.
//  RBAC follow-up for the-oath: flagRecovery is `protectedProcedure`; it should be `vesselProcedure`.
//  Counter-party surfaces 786 / 809 / 810 consume the same `disputes` vertical.
//
//  ───────── AXIS D · FOUR WRONG REFS BEHIND A FALSE VERIFICATION CLAIM ─────────
//  The old header and both <desc> blocks carried "re-verified live 2026-06-20" over four refs that
//  were all wrong: getVesselSettlement:1469, getVesselFinancialSummary:2859,
//  calculateVesselDemurrage:1773, getVesselDemurrage:1441. That claim is withdrawn.
//  Worse than the numbers were the SHAPES — the old port could only ever have failed:
//    · getVesselSettlement takes { shipmentId } coerced to a NUMBER; the port sent { invoiceId: String }.
//    · getVesselFinancialSummary takes NO INPUT at all; the port sent it one.
//    · Neither returns { invoiceTotal, expectedTotal, varianceTotal, breakdownLine, auditStatus } —
//      the struct the port decoded into was invented end to end.
//
//  ───────── WIRING MANIFEST · every line verified first-hand 2026-08-17 ─────────
//    EXISTS · vesselFreightAudit.flagRecovery         :29   { invoiceId, disputedLines[], recoverAmount }
//                                                            ← THIS SCREEN'S WRITE (disputes + disputeEvents)
//    EXISTS · vesselShipments.getVesselSettlement     :2129 { shipmentId }
//                        -> { shipmentId, bookingNumber, status, freight, demurrage, portCharges, total, currency }
//                           ← the BILLED side (aggregates only; see named gap 1)
//    EXISTS · vesselShipments.getVesselShipmentDetail :561  { id } -> vessel_shipments row + joins
//                           ← the CONTRACTED side (`rate` is the agreed lane rate)
//    EXISTS · vesselShipments.getVesselDemurrage      :2101 { shipmentId? } -> [vessel_demurrage]
//                           ← what the carrier BILLED for demurrage, per row
//    EXISTS · vesselShipments.calculateVesselDemurrage:2576 { shipmentId } (a MUTATION)
//                        -> { demurrage, dwellDays, freeTimeDays, message }
//                           ← what the dwell ACTUALLY earns; the difference is the recheck line
//    EXISTS · vesselShipments.getVesselFinancialSummary:3778 (NO INPUT) -> { settlements[], demurrage[] }
//                           ← portfolio context; not used for this invoice's reconcile
//
//  ───────── NAMED GAPS · proposed, never invented ─────────
//    1. getVesselSettlement:2129 returns AGGREGATES (freight / demurrage / portCharges / total), not
//       charge LINES. So per-line duplicate and surcharge detection cannot be proven client-side
//       today, and this screen does not pretend otherwise: it derives every exception it can prove
//       and renders a visible row naming what is still missing.
//       Proposed (the read-side analogue of railFreightAudit.auditInvoice, railFreightAudit.ts:27):
//         vesselFreightAudit.auditInvoice({ invoiceId })
//           -> { invoiceTotal, expectedTotal, varianceTotal,
//                breakdown { oceanFreight, baf, thc, pss, demurrage },
//                exceptions[{ type, severity, expected, actual, variance, message }],
//                auditStatus: "passed" | "flagged" | "failed" }
//    2. There is no vessel invoice table, so the carrier invoice reference is a free string, not a
//       foreign key. flagRecovery encodes it into the dispute subject for its idempotency lookup.
//
//  PERSONA Diego Usoro · Eusorone Technologies (SHIPPER). Booking VES-260524-7B3D90F2C5, the same
//  load row as 009 Vessel Tender Workflow — one row, several vantages.
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  OFFLINE POLICY (doctrine W · Encyclopedia v2), derived not stamped:
//    READ_CACHED(ttl 1h) for the audit ledger — invoice lines do not move minute to minute, but an
//    hour-old variance is worth re-checking before you file money against it, so the window is short
//    and a staleness line marks cached data as visibly distinct from live.
//    ONLINE_ONLY(money) for the recovery filing — opening a dispute is a money claim against a
//    counter-party; it is never queued. Offline the CTA disables and names the reason.
//
import SwiftUI

// MARK: - Screen

struct VesselShipperFreightBillAuditScreen: View {
    let theme: Theme.Palette
    /// The vessel shipment this invoice belongs to — every read on this screen is keyed by it.
    let shipmentId: Int
    /// The carrier's invoice reference. Named gap 2: a free string, not a foreign key.
    let invoiceRef: String

    init(theme: Theme.Palette, shipmentId: Int, invoiceRef: String) {
        self.theme = theme; self.shipmentId = shipmentId; self.invoiceRef = invoiceRef
    }

    var body: some View {
        if shipmentId > 0,
           !invoiceRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Shell(theme: theme) {
                VesselFreightBillAuditBody(shipmentId: shipmentId, invoiceRef: invoiceRef)
            } nav: {
                BottomNav(
                    leading: [NavSlot(label: "Home",  systemImage: "house",       isCurrent: false),
                              NavSlot(label: "Loads", systemImage: "shippingbox", isCurrent: true)],
                    trailing: [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: false),
                               NavSlot(label: "Me",     systemImage: "person",     isCurrent: false)],
                    orbState: .idle
                )
            }
        } else {
            ShipperRecordContextUnavailableScreen(
                theme: theme,
                systemImage: "doc.text.magnifyingglass",
                title: "Freight audit unavailable",
                subtitle: "Open a carrier invoice to verify its shipment, charges, and recovery authority."
            )
        }
    }
}

// MARK: - Wire shapes · field-for-field against the live returns

/// getVesselSettlement:2129 — aggregates only. See named gap 1.
private struct SettlementAgg010: Decodable {
    let shipmentId: Int?
    let bookingNumber: String?
    let status: String?
    let freight: Double?
    let demurrage: Double?
    let portCharges: Double?
    let total: Double?
    let currency: String?
}

/// getVesselShipmentDetail:561 — the contracted side.
private struct ShipmentContract010: Decodable {
    struct PortRow: Decodable { let name: String?; let unlocode: String? }
    let id: Int?
    let bookingNumber: String?
    let rate: String?                 // decimal(10,2) arrives as a string
    let originPort: PortRow?
    let destinationPort: PortRow?
}

/// getVesselDemurrage:2101 — [vessel_demurrage] (schema.ts:12056).
private struct DemurrageRow010: Decodable, Identifiable {
    let id: Int
    let chargeType: String?
    let freeTimeDays: Int?
    let chargeableDays: Int?
    let ratePerDay: String?
    let totalCharge: String?
    let status: String?
}

/// calculateVesselDemurrage:2576 — a MUTATION.
private struct DemurrageCalc010: Decodable {
    let demurrage: Double?
    let dwellDays: Double?
    let freeTimeDays: Int?
    let message: String?
}

/// flagRecovery:29 return.
private struct RecoveryResult010: Decodable {
    let ok: Bool?
    let disputeId: String?
    let recoverAmount: Double?
    let lineCount: Int?
}

// MARK: - The single source of truth for the instrument

/// ONE array feeds the stacked bar AND the swatch ledger. There is no second list to drift from.
private struct AuditException010: Identifiable {
    enum Severity { case critical, warning, info, review }
    let id: Int
    let title: String
    let detail: String
    /// nil == not priced yet. Unpriced rows are excluded from the bar, and the row says so.
    let amount: Double?
    let severity: Severity
}

// MARK: - Body

private struct VesselFreightBillAuditBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let invoiceRef: String

    @State private var billedTotal: Double? = nil
    @State private var billedFreight: Double? = nil
    @State private var billedDemurrage: Double? = nil
    @State private var billedPortCharges: Double? = nil
    @State private var contractRate: Double? = nil
    @State private var currency = ""
    @State private var lane = "Route not reported"
    @State private var bookingNumber = "Booking not reported"

    @State private var exceptions: [AuditException010] = []
    @State private var lineLevelPending = false      // named gap 1, made visible

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var syncedAt: Date? = nil
    @State private var servedFromCache = false

    // Charge-lines disclosure — was an empty closure; now a real state change.
    @State private var showChargeLines = false
    @State private var demurrageRows: [DemurrageRow010] = []

    // The write
    @State private var filing = false
    @State private var openDisputeId: String? = nil
    @State private var fileNotice: String? = nil
    @State private var fileFailed = false

    private var offline: Bool { !OfflineReachabilityHub.shared.isOnline }

    /// Bar segments and swatches BOTH derive from this. One count, so no drift is possible.
    private var pricedExceptions: [AuditException010] { exceptions.filter { ($0.amount ?? 0) > 0 } }
    private var unpricedExceptions: [AuditException010] { exceptions.filter { ($0.amount ?? 0) <= 0 } }
    private var recoverable: Double { pricedExceptions.reduce(0) { $0 + ($1.amount ?? 0) } }

    private func money(_ v: Double) -> String {
        "$" + v.rounded().formatted(.number.precision(.fractionLength(0)))
    }
    private func tint(_ s: AuditException010.Severity) -> Color {
        switch s {
        case .critical: return Brand.danger
        case .warning:  return Brand.warning
        case .info:     return Brand.info
        case .review:   return palette.textTertiary
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Reconciling invoice…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    recoveryCard
                    billedVsContract
                    if showChargeLines { chargeLinesPanel }
                    disputeStateCard
                    esangAdvisory
                    actionRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header — the money is the H1 (Axis A)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · FREIGHT AUDIT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(invoiceRef).font(EType.mono(.micro)).tracking(1.0).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Text("\(recoverable > 0 ? "+" : "")\(money(recoverable)) recoverable")
                    .font(.system(size: 28, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: Space.s2)
                StatusPill(text: auditStatus, kind: auditTone)
            }
            Text(sublineText).font(EType.caption).foregroundStyle(palette.textSecondary)
            if servedFromCache { stalenessLine }
        }
    }
    private var auditStatus: String {
        if exceptions.isEmpty { return "CLEAN" }
        return pricedExceptions.contains { $0.severity == .critical } ? "FLAGGED" : "REVIEW"
    }
    private var auditTone: StatusPill.Kind {
        if exceptions.isEmpty { return .success }
        return pricedExceptions.contains { $0.severity == .critical } ? .warning : .info
    }
    private var sublineText: String {
        let billed = billedTotal.map { money($0) } ?? "—"
        let contract = contractRate.map { money($0) } ?? "—"
        return "Billed \(billed) vs contract \(contract) · \(lane)"
    }
    private var stalenessLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 10, weight: .semibold))
            Text(syncedAt.map { "Cached audit · last synced \($0.formatted(date: .abbreviated, time: .shortened))" }
                 ?? "Cached audit · not yet synced this session")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(Brand.warning)
    }

    // MARK: The instrument — bar and swatches from ONE array

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("RECOVERY · \(pricedExceptions.count) PRICED LINE\(pricedExceptions.count == 1 ? "" : "S") · \(unpricedExceptions.count) UNDER REVIEW")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            ActiveCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("WHERE THE \(recoverable > 0 ? "+" : "")\(money(recoverable)) COMES FROM")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    recoveryBar
                    exceptionLedger
                    if lineLevelPending {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.info)
                Text("Line-item surcharge and duplicate checks are unavailable. Review the invoice document before approval; the amounts above reflect aggregate invoice and contract records only.")
                                .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    /// Segments come from `pricedExceptions` — the same array the swatch rows below iterate.
    private var recoveryBar: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let items = pricedExceptions
            let total = max(recoverable, 0.01)
            let usable = max(geo.size.width - gap * CGFloat(max(items.count - 1, 0)), 1)
            HStack(spacing: gap) {
                if items.isEmpty {
                    Capsule().fill(palette.borderFaint)
                } else {
                    ForEach(items) { e in
                        Capsule()
                            .fill(tint(e.severity))
                            .frame(width: usable * CGFloat((e.amount ?? 0) / total))
                    }
                }
            }
        }
        .frame(height: 12)
    }

    private var exceptionLedger: some View {
        VStack(spacing: 0) {
            ForEach(Array(exceptions.enumerated()), id: \.element.id) { idx, e in
                HStack(alignment: .top, spacing: 12) {
                    // The swatch is the SAME colour the bar segment used, from the SAME element.
                    Group {
                        if e.amount == nil || (e.amount ?? 0) <= 0 {
                            Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [2.5, 2]))
                                .foregroundStyle(palette.textTertiary)
                        } else {
                            Circle().fill(tint(e.severity))
                        }
                    }
                    .frame(width: 10, height: 10).padding(.top, 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(e.amount == nil ? palette.textTertiary : palette.textPrimary)
                        Text(e.detail).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: Space.s2)
                    VStack(alignment: .trailing, spacing: 2) {
                        if let a = e.amount, a > 0 {
                            Text("+\(money(a))").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(tint(e.severity))
                            Text(String(format: "%.1f%% of recovery", (a / max(recoverable, 0.01)) * 100))
                                .font(.system(size: 9.5, weight: .bold)).foregroundStyle(palette.textTertiary)
                        } else {
                            Text("confirm").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                .padding(.vertical, 8)
                if idx != exceptions.count - 1 { Divider().overlay(palette.borderFaint) }
            }
            if exceptions.isEmpty {
                Text("Invoice reconciles against the contracted rate — nothing to recover.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
        }
    }

    // MARK: The carrier's numbers, demoted below the recovery

    private var billedVsContract: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("BILLED VS CONTRACT · \(chargeLines.count) CHARGE LINES")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text(chargeLines.map { "\($0.0) \(money($0.1))" }.joined(separator: " · "))
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    HStack {
                        Text("Invoice \(billedTotal.map { money($0) } ?? "—")")
                            .font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text("Contract \(contractRate.map { money($0) } ?? "—")")
                            .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }
    /// The aggregate buckets getVesselSettlement:2129 actually returns — no invented CAF/PSS split.
    private var chargeLines: [(String, Double)] {
        var out: [(String, Double)] = []
        if let v = billedFreight, v > 0 { out.append(("Ocean", v)) }
        if let v = billedPortCharges, v > 0 { out.append(("Port", v)) }
        if let v = billedDemurrage, v > 0 { out.append(("Demurrage", v)) }
        return out
    }

    /// AXIS: "Charge lines" was `SecondaryButton(title: "Charge lines") { }` — an empty closure.
    /// It now discloses the per-row demurrage detail already loaded. No new fetch, a real change.
    private var chargeLinesPanel: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("DEMURRAGE ROWS · \(demurrageRows.count) BILLED")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(spacing: 0) {
                    if demurrageRows.isEmpty {
                        Text("The carrier billed no demurrage rows against this shipment. Ocean and port charges arrive as aggregates only — see the note above.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(demurrageRows.enumerated()), id: \.element.id) { idx, r in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((r.chargeType ?? "demurrage").uppercased())
                                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                                    Text("\(r.chargeableDays ?? 0) chargeable · \(r.freeTimeDays ?? 0) free · \(r.status ?? "—")")
                                        .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                                }
                                Spacer()
                                Text(money(Double(r.totalCharge ?? "") ?? 0))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                            }
                            .padding(.vertical, 7)
                            if idx != demurrageRows.count - 1 { Divider().overlay(palette.borderFaint) }
                        }
                    }
                }
            }
        }
    }

    // MARK: What the write will actually do, said before the user taps it

    private var disputeStateCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("DISPUTE STATE · ONE PER INVOICE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                HStack(alignment: .center, spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(openDisputeId.map { "Recovery filed · \($0)" } ?? "No recovery filed on this invoice yet")
                            .font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text("opens unassigned — the carrier's account is not resolvable from a bill ref")
                            .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    StatusPill(text: openDisputeId == nil ? "NONE OPEN" : "OPEN",
                               kind: openDisputeId == nil ? .neutral : .info)
                }
            }
        }
    }

    private var esangAdvisory: some View {
        LifecycleCard {
            HStack(spacing: 12) {
                OrbeSang(state: .idle, diameter: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pricedExceptions.isEmpty
                         ? "Invoice reconciles — no exceptions to file"
                         : "Dispute draft built from \(pricedExceptions.count) priced exception\(pricedExceptions.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    HStack(spacing: 6) {
                        Text(pricedExceptions.isEmpty ? "$0" : "+\(money(recoverable))")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(Brand.magenta)
                        Text(pricedExceptions.isEmpty
                             ? "audited against the contracted rate · nothing to file"
                             : "recoverable · file before the B/L is released")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Actions — the primary now performs the real write

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = fileNotice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: fileFailed ? "exclamationmark.triangle" : "checkmark.seal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(fileFailed ? Brand.danger : Brand.success)
                    Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill((fileFailed ? Brand.danger : Brand.success).opacity(0.08)))
            }
            HStack(spacing: 8) {
                CTAButton(title: filing ? "Filing…" : "Flag for recovery · \(money(recoverable))",
                          action: { Task { await flagRecovery() } },
                          leadingIcon: "flag",
                          isLoading: filing)
                    .disabled(!canFile)
                    .opacity(canFile ? 1 : 0.45)
                SecondaryButton(title: showChargeLines ? "Hide lines" : "Charge lines") {
                    withAnimation(.easeInOut(duration: 0.2)) { showChargeLines.toggle() }
                }
            }
            if let why = fileDisabledReason {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.info)
                    Text(why).font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                }
            } else {
                Text("Filing opens one rate dispute · a repeat tap returns the same one")
                    .font(.system(size: 10.5)).foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
    private var canFile: Bool {
        !filing
            && !offline
            && recoverable > 0
            && !invoiceRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var fileDisabledReason: String? {
        if offline { return "Filing a recovery is a money claim against the carrier, so it is never queued offline. Reconnect and it will file." }
        if invoiceRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Open this audit from a carrier invoice so the recovery can be tied to a verified invoice reference."
        }
        if recoverable <= 0 { return "Nothing priced to recover on this invoice, so there is nothing to file." }
        return nil
    }

    // MARK: Load — real inputs, real returns, honest derivation

    private func load() async {
        loading = true; loadError = nil
        struct ShipmentIn: Encodable { let shipmentId: Int }
        struct IdIn: Encodable { let id: Int }
        do {
            async let agg: SettlementAgg010 = EusoTripAPI.shared.query(
                "vesselShipments.getVesselSettlement", input: ShipmentIn(shipmentId: shipmentId))
            async let contract: ShipmentContract010 = EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: IdIn(id: shipmentId))
            async let dem: [DemurrageRow010] = EusoTripAPI.shared.query(
                "vesselShipments.getVesselDemurrage", input: ShipmentIn(shipmentId: shipmentId))
            let (a, c, d) = try await (agg, contract, dem)

            billedTotal       = a.total
            billedFreight     = a.freight
            billedDemurrage   = a.demurrage
            billedPortCharges = a.portCharges
            currency          = a.currency ?? currency
            bookingNumber     = a.bookingNumber ?? c.bookingNumber ?? bookingNumber
            contractRate      = Double(c.rate ?? "")
            if let o = c.originPort?.unlocode, let dst = c.destinationPort?.unlocode { lane = "\(o) → \(dst)" }
            demurrageRows     = d

            // calculateVesselDemurrage:2576 is a MUTATION — it recomputes dwell from the event
            // trail. Best-effort: if it fails, the demurrage recheck line simply does not appear
            // rather than being guessed.
            var computedDemurrage: Double? = nil
            if let calc: DemurrageCalc010 = try? await EusoTripAPI.shared.mutation(
                "vesselShipments.calculateVesselDemurrage", input: ShipmentIn(shipmentId: shipmentId)) {
                computedDemurrage = calc.demurrage
            }
            buildExceptions(computedDemurrage: computedDemurrage)
            syncedAt = Date(); servedFromCache = false
        } catch {
            // READ_CACHED(ttl 1h): keep the last-known ledger but MARK it. Money is never shown as
            // live when it is not.
            if syncedAt != nil { servedFromCache = true } else { loadError = error.eusoUserCopy }
        }
        loading = false
    }

    /// Every exception here is something the live aggregates can PROVE. Anything the aggregates
    /// cannot decompose is declared missing (`lineLevelPending`) rather than fabricated.
    private func buildExceptions(computedDemurrage: Double?) {
        var out: [AuditException010] = []
        var nextId = 1

        let billedDem = billedDemurrage ?? 0
        if let computed = computedDemurrage, billedDem - computed > 0.5 {
            let variance = billedDem - computed
            out.append(AuditException010(
                id: nextId,
                title: "DEMURRAGE RECHECK",
                detail: "carrier billed \(money(billedDem)); recomputed dwell earns \(money(computed))",
                amount: variance,
                severity: variance > 500 ? .critical : .info))
            nextId += 1
        }

        // Overall variance minus anything already attributed above, so nothing is double-counted.
        if let billed = billedTotal, let contract = contractRate {
            let attributed = out.reduce(0) { $0 + ($1.amount ?? 0) }
            let residual = billed - contract - attributed
            if residual > 0.5 {
                out.append(AuditException010(
                    id: nextId,
                    title: "BILLED ABOVE CONTRACT RATE",
                    detail: "\(money(billed)) invoiced against a \(money(contract)) contracted lane rate",
                    amount: residual,
                    severity: residual > 500 ? .critical : .warning))
                nextId += 1
            }
            // The residual exists but cannot be split into surcharge lines from aggregates alone.
            lineLevelPending = residual > 0.5
        } else {
            lineLevelPending = true
        }

        if lineLevelPending {
            out.append(AuditException010(
                id: nextId,
                title: "SURCHARGE SPLIT · REVIEW",
                detail: "BAF / THC / PSS lines are not itemised by the settlement read, so no amount yet",
                amount: nil,
                severity: .review))
        }
        exceptions = out
    }

    // MARK: The write — vesselFreightAudit.flagRecovery:29, for real.

    private func flagRecovery() async {
        guard canFile else { return }
        filing = true; fileNotice = nil; fileFailed = false
        defer { filing = false }
        struct RecoveryIn: Encodable {
            let invoiceId: String
            let disputedLines: [String]
            let recoverAmount: Double
        }
        // disputedLines carries the priced exceptions verbatim — the same array the bar drew — so
        // the dispute thread says exactly what the screen showed. Server caps each line at 300 chars.
        let lines = pricedExceptions.map { e in
            String("\(e.title) +\(money(e.amount ?? 0)) — \(e.detail)".prefix(300))
        }
        do {
            let r: RecoveryResult010 = try await EusoTripAPI.shared.mutation(
                "vesselFreightAudit.flagRecovery",
                input: RecoveryIn(invoiceId: invoiceRef, disputedLines: lines, recoverAmount: recoverable))
            openDisputeId = r.disputeId
            fileFailed = false
            fileNotice = r.disputeId.map {
                "Recovery filed as \($0) for \(money(recoverable)) across \(r.lineCount ?? lines.count) lines. It opens unassigned until the carrier's account is resolved, and tapping again will return this same dispute."
            } ?? "Recovery filed for \(money(recoverable)). The dispute thread is open."
        } catch {
            fileFailed = true
            fileNotice = error.eusoUserCopy
        }
    }
}

/// Outlined secondary action — pairs with the primary CTAButton. File-private
/// (no shared SecondaryButton exists in the app target; house pattern per 815/809).
private struct SecondaryButton: View {
    @Environment(\.palette) private var palette
    let title: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

#Preview("010 · Vessel Freight Bill Audit · Night") {
    VesselShipperFreightBillAuditScreen(theme: Theme.dark, shipmentId: 0, invoiceRef: "")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("010 · Vessel Freight Bill Audit · Light") {
    VesselShipperFreightBillAuditScreen(theme: Theme.light, shipmentId: 0, invoiceRef: "")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
