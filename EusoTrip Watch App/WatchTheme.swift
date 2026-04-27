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
    // Core Esang palette (wrist-optimised for legibility at arm's length)
    static let esangBlue      = Color(red: 0.16, green: 0.47, blue: 0.97)
    static let esangMagenta   = Color(red: 0.93, green: 0.30, blue: 0.64)
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
