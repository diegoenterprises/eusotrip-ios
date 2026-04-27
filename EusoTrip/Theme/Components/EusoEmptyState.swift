//
//  EusoEmptyState.swift
//  EusoTrip
//
//  Branded empty / coming-soon state shown in place of seeded mock data.
//  The user has declared 0% mock data across the iOS app — every screen
//  that doesn't yet have a live backend wire must render this primitive
//  in place of hard-coded sample values.
//
//  Usage (backend up, empty result):
//
//      EusoEmptyState(
//          icon: Image(systemName: "dollarsign.circle"),
//          title: "No transactions yet",
//          subtitle: "Your wallet activity shows up here the moment a load clears.",
//          cta: (label: "Link bank account", action: { sheet = .linkBank })
//      )
//
//  Usage (Phase-3 backend missing):
//
//      EusoEmptyState(
//          icon: Image(systemName: "trophy"),
//          title: "Leaderboard going live soon",
//          subtitle: "We're lining up season standings — you'll see your rank the moment it ships.",
//          comingSoon: true
//      )
//
//  Reads against the dark gradient aesthetic — uses ActiveCard, palette,
//  LinearGradient.diagonal, EType, Space, Radius. Matches every other
//  card pane on the Me hub.
//

import SwiftUI

struct EusoEmptyState: View {
    @Environment(\.palette) var palette

    /// Pre-composed SF Symbol (or custom Image) rendered inside the
    /// gradient glyph chip. Passed as `Image` so callers can supply either
    /// an `Image(systemName:)` or a bundled asset without the primitive
    /// having to care which.
    let icon: Image

    /// Primary title — `EType.h2`, sentence case, centered.
    let title: String

    /// Secondary, numbers-first copy. Optional — some call-sites want a
    /// single-line "We couldn't find anything" and nothing more.
    let subtitle: String?

    /// Optional CTA rendered as the brand gradient button. `nil` = no CTA.
    let cta: CTA?

    /// When true, attach the "Coming soon" StatusPill — for surfaces
    /// whose backend isn't built yet. When false, no pill (the empty
    /// state is just "backend is up, there's nothing to show").
    let comingSoon: Bool

    init(
        icon: Image,
        title: String,
        subtitle: String? = nil,
        cta: CTA? = nil,
        comingSoon: Bool = false
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.cta = cta
        self.comingSoon = comingSoon
    }

    /// Convenience initializer — accepts an SF Symbol name so call-sites
    /// don't have to wrap every invocation in `Image(systemName: …)`.
    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        cta: CTA? = nil,
        comingSoon: Bool = false
    ) {
        self.init(
            icon: Image(systemName: systemImage),
            title: title,
            subtitle: subtitle,
            cta: cta,
            comingSoon: comingSoon
        )
    }

    // MARK: Nested types

    /// Label + closure tuple shape used by the optional CTA. Expressed as
    /// a named tuple so the spec signature
    /// `cta: (label: String, action: () -> Void)?` reads naturally at the
    /// call site.
    typealias CTA = (label: String, action: () -> Void)

    // MARK: Body

    var body: some View {
        ActiveCard {
            VStack(alignment: .center, spacing: Space.s4) {
                glyphChip
                VStack(spacing: Space.s2) {
                    Text(title)
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.center)
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(EType.body)
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let cta = cta {
                    CTAButton(title: cta.label, action: cta.action)
                        .padding(.top, Space.s2)
                }
                if comingSoon {
                    StatusPill(text: "Coming soon", kind: .info)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Empty. \(title). \(subtitle ?? "")")
        .accessibilityHint(cta?.label ?? "")
    }

    // MARK: Glyph

    private var glyphChip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintNeutral)
                .frame(width: 56, height: 56)
            icon
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
        }
    }
}

#Preview("Empty state · dark") {
    VStack(spacing: Space.s5) {
        EusoEmptyState(
            systemImage: "dollarsign.circle",
            title: "No transactions yet",
            subtitle: "Your wallet activity shows up here the moment a load clears.",
            cta: (label: "Link bank account", action: {})
        )

        EusoEmptyState(
            systemImage: "trophy",
            title: "Leaderboard going live soon",
            subtitle: "We're lining up season standings — you'll see your rank the moment it ships.",
            comingSoon: true
        )
    }
    .padding()
    .background(Color.black)
    .environment(\.palette, Theme.dark)
}
