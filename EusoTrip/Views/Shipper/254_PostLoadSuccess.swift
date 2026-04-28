//
//  254_PostLoadSuccess.swift
//  EusoTrip — Shipper · Post-a-Load · Success.
//

import SwiftUI

struct PostLoadSuccessScreen: View {
    let theme: Theme.Palette
    @ObservedObject var draft: PostLoadDraft
    var body: some View {
        Shell(theme: theme) { SuccessBody(draft: draft) } nav: { shipperLifecycleNav() }
    }
}

private struct SuccessBody: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Spacer(minLength: 24)
            successHero
            actionsCard
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var successHero: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .heavy))
                .foregroundStyle(.white)
            Text("Posted").font(.system(size: 28, weight: .heavy)).foregroundStyle(.white)
            Text(draft.postedLoadNumber ?? "—")
                .font(.system(size: 13, weight: .heavy)).tracking(0.6)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(.white.opacity(0.18)).clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var actionsCard: some View {
        VStack(spacing: 8) {
            actionRow(icon: "magnifyingglass", title: "Track this load") {
                if let id = draft.postedLoadId {
                    NotificationCenter.default.post(
                        name: .eusoShipperNavSwap, object: nil,
                        userInfo: ["screenId": "260", "loadId": id]
                    )
                }
            }
            actionRow(icon: "doc.on.doc", title: "Save as template") {
                // Wire to loadTemplates.create when shipped (server gap §5).
            }
            actionRow(icon: "square.and.arrow.up", title: "Share with team") {
                // Sharing surface is iOS-native UIActivityViewController.
            }
            actionRow(icon: "plus.rectangle.on.rectangle", title: "Post another") {
                draft.reset()
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "250"])
            }
            actionRow(icon: "house.fill", title: "Back to dashboard") {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "200"])
            }
        }
    }

    private func actionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).font(.system(size: 14, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }
}

#Preview("254 · Success · Night") {
    let d = PostLoadDraft(); d.postedLoadNumber = "LD-260427-A38FB12C7E"
    return PostLoadSuccessScreen(theme: Theme.dark, draft: d)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("254 · Success · Afternoon") {
    let d = PostLoadDraft(); d.postedLoadNumber = "LD-260427-A38FB12C7E"
    return PostLoadSuccessScreen(theme: Theme.light, draft: d)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
