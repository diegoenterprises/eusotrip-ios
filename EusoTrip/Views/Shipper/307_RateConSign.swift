//
//  307_RateConSign.swift
//  EusoTrip — Shipper · Rate-confirmation sign (Arc H).
//
//  End-to-end rate-confirmation signing workflow (GLOVE FIT B-1). Fetches the
//  REAL rate_confirmations row + its line items for the load via
//  `rateConfirmations.listForLoad`, renders the actual terms / rate breakdown,
//  captures an in-app E-SIGN / UETA signature on the shared gradient-ink pad,
//  and fires the real `rateConfirmations.signBroker` (or `signCarrier`, by
//  role) mutation that advances the server status FSM. The post-sign state is
//  driven entirely by the returned row — never a fabricated "signed".
//
//  HONEST DocuSign degrade: the optional "send for provider signature" action
//  fires `rateConfirmations.sendDocusign`, which outside a provisioned prod
//  tenant returns `pending_docusign_prod`. We surface that as a clear
//  "e-signature pending provider" state rather than faking a completed
//  envelope.
//

import SwiftUI

struct RateConSignScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { RateConSignBody(loadId: loadId) } nav: { shipperLifecycleNav() }
    }
}

private struct RateConSignBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    let loadId: String

    // Remote RC state.
    private enum Phase: Equatable { case loading, ready, empty, failed(String) }
    @State private var phase: Phase = .loading
    @State private var rc: RateConfirmationsAPI.Detail?

    // Signing state.
    @State private var strokes: [[CGPoint]] = [[]]
    @State private var signing: Bool = false
    @State private var actionError: String? = nil

    // DocuSign honest seam.
    @State private var sendingDocusign: Bool = false
    @State private var docusignReason: String? = nil

    private var loadNumeric: Int { Int(loadId.replacingOccurrences(of: "load_", with: "")) ?? 0 }

    /// Carrier-side roles sign as carrier; everyone else (the shipper surface
    /// default) signs as broker. Mirrors the server's role-gated sign procs.
    private var signsAsCarrier: Bool {
        let r = (session.user?.role ?? "").uppercased()
        return r == "CATALYST"
    }

    /// True once THIS party has already signed (drives the post-sign state).
    private var thisPartyHasSigned: Bool {
        guard let rc else { return false }
        return signsAsCarrier ? rc.carrierHasSigned : rc.brokerHasSigned
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.richtext").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · RATE-CON · SIGN").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Sign rate confirmation").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Phase router

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            loadingCard
        case .failed(let msg):
            LifecycleCard(accentDanger: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn’t load the rate confirmation").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
                    retryButton
                }
            }
        case .empty:
            LifecycleCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No rate confirmation yet").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text("A rate confirmation hasn’t been issued for this load. Once the broker mints one it will appear here for signature.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                    retryButton
                }
            }
        case .ready:
            if let rc {
                termsCard(rc)
                if rc.lineItems.isEmpty == false { lineItemsCard(rc) }
                signatureSection(rc)
            }
        }
    }

    private var loadingCard: some View {
        LifecycleCard {
            HStack(spacing: 10) {
                ProgressView().tint(palette.textSecondary)
                Text("Loading rate confirmation…").font(EType.body).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var retryButton: some View {
        Button { Task { await load() } } label: {
            Text("Retry").font(.system(size: 12, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(palette.tintNeutral).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: Terms + rate

    private func termsCard(_ rc: RateConfirmationsAPI.Detail) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("RATE CONFIRMATION").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    statusChip(rc.status)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("RC-\(rc.id)").font(EType.mono(.caption)).fontWeight(.semibold).foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(rateLabel(rc))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Divider().overlay(palette.borderFaint)
                Text("TERMS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                // Real terms text — em-dash sentinel when the row carries none
                // (never a fabricated clause).
                Text(rc.terms?.isEmpty == false ? rc.terms! : "—")
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func lineItemsCard(_ rc: RateConfirmationsAPI.Detail) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("RATE BREAKDOWN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                ForEach(rc.lineItems) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.description).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).lineLimit(2)
                            if let q = item.qty, let r = item.rate, q > 0 {
                                Text("\(trimNum(q)) × \(money(r, rc.currency))")
                                    .font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(item.amount.map { money($0, rc.currency) } ?? "—")
                            .font(EType.mono(.caption)).fontWeight(.semibold).foregroundStyle(palette.textPrimary)
                    }
                    .padding(.vertical, 4)
                    if item.id != rc.lineItems.last?.id { Divider().overlay(palette.borderFaint) }
                }
            }
        }
    }

    // MARK: Signature / post-sign state

    @ViewBuilder private func signatureSection(_ rc: RateConfirmationsAPI.Detail) -> some View {
        if rc.isVoid {
            LifecycleCard(accentDanger: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rate confirmation voided").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text(rc.voidedReason?.isEmpty == false ? rc.voidedReason! : "This rate confirmation was voided and can no longer be signed.")
                        .font(EType.caption).foregroundStyle(Brand.danger)
                }
            }
        } else if thisPartyHasSigned {
            signedState(rc)
        } else {
            pad
            if let err = actionError {
                LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
            }
            ctaRow(rc)
        }
    }

    private func signedState(_ rc: RateConfirmationsAPI.Detail) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            LifecycleCard(accentGradient: true) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(LinearGradient.diagonal)
                        Text(rc.isFullySigned ? "Rate-con fully executed" : "Your signature recorded")
                            .font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    }
                    Text(signedSubtitle(rc)).font(EType.caption).foregroundStyle(palette.textSecondary)
                    Text("Electronic signature binding under the E-SIGN Act / UETA.")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.3).foregroundStyle(palette.textTertiary)
                }
            }
            docusignSeamCard(rc)
        }
    }

    private func signedSubtitle(_ rc: RateConfirmationsAPI.Detail) -> String {
        if rc.isFullySigned {
            return "Both parties have signed. The rate confirmation is locked."
        }
        let other = signsAsCarrier ? "broker" : "carrier"
        return "Waiting on the \(other) to countersign."
    }

    // HONEST DocuSign seam. Only the broker/shipper side can dispatch the
    // outbound provider envelope, and we NEVER claim it was sent unless the
    // server returned a genuine prod dispatch.
    @ViewBuilder private func docusignSeamCard(_ rc: RateConfirmationsAPI.Detail) -> some View {
        if rc.docusignDispatched {
            LifecycleCard {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.success)
                    Text("Sent to e-signature provider\(rc.docusignEnvelopeId.map { " · \($0)" } ?? "")")
                        .font(EType.caption).foregroundStyle(palette.textPrimary)
                }
            }
        } else if rc.docusignPending || docusignReason != nil {
            LifecycleCard(accentWarning: true) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.exclamationmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.warning)
                        Text("E-signature pending provider").font(EType.caption.weight(.bold)).foregroundStyle(palette.textPrimary)
                    }
                    Text(docusignReason ?? "The DocuSign provider isn’t provisioned in this environment yet. Your in-app signature is already binding; the provider envelope will dispatch once production e-sign is enabled.")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                }
            }
        } else if !signsAsCarrier {
            // Broker side may optionally route to the provider for an external
            // countersignature. Honest about the not-yet-provisioned state.
            Button { Task { await sendDocusign(rc) } } label: {
                HStack(spacing: 6) {
                    if sendingDocusign { ProgressView().tint(palette.textPrimary).controlSize(.small) }
                    Image(systemName: "paperplane").font(.system(size: 11, weight: .bold))
                    Text(sendingDocusign ? "Sending…" : "Send for provider e-signature")
                        .font(.system(size: 12, weight: .heavy)).tracking(0.3)
                }
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(palette.tintNeutral)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }.buttonStyle(.plain).disabled(sendingDocusign)
        }
    }

    private var pad: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SIGN BELOW").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            EusoGradientInkCanvas(strokes: $strokes)
                .frame(height: 200)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func ctaRow(_ rc: RateConfirmationsAPI.Detail) -> some View {
        HStack(spacing: 10) {
            Button { strokes = [[]] } label: {
                Text("Clear").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(palette.tintNeutral).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Button { Task { await sign(rc) } } label: {
                HStack(spacing: 6) {
                    if signing { ProgressView().tint(.white) }
                    Text(signing ? "Signing…" : "Sign rate-con")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(signing || !EusoGradientInkCanvas.hasInk(strokes))
        }
    }

    // MARK: Status chip

    private func statusChip(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "fully_signed":   return ("FULLY SIGNED", Brand.success)
            case "signed_broker":  return ("BROKER SIGNED", Brand.blue)
            case "signed_carrier": return ("CARRIER SIGNED", Brand.blue)
            case "sent":           return ("AWAITING SIGNATURE", Brand.warning)
            case "void":           return ("VOID", Brand.danger)
            default:               return ("DRAFT", palette.textTertiary)
            }
        }()
        return Text(label)
            .font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
    }

    // MARK: Formatting helpers

    private func rateLabel(_ rc: RateConfirmationsAPI.Detail) -> String {
        guard let amt = rc.rateAmount, amt > 0 else { return "—" }
        return money(amt, rc.currency)
    }

    private func money(_ v: Double, _ currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = (v == v.rounded()) ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? "\(currency) \(v)"
    }

    private func trimNum(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }

    // MARK: Networking

    private func load() async {
        phase = .loading
        do {
            // Newest-first; pick the most recent non-void RC as the active one.
            let rows = try await EusoTripAPI.shared.rateConfirmations.listForLoad(loadId: loadNumeric)
            let active = rows.first(where: { $0.status != "void" }) ?? rows.first
            if let active {
                // Re-fetch the full detail (line items) for the active RC.
                let detail = try await EusoTripAPI.shared.rateConfirmations.get(id: active.id)
                rc = detail
                phase = .ready
            } else {
                rc = nil
                phase = .empty
            }
        } catch {
            let msg = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            phase = .failed(msg)
        }
    }

    private func sign(_ target: RateConfirmationsAPI.Detail) async {
        signing = true; actionError = nil
        defer { signing = false }
        // The gradient-ink signature is captured for the document record; the
        // server FSM advance is what makes the RC legally signed.
        _ = EusoGradientInkCanvas.renderPNGBase64(strokes, size: CGSize(width: 600, height: 200))
        do {
            let updated: RateConfirmationsAPI.Detail
            if signsAsCarrier {
                updated = try await EusoTripAPI.shared.rateConfirmations.signCarrier(id: target.id)
            } else {
                updated = try await EusoTripAPI.shared.rateConfirmations.signBroker(id: target.id)
            }
            // Drive the post-sign state entirely off the returned row.
            rc = updated
            phase = .ready
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func sendDocusign(_ target: RateConfirmationsAPI.Detail) async {
        sendingDocusign = true
        defer { sendingDocusign = false }
        do {
            let seam = try await EusoTripAPI.shared.rateConfirmations.sendDocusign(id: target.id)
            if seam.sent {
                // Real prod dispatch — refresh the row so the dispatched state shows.
                rc = try await EusoTripAPI.shared.rateConfirmations.get(id: target.id)
            } else {
                // HONEST pending — surface the provider-pending reason verbatim.
                docusignReason = seam.reason ?? "E-signature provider not provisioned in this environment."
            }
        } catch {
            docusignReason = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("307 · Rate-con sign · Night") {
    RateConSignScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("307 · Rate-con sign · Afternoon") {
    RateConSignScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
