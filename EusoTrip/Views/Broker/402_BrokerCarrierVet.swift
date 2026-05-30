//
//  402_BrokerCarrierVet.swift
//  EusoTrip — Broker · Carrier vetting (Highway / RMIS / Carrier411 / Carrier Assure).
//
//  LIVE PATH (2026-05-30): lane-eligible candidates load from
//  `brokers.getVetCandidates`, then each candidate is run through the
//  real FMCSA/authority/insurance verdict source —
//  `EusoTripAPI.shared.carrierVetAgent.vet` (3-child Cortex fanout:
//  perception parses the FMCSA snapshot, memory pulls the EusoTrip
//  scorecard, guardian emits {pass | needs_review | fail} + redFlags[]
//  + citations[]). Each card binds to that live verdict; there are no
//  fabricated rows on the live path — em-dash / EusoEmptyState only.
//  Mirrors the wiring of the LIVE sibling 406_BrokerCatalystVetting and
//  Components/CarrierVetSheet (which back the same carrierVetAgent.vet).
//

import SwiftUI

struct BrokerCarrierVetScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { CarrierVetBody(loadId: loadId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Carriers", systemImage: "person.3.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire models

private struct VetCandidate: Decodable, Identifiable, Hashable {
    let catalystId: String
    let name: String
    let dotNumber: String
    let mcNumber: String?
    let safetyRating: String?
    let highwayScore: Double?         // Highway-style identity / fraud confidence
    let rmisOnboarded: Bool?
    let insuranceFiling: Bool?
    let oosViolations: Int?
    let lanesCovered: [String]?
    var id: String { catalystId }
}

/// Per-carrier live FMCSA/authority/insurance verdict, resolved by
/// `carrierVetAgent.vet`. Held alongside the lane candidate so each
/// card can render the guarded verdict + redFlags without fabricating
/// anything: a nil verdict renders as an honest em-dash / "Vetting…".
private struct VetVerdictState: Hashable {
    var loading: Bool = true
    var verdict: CarrierVetResponse? = nil
    var error: String? = nil
}

// MARK: - Body

private struct CarrierVetBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    let loadId: String
    @State private var candidates: [VetCandidate] = []
    @State private var verdicts: [String: VetVerdictState] = [:]   // keyed by USDOT
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Tier 2 #38 (2026-05-21) — present the ESANG carrier-vetting
    /// sheet for any DOT. Sits above the lane-eligible candidate
    /// list so the broker can drill on an off-board carrier too.
    @State private var showEsangVet: Bool = false
    @State private var esangVetPrefillDot: String? = nil

    private var companyId: Int { Int(session.user?.companyId ?? "") ?? 1 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                esangVetCTA
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showEsangVet) {
            CarrierVetSheet(
                companyId: companyId,
                prefillDot: esangVetPrefillDot
            )
        }
    }

    /// Tier 2 #38 — entry CTA for the ESANG vet sheet. Broker can
    /// type any DOT (off-board carriers too) and get a guarded
    /// verdict with FMCSA + scorecard + redFlags + citations.
    private var esangVetCTA: some View {
        Button {
            esangVetPrefillDot = nil
            showEsangVet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask ESANG to vet a carrier")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Any DOT — FMCSA + your scorecard + a guarded verdict with citations.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, 12)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.4))
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("BROKER · CARRIER VET · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Vet carriers for this lane").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Highway identity + RMIS onboard + FMCSA authority + insurance filing + OOS history, each cleared through a guarded ESANG verdict. Tap to tender.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Vetting carriers…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if candidates.isEmpty { EusoEmptyState(systemImage: "person.3", title: "No matched carriers", subtitle: "Lane-eligible carriers with cleared identity surface here.") }
        else {
            ForEach(candidates) { c in
                Button {
                    NotificationCenter.default.post(name: .eusoBrokerNavSwap, object: nil, userInfo: ["screenId": "403", "loadId": loadId, "catalystId": c.catalystId])
                } label: {
                    candidateCard(c)
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func candidateCard(_ c: VetCandidate) -> some View {
        let state = verdicts[c.dotNumber]
        let verdict = state?.verdict
        // Card glows gold only when the live guarded verdict cleared PASS.
        LifecycleCard(accentGradient: verdict?.verdict == .pass) {
            LifecycleSection(label: c.name.uppercased(), icon: "person.2")
            LifecycleRow(label: "USDOT",            value: dashIfEmpty(c.dotNumber))
            LifecycleRow(label: "MC",               value: dashIfEmpty(c.mcNumber))
            LifecycleRow(label: "Safety",           value: dashIfEmpty(c.safetyRating))
            LifecycleRow(label: "Highway score",    value: c.highwayScore.map { String(format: "%.2f", $0) } ?? "—")
            LifecycleRow(label: "RMIS",             value: c.rmisOnboarded == true ? "Onboarded" : "—")
            LifecycleRow(label: "Insurance",        value: c.insuranceFiling == true ? "Filed" : "—")
            LifecycleRow(label: "OOS",              value: "\(c.oosViolations ?? 0)")
            verdictRow(state)
        }
    }

    /// Honest verdict line: spinner while the live vet is in flight,
    /// the guarded {PASS | NEEDS REVIEW | FAIL} badge + flag/citation
    /// counts once it resolves, an em-dash if it could not resolve.
    @ViewBuilder
    private func verdictRow(_ state: VetVerdictState?) -> some View {
        if let v = state?.verdict {
            let tint = verdictColor(v.verdict)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: verdictSymbol(v.verdict))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(tint)
                    Text(verdictLabel(v.verdict))
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(tint)
                    Spacer(minLength: 0)
                    if !v.redFlags.isEmpty {
                        Label("\(v.redFlags.count)", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.orange)
                    }
                    if !v.citations.isEmpty {
                        Label("\(v.citations.count)", systemImage: "text.book.closed.fill")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if !v.synthesis.isEmpty {
                    Text(v.synthesis)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
        } else if state?.loading == true {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("ESANG vetting authority + insurance…")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
            }
            .padding(.top, 4)
        } else if let e = state?.error {
            LifecycleRow(label: "Verdict", value: "— (\(e))")
        } else {
            LifecycleRow(label: "Verdict", value: "—")
        }
    }

    // MARK: pipeline

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let loadId: String }
        do {
            let r: [VetCandidate] = try await EusoTripAPI.shared.query("brokers.getVetCandidates", input: In(loadId: loadId))
            candidates = r
            // Seed every candidate's verdict slot as loading, then fan
            // out the real FMCSA/authority/insurance vet for each DOT.
            var seed: [String: VetVerdictState] = [:]
            for c in r where !c.dotNumber.isEmpty { seed[c.dotNumber] = VetVerdictState() }
            verdicts = seed
            loading = false
            await vetAll(r)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
        }
    }

    /// Fire the real `carrierVetAgent.vet` for each lane candidate so
    /// the verdict shown is the live guarded FMCSA/authority/insurance
    /// envelope — not a static literal. Failures degrade to an honest
    /// em-dash on that single card without sinking the whole list.
    private func vetAll(_ rows: [VetCandidate]) async {
        let cid = companyId
        await withTaskGroup(of: (String, VetVerdictState).self) { group in
            for c in rows where !c.dotNumber.isEmpty {
                group.addTask {
                    do {
                        let resp: CarrierVetResponse = try await EusoTripAPI.shared
                            .carrierVetAgent.vet(input: CarrierVetInput(
                                dotNumber: c.dotNumber,
                                question: nil,
                                companyId: cid
                            ))
                        return (c.dotNumber, VetVerdictState(loading: false, verdict: resp, error: nil))
                    } catch {
                        let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                        return (c.dotNumber, VetVerdictState(loading: false, verdict: nil, error: msg))
                    }
                }
            }
            for await (dot, state) in group {
                verdicts[dot] = state
            }
        }
    }

    // MARK: render helpers

    private func dashIfEmpty(_ s: String?) -> String {
        let trimmed = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func verdictLabel(_ v: CarrierVetVerdict) -> String {
        switch v {
        case .pass:        return "PASS"
        case .needsReview: return "NEEDS REVIEW"
        case .fail:        return "FAIL"
        }
    }
    private func verdictSymbol(_ v: CarrierVetVerdict) -> String {
        switch v {
        case .pass:        return "checkmark.seal.fill"
        case .needsReview: return "exclamationmark.circle.fill"
        case .fail:        return "xmark.octagon.fill"
        }
    }
    private func verdictColor(_ v: CarrierVetVerdict) -> Color {
        switch v {
        case .pass:        return Brand.success
        case .needsReview: return .orange
        case .fail:        return Brand.danger
        }
    }
}

#Preview("402 · Carrier vet · Night") { BrokerCarrierVetScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("402 · Carrier vet · Afternoon") { BrokerCarrierVetScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
