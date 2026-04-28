//
//  417_BidAcceptConfirmation.swift
//  EusoTrip — Shipper · Bid accept confirmation (Arc C deepening).
//

import SwiftUI

struct BidAcceptConfirmationScreen: View {
    let theme: Theme.Palette
    let loadId: String
    let bidId: String
    var body: some View {
        Shell(theme: theme) { ConfirmBody(loadId: loadId, bidId: bidId) } nav: { shipperLifecycleNav() }
    }
}

private struct ConfirmBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    let bidId: String

    var body: some View {
        VStack(spacing: Space.s4) {
            Spacer()
            heroCard
            actionsCard
            Spacer()
            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, 14)
    }

    private var heroCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56, weight: .heavy)).foregroundStyle(.white)
            Text("Bid accepted").font(.system(size: 28, weight: .heavy)).foregroundStyle(.white)
            Text("Carrier locked in. Tender notification sent. Load advances to AWARDED.")
                .font(EType.body).foregroundStyle(.white.opacity(0.92)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var actionsCard: some View {
        VStack(spacing: 8) {
            cell(icon: "shippingbox", title: "Open load detail", screen: "262")
            cell(icon: "phone.fill", title: "Call dispatcher", screen: "311")
            cell(icon: "doc.text", title: "View rate-confirmation", screen: "307")
            cell(icon: "house.fill", title: "Back to dashboard", screen: "200")
        }
    }

    private func cell(icon: String, title: String, screen: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screen, "loadId": loadId])
        } label: {
            LifecycleCard {
                HStack {
                    Image(systemName: icon).foregroundStyle(LinearGradient.diagonal)
                    Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                }
            }
        }.buttonStyle(.plain)
    }
}

#Preview("417 · Accept · Night") { BidAcceptConfirmationScreen(theme: Theme.dark, loadId: "1", bidId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("417 · Accept · Afternoon") { BidAcceptConfirmationScreen(theme: Theme.light, loadId: "1", bidId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
