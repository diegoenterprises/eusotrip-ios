//
//  307_RateConSign.swift
//  EusoTrip — Shipper · Rate-confirmation sign (Arc H).
//
//  End-to-end rate-confirmation signing workflow (GLOVE FIT B-1). Fetches the
//  REAL rate_confirmations row + its line items for the load via
//  `rateConfirmations.listForLoad`, renders the actual terms / rate breakdown,
//  captures an in-app E-SIGN / UETA signature on the shared gradient-ink pad,
//  and submits the exact PNG evidence through `rateConfirmations.sign` only
//  after the authenticated PDF bytes, immutable source hash, consent, and
//  App Attest payload all agree. The post-sign state is re-fetched from the
//  server — never fabricated from a button tap.
//

import SwiftUI
import CryptoKit

struct RateConSignScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { RateConSignBody(loadId: loadId) } nav: { shipperLifecycleNav() }
    }
}

struct RateConSignBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    let loadId: String

    // Remote RC state.
    private enum Phase: Equatable { case loading, ready, empty, failed(String) }
    @State private var phase: Phase = .loading
    @State private var rc: RateConfirmationsAPI.Detail?
    @State private var review: RateConfirmationsAPI.ReviewSource?
    @State private var pdfData: Data?
    @State private var showingPDF: Bool = false
    @State private var reviewedChecksum: String?
    @State private var consentAccepted: Bool = false

    // Signing state.
    @State private var strokes: [[CGPoint]] = [[]]
    @State private var signing: Bool = false
    @State private var actionError: String? = nil
    @State private var pendingSignatureDataURL: String?
    @State private var pendingSignatureId: UUID = UUID()

    private var loadNumeric: Int { Int(loadId.replacingOccurrences(of: "load_", with: "")) ?? 0 }

    /// True once THIS party has already signed (drives the post-sign state).
    private var thisPartyHasSigned: Bool {
        guard let rc, let side = review?.signerSide else { return false }
        if review?.signatures.contains(where: { $0.side == side }) == true { return true }
        return side == "carrier" ? rc.carrierHasSigned : rc.brokerHasSigned
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
        .fullScreenCover(isPresented: $showingPDF, onDismiss: acknowledgePDFReview) {
            if let pdfData, let source = review {
                EusoPDFViewer(
                    title: "Rate Confirmation #\(source.id)",
                    subtitle: "\(source.loadNumber) · revision \(source.bookingRevision)",
                    source: .data(pdfData),
                    allowSigning: false,
                    onSigned: nil
                )
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.richtext").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RATE CONFIRMATION · E-SIGN").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
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
                if !thisPartyHasSigned { evidenceReviewCard }
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

    private var evidenceReviewCard: some View {
        LifecycleCard(accentGradient: reviewedChecksum == review?.pdfChecksumSha256) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("SOURCE-BOUND REVIEW")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    if reviewedChecksum == review?.pdfChecksumSha256 {
                        Label("REVIEWED", systemImage: "checkmark.shield.fill")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Brand.success)
                    }
                }
                if let source = review {
                    Text("Booking revision \(source.bookingRevision) · source v\(source.sourceVersion)")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("PDF SHA-256 · \(shortHash(source.pdfChecksumSha256))")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                    Button { showingPDF = true } label: {
                        Label(
                            reviewedChecksum == source.pdfChecksumSha256 ? "Review exact PDF again" : "Review exact PDF",
                            systemImage: "doc.text.magnifyingglass"
                        )
                        .font(.system(size: 12, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(pdfData == nil)

                    Toggle(isOn: $consentAccepted) {
                        Text(source.consentText)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tint(Brand.blue)
                    .disabled(reviewedChecksum != source.pdfChecksumSha256)
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
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(LinearGradient.diagonal)
                    Text(rc.isFullySigned ? "Rate-con fully executed" : "Your signature recorded")
                        .font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                }
                Text(signedSubtitle(rc)).font(EType.caption).foregroundStyle(palette.textSecondary)
                if let signature = review?.signatures.first(where: { $0.side == review?.signerSide }) {
                    Text("Evidence · \(shortHash(signature.serverDigestSha256))")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textTertiary)
                }
                Text("Electronic signature binding under the E-SIGN Act / UETA.")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.3).foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func signedSubtitle(_ rc: RateConfirmationsAPI.Detail) -> String {
        if rc.isFullySigned {
            return "Both parties have signed. The rate confirmation is locked."
        }
        let other = review?.signerSide == "carrier" ? "broker" : "carrier"
        return "Waiting on the \(other) to countersign."
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
            Button { resetSignature() } label: {
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
            }.buttonStyle(.plain).disabled(
                signing ||
                !EusoGradientInkCanvas.hasInk(strokes) ||
                reviewedChecksum != review?.pdfChecksumSha256 ||
                !consentAccepted
            )
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

    private func shortHash(_ value: String) -> String {
        guard value.count > 20 else { return value }
        return "\(value.prefix(12))…\(value.suffix(8))"
    }

    // MARK: Networking

    private func load() async {
        phase = .loading
        actionError = nil
        do {
            guard loadNumeric > 0 else {
                throw EusoTripAPIError.trpcError("The load identifier is invalid. Reopen the load and try again.")
            }
            // Newest-first; pick the most recent non-void RC as the active one.
            let rows = try await EusoTripAPI.shared.rateConfirmations.listForLoad(loadId: loadNumeric)
            let active = rows.first(where: { $0.status != "void" }) ?? rows.first
            if let active {
                // Re-fetch the full detail (line items) for the active RC.
                let detail = try await EusoTripAPI.shared.rateConfirmations.get(id: active.id)
                let source = try await EusoTripAPI.shared.rateConfirmations.reviewSource(id: active.id)
                guard source.id == detail.id,
                      source.sourceHashSha256 == detail.sourceHashSha256,
                      source.pdfChecksumSha256 == detail.pdfChecksumSha256,
                      source.signerSide != nil else {
                    throw EusoTripAPIError.trpcError("The live booking party or rate-confirmation evidence did not match.")
                }
                guard let url = absoluteURL(source.pdfUrl) else {
                    throw EusoTripAPIError.trpcError("The exact rate-confirmation PDF URL is invalid.")
                }
                let (bytes, response) = try await EusoTripAPI.shared.fetchAuthenticatedData(url)
                guard response.mimeType?.lowercased() == source.pdfMimeType.lowercased() else {
                    throw EusoTripAPIError.trpcError("The rate-confirmation download was not the expected PDF document.")
                }
                if let expectedSize = source.pdfFileSizeBytes, expectedSize > 0,
                   bytes.count != expectedSize {
                    throw EusoTripAPIError.trpcError("The rate-confirmation PDF byte count did not match its evidence record.")
                }
                let checksum = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                guard checksum == source.pdfChecksumSha256 else {
                    throw EusoTripAPIError.trpcError("The downloaded rate-confirmation PDF failed its integrity check.")
                }
                rc = detail
                review = source
                pdfData = bytes
                reviewedChecksum = nil
                consentAccepted = false
                phase = .ready
            } else {
                rc = nil
                review = nil
                pdfData = nil
                phase = .empty
            }
        } catch {
            let msg = error.eusoUserCopy
            phase = .failed(msg)
        }
    }

    private func sign(_ target: RateConfirmationsAPI.Detail) async {
        guard let source = review,
              source.id == target.id,
              reviewedChecksum == source.pdfChecksumSha256,
              consentAccepted,
              let actorUserId = Int(session.user?.id ?? ""), actorUserId > 0 else {
            actionError = "Review the exact PDF and accept the electronic-signature consent before signing."
            return
        }
        signing = true; actionError = nil
        defer { signing = false }
        if pendingSignatureDataURL == nil {
            let base64 = EusoGradientInkCanvas.renderPNGBase64(strokes, size: CGSize(width: 600, height: 200))
            guard !base64.isEmpty else {
                actionError = "The signature image could not be prepared. Clear it and sign again."
                return
            }
            pendingSignatureDataURL = "data:image/png;base64,\(base64)"
        }
        guard let signatureDataURL = pendingSignatureDataURL else { return }
        do {
            _ = try await EusoTripAPI.shared.rateConfirmations.sign(
                id: target.id,
                signatureDataURL: signatureDataURL,
                consentAccepted: true,
                idempotencyKey: pendingSignatureId,
                actorUserId: actorUserId,
                sourceHashSha256: source.sourceHashSha256,
                pdfChecksumSha256: source.pdfChecksumSha256
            )
            resetSignature()
            await load()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func acknowledgePDFReview() {
        guard pdfData != nil, let checksum = review?.pdfChecksumSha256 else { return }
        reviewedChecksum = checksum
    }

    private func resetSignature() {
        strokes = [[]]
        pendingSignatureDataURL = nil
        pendingSignatureId = UUID()
    }

    private func absoluteURL(_ raw: String) -> URL? {
        if let absolute = URL(string: raw), absolute.scheme != nil { return absolute }
        guard let base = EusoTripAPI.shared.baseURL else { return nil }
        return URL(string: raw, relativeTo: base)?.absoluteURL
    }
}

/// Reuses the exact same source-bound signing body from carrier/catalyst
/// document surfaces without exposing the unsafe historical one-tap mutation.
struct RateConSigningSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let loadId: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            palette.bgPrimary.ignoresSafeArea()
            RateConSignBody(loadId: loadId)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                    .padding(16)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview("307 · Rate-con sign · Night") {
    RateConSignScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("307 · Rate-con sign · Afternoon") {
    RateConSignScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
