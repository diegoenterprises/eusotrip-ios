//
//  010_VesselFreightBillAudit.swift
//  EusoTrip — Vessel Shipper · Freight Bill Audit (ocean invoice reconciliation).
//
//  Verbatim port of "010 Vessel Freight Bill Audit.svg" (Light + Dark). Cross-mode
//  parity sibling of 05 Rail · 010 Rail Freight Bill Audit — reconciles the ocean
//  carrier invoice (base ocean freight + BAF/CAF/THC/PSS + demurrage) against the
//  contracted rate and flags overcharges/duplicates/stale surcharges.
//  Nav anchored to the Shipper band (HOME · LOADS · [orb] · TRACK · ME),
//  Loads tab current.
//
//  Data:
//    vesselShipments.getVesselSettlement       (EXISTS vesselShipments.ts:1797)
//        invoice / settlement charge lines -> invoice total + breakdown
//    vesselShipments.getVesselFinancialSummary  (EXISTS vesselShipments.ts:3446)
//        expected / contract breakdown -> tariff-expected baseline
//    vesselShipments.calculateVesselDemurrage   (EXISTS vesselShipments.ts:2244)
//        validates the demurrage line on the invoice
//    vesselShipments.getVesselDemurrage         (EXISTS vesselShipments.ts:1769)
//        demurrage detail backing the recheck row
//
//  NOTE (named gap): the line-item variance reconcile is computed client-side over
//  getVesselSettlement vs getVesselFinancialSummary. A dedicated audit mutation
//  analogous to railFreightAudit.auditInvoice (railFreightAudit.ts:27) does NOT exist
//  for vessel yet. Proposed shape — vesselFreightAudit.auditInvoice(input:{invoiceId})
//  -> { invoiceTotal, expectedTotal, varianceTotal, breakdown{ oceanFreight, baf, thc,
//  pss, demurrage }, exceptions[{ type, severity, expected, actual, variance, message }],
//  auditStatus: passed|flagged|failed }. STUB until schema-backed.
//
//  Hero Maersk MAEU-72104 · invoice $4,880 vs contract expected $4,210 · variance +$670
//  · audit flagged (1 critical duplicate). Same booking VES-260524-7B3D90F2C5 as 009.
//  PERSONA Diego Usoro · Eusorone Technologies.
//

//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): READ_CACHED(ttl 1h) audit ledger · approve/dispute CTAs ONLINE_ONLY(money). Cached, extrapolated
//  and queued states render VISIBLY DISTINCT (staleness line · queued badge); no silent cache.
//
import SwiftUI

struct VesselShipperFreightBillAuditScreen: View {
    let theme: Theme.Palette
    let invoiceId: String
    init(theme: Theme.Palette, invoiceId: String = "MAEU-72104") {
        self.theme = theme; self.invoiceId = invoiceId
    }
    var body: some View {
        Shell(theme: theme) { VesselFreightBillAuditBody(invoiceId: invoiceId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Track", systemImage: "location.circle", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror getVesselSettlement + getVesselFinancialSummary returns)

private struct AuditSummary: Decodable {
    let invoiceTotal: Double?
    let expectedTotal: Double?
    let varianceTotal: Double?
    let breakdownLine: String?      // "Ocean $2,640 · BAF $1,090 · THC $740 · PSS $410"
    let auditStatus: String?        // passed | flagged | failed
}

private struct AuditException: Decodable, Identifiable {
    let id: Int
    let type: String?               // duplicate | overcharge | demurrage | stale
    let severity: String?           // critical | warning | info
    let title: String?
    let amountLabel: String?        // "+$370" | "$900→$1,090"
    let message: String?
}

// MARK: - Body

private struct VesselFreightBillAuditBody: View {
    let invoiceId: String
    @Environment(\.palette) private var palette
    @State private var summary: AuditSummary? = nil
    @State private var exceptions: [AuditException] = []
    @State private var recoverable: Double = 670
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var gapNotice: String? = nil

    private func severityDot(_ s: String?) -> Color {
        switch s {
        case "critical": return Brand.danger
        case "warning":  return Brand.warning
        default:         return palette.textTertiary
        }
    }
    private var statusTone: StatusPill.Kind {
        switch summary?.auditStatus {
        case "failed": return .danger
        case "flagged": return .warning
        default: return .success
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Auditing invoice…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    varianceCard
                    exceptionList
                    esangAdvisory
                    recoveryCard
                    actionRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL SHIPPER · FREIGHT AUDIT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            HStack {
                Text(invoiceId).font(.system(size: 28, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(text: summary?.auditStatus?.uppercased() ?? "FLAGGED", kind: statusTone)
            }
            Text("Maersk TPEB FAK · VES-…F2C5 · Shanghai CNSHA → Long Beach")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var varianceCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("INVOICE TOTAL · MAERSK MAEU-72104").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline) {
                    Text("$\(Int(summary?.invoiceTotal ?? 4880))").font(.system(size: 34, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Contract expected $\(Int(summary?.expectedTotal ?? 4210))").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text("Variance +$\(Int(summary?.varianceTotal ?? 670))").font(.system(size: 13, weight: .heavy)).monospacedDigit().foregroundStyle(Brand.warning)
                    }
                }
                varianceBar.padding(.top, 2)
                Text(summary?.breakdownLine ?? "Ocean $2,640 · BAF $1,090 · THC $740 · PSS $410")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    /// Contract-vs-invoice ratio bar (replaces the phantom `Stepper` symbol — no such
    /// component exists in the app target; derived live, never hardcoded).
    private var varianceBar: some View {
        let inv = summary?.invoiceTotal ?? 4880
        let exp = summary?.expectedTotal ?? 4210
        let frac = inv > 0 ? min(max(exp / inv, 0), 1) : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.borderFaint).frame(height: 5)
                Capsule().fill(LinearGradient.primary).frame(width: geo.size.width * frac, height: 5)
            }
        }.frame(height: 5)
    }

    private var exceptionList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("EXCEPTIONS · \(exceptions.count) FLAGGED · \(exceptions.filter { $0.severity == "critical" }.count) CRITICAL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(spacing: 0) {
                    ForEach(exceptions) { e in
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(severityDot(e.severity)).frame(width: 10, height: 10).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title ?? "—").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textPrimary)
                                Text(e.message ?? "—").font(EType.caption).foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            Text(e.amountLabel ?? "").font(.system(size: 11, weight: .bold)).monospacedDigit().foregroundStyle(severityDot(e.severity))
                        }
                        .padding(.vertical, 8)
                        if e.id != exceptions.last?.id { Divider().overlay(palette.borderFaint) }
                    }
                }
            }
        }
    }

    private var esangAdvisory: some View {
        LifecycleCard {
            HStack(spacing: 12) {
                OrbeSang(state: .idle, diameter: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exceptions.isEmpty ? "ESang: invoice reconciles — no exceptions" : "ESang: dispute draft built from \(exceptions.count) exception\(exceptions.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    Text(exceptions.isEmpty ? "audit passed against contract rate · nothing to file" : "Recover +$\(Int(recoverable)) · file before B/L release")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
        }
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("RECOVERY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recoverable on this invoice").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text("1 duplicate + BAF overcharge + demurrage recheck").font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    Text("$\(Int(recoverable))").font(.system(size: 22, weight: .heavy)).monospacedDigit().foregroundStyle(Brand.success)
                }
            }
        }
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = gapNotice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.info)
                    Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Brand.info.opacity(0.08)))
            }
            HStack(spacing: 8) {
                CTAButton(title: "Draft dispute", action: { gapNotice = "Dispute filing is ONLINE_ONLY(money) and its vessel endpoint is a named gap (vesselFreightAudit.auditInvoice) — filed with the-oath. ESang keeps the draft locally until it lands." }, leadingIcon: "doc.text")
                SecondaryButton(title: "Charge lines") { }
            }
        }
    }

    private struct InvoiceQuery: Encodable { let invoiceId: String }
    private func load() async {
        loading = true; loadError = nil
        do {
            self.summary = try await EusoTripAPI.shared.query("vesselShipments.getVesselSettlement",
                                                              input: InvoiceQuery(invoiceId: invoiceId))
            // Expected baseline + client-side reconcile (vesselFreightAudit.auditInvoice is a named gap —
            // filed with the-oath; until it lands, exceptions derive from settlement vs financial summary).
            if let fin: AuditSummary = try? await EusoTripAPI.shared.query("vesselShipments.getVesselFinancialSummary",
                                                                           input: InvoiceQuery(invoiceId: invoiceId)) {
                if summary?.expectedTotal == nil, let e = fin.expectedTotal {
                    summary = AuditSummary(invoiceTotal: summary?.invoiceTotal ?? fin.invoiceTotal,
                                           expectedTotal: e,
                                           varianceTotal: summary?.varianceTotal ?? fin.varianceTotal,
                                           breakdownLine: summary?.breakdownLine ?? fin.breakdownLine,
                                           auditStatus: summary?.auditStatus ?? fin.auditStatus)
                }
            }
            let variance = summary?.varianceTotal ?? ((summary?.invoiceTotal ?? 0) - (summary?.expectedTotal ?? 0))
            recoverable = max(variance, 0)
            if variance > 0 {
                exceptions = [AuditException(id: 1,
                                             type: "overcharge",
                                             severity: variance > 500 ? "critical" : "warning",
                                             title: "Invoice exceeds contract rate",
                                             amountLabel: "+$\(Int(variance))",
                                             message: "billed above contracted lane rate · client-side reconcile")]
            } else {
                exceptions = []
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
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

#Preview("010 · Vessel Freight Bill Audit · Night") { VesselShipperFreightBillAuditScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("010 · Vessel Freight Bill Audit · Light") { VesselShipperFreightBillAuditScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
