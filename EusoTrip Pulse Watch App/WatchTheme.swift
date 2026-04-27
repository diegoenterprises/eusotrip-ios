//
//  WatchTheme.swift
//  EusoTrip Watch App
//
//  Design tokens. Matches the iOS EusoTrip Brand palette so the
//  wrist/phone feel like one product. Keep this file small — the wrist
//  is a glance surface, so we lean on SF Symbols + a tight palette
//  instead of a full theming system.
//

import SwiftUI

extension Color {
    // Core Esang palette — aligned 1:1 with iOS `Brand.blue` (0x1473FF)
    // and `Brand.magenta` (0xBE01FF) from EusoTrip/Theme/DesignSystem.swift.
    // Previously the watch tokens skewed toward a hot pink (magenta RGB
    // 0.93/0.30/0.64) which made the idle orb, buttons, glow, and brand
    // hairline read pink on-wrist while the phone app read blue→purple.
    // Anchoring to the phone's hex values keeps the two surfaces feeling
    // like one product.
    static let esangBlue      = Color(red: 0.08, green: 0.45, blue: 1.00)
    static let esangMagenta   = Color(red: 0.75, green: 0.00, blue: 1.00)
    static let esangGreen     = Color(red: 0.15, green: 0.80, blue: 0.45)
    static let esangAmber     = Color(red: 1.00, green: 0.72, blue: 0.25)
    static let esangDanger    = Color(red: 1.00, green: 0.40, blue: 0.38)
    static let esangListening = Color(red: 1.00, green: 0.38, blue: 0.42)
    static let esangHazmat    = Color(red: 0.98, green: 0.70, blue: 0.10)

    // Neutrals
    static let esangBg        = Color.black
    static let esangCard      = Color(white: 0.10)
    static let esangBorder    = Color(white: 0.20)
    static let esangText      = Color.white
    static let esangTextDim   = Color(white: 0.72)
}

extension LinearGradient {
    static var esangPrimary: LinearGradient {
        LinearGradient(
            colors: [.esangBlue, .esangMagenta],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    static var esangDanger: LinearGradient {
        LinearGradient(
            colors: [.esangDanger, .esangMagenta],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    static var esangSuccess: LinearGradient {
        LinearGradient(
            colors: [.esangGreen, .esangBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Corner radius tokens
enum R { static let sm: CGFloat = 8; static let md: CGFloat = 12; static let lg: CGFloat = 16 }

/// Spacing tokens
enum S { static let s1: CGFloat = 4; static let s2: CGFloat = 8; static let s3: CGFloat = 12; static let s4: CGFloat = 16 }

// MARK: - Brand background

/// The Home (orb) tab paints a soft radial halo behind its content so the
/// rounded watch bezel "lights up" the corners — that's why the orb tab
/// reads as edge-to-edge while rectangular tabs (HOS rings, eDVIR tile
/// grid, list boards) used to read as letterboxed cards. Apply this
/// modifier on every watch tab so they share the same edge-glow language
/// and the bezel's curve looks intentional, not clipped.
struct WatchEdgeGlowBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.esangBg
                    RadialGradient(
                        colors: [.esangMagenta.opacity(0.22), .esangBlue.opacity(0.08), .clear],
                        center: .init(x: 0.5, y: 0.45),
                        startRadius: 2,
                        endRadius: 220
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            )
    }
}

extension View {
    /// Pour the same brand halo HomeView uses behind any watch tab so the
    /// bezel's rounded corners feel illuminated, not letterboxed.
    func watchEdgeGlow() -> some View { modifier(WatchEdgeGlowBackground()) }
}
