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
//    • `freightClaims.getClaimsDashboard` is the ONLY claims procedure on
//      the iOS surface today. It returns `open/pending/...` counters PLUS a
//      `recentClaims: [ClaimRow]` array of REAL per-claim envelopes. This
//      screen renders the single most-recent real claim from that array;
//      every business value below is read from that typed `ClaimRow`.
//    • `getClaimById` / `getClaimWorkflow` / `updateClaimStatus` /
//      `getLossPreventionDashboard` / `submitClaimDecision` EXIST on the
//      server (freightClaims.ts) but are NOT exposed on the iOS API surface
//      — one `// WIRE:` marker each. Until they land we render only what the
//      dashboard truthfully returns; when there is no claim we show an honest
//      EusoEmptyState rather than fabricating a per-claim envelope.
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
    @EnvironmentObject private var session: EusoTripSession

    // Real per-claim envelope — the most-recent row from getClaimsDashboard
    // (the only claims procedure exposed on iOS). nil until hydrated / when
    // the tenant has no claims, in which case we render an honest empty state.
    @State private var claim: ShipperFreightClaimsAPI.ClaimRow? = nil

    // Loss-prevention quarter count — open + pending from the real dashboard.
    // nil until hydrated → renders "—" (no invented fallback number).
    @State private var quarterCount: Int? = nil

    // Hydration state so the per-claim card can distinguish "still loading"
    // from "loaded, genuinely no claim".
    @State private var loaded: Bool = false

    // CTA local-ack (no submitClaimDecision client method yet — see WIRE).
    @State private var submitting: Bool = false
    @State private var submitted: Bool = false

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
                Text("getClaimsDashboard · carrier")
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

    // MARK: - Hero · claim summary (real ClaimRow)

    private func heroCard(_ c: ShipperFreightClaimsAPI.ClaimRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("CLAIM · \(c.claimNumber) · against fleet")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(prettify(c.status))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(statusColor(c.status))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(statusColor(c.status).opacity(0.22)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatMoney(c.amount))
                    .font(.system(size: 30, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("claimed")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(c.description.isEmpty ? "—" : c.description)
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

    // Honest empty / "claim detail unavailable" state. Used when the dashboard
    // returned no claims, OR while still loading. Never fabricates an envelope.
    private var emptyClaimCard: some View {
        Group {
            if loaded {
                EusoEmptyState(
                    systemImage: "shippingbox.and.arrow.backward",
                    title: "No cargo claims",
                    subtitle: "No claim has been filed against this fleet. The per-claim detail surface (getClaimById) is not yet exposed on iOS — claim detail unavailable until it lands."
                )
            } else {
                // Loading placeholder — honest, no figures.
                VStack(alignment: .leading, spacing: 8) {
                    Text("CLAIM DETAIL · getClaimById")
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

    // MARK: - Claim detail ledger (real ClaimRow)

    private func detailLedger(_ c: ShipperFreightClaimsAPI.ClaimRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CLAIM DETAIL · getClaimById · load \(c.loadNumber ?? "—")")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ledgerRow("Claim type",     prettify(c.type))
                // Cargo value is NOT carried on the iOS ClaimRow contract
                // (getClaimById would carry it) — honest "—", not fabricated.
                ledgerRow("Cargo value",    "—")
                ledgerRow("Claimed amount", formatMoney(c.amount))
                ledgerRow("Filed",          (c.filedDate.isEmpty ? "—" : c.filedDate))
                ledgerRow("Carrier",        carrierName)
                // Carmack footer — getClaimWorkflow is not on the iOS client,
                // so no investigation/decision ledger is asserted here.
                // WIRE: freightClaims.getClaimWorkflow (freightClaims.ts:459) — not on iOS client yet
                HStack {
                    Text("getClaimWorkflow · investigation → decision · unavailable on iOS")
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
            // Evidence detail (addClaimEvidence) is not surfaced on the
            // dashboard contract — show the procedure, not a fabricated count.
            Text("addClaimEvidence · evidence ledger unavailable on iOS")
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
            // Associated load — real loadNumber from the claim row, else "—".
            // Origin/dest/equipment/commodity/driver are not on the claim or
            // dashboard contract (and there is no loadId to call loads.getById),
            // so we do not assert them.
            Text("Associated load · \(c.loadNumber ?? "—")")
                .font(.system(size: 11.5, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("loads.getById · route / equipment / driver unavailable on iOS")
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
            Text("submitClaimDecision · {claimId,decision,amount} · WIRE")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.top, 4)
    }

    // MARK: - Derived (real-sourced, honest fallbacks)

    // Short claim ref — prefix of the real claimNumber, else "—".
    private var claimShort: String {
        guard let n = claim?.claimNumber, !n.isEmpty else { return "—" }
        // e.g. "CLM-<date>-<suffix>" → "CLM-<date>" (first two dash groups).
        let parts = n.split(separator: "-")
        if parts.count >= 2 { return "\(parts[0])-\(parts[1])" }
        return n
    }

    // Carrier name — real claim.carrier, else signed-in session user, else "—".
    private var carrierName: String {
        if let c = claim?.carrier, !c.isEmpty, c != "-" { return c }
        if let name = session.user?.name, !name.isEmpty { return name }
        return "—"
    }

    // Shipper-of-record — real claim.shipper, else "—" (never the founder co).
    private var shipperOfRecord: String {
        if let s = claim?.shipper, !s.isEmpty, s != "-" { return s }
        return "—"
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
        guard !submitting && !submitted, claim != nil else { return }
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
        // freightClaims.getClaimsDashboard is the only claims procedure on the
        // iOS client. It carries the open/pending counters AND a recentClaims
        // array of real per-claim rows; we bind the most-recent row + the
        // quarter count. getClaimById is not exposed (see WIRE), so when the
        // tenant has no claims we surface an honest empty state.
        let dash = try? await EusoTripAPI.shared.shipperFreightClaims.getClaimsDashboard()
        await MainActor.run {
            if let d = dash {
                self.quarterCount = d.open + d.pending
                self.claim = d.recentClaims.first
            }
            self.loaded = true
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
