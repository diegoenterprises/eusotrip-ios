//
//  294_DisputeSettlement.swift
//  EusoTrip — Shipper · Dispute settlement (Arc G).
//  Files a freight claim with type=settlement_dispute.
//

import SwiftUI

struct DisputeSettlementScreen: View {
    let theme: Theme.Palette
    let settlementId: String
    var body: some View {
        Shell(theme: theme) { DisputeBody(settlementId: settlementId) } nav: { shipperLifecycleNav() }
    }
}

private struct DisputeBody: View {
    @Environment(\.palette) private var palette
    let settlementId: String
    @State private var reason: String = ""
    @State private var detail: String = ""
    @State private var amount: Double? = nil
    @State private var sending: Bool = false
    @State private var sent: Bool = false
    @State private var actionError: String? = nil

    private let reasons = ["Wrong amount", "Missing accessorial", "Duplicate charge", "Wrong rate", "Other"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { successCard }
                if let err = actionError { errorCard(err) }
                fieldsCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                Text("SHIPPER · DISPUTE SETTLEMENT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(Brand.warning)
            }
            Text("Dispute settlement").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var fieldsCard: some View {
        LifecycleCard(accentWarning: true) {
            LifecycleSection(label: "DETAILS", icon: "pencil")
            VStack(alignment: .leading, spacing: 4) {
                Text("REASON").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Picker("", selection: $reason) { ForEach(reasons, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("DISPUTED AMOUNT (USD)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                TextField("e.g. 487", value: $amount, format: .number).keyboardType(.decimalPad).textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("DETAIL").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                TextField("Describe the discrepancy", text: $detail, axis: .vertical).lineLimit(3...8).textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var successCard: some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(LinearGradient.diagonal)
                Text("Dispute filed. The accounting team will review within 24 hours.").font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
    }

    private var ctaRow: some View {
        Button { Task { await send() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Filing…" : "File dispute")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || reason.isEmpty || amount == nil)
    }

    private func send() async {
        sending = true; actionError = nil
        struct In: Encodable {
            let settlementId: String; let reason: String; let amount: Double; let detail: String
            let claimType: String  // "settlement_dispute"
        }
        struct Out: Decodable { let success: Bool; let claimId: String? }
        do {
            let _ : Out = try await EusoTripAPI.shared.api.mutation(
                "freightClaims.fileClaim",
                input: In(settlementId: settlementId, reason: reason, amount: amount ?? 0, detail: detail, claimType: "settlement_dispute")
            )
            sent = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("294 · Dispute · Night") {
    DisputeSettlementScreen(theme: Theme.dark, settlementId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("294 · Dispute · Afternoon") {
    DisputeSettlementScreen(theme: Theme.light, settlementId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
