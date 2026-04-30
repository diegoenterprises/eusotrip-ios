//
//  416_BidRejectSheet.swift
//  EusoTrip — Shipper · Bid reject sheet (Arc C deepening).
//

import SwiftUI

struct BidRejectSheetScreen: View {
    let theme: Theme.Palette
    let loadId: String
    let bidId: String
    var body: some View {
        Shell(theme: theme) { BidRejectBody(loadId: loadId, bidId: bidId) } nav: { shipperLifecycleNav() }
    }
}

private struct BidRejectBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    let bidId: String
    @State private var reason: String = "Rate too high"
    @State private var note: String = ""
    @State private var sending = false
    @State private var sent = false
    @State private var actionError: String? = nil

    private let reasons = ["Rate too high", "Carrier scorecard too low", "Equipment mismatch", "Tendered to another carrier", "Hazmat cert missing", "Other"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { LifecycleCard(accentGradient: true) { Text("Bid rejected. Carrier notified.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                reasonCard
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
                Image(systemName: "xmark.octagon").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.danger)
                Text("SHIPPER · REJECT BID").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(Brand.danger)
            }
            Text("Reject bid").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var reasonCard: some View {
        LifecycleCard(accentDanger: true) {
            LifecycleSection(label: "REASON", icon: "questionmark.circle")
            ForEach(reasons, id: \.self) { r in
                Button { reason = r } label: {
                    HStack {
                        Image(systemName: reason == r ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(reason == r ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(palette.textTertiary))
                        Text(r).font(EType.body).foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }.buttonStyle(.plain)
            }
        }
    }

    private var noteCard: some View {
        LifecycleCard {
            LifecycleSection(label: "NOTE (OPTIONAL)", icon: "text.alignleft")
            TextField("Add detail for the carrier", text: $note, axis: .vertical).lineLimit(2...5).textFieldStyle(.plain)
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
                Text(sending ? "Rejecting…" : "Reject bid").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Brand.danger)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending)
    }

    private func send() async {
        sending = true; actionError = nil
        let combined = note.isEmpty ? reason : "\(reason) — \(note)"
        do {
            _ = try await EusoTripAPI.shared.shipper.rejectBid(loadId: loadId, bidId: bidId, reason: combined)
            sent = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("416 · Reject · Night") { BidRejectSheetScreen(theme: Theme.dark, loadId: "1", bidId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("416 · Reject · Afternoon") { BidRejectSheetScreen(theme: Theme.light, loadId: "1", bidId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
