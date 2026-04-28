//
//  396_HomeEmptyState.swift
//  EusoTrip — Shipper · Home empty state (Arc B+).
//

import SwiftUI

struct HomeEmptyStateScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { HomeEmptyBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: true),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct HomeEmptyBody: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: Space.s4) {
            Spacer()
            heroCard
            quickActions
            Spacer()
            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, 14)
    }

    private var heroCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox.fill").font(.system(size: 56, weight: .heavy)).foregroundStyle(.white)
            Text("No loads yet").font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
            Text("Post your first load — carriers will start bidding within minutes.").font(EType.body).foregroundStyle(.white.opacity(0.92)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "250"])
            } label: {
                Text("Post a load").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(.white).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var quickActions: some View {
        VStack(spacing: 8) {
            cell(icon: "doc.on.doc", title: "Use a saved template", screen: "259")
            cell(icon: "tray.full", title: "Browse open RFPs", screen: "380")
            cell(icon: "dollarsign.circle", title: "Run an instant quote", screen: "394")
            cell(icon: "person.3", title: "Browse carrier directory", screen: "280")
        }
    }

    private func cell(icon: String, title: String, screen: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screen])
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

#Preview("396 · Home empty · Night") { HomeEmptyStateScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("396 · Home empty · Afternoon") { HomeEmptyStateScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
