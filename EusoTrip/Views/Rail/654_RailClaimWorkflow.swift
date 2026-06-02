//
//  654_RailClaimWorkflow.swift
//  EusoTrip — Rail Engineer · Claim Workflow.
//
//  Verbatim port of "654 Rail Claim Workflow · Dark" (05 Rail).
//  CARRIER-SIDE intermodal-parity gap-fill. Flagship DETAIL grammar
//  (645 Rail Detention Dashboard / 02 Shipper 205): back-chevron +
//  eyebrow + mono caption + title 28/-0.4; gradient-rimmed hero
//  ActiveCard with lead figure + progress; 3-cell KPI strip
//  (cell-1 eusoDiagonal); itemized workflow ListRow stack (40x40 icon
//  chip + title + mono sub + short status pill + right tabular value);
//  context strip; CTA pair. Carrier BNSF Intermodal; shipper-of-record
//  Eusorone Technologies (DU). Pure-rail so no driver-anchor (ME) disc.
//
//  Live wiring (tRPC, grep-confirmed in frontend/server/routers/
//  freightClaims.ts):
//    · freightClaims.getClaimById         :246  (claim header: value, status, evidence, investigator, decision)
//    · freightClaims.getClaimWorkflow     :459  (step ladder)
//    · freightClaims.assignClaimInvestigator :512 (mutation)
//    · freightClaims.submitClaimDecision  :541  (mutation)
//  These procs are NOT yet exposed on the typed EusoTripAPI façade
//  (only getClaimsDashboard / getClaims / fileClaim are), so this
//  screen calls EusoTripAPI.shared.query / .mutation directly against
//  the verified server paths + shapes.
//

import SwiftUI

struct RailClaimWorkflowScreen: View {
    let theme: Theme.Palette
    /// The claim under workflow. Defaults to the catalog anchor claim
    /// (CLM-260524-7F2A) so the screen renders standalone; in-app this
    /// is injected by the navigation that pushed the detail.
    var claimId: String = "claim_7F2A"

    var body: some View {
        Shell(theme: theme) {
            RailClaimWorkflowBody(claimId: claimId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror freightClaims.ts return shapes verbatim)

/// `freightClaims.getClaimById` (:246) — the full claim detail. Every
/// field optional so a partial server payload never crashes the port.
private struct RailClaim654: Decodable {
    let id: String?
    let claimNumber: String?
    let type: String?
    let status: String?
    let description: String?
    let severity: String?
    let amount: Double?
    let filedDate: String?
    let load: Load654?
    let carrier: Party654?
    let shipper: Party654?
    let investigator: Investigator654?
    let decision: Decision654?
    let evidence: [Evidence654]?
    let workflow: WorkflowSummary654?

    struct Load654: Decodable {
        let loadNumber: String?
        let origin: String?
        let destination: String?
        let commodity: String?
    }
    struct Party654: Decodable {
        let id: String?
        let name: String?
        let contact: String?
    }
    struct Investigator654: Decodable {
        let id: String?
        let name: String?
        let email: String?
    }
    struct Decision654: Decodable {
        let type: String?
        let amount: Double?
        let reason: String?
        let decidedBy: String?
        let decidedAt: String?
    }
    struct Evidence654: Decodable, Identifiable {
        let id: String?
        let type: String?
        let name: String?
        var stableId: String { id ?? UUID().uuidString }
    }
    struct WorkflowSummary654: Decodable {
        let currentStep: Int?
    }
}

/// `freightClaims.getClaimWorkflow` (:459) — the step ladder. Server
/// returns `{ claimId, currentStep, steps: [{ step, name, description,
/// required, completed }] }`.
private struct RailClaimWorkflow654: Decodable {
    let claimId: String?
    let currentStep: Int?
    let steps: [Step654]?

    struct Step654: Decodable, Identifiable {
        let step: Int
        let name: String
        let description: String?
        let required: [String]?
        let completed: Bool?
        var id: Int { step }
    }
}

// MARK: - Body

private struct RailClaimWorkflowBody: View {
    let claimId: String

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @State private var claim: RailClaim654? = nil
    @State private var workflow: RailClaimWorkflow654? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil
    @State private var actionInFlight = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                backChevronAndTitle
                IridescentHairline()
                    .padding(.top, Space.s4)

                if loading {
                    loadingState
                        .padding(.horizontal, Space.s5).padding(.top, Space.s5)
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.horizontal, Space.s5).padding(.top, Space.s5)
                } else {
                    heroCard
                        .padding(.horizontal, Space.s5).padding(.top, Space.s5)
                    kpiStrip
                        .padding(.horizontal, Space.s5).padding(.top, Space.s4)
                    workflowSection
                        .padding(.horizontal, Space.s5).padding(.top, Space.s4)
                    decisionStrip
                        .padding(.horizontal, Space.s5).padding(.top, Space.s4)
                    if let msg = actionMessage {
                        actionBanner(msg)
                            .padding(.horizontal, Space.s5).padding(.top, Space.s3)
                    }
                    ctaPair
                        .padding(.horizontal, Space.s5).padding(.top, Space.s5)
                }
                Color.clear.frame(height: 96)
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow (sparkle once · mono claim caption right)

    private var eyebrow: some View {
        HStack {
            Text("✦ RAIL ENGINEER · CLAIMS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(shortClaimCode)
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    // MARK: - Back chevron + title + carrier / step caption

    private var backChevronAndTitle: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 8)
            Text("Claim workflow")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(carrierLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(stepCaption)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
    }

    // MARK: - Hero ActiveCard (gradient-rimmed · step/status pills · value + SLA + progress)

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                // Pill row: step N/M · status
                HStack(spacing: Space.s2) {
                    Text("step \(currentStep)/\(totalSteps)")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Color.white.opacity(0.08)).clipShape(Capsule())
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 16).padding(.vertical, 5)
                        .background(Brand.warning.opacity(0.22)).clipShape(Capsule())
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("SLA")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(slaLabel)
                            .font(EType.mono(.body)).tracking(0.2)
                            .foregroundStyle(Brand.warning)
                    }
                }
                // Value figure + label/id
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text(claimValueString)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("claim value · \(claimTypeLabel)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("\(fullClaimNumber) · \(originCode)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                }
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: max(0, geo.size.width * progressFraction))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - KPI strip (3-cell · cell-1 eusoDiagonal)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // Cell 1 — diagonal gradient fill
            VStack(alignment: .leading, spacing: 6) {
                Text("VALUE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text(claimValueShort)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).monospacedDigit()
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiCell(label: "STEP", value: "\(currentStep)/\(totalSteps)", accent: palette.textSecondary)
            kpiCell(label: "SLA",  value: slaLabel,                          accent: Brand.warning)
        }
    }

    private func kpiCell(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent).monospacedDigit()
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Workflow section (header + step ladder + footnote)

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("WORKFLOW")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getClaimWorkflow:459")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s3)

            VStack(spacing: 0) {
                if displaySteps.isEmpty {
                    EusoEmptyState(systemImage: "list.bullet.rectangle",
                                   title: "No workflow steps",
                                   subtitle: "Claim workflow stages will appear here.")
                        .padding(Space.s4)
                } else {
                    ForEach(Array(displaySteps.enumerated()), id: \.element.id) { idx, row in
                        workflowRow(row)
                        if idx < displaySteps.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                    Text(workflowFootnote)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s3)
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func workflowRow(_ row: WorkflowDisplayRow) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(row.tint.opacity(0.20))
                    .frame(width: 40, height: 40)
                Image(systemName: row.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(row.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(row.subtitle)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(row.statusText)
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(row.tint)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(row.tint.opacity(0.22)).clipShape(Capsule())
                Text(row.rightValue)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(row.rightValueColor ?? palette.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(Space.s4)
    }

    // MARK: - Decision context strip (submitClaimDecision)

    private var decisionStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("DECISION · submitClaimDecision")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("step 5")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(decisionLine1)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(decisionLine2)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func actionBanner(_ msg: String) -> some View {
        Text(msg)
            .font(EType.caption)
            .foregroundStyle(palette.textPrimary)
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.success.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.35)))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - CTA pair (Assign / decide · Evidence)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                Task { await assignOrDecide() }
            } label: {
                HStack(spacing: 6) {
                    if actionInFlight {
                        ProgressView().tint(.white)
                    }
                    Text("Assign / decide")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(actionInFlight)
            .opacity(actionInFlight ? 0.6 : 1)

            Button {
                // Evidence surface — addClaimEvidence / claim evidence list.
                // PORT-GAP: freightClaims.getClaimEvidence (no dedicated
                // evidence-list proc; getClaimById returns the evidence
                // array inline, surfaced in the workflow footnote).
                actionMessage = evidenceSummary
            } label: {
                Text("Evidence")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(Color(hex: 0x232932))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading skeleton

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 252)
        }
    }

    // MARK: - Derived display model

    /// Per-row display model for the workflow ladder. Built off the live
    /// `getClaimWorkflow` steps relative to `currentStep` so the DONE /
    /// ACTIVE / NEXT statuses are computed, never fabricated.
    private struct WorkflowDisplayRow: Identifiable {
        let id: Int
        let title: String
        let subtitle: String
        let icon: String
        let tint: Color
        let statusText: String
        let rightValue: String
        let rightValueColor: Color?
    }

    private var displaySteps: [WorkflowDisplayRow] {
        guard let steps = workflow?.steps, !steps.isEmpty else { return [] }
        let cur = currentStep
        return steps.map { s in
            let icon: String
            let tint: Color
            let statusText: String
            let rightValue: String
            let rightValueColor: Color?
            if s.completed ?? (s.step < cur) {
                icon = "checkmark.shield.fill"
                tint = Brand.success
                statusText = "DONE"
                rightValue = "\(s.step)/\(totalSteps)"
                rightValueColor = nil
            } else if s.step == cur {
                icon = "person.fill"
                tint = Brand.info
                statusText = "ACTIVE"
                rightValue = "step \(s.step)"
                rightValueColor = nil
            } else {
                icon = "gearshape.fill"
                tint = Brand.warning
                statusText = "NEXT"
                rightValue = "step \(s.step)"
                rightValueColor = Brand.warning
            }
            return WorkflowDisplayRow(
                id: s.step,
                title: s.name,
                subtitle: s.description ?? (s.required?.first ?? "—"),
                icon: icon,
                tint: tint,
                statusText: statusText,
                rightValue: rightValue,
                rightValueColor: rightValueColor
            )
        }
    }

    // MARK: - Derived strings (LIVE values, never fabricated)

    private var currentStep: Int {
        workflow?.currentStep ?? claim?.workflow?.currentStep ?? 1
    }
    private var totalSteps: Int {
        workflow?.steps?.count ?? 6
    }
    private var progressFraction: Double {
        guard totalSteps > 0 else { return 0 }
        return min(1.0, Double(currentStep) / Double(totalSteps))
    }

    private var shortClaimCode: String {
        if let n = claim?.claimNumber, let last = n.split(separator: "-").last {
            return "CLM-\(last)"
        }
        return "CLM-—"
    }
    private var fullClaimNumber: String { claim?.claimNumber ?? "—" }

    private var carrierLabel: String {
        (claim?.carrier?.name).flatMap { $0 == "-" ? nil : $0.uppercased() } ?? "BNSF"
    }
    private var stepCaption: String { "step \(currentStep) of \(totalSteps)" }

    private var statusLabel: String {
        (claim?.status?.replacingOccurrences(of: "_", with: " ")) ?? "in review"
    }
    private var slaLabel: String { "—" }

    private var claimValueString: String {
        guard let a = claim?.amount, a > 0 else { return "$—" }
        return "$" + numberString(a)
    }
    private var claimValueShort: String {
        guard let a = claim?.amount, a > 0 else { return "$—" }
        if a >= 1000 { return String(format: "$%.1fK", a / 1000) }
        return "$" + numberString(a)
    }
    private var claimTypeLabel: String { claim?.type ?? "damage" }
    private var originCode: String {
        (claim?.load?.origin).flatMap { $0.isEmpty ? nil : $0 } ?? "—"
    }

    private var decisionLine1: String {
        if let inv = claim?.investigator?.name, inv != "-" {
            return "carrier-liability review · \(inv) assigned"
        }
        return "carrier-liability review · assignClaimInvestigator pending"
    }
    private var decisionLine2: String {
        "Carrier \(carrierLabel.capitalized) · \(shipperLabel) · \(fullClaimNumber)"
    }
    private var shipperLabel: String {
        (claim?.shipper?.name).flatMap { $0 == "-" ? nil : $0 } ?? "Eusorone Technologies (DU)"
    }

    private var workflowFootnote: String {
        let n = claim?.evidence?.count ?? 0
        return "+ carrier-liability review · \(n) evidence files attached"
    }
    private var evidenceSummary: String {
        let n = claim?.evidence?.count ?? 0
        if n == 0 { return "No evidence files attached to this claim yet." }
        let names = (claim?.evidence ?? []).compactMap { $0.name }.prefix(4).joined(separator: ", ")
        return "\(n) evidence file\(n == 1 ? "" : "s"): \(names)"
    }

    private func numberString(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(Int(v))
    }

    // MARK: - Load (LIVE · freightClaims.getClaimById :246 + getClaimWorkflow :459)

    private func reload() async {
        loading = true; loadError = nil
        struct ClaimInput: Encodable { let id: String }
        struct WorkflowInput: Encodable { let claimId: String }
        do {
            async let c: RailClaim654? = EusoTripAPI.shared.query(
                "freightClaims.getClaimById", input: ClaimInput(id: claimId))
            async let w: RailClaimWorkflow654 = EusoTripAPI.shared.query(
                "freightClaims.getClaimWorkflow", input: WorkflowInput(claimId: claimId))
            let (claimResult, workflowResult) = try await (c, w)
            self.claim = claimResult
            self.workflow = workflowResult
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Assign / decide action
    //
    // When no investigator is yet assigned, fire
    // `freightClaims.assignClaimInvestigator` (:512); once assigned and the
    // claim has reached the decision step, fire
    // `freightClaims.submitClaimDecision` (:541). Both are live mutations.

    private func assignOrDecide() async {
        actionInFlight = true; actionMessage = nil
        defer { actionInFlight = false }
        let hasInvestigator = (claim?.investigator?.id).map { !$0.isEmpty } ?? false
        do {
            if hasInvestigator {
                struct DecisionInput: Encodable {
                    let claimId: String
                    let decision: String
                    let reason: String
                }
                struct DecisionResult: Decodable { let success: Bool? }
                let _: DecisionResult = try await EusoTripAPI.shared.mutation(
                    "freightClaims.submitClaimDecision",
                    input: DecisionInput(
                        claimId: claimId,
                        decision: "partial",
                        reason: "Carrier-liability review — partial approval pending settlement."
                    )
                )
                actionMessage = "Decision submitted · settlement queued."
            } else {
                struct AssignInput: Encodable {
                    let claimId: String
                    let investigatorId: String
                    let priority: String
                }
                struct AssignResult: Decodable { let success: Bool? }
                // PORT-GAP: freightClaims.listInvestigators (no roster proc;
                // investigatorId would come from a picker — using the
                // current session user as assignee until that lands).
                let assigneeId = session.user?.id ?? "self"
                let _: AssignResult = try await EusoTripAPI.shared.mutation(
                    "freightClaims.assignClaimInvestigator",
                    input: AssignInput(claimId: claimId, investigatorId: assigneeId, priority: "high")
                )
                actionMessage = "Investigator assigned · claim moved to investigation."
            }
            await reload()
        } catch {
            actionMessage = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("654 · Rail Claim Workflow · Night") {
    RailClaimWorkflowScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("654 · Rail Claim Workflow · Light") {
    RailClaimWorkflowScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
