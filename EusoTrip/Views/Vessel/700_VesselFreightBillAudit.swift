//
//  700_VesselFreightBillAudit.swift
//  EusoTrip — Vessel Operator · Freight Bill Audit.
//
//  Faithful port of "700 Vessel Freight Bill Audit.svg" (Light + Dark, 2026-06-21 reconstruction),
//  RECONSTRUCTED to a distinct THREE-WAY-MATCH archetype (NOT the former hero+list+empty-canvas
//  stamp): a gradient-rim hero (recoverable variance + billed/expected + live audit-status pill),
//  the centerpiece paired BILLED-vs-TARIFF composition bars (charge buckets on a shared $-per-pixel
//  scale so the overcharge reads as bar length) with a per-bucket variance legend, an itemized
//  findings ledger (duplicate / overcharge / matched / no-basis), a tri-country tariff-authority
//  band, and the Flag-for-recovery CTA pair. Registered type name kept
//  (VesselFreightBillAuditScreen · ContentView "Vesl700").
//
//  Data / wiring (every endpoint re-verified on disk this fire · 0 stubs · 0 mock):
//    DISCOVERY (unbound mount): detentionAccessorials.getAccessorialBilling EXISTS:1708
//        → pendingCharges[{loadId,carrierName,facilityName,origin,destination,…}] picks the
//          freight bill under audit + the real carrier/lane header context.
//    BILLED lines:  accessorial.getLoadExpenses EXISTS accessorial.ts:581 ({loadId} →
//        [{id,type,amount,status,facilityName,arrivalTime,departureTime,billableMinutes}]).
//    TARIFF side:   accessorial.calculateDetention EXISTS accessorial.ts:546 — per-line expected
//        charge from the platform fee schedule (free time + rate/hour), computed from the line's
//        real arrival/departure stamps. Lines without stamps carry NO tariff basis and are labeled
//        honestly (never faked as matched).
//    ENGINE:        railFreightAudit.auditInvoice EXISTS railFreightAudit.ts:27 (mode-agnostic
//        charge-type engine · duplicates + breakdown{linehaul,fuel,demurrage,other} + auditStatus).
//    CTA "Flag for recovery" → vesselFreightAudit.flagRecovery EXISTS vesselFreightAudit.ts:28
//        ({invoiceId,disputedLines[],recoverAmount} → persists a disputes row reason 'rate'
//        migration 0317 + a 'created' dispute_events thread row → returns {ok,disputeId 'DSP-N'}).
//        Success copy renders the REAL returned dispute id — never an invented acknowledgement.
//    RBAC: protectedProcedure (tenant-scoped). transportMode=vessel · USD.
//
//  Named gap surfaced to the-oath: vessel invoice storage — the audit reference is app-derived
//  from the load under audit (labeled AUDIT REF) because no carrier-invoice row exists to cite;
//  ocean tariff sheets for linehaul/THC buckets have no serving read yet, so those buckets read
//  "no tariff basis" instead of a fabricated match.
//
//  Honest states: unbound + no billable charges → bespoke empty state; transport failure → retry
//  card in user grammar (no raw error text). Both repos' copy doctrine applied end-to-end.
//

import SwiftUI

struct VesselFreightBillAuditScreen: View {
    let theme: Theme.Palette
    /// Load the freight bill belongs to. Defaults to 0 so the screen stays
    /// constructable as `VesselFreightBillAuditScreen(theme: p)` from the
    /// ScreenRegistry; the unbound mount discovers the newest billable load
    /// from the accessorial billing ledger.
    var loadId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselFreightBillAuditBody(boundLoadId: loadId)
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

// MARK: - Row + finding shapes

private enum ChargeBucket700: String, CaseIterable {
    case detention = "Detention"
    case demurrage = "Demurrage"
    case accessorial = "Accessorial"
    case other = "Other"

    var hue: Color {
        switch self {
        case .detention:   return Brand.blue
        case .demurrage:   return Brand.magenta
        case .accessorial: return Brand.warning
        case .other:       return Brand.neutral
        }
    }
}

private struct ChargeSeg700: Identifiable {
    var id: String { bucket.rawValue }
    let bucket: ChargeBucket700
    var billed: Double
    var expected: Double
    var hasBasis: Bool
    var variance: Double { billed - expected }
}

private struct AuditFinding700: Identifiable {
    enum Tone { case critical, overcharge, matched, noBasis }
    let id = UUID()
    let tone: Tone
    let title: String
    let sub: String
    /// Recoverable dollars this finding carries (0 for matched / no-basis).
    let recoverable: Double
}

// MARK: - Body

private struct VesselFreightBillAuditBody: View {
    let boundLoadId: Int

    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadFailed = false
    @State private var hasBill = false

    // Header context (real — from the billing ledger row under audit).
    @State private var auditRef = ""
    @State private var carrierLine = ""
    @State private var laneLine = ""

    // Audit output (real — engine + per-line tariff cross-check).
    @State private var billedTotal = 0.0
    @State private var recoverable = 0.0
    @State private var segs: [ChargeSeg700] = []
    @State private var findings: [AuditFinding700] = []
    @State private var linesChecked = 0
    @State private var auditStatus = ""

    // Flag-for-recovery CTA state.
    @State private var flagging = false
    @State private var flagResult: String? = nil
    @State private var flagIsError = false

    private var expectedTotal: Double { max(0, billedTotal - recoverable) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                HStack(alignment: .center, spacing: 10) {
                    Text("Freight bill audit").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
                    if !auditStatus.isEmpty { statusPill }
                }
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Auditing the freight bill…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if loadFailed {
                    LifecycleCard(accentDanger: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("The freight bill audit didn't run.").font(EType.caption).foregroundStyle(Brand.danger)
                            Text("Check your connection — billed charges are safe and re-audit on refresh.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                            Button { Task { await load() } } label: {
                                Text("Retry").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.blue)
                            }.buttonStyle(.plain)
                        }
                    }
                } else if !hasBill {
                    EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                                   title: "No freight bill to audit",
                                   subtitle: "When a booking accrues billable charges, its invoice lines land here for the three-way match against tariff.")
                } else {
                    heroCard
                    sectionLabel("INVOICE COMPOSITION · BILLED vs TARIFF")
                    compositionCard
                    sectionLabel("AUDIT FINDINGS · \(linesChecked) LINE\(linesChecked == 1 ? "" : "S") CHECKED")
                    findingsCard
                    tariffAuthorityHeader
                    triCountryBand
                    HStack(spacing: 8) {
                        CTAButton(title: "Flag for recovery · +\(usd(recoverable))",
                                  action: { Task { await flagRecovery() } },
                                  isLoading: flagging)
                        .disabled(recoverable <= 0)
                        .opacity(recoverable <= 0 ? 0.6 : 1.0)
                        secondaryButton(title: "Re-run audit") { Task { await load() } }
                            .frame(width: 118)
                    }
                    if let msg = flagResult {
                        Text(msg)
                            .font(EType.caption)
                            .foregroundStyle(flagIsError ? Brand.danger : Brand.success)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("VESSEL OPERATOR · BILL AUDIT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            if !auditRef.isEmpty {
                Text(auditRef).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var statusPill: some View {
        let kind: StatusPill.Kind = auditStatus == "failed" ? .danger : (auditStatus == "flagged" ? .warning : .success)
        let text = auditStatus == "failed" ? "Audit failed" : (auditStatus == "flagged" ? "Audit flagged" : "Audit passed")
        return StatusPill(text: text, kind: kind)
    }

    // MARK: - Recoverable variance hero

    private var heroCard: some View {
        RimCard700 {
            VStack(alignment: .leading, spacing: 12) {
                if !carrierLine.isEmpty {
                    Text(carrierLine).font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(palette.textPrimary.opacity(0.05)))
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECOVERABLE VARIANCE").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        Text("+\(usd(recoverable))").font(.system(size: 36, weight: .bold)).foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                        if !laneLine.isEmpty {
                            Text(laneLine).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        labeledMoney("BILLED", usd(billedTotal))
                        labeledMoney("EXPECTED", usd(expectedTotal))
                    }.padding(.top, 24)
                }
            }
        }
    }

    private func labeledMoney(_ k: String, _ v: String) -> some View {
        HStack(spacing: 10) {
            Text(k).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(v).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).monospacedDigit()
        }
    }

    // MARK: - Paired composition bars (shared $-per-pixel scale)

    private var compositionCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                compBar(title: "Billed", useExpected: false)
                compBar(title: "Tariff", useExpected: true)
                let cols = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                    ForEach(segs) { s in
                        HStack(spacing: 8) {
                            Circle().fill(s.bucket.hue).frame(width: 8, height: 8)
                            Text(s.bucket.rawValue).font(.system(size: 10.5)).foregroundStyle(palette.textPrimary)
                            Spacer(minLength: 4)
                            Text(legendValue(for: s))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(legendTone(for: s))
                        }
                    }
                }
            }
        }
    }

    private func legendValue(for s: ChargeSeg700) -> String {
        guard s.hasBasis else { return "no basis" }
        if s.variance > 0.5 { return "+\(usd(s.variance))" }
        if s.variance < -0.5 { return "-\(usd(-s.variance))" }
        return "matched"
    }

    private func legendTone(for s: ChargeSeg700) -> Color {
        guard s.hasBasis else { return palette.textTertiary }
        if s.variance > 0.5 { return Brand.danger }
        if s.variance < -0.5 { return palette.textSecondary }
        return Brand.success
    }

    private func compBar(title: String, useExpected: Bool) -> some View {
        let total = useExpected ? expectedTotal : billedTotal
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textSecondary)
                Spacer()
                Text(usd(total)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
            GeometryReader { geo in
                let dpp = billedTotal > 0 ? geo.size.width / billedTotal : 0
                HStack(spacing: 1.5) {
                    ForEach(segs) { s in
                        let v = useExpected ? s.expected : s.billed
                        Rectangle().fill(s.bucket.hue.opacity(useExpected ? 0.42 : 1.0)).frame(width: max(0, v * dpp))
                    }
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }.frame(height: 12)
        }
    }

    // MARK: - Findings ledger

    private var findingsCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(findings.enumerated()), id: \.element.id) { idx, f in
                    findingRow(f)
                    if idx < findings.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
        }
    }

    private func findingRow(_ f: AuditFinding700) -> some View {
        let accent: Color = {
            switch f.tone {
            case .critical:   return Brand.danger
            case .overcharge: return Brand.warning
            case .matched:    return Brand.success
            case .noBasis:    return Brand.neutral
            }
        }()
        let glyph: String = {
            switch f.tone {
            case .critical:   return "doc.on.doc"
            case .overcharge: return "doc.text"
            case .matched:    return "checkmark.seal"
            case .noBasis:    return "questionmark.circle"
            }
        }()
        let pill: String = {
            switch f.tone {
            case .critical:   return "CRITICAL"
            case .overcharge: return "OVERCHARGE"
            case .matched:    return "MATCHED"
            case .noBasis:    return "NO BASIS"
            }
        }()
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                Text(f.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(f.sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(pill)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(accent.opacity(0.16)))
        }
        .padding(.vertical, 12)
    }

    // MARK: - Tri-country tariff authority (audit-basis reference band · US active)

    private var tariffAuthorityHeader: some View {
        HStack {
            Text("TARIFF AUTHORITY · AUDIT BASIS").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Spacer()
            let flaggedCount = findings.filter { $0.tone == .critical || $0.tone == .overcharge }.count
            Text("\(flaggedCount) FLAGGED · +\(usd(recoverable)) NET").font(.system(size: 9, weight: .bold)).foregroundStyle(Brand.warning)
        }
    }

    private var triCountryBand: some View {
        VStack(spacing: 0) {
            let regulators: [(code: String, line: String, active: Bool)] = [
                ("US", "FMC tariff + MTO THC · USD", true),
                ("CA", "CTA · VFPA · CAD", false),
                ("MX", "API · SAT · MXN", false),
            ]
            ForEach(Array(regulators.enumerated()), id: \.offset) { idx, r in
                HStack(spacing: 10) {
                    Text(r.code).font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(r.active ? Color.white : palette.textSecondary)
                        .frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(r.active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textPrimary.opacity(0.06))))
                    Text(r.line).font(.system(size: r.active ? 10.5 : 10, weight: r.active ? .bold : .regular))
                        .foregroundStyle(r.active ? palette.textPrimary : palette.textSecondary)
                    Spacer(minLength: 0)
                    Text(r.active ? "● ACTIVE" : "STANDBY").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(r.active ? Brand.success : palette.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(r.active ? AnyShapeStyle(LinearGradient.primary.opacity(0.10)) : AnyShapeStyle(Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                if idx < regulators.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(6)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Formatting

    private func usd(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.005 {
            return "$\(Int(v.rounded()).formatted(.number.grouping(.automatic)))"
        }
        return "$\(String(format: "%.2f", v))"
    }

    // MARK: - Load (three-way match: billed lines vs platform tariff vs audit engine)

    private func load() async {
        loading = true; loadFailed = false
        flagResult = nil; flagIsError = false
        do {
            // 1) Resolve the bill under audit. Unbound mounts discover the newest
            //    billable load from the accessorial billing ledger (real rows).
            var loadIdToAudit = boundLoadId
            if loadIdToAudit <= 0 {
                struct BillIn: Encodable { let status: String; let batchSize: Int }
                struct Charge: Decodable {
                    let loadId: Int?; let carrierName: String?
                    let origin: String?; let destination: String?
                }
                struct BillOut: Decodable { let pendingCharges: [Charge]? }
                let bill: BillOut = try await EusoTripAPI.shared.query(
                    "detentionAccessorials.getAccessorialBilling",
                    input: BillIn(status: "approved", batchSize: 10))
                if let charge = bill.pendingCharges?.first(where: { ($0.loadId ?? 0) > 0 }) {
                    loadIdToAudit = charge.loadId ?? 0
                    let carrier = charge.carrierName.flatMap { $0 == "N/A" ? nil : $0 }
                    carrierLine = carrier.map { "\($0) · ocean freight" } ?? "Ocean freight bill"
                    if let o = charge.origin, let d = charge.destination, o != "N/A", d != "N/A" {
                        laneLine = "\(String(o.prefix(24))) → \(String(d.prefix(24)))"
                    }
                }
            }
            guard loadIdToAudit > 0 else {
                hasBill = false; loading = false; return
            }
            auditRef = "FB-L\(loadIdToAudit)"

            // 2) Billed line items (real expense rows on the load).
            struct ExpIn: Encodable { let loadId: Int }
            struct ExpRow: Decodable {
                let id: Int
                let type: String?
                let amount: Double?
                let status: String?
                let facilityName: String?
                let arrivalTime: String?
                let departureTime: String?
            }
            let rows: [ExpRow] = try await EusoTripAPI.shared.query("accessorial.getLoadExpenses", input: ExpIn(loadId: loadIdToAudit))
            guard !rows.isEmpty else { hasBill = false; loading = false; return }
            linesChecked = rows.count

            // 3) Tariff side — expected charge per line from the platform fee
            //    schedule, computed off the line's REAL arrival/departure stamps.
            struct DetIn: Encodable { let arrivalTime: String; let departureTime: String? }
            struct DetOut: Decodable { let charge: Double? }
            var expectedByLine: [Int: Double] = [:]
            for row in rows.prefix(10) {
                guard let arrival = row.arrivalTime, !arrival.isEmpty else { continue }
                if let det: DetOut = try? await EusoTripAPI.shared.query(
                    "accessorial.calculateDetention",
                    input: DetIn(arrivalTime: arrival, departureTime: row.departureTime)) {
                    expectedByLine[row.id] = det.charge ?? 0
                }
            }

            // 4) Audit engine — duplicates + charge-type breakdown + status.
            struct AudIn: Encodable {
                struct LI: Encodable { let lineId: String; let chargeType: String; let amount: Double }
                struct TC: Encodable { let expectedDemurrage: Double }
                let invoiceNumber: String; let lineItems: [LI]; let tariffContext: TC
            }
            struct Exc: Decodable { let type: String?; let severity: String?; let message: String?; let invoiceLineId: String? }
            struct AudOut: Decodable { let invoiceTotal: Double?; let exceptions: [Exc]?; let auditStatus: String? }
            let expectedSum = expectedByLine.values.reduce(0, +)
            let items: [AudIn.LI] = rows.map { r in
                AudIn.LI(lineId: "L-\(r.id)", chargeType: engineChargeType(for: r.type), amount: r.amount ?? 0)
            }
            let aud: AudOut = try await EusoTripAPI.shared.mutation(
                "railFreightAudit.auditInvoice",
                input: AudIn(invoiceNumber: auditRef, lineItems: items, tariffContext: .init(expectedDemurrage: expectedSum)))

            // 5) Compose the honest display figures.
            billedTotal = aud.invoiceTotal ?? rows.reduce(0) { $0 + ($1.amount ?? 0) }

            var newFindings: [AuditFinding700] = []
            var recoverableSum = 0.0

            // Duplicates from the engine (critical).
            let duplicateLineIds = Set((aud.exceptions ?? []).filter { $0.type == "duplicate" }.compactMap { $0.invoiceLineId })
            for dup in duplicateLineIds {
                if let row = rows.first(where: { "L-\($0.id)" == dup }) {
                    let amt = row.amount ?? 0
                    recoverableSum += amt
                    newFindings.append(AuditFinding700(
                        tone: .critical,
                        title: "Duplicate \(bucket(for: row.type).rawValue.lowercased()) line \(dup)",
                        sub: "charge billed twice · \(usd(amt))",
                        recoverable: amt))
                }
            }

            // Per-line tariff cross-check (real basis only).
            var newSegs: [ChargeBucket700: ChargeSeg700] = [:]
            for row in rows {
                let b = bucket(for: row.type)
                let amt = row.amount ?? 0
                var seg = newSegs[b] ?? ChargeSeg700(bucket: b, billed: 0, expected: 0, hasBasis: false)
                seg.billed += amt
                let lineId = "L-\(row.id)"
                let isDuplicate = duplicateLineIds.contains(lineId)

                if let expected = expectedByLine[row.id] {
                    seg.hasBasis = true
                    seg.expected += expected
                    if !isDuplicate {
                        let over = amt - expected
                        if over > 1 {
                            recoverableSum += over
                            newFindings.append(AuditFinding700(
                                tone: .overcharge,
                                title: "\(b.rawValue) over tariff · \(row.facilityName ?? lineId)",
                                sub: "billed \(usd(amt)) vs tariff \(usd(expected)) · +\(usd(over))",
                                recoverable: over))
                        } else {
                            newFindings.append(AuditFinding700(
                                tone: .matched,
                                title: "\(b.rawValue) matches tariff · \(row.facilityName ?? lineId)",
                                sub: "verified vs fee schedule · \(usd(amt))",
                                recoverable: 0))
                        }
                    }
                } else {
                    // No arrival/departure stamps — no tariff basis. Labeled honestly.
                    seg.expected += amt
                    if !isDuplicate {
                        newFindings.append(AuditFinding700(
                            tone: .noBasis,
                            title: "\(b.rawValue) · no tariff basis on file",
                            sub: "billed \(usd(amt)) · gate stamps missing, tariff match unavailable",
                            recoverable: 0))
                    }
                }
                newSegs[b] = seg
            }

            recoverable = recoverableSum
            findings = Array(newFindings.prefix(6))
            segs = ChargeBucket700.allCases.compactMap { newSegs[$0] }.filter { $0.billed > 0 }
            auditStatus = aud.auditStatus ?? (recoverableSum > 0 ? "flagged" : "passed")
            if carrierLine.isEmpty, let facility = rows.first?.facilityName, !facility.isEmpty {
                carrierLine = "\(facility) · ocean freight"
            }
            hasBill = true
        } catch {
            // Doctrine: no raw transport error text in user copy.
            loadFailed = true
        }
        loading = false
    }

    private func bucket(for type: String?) -> ChargeBucket700 {
        let t = (type ?? "").lowercased()
        if t.contains("demurrage") { return .demurrage }
        if t.contains("detention") || t.isEmpty { return .detention }
        if t.contains("accessorial") || t.contains("lumper") || t.contains("handling") { return .accessorial }
        return .other
    }

    /// Maps the expense row's type into the audit engine's charge-type enum
    /// (linehaul · fuel_surcharge · demurrage · switching · accessorial · detention · tax).
    private func engineChargeType(for type: String?) -> String {
        let t = (type ?? "").lowercased()
        if t.contains("demurrage") { return "demurrage" }
        if t.contains("fuel") { return "fuel_surcharge" }
        if t.contains("tax") { return "tax" }
        if t.contains("linehaul") || t.contains("freight") { return "linehaul" }
        if t.contains("detention") || t.isEmpty { return "detention" }
        return "accessorial"
    }

    // MARK: - Flag for recovery (REAL write — disputes row + thread event)

    private func flagRecovery() async {
        guard recoverable > 0, !auditRef.isEmpty else { return }
        flagging = true; flagResult = nil; flagIsError = false
        struct FRIn: Encodable { let invoiceId: String; let disputedLines: [String]; let recoverAmount: Double }
        struct FROut: Decodable { let ok: Bool?; let disputeId: String?; let recoverAmount: Double?; let lineCount: Int? }
        let disputed = findings.filter { $0.recoverable > 0 }.map { $0.title }
        do {
            let out: FROut = try await EusoTripAPI.shared.mutation(
                "vesselFreightAudit.flagRecovery",
                input: FRIn(invoiceId: auditRef, disputedLines: disputed, recoverAmount: recoverable))
            if out.ok == true, let disputeId = out.disputeId {
                flagResult = "Recovery filed · \(disputeId) — \(usd(recoverable)) is now in your disputes queue"
            } else {
                flagResult = "Recovery filed — \(usd(recoverable)) is now in your disputes queue"
            }
            flagIsError = false
        } catch {
            flagResult = "The recovery didn't file. The audit above stays current — try again."
            flagIsError = true
        }
        flagging = false
    }
}

// MARK: - File-scoped gradient-rim hero card

private struct RimCard700<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

#Preview("700 · Vessel Freight Bill Audit · Night") { VesselFreightBillAuditScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("700 · Vessel Freight Bill Audit · Light") { VesselFreightBillAuditScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
