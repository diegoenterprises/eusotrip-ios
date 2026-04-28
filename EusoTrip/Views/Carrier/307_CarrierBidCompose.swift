//
//  307_CarrierBidCompose.swift
//  EusoTrip — Carrier · Bid composer.
//
//  Cross-role chain: carrier submits bid → bids row appended to load
//  → emits BID_RECEIVED → shipper's getLifecycleSnapshot bidsSummary
//  refreshes + bid feed pulses on 261 BiddingLiveFeed.
//

import SwiftUI

struct CarrierBidComposeScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { BidComposeBody(loadId: loadId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct BidComposeBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State private var amount: Double? = nil
    @State private var transitTime: String = ""
    @State private var message: String = ""
    @State private var sending = false
    @State private var sent = false
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { LifecycleCard(accentGradient: true) { Text("Bid submitted. Shipper notified via realtime.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
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
                Image(systemName: "hand.raised.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · BID COMPOSE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Submit your bid").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var fieldsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "BID DETAILS", icon: "pencil")
            VStack(alignment: .leading, spacing: 4) {
                Text("AMOUNT (USD)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                TextField("e.g. 1900", value: $amount, format: .number).keyboardType(.decimalPad).textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("TRANSIT TIME").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                TextField("e.g. 2 days", text: $transitTime).textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("MESSAGE TO SHIPPER (OPTIONAL)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                TextField("Add context, restrictions, requests", text: $message, axis: .vertical).lineLimit(2...6).textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var ctaRow: some View {
        Button { Task { await submit() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Submitting…" : "Submit bid").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || amount == nil)
    }

    private func submit() async {
        sending = true; actionError = nil
        struct In: Encodable { let loadId: String; let amount: Double; let transitTime: String?; let message: String? }
        struct Out: Decodable { let success: Bool; let bidId: String? }
        do {
            let _ : Out = try await EusoTripAPI.shared.api.mutation(
                "catalysts.submitBid",
                input: In(loadId: loadId, amount: amount ?? 0, transitTime: transitTime.isEmpty ? nil : transitTime, message: message.isEmpty ? nil : message)
            )
            sent = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("307 · Carrier bid · Night") { CarrierBidComposeScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("307 · Carrier bid · Afternoon") { CarrierBidComposeScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
