//
//  414_BidDetailSheet.swift
//  EusoTrip — Shipper · Bid detail sheet (Arc C deepening).
//

import SwiftUI

struct BidDetailSheetScreen: View {
    let theme: Theme.Palette
    let loadId: String
    let bidId: String
    var body: some View {
        Shell(theme: theme) { BidDetailBody(loadId: loadId, bidId: bidId) } nav: { shipperLifecycleNav() }
    }
}

private struct BidDetailBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    let bidId: String
    @StateObject private var bids = ShipperBidsStore()
    @State private var processing: String? = nil
    @State private var actionError: String? = nil

    // Carrier-vetting gate (§61 · post-Montgomery negligent-selection).
    // Fetched read-only when the bid resolves; re-recorded immutably at accept.
    @State private var vetting: CarrierVettingVerdict? = nil
    @State private var vettingLoading: Bool = false
    @State private var vettedDot: String? = nil

    private var bid: ShipperAPI.Bid? {
        (bids.state.value ?? []).first(where: { $0.id == bidId })
    }

    /// True only when the resolved policy is hard-enforcing AND a real floor
    /// failed. `review` (indeterminate/missing data) is NEVER hard-blocked —
    /// the gate refuses to certify on missing data, but does not stop the bind.
    private var isHardBlocked: Bool {
        guard let v = vetting else { return false }
        return v.policy.mode == .block && v.decision == .block
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                if let b = bid {
                    bidCard(b)
                    CarrierVettingPanel(verdict: vetting, loading: vettingLoading)
                    scoreCard(b)
                    actionRow(b)
                } else {
                    LifecycleCard { Text("Bid not found in cache. Pull-to-refresh the bids list and tap again.").font(EType.caption).foregroundStyle(palette.textSecondary) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task {
            bids.setLoadId(loadId)
            await bids.refresh()
            await fetchVettingIfNeeded()
        }
        .onChange(of: bid?.dotNumber) { _, _ in
            Task { await fetchVettingIfNeeded() }
        }
    }

    /// Read-only evaluate of the carrier on this bid. Keyed off the bid's
    /// USDOT (the FMCSA key the four floors resolve against), scoped to the
    /// load so the verdict + any audit row ties to this tender. Idempotent:
    /// re-runs only when the resolved DOT changes. Failures are silent — a
    /// gate that can't reach FMCSA must not block the screen, but it also
    /// never fabricates a pass (panel simply shows nothing / last verdict).
    private func fetchVettingIfNeeded() async {
        guard let dot = bid?.dotNumber, !dot.isEmpty, dot != vettedDot else { return }
        vettedDot = dot
        vettingLoading = true
        defer { vettingLoading = false }
        do {
            vetting = try await EusoTripAPI.shared.carrierVetting.evaluate(
                dotNumber: dot,
                loadId: Int(loadId)
            )
        } catch {
            // Honest silence: no fabricated verdict on transport failure.
            vetting = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · BID DETAIL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(bid?.catalystName ?? "-").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func bidCard(_ b: ShipperAPI.Bid) -> some View {
        LifecycleCard(accentGradient: b.recommended) {
            LifecycleSection(label: "BID", icon: "dollarsign.circle")
            LifecycleRow(label: "Carrier",       value: b.catalystName)
            LifecycleRow(label: "USDOT",         value: dashIfEmpty(b.dotNumber))
            LifecycleRow(label: "Bid amount",    value: usd(b.amount))
            LifecycleRow(label: "Transit time",  value: dashIfEmpty(b.transitTime))
            LifecycleRow(label: "Submitted",     value: humanISO(b.submittedAt))
            if !b.message.isEmpty {
                Text("MESSAGE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary).padding(.top, 4)
                Text(b.message).font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func scoreCard(_ b: ShipperAPI.Bid) -> some View {
        LifecycleCard {
            LifecycleSection(label: "SAFETY + SCORE", icon: "shield")
            LifecycleRow(label: "Safety score", value: b.safetyScore > 0 ? String(format: "%.2f", b.safetyScore) : "-")
            if b.recommended {
                Text("ESANG ★ RECOMMENDED").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }
        }
    }

    private func actionRow(_ b: ShipperAPI.Bid) -> some View {
        VStack(alignment: .leading, spacing: 8) {
        if isHardBlocked {
            HStack(spacing: 6) {
                Image(systemName: "xmark.octagon.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text("Acceptance blocked — carrier failed a hard vetting floor. Resolve the flag(s) above or vet another carrier.")
                    .font(EType.caption).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true)
            }
        }
        HStack(spacing: 10) {
            Button { Task { await accept(b.id) } } label: {
                HStack(spacing: 6) {
                    if processing == b.id + ":accept" { ProgressView().tint(.white) }
                    Image(systemName: isHardBlocked ? "lock.fill" : "checkmark")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                    Text(processing == b.id + ":accept" ? "Accepting…" : (isHardBlocked ? "Blocked" : "Accept")).font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(isHardBlocked ? AnyShapeStyle(Brand.danger.opacity(0.55)) : AnyShapeStyle(LinearGradient.diagonal))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(processing != nil || isHardBlocked)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "415", "loadId": loadId, "bidId": b.id])
            } label: {
                Text("Counter").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(palette.tintNeutral)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "416", "loadId": loadId, "bidId": b.id])
            } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Brand.danger)
                    .frame(width: 44, height: 44).background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.5), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
        }
    }

    private func accept(_ id: String) async {
        // Hard-block guard (mode == block + real fail). Belt-and-suspenders
        // to the disabled CTA — the authoritative block is the server gate.
        if isHardBlocked { return }
        processing = id + ":accept"; actionError = nil
        // Write the immutable negligent-selection vetting record at the human
        // decision moment (the server re-evaluates and never trusts a client
        // verdict; this is best-effort and must not stop the accept).
        if let dot = bid?.dotNumber, !dot.isEmpty {
            _ = try? await EusoTripAPI.shared.carrierVetting.recordDecision(
                dotNumber: dot,
                loadId: Int(loadId),
                reason: "shipper bid-accept (414)"
            )
        }
        do {
            _ = try await EusoTripAPI.shared.shipper.acceptBid(loadId: loadId, bidId: id)
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "417", "loadId": loadId, "bidId": id])
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        processing = nil
    }
}

#Preview("414 · Bid detail · Night") { BidDetailSheetScreen(theme: Theme.dark, loadId: "1", bidId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("414 · Bid detail · Afternoon") { BidDetailSheetScreen(theme: Theme.light, loadId: "1", bidId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }

// MARK: - Carrier-Vetting Panel (§61 · post-Montgomery negligent-selection gate)
//
// Bespoke verdict surface for the carrier-eligibility four-floor gate. Renders
// the overall PASS / REVIEW / BLOCKED chip + a per-check list (insurance,
// safety rating, authority age, BASIC), each carrying pass/fail/indeterminate
// state and the actual-vs-threshold readout. INDETERMINATE renders honestly —
// an amber "DATA UNAVAILABLE" pill with the server's WHY note — and is NEVER
// shown green. Reusable at every carrier-selection/assignment commit point;
// consumes EusoTripAPI.carrierVetting. DesignSystem-conformant (Space/Radius/
// EType/Brand/palette).
struct CarrierVettingPanel: View {
    @Environment(\.palette) private var palette
    let verdict: CarrierVettingVerdict?
    var loading: Bool = false

    var body: some View {
        if let v = verdict {
            LifecycleCard(
                accentDanger: v.decision == .block,
                accentWarning: v.decision == .review
            ) {
                LifecycleSection(label: "CARRIER VETTING · \(v.policy.mode.label)", icon: "checkmark.shield")
                headerChip(v)
                Divider().overlay(palette.borderFaint)
                ForEach(v.checks) { check in
                    checkRow(check)
                }
                if v.policy.mode != .block && (v.decision == .block || v.decision == .review) {
                    // warn / audit-only: surface the warning, but the bind is allowed.
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                        Text(v.decision == .block
                             ? "Carrier failed a floor. Recorded to the audit trail; acceptance is allowed under \(v.policy.mode.label) mode — proceed with caution."
                             : "One or more floors are unverified. Recorded to the audit trail; this is not a clean pass.")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
        } else if loading {
            LifecycleCard {
                LifecycleSection(label: "CARRIER VETTING", icon: "checkmark.shield")
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Running the eligibility floors…").font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
        // No verdict + not loading → render nothing (honest: never a fabricated pass).
    }

    // MARK: overall chip

    @ViewBuilder
    private func headerChip(_ v: CarrierVettingVerdict) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: decisionSymbol(v.decision)).font(.system(size: 11, weight: .heavy))
                Text(decisionLabel(v.decision)).font(.system(size: 11, weight: .heavy)).tracking(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(decisionColor(v.decision))
            .clipShape(Capsule())
            Spacer(minLength: Space.s2)
            if let name = v.carrier.legalName, !name.isEmpty {
                Text(name).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary).lineLimit(1)
            } else if let dot = v.carrier.dotNumber, !dot.isEmpty {
                Text("DOT \(dot)").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: per-check row

    @ViewBuilder
    private func checkRow(_ c: CarrierVettingCheck) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: statusSymbol(c.status)).font(.system(size: 10, weight: .heavy)).foregroundStyle(statusColor(c.status)).frame(width: 14)
                Text(checkLabel(c)).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                statusPill(c.status)
            }
            // actual-vs-threshold readout. Indeterminate => honest "data unavailable".
            HStack(spacing: 4) {
                Text(c.status == .indeterminate ? "Data unavailable" : "Observed \(actualText(c))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(c.status == .indeterminate ? Brand.warning : palette.textSecondary)
                if let t = c.threshold?.display, !t.isEmpty, c.status != .indeterminate {
                    Text("· floor \(thresholdText(c))").font(.system(size: 10, weight: .medium)).foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.leading, 22)
            if !c.note.isEmpty {
                Text(c.note).font(.system(size: 10, weight: .regular)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 22)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func statusPill(_ s: CarrierVettingCheckStatus) -> some View {
        Text(statusLabel(s))
            .font(.system(size: 8, weight: .heavy)).tracking(0.6)
            .foregroundStyle(statusColor(s))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(statusColor(s).opacity(0.16)))
    }

    // MARK: value formatting

    /// Insurance floor (`insurance_min`) carries USD — format with separators;
    /// other floors render their raw scalar.
    private func actualText(_ c: CarrierVettingCheck) -> String {
        formatScalar(c.actual, key: c.key)
    }
    private func thresholdText(_ c: CarrierVettingCheck) -> String {
        formatScalar(c.threshold, key: c.key)
    }
    private func formatScalar(_ s: VettingScalar?, key: String) -> String {
        guard let raw = s?.display, !raw.isEmpty else { return "—" }
        if key == "insurance_min", let n = Double(raw) {
            let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 0; f.currencyCode = "USD"
            return f.string(from: NSNumber(value: n)) ?? "$\(raw)"
        }
        if key == "authority_age", let n = Int(raw) {
            return "\(n) day\(n == 1 ? "" : "s")"
        }
        return raw
    }

    // MARK: check labels

    private func checkLabel(_ c: CarrierVettingCheck) -> String {
        switch c.key {
        case "insurance_min":    return "Insurance minimum"
        case "safety_rating":    return "Safety rating"
        case "authority_age":    return "Authority age"
        case "basic_percentile": return "BASIC percentiles"
        default:                 return c.label.isEmpty ? c.key : c.label
        }
    }

    // MARK: decision rendering

    private func decisionLabel(_ d: CarrierVettingDecision) -> String {
        switch d { case .pass: return "PASS"; case .review: return "REVIEW"; case .block: return "BLOCKED" }
    }
    private func decisionSymbol(_ d: CarrierVettingDecision) -> String {
        switch d { case .pass: return "checkmark.seal.fill"; case .review: return "exclamationmark.circle.fill"; case .block: return "xmark.octagon.fill" }
    }
    private func decisionColor(_ d: CarrierVettingDecision) -> Color {
        switch d { case .pass: return Brand.success; case .review: return Brand.warning; case .block: return Brand.danger }
    }

    // MARK: status rendering

    private func statusLabel(_ s: CarrierVettingCheckStatus) -> String {
        switch s { case .pass: return "PASS"; case .fail: return "FAIL"; case .indeterminate: return "UNVERIFIED" }
    }
    private func statusSymbol(_ s: CarrierVettingCheckStatus) -> String {
        switch s { case .pass: return "checkmark.circle.fill"; case .fail: return "xmark.circle.fill"; case .indeterminate: return "questionmark.circle.fill" }
    }
    private func statusColor(_ s: CarrierVettingCheckStatus) -> Color {
        switch s { case .pass: return Brand.success; case .fail: return Brand.danger; case .indeterminate: return Brand.warning }
    }
}

private extension CarrierVettingMode {
    /// Short uppercase label for the section eyebrow + warn-mode copy.
    var label: String {
        switch self { case .block: return "BLOCK"; case .warn: return "WARN"; case .auditOnly: return "AUDIT" }
    }
}
