//
//  GeminiAttributionBadge.swift
//  "Built on Gemini" attribution badge — IO 2026 P0-14.
//
//  Co-marketing badge surfaced in EusoTrip app headers, ESang
//  chat headers, the wallet AI-Ultra paywall, and the dev-docs
//  landing page. Every Gemini-backed UI surface that wants to
//  attribute the AI provenance drops this in.
//
//  Two display modes:
//    - `.compact` — small icon-only pill (header chrome, nav bars)
//    - `.full`    — icon + "Built on Gemini" wordmark (footer,
//                   paywall card, About screen, dev docs)
//
//  Trademark note: "Gemini" + "Gemini Ultra" are Google trademarks.
//  Per the IO 2026 brief, EusoTrip uses them under co-marketing
//  attribution. The wire `trademark` string is shipped from the
//  server in `aiHealth.getStatus → meta.trademark` for legal
//  audit visibility.
//
//  Drop into: EusoTrip/Views/Branding/GeminiAttributionBadge.swift
//

import SwiftUI

public enum GeminiBadgeStyle {
    case compact   // small icon-only pill
    case full      // icon + wordmark
    case footer    // long-form attribution line
}

public struct GeminiAttributionBadge: View {
    let style: GeminiBadgeStyle
    let tier: String   // "Gemini Ultra" by default

    public init(style: GeminiBadgeStyle = .compact, tier: String = "Gemini Ultra") {
        self.style = style
        self.tier = tier
    }

    public var body: some View {
        switch style {
        case .compact: compactPill
        case .full:    fullPill
        case .footer:  footerLine
        }
    }

    /// Icon-only gradient pill. Used in nav chrome where space is tight.
    private var compactPill: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.45, blue: 0.95),   // Gemini blue
                    Color(red: 0.66, green: 0.27, blue: 0.95),   // Gemini purple
                ],
                startPoint: .leading, endPoint: .trailing
            ), in: Capsule())
            .accessibilityLabel("Built on \(tier)")
    }

    /// Full pill — icon + "Built on Gemini" wordmark. Used on
    /// the wallet AI-Ultra paywall + About screen.
    private var fullPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .heavy))
            Text("BUILT ON ")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
            + Text(tier.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundColor(.white)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(LinearGradient(
            colors: [
                Color(red: 0.16, green: 0.45, blue: 0.95),
                Color(red: 0.66, green: 0.27, blue: 0.95),
            ],
            startPoint: .leading, endPoint: .trailing
        ), in: Capsule())
        .accessibilityLabel("Built on \(tier)")
    }

    /// Footer-style attribution line. Used on legal / About surfaces.
    private var footerLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 9))
                .foregroundStyle(LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.45, blue: 0.95),
                        Color(red: 0.66, green: 0.27, blue: 0.95),
                    ],
                    startPoint: .leading, endPoint: .trailing
                ))
            Text("Powered by ")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            + Text(tier)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            + Text(" · ")
                .font(.system(size: 10))
                .foregroundColor(.tertiaryLabel)
            + Text("Gemini™ is a trademark of Google LLC")
                .font(.system(size: 10))
                .foregroundColor(.tertiaryLabel)
        }
        .accessibilityLabel("Powered by \(tier). Gemini is a trademark of Google LLC.")
    }
}

// MARK: - Color helpers (avoid platform-specific UIColor / NSColor branching)

private extension Color {
    static var tertiaryLabel: Color { Color.secondary.opacity(0.5) }
}

// MARK: - Previews

#Preview("Compact · Dark") {
    HStack(spacing: 12) {
        GeminiAttributionBadge(style: .compact)
        GeminiAttributionBadge(style: .full)
    }
    .padding(20)
    .preferredColorScheme(.dark)
}

#Preview("Footer · Light") {
    VStack(spacing: 20) {
        GeminiAttributionBadge(style: .compact)
        GeminiAttributionBadge(style: .full)
        GeminiAttributionBadge(style: .footer)
    }
    .padding(20)
    .preferredColorScheme(.light)
}
