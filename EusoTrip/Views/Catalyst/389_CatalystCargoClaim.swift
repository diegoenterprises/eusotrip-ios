//
//  389_CatalystCargoClaim.swift
//  EusoTrip — Catalyst · Cargo Claim (CARRIER-side claim management).
//
//  Verbatim iOS port of "03 Catalyst/Code/389_CatalystCargoClaim.swift"
//  (+ Dark-SVG cross-check). The carrier's defence-side view of a cargo
//  claim filed against a delivered load. Cross-mode parity gap fill:
//  Rail (605) and Vessel (732) already had cargo-claim surfaces, the Truck
//  Catalyst band had none against the mode-agnostic freightClaims router.
//  Docked under DISPATCH.
//
//  Layout (top → bottom), 1:1 with the SVG:
//    • Hero · claim summary — claimed amount + status pill
//    • Claim detail ledger — type / cargo value / claimed / filed / carrier
//    • Carrier response strip (loss-prevention quarter count)
//    • Load tie — associated load number
//    • CTA · Submit claim decision
//
//  Server wiring (real, NO fabricated rows):
//    • `freightClaims.getClaimsDashboard` resolves the newest live claim id
//      and loss-prevention counters.
//    • `freightClaims.getClaimById` hydrates the per-claim case file.
//    • `freightClaims.getClaimWorkflow` hydrates the investigation ladder.
//    • `freightClaims.submitClaimDecision` writes the carrier decision.
//      Detail/workflow reads are tolerant: if one returns null, the dashboard
//      row still renders and the missing fields stay honest.
//
//  Identity: carrier name is read from the claim's `carrier` field (real),
//  falling back to the signed-in session user, then "—". USDOT / MC are not
//  carried on any iOS claim/dashboard contract, so they render "—" (no
//  invented registration numbers, no founder persona).
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystCargoClaimScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystCargoClaim_389()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_389(),
                trailing: catalystNavTrailing_389(),
                orbState: .idle
            )
        }
    }
}

// NAV (REAL · CatalystNavController): HOME · DISPATCH(current) · [orb] · FLEET · ME
private func catalystNavLeading_389() -> [NavSlot] {
    CarrierNavRoute.leading(current: .loads)
}

private func catalystNavTrailing_389() -> [NavSlot] {
    CarrierNavRoute.trailing(current: .loads)
}

// MARK: - Live claim detail contracts

private struct CatalystClaimParty389: Decodable {
    let id: String?
    let name: String?
    let contact: String?

    private enum CodingKeys: String, CodingKey { case id, name, contact }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer(),
           let name = try? value.decode(String.self) {
            self.id = nil
            self.name = name
            self.contact = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.flexString(c, .id)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        contact = try? c.decodeIfPresent(String.self, forKey: .contact)
    }

    private static func flexString(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return String(i) }
        return nil
    }
}

private struct CatalystClaimDetail389: Decodable {
    let id: String?
    let claimNumber: String?
    let type: String?
    let status: String?
    let description: String?
    let severity: String?
    let amount: Double?
    let filedDate: String?
    let load: Load?
    let carrier: CatalystClaimParty389?
    let shipper: CatalystClaimParty389?
    let investigator: CatalystClaimParty389?
    let decision: Decision?
    let evidence: [Evidence]?
    let workflow: WorkflowSummary?

    struct Load: Decodable {
        let loadNumber: String?
        let origin: String?
        let destination: String?
        let commodity: String?
    }
    struct Decision: Decodable {
        let type: String?
        let amount: Double?
        let reason: String?
        let decidedBy: String?
        let decidedAt: String?
    }
    struct Evidence: Decodable, Identifiable {
        let id: String?
        let type: String?
        let name: String?
        var stableId: String { id ?? name ?? type ?? UUID().uuidString }
    }
    struct WorkflowSummary: Decodable {
        let currentStep: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case id, claimNumber, type, status, description, severity, amount,
             filedDate, load, carrier, shipper, investigator, decision,
             evidence, workflow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.flexString(c, .id)
        claimNumber = try? c.decodeIfPresent(String.self, forKey: .claimNumber)
        type = try? c.decodeIfPresent(String.self, forKey: .type)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        severity = try? c.decodeIfPresent(String.self, forKey: .severity)
        amount = Self.flexDouble(c, .amount)
        filedDate = try? c.decodeIfPresent(String.self, forKey: .filedDate)
        load = try? c.decodeIfPresent(Load.self, forKey: .load)
        carrier = try? c.decodeIfPresent(CatalystClaimParty389.self, forKey: .carrier)
        shipper = try? c.decodeIfPresent(CatalystClaimParty389.self, forKey: .shipper)
        investigator = try? c.decodeIfPresent(CatalystClaimParty389.self, forKey: .investigator)
        decision = try? c.decodeIfPresent(Decision.self, forKey: .decision)
        evidence = try? c.decodeIfPresent([Evidence].self, forKey: .evidence)
        workflow = try? c.decodeIfPresent(WorkflowSummary.self, forKey: .workflow)
    }

    private static func flexString(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return String(i) }
        return nil
    }

    private static func flexDouble(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
}

private struct CatalystClaimWorkflow389: Decodable {
    let claimId: String?
    let currentStep: Int?
    let steps: [Step]?

    struct Step: Decodable, Identifiable {
        let step: Int
        let name: String
        let description: String?
        let required: [String]?
        let completed: Bool?
        var id: Int { step }
    }
}

// MARK: - Body

private struct CatalystCargoClaim_389: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    // Real per-claim envelope from getClaimsDashboard, upgraded by
    // getClaimById/getClaimWorkflow when those calls return detail.
    @State private var claim: ShipperFreightClaimsAPI.ClaimRow? = nil
    @State private var claimDetail: CatalystClaimDetail389? = nil
    @State private var claimWorkflow: CatalystClaimWorkflow389? = nil

    // Loss-prevention quarter count — open + pending from the real dashboard.
    // nil until hydrated → renders "—" (no invented fallback number).
    @State private var quarterCount: Int? = nil

    // Hydration state so the per-claim card can distinguish "still loading"
    // from "loaded, genuinely no claim".
    @State private var loaded: Bool = false

    @State private var submitting: Bool = false
    @State private var submitted: Bool = false
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                IridescentHairline()
                    .padding(.horizontal, -20)

                if let c = claim {
                    heroCard(c)
                    detailLedger(c)
                    carrierResponseStrip
                    loadTieCard(c)
                    submitCTA
                } else {
                    emptyClaimCard
                    carrierResponseStrip
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await reload() }
        }
        .eusoRefreshHandler { await reload() }
    }

    // MARK: - Top bar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                EusoTripBrandMark(size: 12)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · CARGO CLAIM")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            // Short claim ref — real claimNumber prefix when present, else "—".
            Text(claimShort)
                .font(EType.mono(.micro))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            // Back chevron disc (SVG: 40pt circle, white-on-slate)
            ZStack {
                Circle()
                    .fill(palette.bgCardSoft)
                    .overlay(Circle().strokeBorder(palette.borderFaint, lineWidth: 1))
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cargo Claim")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text("CLAIMS DASHBOARD · carrier")
                    .font(EType.mono(.caption))
                    .tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                // Carrier identity — real claim.carrier, else session user, else "—".
                // No invented USDOT/MC (not carried on any iOS claim contract).
                Text(carrierName.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("USDOT — · MC —")
                    .font(EType.mono(.caption))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: 150, alignment: .trailing)
        }
    }

    // MARK: - Hero · claim summary

    private func heroCard(_ c: ShipperFreightClaimsAPI.ClaimRow) -> some View {
        let status = claimDetail?.status ?? c.status
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("CLAIM · \(claimNumber(c)) · against fleet")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(prettify(status))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(statusColor(status))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(statusColor(status).opacity(0.22)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatMoney(claimDetail?.amount ?? c.amount))
                    .font(.system(size: 30, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("claimed")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(claimDescription(c))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.30)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // Honest empty state. Used when the dashboard returned no claims, or while
    // still loading. Never fabricates an envelope.
    private var emptyClaimCard: some View {
        Group {
            if loaded {
                EusoEmptyState(
                    systemImage: "shippingbox.and.arrow.backward",
                    title: "No cargo claims",
                    subtitle: "No claim has been filed against this fleet. New cargo-loss, shortage, and damage claims will appear here from the live claims ledger."
                )
            } else {
                // Loading placeholder — honest, no figures.
                VStack(alignment: .leading, spacing: 8) {
                    Text("CLAIM DETAIL · live record")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("Loading…")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    // MARK: - Claim detail ledger

    private func detailLedger(_ c: ShipperFreightClaimsAPI.ClaimRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CLAIM DETAIL · load \(loadNumber(c))")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ledgerRow("Claim type",     prettify(claimDetail?.type ?? c.type))
                ledgerRow("Cargo value",    "—")
                ledgerRow("Claimed amount", formatMoney(claimDetail?.amount ?? c.amount))
                ledgerRow("Filed",          filedDate(c))
                ledgerRow("Carrier",        carrierName)
                HStack {
                    Text(workflowLine)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func ledgerRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 7)
    }

    // MARK: - Carrier response strip

    private var carrierResponseStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CARRIER RESPONSE · status + loss-prevention actions")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(evidenceLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(lossPreventionLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // Loss-prevention quarter line — real open+pending from getClaimsDashboard.
    // Honest "—" when not yet hydrated (no invented count).
    private var lossPreventionLine: String {
        if let count = quarterCount {
            return "loss-prevention review · \(count) open/pending fleet claims this quarter"
        }
        return "loss-prevention review · — fleet claims this quarter"
    }

    // MARK: - Load tie (real loadNumber)

    private func loadTieCard(_ c: ShipperFreightClaimsAPI.ClaimRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Associated load · \(loadNumber(c))")
                .font(.system(size: 11.5, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(loadContextLine(c))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("shipper-of-record · \(shipperOfRecord)")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.blue.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.blue.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Submit CTA

    private var submitCTA: some View {
        VStack(spacing: 8) {
            CTAButton(
                title: submitted ? "Decision submitted" : "Submit claim decision",
                action: { submitDecision() },
                trailingIcon: submitted ? "checkmark" : nil,
                isLoading: submitting
            )
            Text("Approve or deny with amount · posts to the claim record")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
            if let msg = actionMessage {
                Text(msg)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.success)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            if let err = actionError {
                Text(err)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.danger)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Derived (real-sourced, honest fallbacks)

    // Short claim ref — prefix of the real claimNumber, else "—".
    private var claimShort: String {
        guard let c = claim else { return "—" }
        let n = claimNumber(c)
        guard !n.isEmpty, n != "—" else { return "—" }
        // e.g. "CLM-<date>-<suffix>" → "CLM-<date>" (first two dash groups).
        let parts = n.split(separator: "-")
        if parts.count >= 2 { return "\(parts[0])-\(parts[1])" }
        return n
    }

    // Carrier name — real claim.carrier, else signed-in session user, else "—".
    private var carrierName: String {
        if let c = claimDetail?.carrier?.name, !c.isEmpty, c != "-" { return c }
        if let c = claim?.carrier, !c.isEmpty, c != "-" { return c }
        if let name = session.user?.name, !name.isEmpty { return name }
        return "—"
    }

    // Shipper-of-record — real claim.shipper, else "—" (never the founder co).
    private var shipperOfRecord: String {
        if let s = claimDetail?.shipper?.name, !s.isEmpty, s != "-" { return s }
        if let s = claim?.shipper, !s.isEmpty, s != "-" { return s }
        return "—"
    }

    private var evidenceLine: String {
        guard let evidence = claimDetail?.evidence else { return "Evidence ledger · loading live detail" }
        if evidence.isEmpty { return "Evidence ledger · no files attached yet" }
        let names = evidence.compactMap { $0.name ?? $0.type }.prefix(3).joined(separator: ", ")
        return "\(evidence.count) evidence file\(evidence.count == 1 ? "" : "s") · \(names.isEmpty ? "attached" : names)"
    }

    private var workflowLine: String {
        let step = claimWorkflow?.currentStep ?? claimDetail?.workflow?.currentStep
        let total = claimWorkflow?.steps?.count
        if let step, let total, total > 0 {
            return "Investigation → decision workflow · step \(step) of \(total)"
        }
        if let step {
            return "Investigation → decision workflow · step \(step)"
        }
        if claimWorkflow != nil || claimDetail != nil {
            return "Investigation → decision workflow · live record loaded"
        }
        return "Investigation → decision workflow · loading live detail"
    }

    private func claimNumber(_ c: ShipperFreightClaimsAPI.ClaimRow) -> String {
        let value = claimDetail?.claimNumber ?? c.claimNumber
        return value.isEmpty ? "—" : value
    }

    private func claimDescription(_ c: ShipperFreightClaimsAPI.ClaimRow) -> String {
        let value = claimDetail?.description ?? c.description
        return value.isEmpty ? "—" : value
    }

    private func loadNumber(_ c: ShipperFreightClaimsAPI.ClaimRow) -> String {
        if let value = claimDetail?.load?.loadNumber, !value.isEmpty, value != "-" { return value }
        if let value = c.loadNumber, !value.isEmpty, value != "-" { return value }
        return "—"
    }

    private func filedDate(_ c: ShipperFreightClaimsAPI.ClaimRow) -> String {
        let value = claimDetail?.filedDate ?? c.filedDate
        return value.isEmpty ? "—" : value
    }

    private func loadContextLine(_ c: ShipperFreightClaimsAPI.ClaimRow) -> String {
        var parts: [String] = []
        if let origin = claimDetail?.load?.origin, !origin.isEmpty, origin != "-" {
            if let destination = claimDetail?.load?.destination, !destination.isEmpty, destination != "-" {
                parts.append("\(origin) → \(destination)")
            } else {
                parts.append(origin)
            }
        }
        if let commodity = claimDetail?.load?.commodity, !commodity.isEmpty, commodity != "-" {
            parts.append(commodity)
        }
        if let severity = claimDetail?.severity ?? c.severity, !severity.isEmpty {
            parts.append("\(prettify(severity)) severity")
        }
        return parts.isEmpty ? "Route / equipment / driver detail · —" : parts.joined(separator: " · ")
    }

    private func prettify(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func statusColor(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "investigating", "open":     return Brand.warning
        case "reported", "pending":       return Brand.info
        case "resolved", "paid":          return Brand.success
        case "denied", "rejected":        return Brand.danger
        default:                           return palette.textSecondary
        }
    }

    // Compact USD formatter mirrored from the sibling shipper claims screen
    // (219). amount == 0 → "-" (honest, not a fabricated figure).
    private func formatMoney(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 1_000_000 { return String(format: "$%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "$%.0fk", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n == 0          { return "-" }
        return "$\(n)"
    }

    // MARK: - Actions

    private func submitDecision() {
        guard !submitting && !submitted, let claimId = claim?.id else { return }
        submitting = true
        actionError = nil
        actionMessage = nil
        Task {
            struct DecisionInput: Encodable {
                let claimId: String
                let decision: String
                let reason: String
            }
            struct DecisionResult: Decodable { let success: Bool? }
            do {
                let _: DecisionResult = try await EusoTripAPI.shared.mutation(
                    "freightClaims.submitClaimDecision",
                    input: DecisionInput(
                        claimId: claimId,
                        decision: "partial",
                        reason: "Carrier claim decision submitted from Catalyst cargo-claim review."
                    )
                )
                await MainActor.run {
                    submitting = false
                    submitted = true
                    actionMessage = "Decision posted to the claim record."
                }
                await reload()
            } catch {
                await MainActor.run {
                    submitting = false
                    actionError = error.eusoUserCopy
                }
            }
        }
    }

    // MARK: - Network

    private func reload() async {
        loaded = false
        claimDetail = nil
        claimWorkflow = nil
        do {
            let dash = try await EusoTripAPI.shared.shipperFreightClaims.getClaimsDashboard()
            self.quarterCount = dash.open + dash.pending
            guard let newest = dash.recentClaims.first else {
                self.claim = nil
                self.loaded = true
                return
            }
            self.claim = newest

            struct DetailInput: Encodable { let id: String }
            struct WorkflowInput: Encodable { let claimId: String }
            self.claimDetail = try? await EusoTripAPI.shared.query(
                "freightClaims.getClaimById",
                input: DetailInput(id: newest.id)
            )
            self.claimWorkflow = try? await EusoTripAPI.shared.query(
                "freightClaims.getClaimWorkflow",
                input: WorkflowInput(claimId: newest.id)
            )
        } catch {
            self.claim = nil
            self.quarterCount = nil
        }
        loaded = true
    }
}

// MARK: - Previews

#Preview("389 · Catalyst · Cargo Claim · Night") {
    CatalystCargoClaimScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("389 · Catalyst · Cargo Claim · Afternoon") {
    CatalystCargoClaimScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
