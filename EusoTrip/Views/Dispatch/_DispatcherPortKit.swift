//
//  _DispatcherPortKit.swift
//  EusoTrip — shared chrome for the Dispatcher revenue-assurance ports
//  (538/540/541/542/543/544/545).
//
//  These are the small, repeated primitives every one of the seven ported
//  screens needs — the BOARD-current bottom nav, the DETAIL back chevron, and
//  the loading / error cards. Factored here so each screen file stays focused
//  on its bespoke composition. All bind the real Theme.Palette + Brand tokens;
//  no hardcoded drift.
//
//  Author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Money / number formatting (shared across the port band)

enum PortMoney {
    /// Full grouped dollars, no cents: "$182,400".
    static func full(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))")
    }
    /// Compact K/M: "$182.4K".
    static func compact(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if a >= 1_000 { return String(format: "$%.1fK", v / 1_000) }
        return "$\(Int(v.rounded()))"
    }
}

// MARK: - Dispatcher BOARD-current bottom nav
//
// Every screen in the 538-545 band is reached from the Board, so the real
// DispatchNavController enum renders with BOARD inked. Slot taps resolve
// through the env-injected dispatchNavHandler (Home→Disp400 · Board→Disp401 ·
// Comms→Dpch721 · Me→Dpch713); the orb routes to esang.chat.

struct DispatchPortNav: View {
    var body: some View {
        BottomNav(
            leading: [
                NavSlot(label: "Home",  systemImage: "house",                      isCurrent: false),
                NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill",    isCurrent: true),
            ],
            trailing: [
                NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                NavSlot(label: "Me",    systemImage: "person",                      isCurrent: false),
            ],
            orbState: .idle
        )
    }
}

// MARK: - DETAIL back chevron (routes to the Board)

struct DispatchPortBackChevron: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Button {
            DispatchNavDispatcher.handle("board")
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to board")
    }
}

// MARK: - Loading card

struct DispatchPortLoadingCard: View {
    @Environment(\.palette) private var palette
    let text: String
    var body: some View {
        HStack(spacing: Space.s3) {
            ProgressView().tint(palette.textSecondary)
            Text(text).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

// MARK: - Error card

struct DispatchPortErrorCard: View {
    @Environment(\.palette) private var palette
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Couldn't load this surface")
                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text(message).font(EType.caption).foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) {
                Text("Retry").font(EType.caption.weight(.heavy))
                    .foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, Space.s4).frame(height: 32)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain).padding(.top, Space.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - ESANG suggestion strip (calm-expert card; taps open esang.chat)
//
// Renders the house ESang orb + a derived, honest one-line recommendation and
// routes the tap THROUGH esang.chat (never a direct mutation) per the canonical
// voice-surface doctrine. `headline` / `detail` are always derived from the
// screen's real, already-loaded data.

struct DispatchPortESangStrip: View {
    @Environment(\.palette) private var palette
    let headline: String
    let detail: String

    var body: some View {
        Button {
            DispatchNavDispatcher.handle("esang")
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.7), .white.opacity(0)],
                                             center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 16))
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text(detail).font(.system(size: 11)).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}
