//
//  EusoBadge.swift
//  EusoTrip — Unified capsule badge primitive (Patch #2, 2026-04-22)
//
//  Replaces the scatter of hand-rolled capsules across the Driver
//  surface: LoadBoardCard's HOT gradient pill, the REEFER / FLATBED /
//  HAZMAT equipment chips (previously `StatusPill`), the inline
//  "HOT LANE" text on LoadDetailSheet, HotZonesListSheet's
//  flame-in-circle ELEVATED marker, and the HaulLobbyTab role color
//  chips.
//
//  Signature (per Patch #2 spec):
//      EusoBadge(label: String,
//                kind:  EusoBadgeKind = .neutral,
//                icon:  Image?        = nil)
//
//  Kinds share one geometry:
//      • 8pt vertical padding via explicit 4pt top+bottom pad
//      • 8pt horizontal padding
//      • 4pt corner radius (uses a sharp rounded rect so every badge
//        — tinted, gradient, or outlined — has the same silhouette)
//      • Identical outline weight (1.25) for outlined variants
//      • Filled variants carry NO stroke
//
//  All kinds read as Brand tokens — no new hex values are introduced;
//  every color flows from `Brand.*` or `palette.tint*` already defined
//  in DesignSystem.swift.
//

import SwiftUI

// MARK: - Kind

enum EusoBadgeKind: Equatable {
    case info       // blue — equipment types, generic "live" markers
    case warning    // amber — warnings, cautions
    case hot        // blue→magenta gradient fill, white text — the canonical "HOT"
    case success    // green — positive status
    case neutral    // gray — fallback / inert
    case hazmat     // hazmat amber — 49 CFR placards, HM markers
}

// MARK: - EusoBadge

struct EusoBadge: View {

    // MARK: Input

    let label: String
    let kind: EusoBadgeKind
    let icon: Image?

    // MARK: Init

    init(
        label: String,
        kind: EusoBadgeKind = .neutral,
        icon: Image? = nil
    ) {
        self.label = label
        self.kind  = kind
        self.icon  = icon
    }

    // MARK: Environment

    @Environment(\.palette) private var palette

    // MARK: Body

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                icon
                    .font(.system(size: 9, weight: .heavy))
            }
            Text(label.uppercased())
                .font(EType.micro)
                .tracking(0.6)
        }
        .foregroundStyle(foregroundStyle)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(backgroundFill)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
    }

    // MARK: - Styling derived from `kind`

    /// Foreground color / gradient. `.hot` uses white-on-gradient so
    /// the fill reads as the hero chip everywhere it lands. All other
    /// kinds tint the label with the corresponding Brand token.
    private var foregroundStyle: AnyShapeStyle {
        switch kind {
        case .hot:     return AnyShapeStyle(Color.white)
        case .info:    return AnyShapeStyle(Brand.info)
        case .warning: return AnyShapeStyle(Brand.warning)
        case .success: return AnyShapeStyle(Brand.success)
        case .hazmat:  return AnyShapeStyle(Brand.hazmat)
        case .neutral: return AnyShapeStyle(palette.textSecondary)
        }
    }

    /// Background fill. `.hot` paints the full diagonal gradient so it
    /// matches the app-wide "HOT" treatment (LoadBoardCard,
    /// SuggestedLoadCard). All other kinds use the palette tint token
    /// so they adapt between dark (14% opacity) and light (10–12%).
    private var backgroundFill: AnyShapeStyle {
        switch kind {
        case .hot:     return AnyShapeStyle(LinearGradient.diagonal)
        case .info:    return AnyShapeStyle(palette.tintInfo)
        case .warning: return AnyShapeStyle(palette.tintWarning)
        case .success: return AnyShapeStyle(palette.tintSuccess)
        case .hazmat:  return AnyShapeStyle(palette.tintHazmat)
        case .neutral: return AnyShapeStyle(palette.tintNeutral)
        }
    }

    /// Accessibility readout — kind name gets folded in so VoiceOver
    /// users hear "HOT, hot badge" / "REEFER, info badge" rather than
    /// just the raw text label.
    private var accessibilityLabelText: String {
        let suffix: String
        switch kind {
        case .hot:     suffix = "hot badge"
        case .info:    suffix = "info badge"
        case .warning: suffix = "warning badge"
        case .success: suffix = "success badge"
        case .hazmat:  suffix = "hazmat badge"
        case .neutral: suffix = "badge"
        }
        return "\(label), \(suffix)"
    }
}
