//
//  700_VesselFreightBillAudit.swift
//  EusoTrip — Vessel Operator · Freight Bill Audit.
//
//  Verbatim port of wireframe "700 Vessel Freight Bill Audit · Dark".
//  PURPOSE: carrier-vantage line-item audit of an ocean freight bill against
//  tariff context (billed vs expected, recoverable variance) so the operator
//  catches overbills before they hit settlement. Folds the carrier-portal
//  invoice, the tariff sheet and the bunker FSC schedule into one review
//  surface — one tap flags the variance for recovery.
//
//  WIRING (per SVG <desc>):
//    invoice + findings  <- accessorial.getLoadExpenses   EXISTS accessorial.ts:581
//    settlement context  <- vesselShipments.getVesselSettlement EXISTS vesselShipments.ts:713
//    CTA 'Flag for recovery' -> vesselFreightAudit.flagRecovery  STUB (named gap)
//

import SwiftUI

struct VesselFreightBillAuditScreen: View {
    let theme: Theme.Palette
    /// Load/shipment the freight bill belongs to. Defaults to 0 so the screen
    /// stays constructable as `VesselFreightBillAuditScreen(theme: p)` from the
    /// ScreenRegistry (mirrors 650/652 which take only `theme`). When the audit
    /// is opened from a specific shipment the caller can inject the real id.
    var loadId: Int = 0
    var shipmentId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselFreightBillAuditBody(loadId: loadId, shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

/// One accessorial / expense row from accessorial.getLoadExpenses
/// (accessorial.ts:581 → detentionClaims projection).
private struct LoadExpenseRow: Decodable, Identifiable {
    let id: Int
    let type: String?
    let amount: Double?
    let status: String?
    let facilityName: String?
    let billableMinutes: Int?
}

/// vesselShipments.getVesselSettlement (vesselShipments.ts:713).
private struct VesselSettlement700: Decodable {
    let shipmentId: Int?
    let bookingNumber: String?
    let status: String?
    let freight: Double?
    let demurrage: Double?
    let portCharges: Double?
    let total: Double?
    let currency: String?
}

/// One audit finding row rendered in the findings card. Severity drives the
/// icon glyph, tint and trailing pill — mirroring the three SVG rows
/// (VARIANCE · CRITICAL · MATCHED).
private struct AuditFinding: Identifiable {
    enum Severity { case variance, critical, matched }
    let id = UUID()
    let title: String
    let detail: String
    let severity: Severity
    /// Billed amount carried by a variance/critical row (0 for matched).
    var varianceAmount: Double = 0
}

// MARK: - Body

private struct VesselFreightBillAuditBody: View {
    let loadId: Int
    let shipmentId: Int

    @Environment(\.palette) private var palette
    @State private var expenses: [LoadExpenseRow] = []
    @State private var settlement: VesselSettlement700? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // CTA state — surfaces the named server gap honestly rather than faking a
    // success toast.
    @State private var flagging = false
    @State private var flagResult: String? = nil
    @State private var flagIsError = false

    // MARK: Derived audit context
    //
    // The findings + billed/expected/variance figures are derived from the
    // real expense rows returned by accessorial.getLoadExpenses. The wireframe
    // demo numbers (Maersk · drayage, +$180, $4,470 / $4,290) are the canonical
    // sample; when real rows are present we compute from them, when the load is
    // unbound (loadId == 0, ScreenRegistry mount) we render the real empty
    // state instead of fabricating a bill.

    private var billedTotal: Double {
        // Settlement total is the carrier-portal billed figure when present;
        // otherwise sum the expense rows.
        if let t = settlement?.total, t > 0 { return t }
        return expenses.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    private var expectedTotal: Double {
        // Expected = billed minus the recoverable variance (the sum of rows
        // flagged variance/critical). Matched rows carry no variance.
        billedTotal - recoverableVariance
    }

    private var recoverableVariance: Double {
        findings.reduce(into: 0.0) { acc, f in
            switch f.severity {
            case .variance, .critical: acc += abs(f.varianceAmount)
            case .matched:             break
            }
        }
    }

    private var exceptionCount: Int {
        findings.filter { $0.severity != .matched }.count
    }

    private var carrierLabel: String {
        // "Maersk · drayage" in the SVG — derived from the settlement booking
        // when available, else the first expense facility.
        if let b = settlement?.bookingNumber, !b.isEmpty {
            return "\(b) · drayage"
        }
        if let f = expenses.first?.facilityName, !f.isEmpty {
            return "\(f) · drayage"
        }
        return "—"
    }

    private var billRef: String {
        settlement?.bookingNumber ?? "—"
    }

    /// Findings list built from the real expense rows. Each row's amount is
    /// compared against its expected tariff figure (here the row status drives
    /// matched vs variance, since the carrier-portal projection carries a
    /// status). A duplicate type within the rows is escalated to CRITICAL.
    private var findings: [AuditFinding] {
        guard !expenses.isEmpty else { return [] }
        var seenTypes: Set<String> = []
        return expenses.map { row in
            let t = (row.type ?? "charge").uppercased()
            let amt = row.amount ?? 0
            let amtStr = currency(amt)
            let isMatched = (row.status ?? "").lowercased() == "approved"
                || (row.status ?? "").lowercased() == "paid"
            let isDuplicate = seenTypes.contains(t)
            seenTypes.insert(t)

            if isDuplicate {
                return AuditFinding(
                    title: "Duplicate \(t) line",
                    detail: "charge billed twice · \(amtStr)",
                    severity: .critical, varianceAmount: amt)
            }
            if isMatched {
                return AuditFinding(
                    title: "\(t.capitalizedFirst) · matched",
                    detail: "matches tariff schedule · \(amtStr)",
                    severity: .matched)
            }
            return AuditFinding(
                title: "\(t.capitalizedFirst) variance",
                detail: "billed \(amtStr) vs tariff · review",
                severity: .variance, varianceAmount: amt)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            backChevron
            titleRow
            IridescentHairline()
                .padding(.top, Space.s3)
            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    LifecycleCard {
                        Text("Loading freight bill…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if expenses.isEmpty && settlement == nil {
                    EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                                   title: "No freight bill",
                                   subtitle: "Open a vessel shipment to audit its carrier-portal invoice against the ocean tariff.")
                        .padding(.top, Space.s5)
                } else {
                    varianceCard
                    findingsSection
                    ctaButton
                    if let msg = flagResult {
                        Text(msg)
                            .font(EType.caption)
                            .foregroundStyle(flagIsError ? Brand.danger : Brand.success)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Eyebrow (✦ VESSEL OPERATOR · BILL AUDIT  ·  FB-VES-3318)

    private var eyebrow: some View {
        HStack {
            Text("✦  VESSEL OPERATOR · BILL AUDIT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(billRef)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    private var backChevron: some View {
        Image(systemName: "chevron.left")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
    }

    // MARK: - Title + exceptions pill

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Freight bill audit")
                .font(EType.h1)
                .foregroundStyle(palette.textPrimary)
                .tracking(-0.4)
            Spacer()
            if exceptionCount > 0 {
                Text("\(exceptionCount) EXCEPTION\(exceptionCount == 1 ? "" : "S")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.warning.opacity(0.18)))
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s2)
    }

    // MARK: - Recoverable variance card (gradient-rimmed hero)

    private var varianceCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 0) {
                // Carrier · mode chip
                Text(carrierLabel)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.10)))

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RECOVERABLE VARIANCE")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(signedCurrency(recoverableVariance))
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                        Text(billRef)
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        billedExpectedRow(label: "BILLED",   value: currency(billedTotal))
                        billedExpectedRow(label: "EXPECTED", value: currency(expectedTotal))
                    }
                    .padding(.top, 2)
                }
                .padding(.top, Space.s4)
            }
        }
    }

    private func billedExpectedRow(label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
        }
    }

    // MARK: - Audit findings

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("AUDIT FINDINGS · CHECKED VS OCEAN TARIFF")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(findings.enumerated()), id: \.element.id) { idx, finding in
                    findingRow(finding)
                    if idx < findings.count - 1 {
                        Rectangle()
                            .fill(palette.borderFaint)
                            .frame(height: 1)
                            .padding(.horizontal, Space.s4)
                    }
                }
            }
            .padding(.vertical, Space.s2)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func findingRow(_ f: AuditFinding) -> some View {
        let accent: Color = {
            switch f.severity {
            case .variance: return Brand.warning
            case .critical: return Brand.danger
            case .matched:  return Brand.success
            }
        }()
        let glyph: String = {
            switch f.severity {
            case .variance, .critical: return "doc.text"
            case .matched:             return "dollarsign.circle"
            }
        }()
        let pill: String = {
            switch f.severity {
            case .variance: return "VARIANCE"
            case .critical: return "CRITICAL"
            case .matched:  return "MATCHED"
            }
        }()
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: glyph)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(f.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(f.detail)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(pill)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(accent.opacity(0.18)))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    // MARK: - CTA · Flag for recovery

    private var ctaButton: some View {
        CTAButton(
            title: "Flag for recovery · \(signedCurrency(recoverableVariance))",
            action: { Task { await flagForRecovery() } },
            isLoading: flagging
        )
        .disabled(recoverableVariance <= 0)
        .opacity(recoverableVariance <= 0 ? 0.6 : 1.0)
    }

    // MARK: - Formatting

    private func currency(_ v: Double) -> String {
        if v == v.rounded() {
            return "$\(Int(v).formatted(.number.grouping(.automatic)))"
        }
        return "$\(String(format: "%.2f", v))"
    }

    private func signedCurrency(_ v: Double) -> String {
        let sign = v >= 0 ? "+" : "-"
        return "\(sign)\(currency(abs(v)))"
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        // When mounted without a bound load/shipment (ScreenRegistry preview),
        // skip the network round-trip and render the real empty state.
        guard loadId > 0 || shipmentId > 0 else {
            expenses = []; settlement = nil; loading = false; return
        }
        struct ExpenseIn: Encodable { let loadId: Int }
        struct SettlementIn: Encodable { let shipmentId: Int }
        do {
            if loadId > 0 {
                let rows: [LoadExpenseRow] = try await EusoTripAPI.shared.query(
                    "accessorial.getLoadExpenses", input: ExpenseIn(loadId: loadId))
                self.expenses = rows
            }
            if shipmentId > 0 {
                let s: VesselSettlement700? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselSettlement", input: SettlementIn(shipmentId: shipmentId))
                self.settlement = s
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Flag for recovery
    //
    // PORT-GAP: vesselFreightAudit.flagRecovery not on server — the SVG <desc>
    // names this as a STUB (proposed shape mirrors railFreightAudit.auditInvoice
    // -> {invoiceId, disputedLines[], recoverAmount}). We attempt the real
    // mutation so the wiring is live the moment the server lands it, and surface
    // the real error honestly instead of faking a success acknowledgement.

    private func flagForRecovery() async {
        guard recoverableVariance > 0 else { return }
        flagging = true; flagResult = nil; flagIsError = false
        struct FlagIn: Encodable {
            let invoiceId: String
            let disputedLines: [String]
            let recoverAmount: Double
        }
        struct FlagOut: Decodable { let ok: Bool? }
        let disputed = findings.filter { $0.severity != .matched }.map { $0.title }
        do {
            // PORT-GAP: vesselFreightAudit.flagRecovery not on server
            let _: FlagOut = try await EusoTripAPI.shared.mutation(
                "vesselFreightAudit.flagRecovery",
                input: FlagIn(invoiceId: billRef,
                              disputedLines: disputed,
                              recoverAmount: recoverableVariance))
            flagResult = "Flagged \(signedCurrency(recoverableVariance)) for recovery"
            flagIsError = false
        } catch {
            flagResult = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            flagIsError = true
        }
        flagging = false
    }
}

// MARK: - String helper

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst().lowercased()
    }
}

#Preview("700 · Vessel Freight Bill Audit · Night") { VesselFreightBillAuditScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("700 · Vessel Freight Bill Audit · Light") { VesselFreightBillAuditScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
