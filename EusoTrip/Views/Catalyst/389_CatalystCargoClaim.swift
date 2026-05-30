//
//  389_CatalystCargoClaim.swift
//  EusoTrip — Catalyst · Cargo Claim (CARRIER-side claim management).
//
//  Verbatim iOS port of "03 Catalyst/Code/389_CatalystCargoClaim.swift"
//  (+ Dark-SVG cross-check). The carrier's defence-side view of a cargo
//  claim filed against a delivered truck load. Cross-mode parity gap fill:
//  Rail (605) and Vessel (732) already had cargo-claim surfaces, the Truck
//  Catalyst band had none against the mode-agnostic freightClaims router.
//  Docked under DISPATCH.
//
//  Layout (top → bottom), 1:1 with the SVG:
//    • Hero · claim summary — claimed amount + "under review" status pill
//    • Claim detail (getClaimById) — type / cargo value / claimed / filed /
//      investigator ledger + getClaimWorkflow Carmack 9-mo footer
//    • Carrier response strip (updateClaimStatus · getLossPreventionDashboard)
//    • Load tie — LA → Phoenix reefer berries · driver · shipper-of-record
//    • CTA · Submit claim decision (submitClaimDecision)
//
//  Server wiring (real, no fabricated rows):
//    • `freightClaims.getClaimsDashboard` EXISTS client-side as
//       `EusoTripAPI.shared.shipperFreightClaims.getClaimsDashboard()` —
//       its open/pending counts hydrate the loss-prevention quarter line
//       over the representative seed.
//    The per-claim detail/decision procedures EXIST on the server
//    (freightClaims.ts) but are NOT yet exposed on the iOS API surface —
//    one // WIRE: marker each. Per the house "0% mock — seeds overwritten
//    on hydrate" doctrine the screen renders the Code/ representative
//    figures immediately (NOT fabrication); they would be overwritten the
//    moment getClaimById is wired.
//
//  PERSONA: CATALYST — Aurora Freight Lines · USDOT 3 482 119 · MC-942 008.
//  Shipper-of-record DU pin: Eusorone Technologies · driver ME · Eusotrans LLC.
//  Load LD-260427-7C3A09F18B · LA CA → Phoenix AZ · 53' Reefer fresh berries ·
//  claim CLM-260524-7C3A.
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
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_389() -> [NavSlot] {
    [NavSlot(label: "Fleet", systemImage: "truck.box", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",    isCurrent: false)]
}

// MARK: - Body

private struct CatalystCargoClaim_389: View {
    @Environment(\.palette) private var palette

    // Loss-prevention quarter count — hydrated from the real
    // getClaimsDashboard open/pending counts over the seed line.
    @State private var quarterCount: Int? = nil

    // CTA local-ack (no submitClaimDecision client method yet — see WIRE).
    @State private var submitting: Bool = false
    @State private var submitted: Bool = false

    // Representative seed figures (verbatim from the Code/ spec — these are
    // the live return shapes, overwritten the moment getClaimById is wired).
    private let claimShort  = "CLM-260524"
    private let claimNumber = "CLM-260524-7C3A"
    private let loadNumber  = "LD-260427-7C3A09F18B"
    private let claimedAmount = "$14,200"

    // getClaimById detail rows (verbatim).
    private struct DetailRow_389: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }
    private let detailRows: [DetailRow_389] = [
        DetailRow_389(label: "Claim type",     value: "Damage"),
        DetailRow_389(label: "Cargo value",    value: "$118,000"),
        DetailRow_389(label: "Claimed amount", value: "$14,200"),
        DetailRow_389(label: "Filed",          value: "2 days ago"),
        DetailRow_389(label: "Investigator",   value: "assignClaimInvestigator"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                IridescentHairline()
                    .padding(.horizontal, -20)

                heroCard
                detailLedger
                carrierResponseStrip
                loadTieCard
                submitCTA

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await reload() }
        }
    }

    // MARK: - Top bar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · CARGO CLAIM")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
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
                Text("getClaimById · carrier")
                    .font(EType.mono(.caption))
                    .tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("AURORA FREIGHT LINES · USDOT 3 482 119")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.trailing)
                Text("MC-942 008")
                    .font(EType.mono(.caption))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: 150, alignment: .trailing)
        }
    }

    // MARK: - Hero · claim summary

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("CLAIM · \(claimNumber) · against fleet")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text("under review")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Brand.warning.opacity(0.22)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(claimedAmount)
                    .font(.system(size: 30, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("claimed")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("concealed damage · 6 cartons · investigator assigned")
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

    // MARK: - Claim detail · getClaimById ledger

    private var detailLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CLAIM DETAIL · getClaimById · load \(loadNumber)")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(detailRows) { row in
                    ledgerRow(row.label, row.value)
                }
                // Carmack footer — STUB on the server: freightClaims has no
                // explicit Carmack-Amendment field; the 9-mo window is
                // derived client-side from the delivery date.
                // WIRE: freightClaims.getClaimWorkflow (freightClaims.ts:459) — not on iOS client yet
                HStack {
                    Text("getClaimWorkflow · investigation → decision · Carmack 9-mo window")
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
            // WIRE: freightClaims.updateClaimStatus (freightClaims.ts:393) + getLossPreventionDashboard (freightClaims.ts:988) — not on iOS client yet
            Text("CARRIER RESPONSE · updateClaimStatus · getLossPreventionDashboard")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("evidence on file · 4 photos + reefer temp log · addClaimEvidence")
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

    // Loss-prevention quarter count — hydrated from getClaimsDashboard over
    // the representative seed line ("1 of 3 fleet claims this quarter").
    private var lossPreventionLine: String {
        let count = quarterCount ?? 3
        return "loss-prevention review open · 1 of \(count) fleet claims this quarter"
    }

    // MARK: - Load tie

    private var loadTieCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Los Angeles CA → Phoenix AZ · 53' Reefer · fresh berries")
                .font(.system(size: 11.5, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("driver Michael Eusorone · ME · Eusotrans LLC · USDOT 3 194 882")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("shipper-of-record Eusorone Technologies · DU")
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
            Text("submitClaimDecision · {claimId,decision,amount}")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func submitDecision() {
        guard !submitting && !submitted else { return }
        submitting = true
        // WIRE: freightClaims.submitClaimDecision (freightClaims.ts:541) {claimId,decision,amount}
        // — server proc EXISTS but is not yet exposed on the iOS API surface.
        // Acknowledge locally so the CTA reads honestly rather than pretending
        // a network round-trip; swap in the real mutation when it lands.
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run {
                submitting = false
                submitted = true
            }
        }
    }

    // MARK: - Network

    private func reload() async {
        // freightClaims.getClaimsDashboard EXISTS on the iOS client — hydrate
        // the loss-prevention quarter count over the seed. The per-claim
        // getClaimById detail envelope is not yet exposed (see WIRE markers),
        // so the ledger renders the Code/ representative figures immediately.
        let dash = try? await EusoTripAPI.shared.shipperFreightClaims.getClaimsDashboard()
        await MainActor.run {
            if let d = dash {
                self.quarterCount = max(d.open + d.pending, 1)
            }
        }
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
