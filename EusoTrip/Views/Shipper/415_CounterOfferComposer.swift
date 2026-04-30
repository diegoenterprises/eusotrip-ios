//
//  415_CounterOfferComposer.swift
//  EusoTrip — Shipper · Counter-offer composer (Arc C deepening).
//

import SwiftUI

struct CounterOfferComposerScreen: View {
    let theme: Theme.Palette
    let loadId: String
    let bidId: String
    var body: some View {
        Shell(theme: theme) { CounterOfferBody(loadId: loadId, bidId: bidId) } nav: { shipperLifecycleNav() }
    }
}

private struct CounterOfferBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    let bidId: String
    @State private var rate: Double? = nil
    @State private var note: String = ""
    @State private var sending = false
    @State private var sent = false
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { LifecycleCard(accentGradient: true) { Text("Counter sent — carrier has 30 min to respond.").font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                rateCard
                noteCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.swap").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · COUNTER-OFFER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Counter the bid").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var rateCard: some View {
        LifecycleCard {
            LifecycleSection(label: "COUNTER RATE (USD)", icon: "dollarsign.circle")
            TextField("e.g. 1900", value: $rate, format: .number).keyboardType(.decimalPad).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var noteCard: some View {
        LifecycleCard {
            LifecycleSection(label: "NOTE TO CARRIER", icon: "text.alignleft")
            TextField("Why this rate? (optional)", text: $note, axis: .vertical).lineLimit(2...5).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var ctaRow: some View {
        Button { Task { await send() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Sending…" : "Send counter").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || rate == nil)
    }

    private func send() async {
        sending = true; actionError = nil
        struct In: Encodable { let loadId: String; let bidId: String; let rate: Double; let note: String? }
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("shippers.counterBid", input: In(loadId: loadId, bidId: bidId, rate: rate ?? 0, note: note.isEmpty ? nil : note))
            sent = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("415 · Counter · Night") { CounterOfferComposerScreen(theme: Theme.dark, loadId: "1", bidId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("415 · Counter · Afternoon") { CounterOfferComposerScreen(theme: Theme.light, loadId: "1", bidId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
