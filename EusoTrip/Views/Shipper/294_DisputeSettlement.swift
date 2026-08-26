//
//  294_DisputeSettlement.swift
//  EusoTrip — Shipper · Dispute settlement (Arc G).
//  Opens a dispute on the referenced settlement.
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
    @State private var sending: Bool = false
    @State private var sent: Bool = false
    @State private var confirmedStatus: String? = nil
    @State private var confirmedDisputeId: String? = nil
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
            .padding(.horizontal, 14).padding(.top, 56)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settlement dispute confirmed")
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                    Text(confirmationLine)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var confirmationLine: String {
        var parts = ["Settlement \(settlementId)"]
        if let status = confirmedStatus { parts.append(status.replacingOccurrences(of: "_", with: " ").capitalized) }
        if let disputeId = confirmedDisputeId { parts.append("Dispute \(disputeId)") }
        return parts.joined(separator: " · ")
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
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(sending || reason.isEmpty || detail.trimmingCharacters(in: .whitespacesAndNewlines).count < 5)
        .accessibilityHint("Files a dispute on this settlement and confirms the updated settlement status")
    }

    private func send() async {
        guard !sending else { return }
        sending = true
        actionError = nil
        defer { sending = false }
        do {
            let ack = try await EusoTripAPI.shared.shipperSettlements.dispute(
                settlementId: settlementId,
                reason: reason,
                evidence: detail.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard ack.success == true,
                  ack.settlementId == settlementId,
                  ack.status?.lowercased() == "disputed" else {
                throw SettlementDisputeConfirmationError.invalidAcknowledgement
            }
            let readback = try await EusoTripAPI.shared.shipperSettlements.getDetail(settlementId: settlementId)
            guard readback.id == settlementId,
                  readback.status?.lowercased() == "disputed" else {
                throw SettlementDisputeConfirmationError.readbackMismatch
            }
            confirmedStatus = readback.status
            confirmedDisputeId = ack.disputeId
            sent = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private enum SettlementDisputeConfirmationError: LocalizedError {
    case invalidAcknowledgement
    case readbackMismatch

    var errorDescription: String? {
        switch self {
        case .invalidAcknowledgement:
            return "This settlement dispute was not confirmed. Refresh the settlement before trying again."
        case .readbackMismatch:
            return "The dispute was acknowledged, but the settlement did not read back as disputed."
        }
    }
}

#Preview("294 · Dispute · Night") {
    DisputeSettlementScreen(theme: Theme.dark, settlementId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("294 · Dispute · Afternoon") {
    DisputeSettlementScreen(theme: Theme.light, settlementId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
