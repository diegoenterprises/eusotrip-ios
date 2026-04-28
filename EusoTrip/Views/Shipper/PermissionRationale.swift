//
//  PermissionRationale.swift
//  EusoTrip — Shipper · Arc M shared rationale card.
//

import SwiftUI

struct PermissionRationaleScreen: View {
    let theme: Theme.Palette
    let title: String
    let eyebrow: String
    let icon: String
    let message: String
    let bullets: [String]
    /// Action that opens the actual system prompt — the screen is the
    /// pre-prompt rationale; the system call happens here on tap.
    let onGrant: () -> Void
    var body: some View {
        Shell(theme: theme) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    bulletsCard
                    cta
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }
        } nav: { shipperLifecycleNav() }
    }

    @Environment(\.palette) private var palette

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(eyebrow.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(message).font(EType.body).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bulletsCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "WHY WE NEED THIS", icon: "questionmark.circle")
            ForEach(Array(bullets.enumerated()), id: \.offset) { _, b in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(LinearGradient.diagonal).padding(.top, 2)
                    Text(b).font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var cta: some View {
        Button { onGrant() } label: {
            Text("Continue").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }
}
