//
//  Glass.swift
//  EusoTrip — Glassmorphism primitives layered on top of DesignSystem.swift
//
//  Authority: §4 (surfaces) + §9 (ActiveCard rim) in the wireframe doctrine,
//  extended for auth-surface "premium" glass treatment.
//
//  All components obey the palette registry (@Environment(\.palette)) so they
//  flip between Night and Afternoon without any per-view conditionals.
//

import SwiftUI

// MARK: - GlassCard

/// Frosted card with a diagonal iridescent rim.  Use for sign-in, sign-up,
/// and forgot-password surfaces where we want a premium, floaty feel.
struct GlassCard<Content: View>: View {
    @Environment(\.palette) var palette
    var cornerRadius: CGFloat = Radius.xl
    var rim: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.bgCard.opacity(0.72))
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
            if rim {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(palette.borderSoft, lineWidth: 1)
            }
            content()
                .padding(Space.s5)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 40, x: 0, y: 22)
    }
}

// MARK: - GlassField

/// Text input styled as a glass pill.
struct GlassField: View {
    @Environment(\.palette) var palette
    let label: String
    let placeholder: String
    let icon: String?
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .never
    var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)

            HStack(spacing: Space.s2) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 20)
                }
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .textInputAutocapitalization(autocapitalization)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .autocorrectionDisabled(true)
            }
            .padding(.horizontal, Space.s4)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(error == nil ? palette.borderSoft : Brand.danger,
                                  lineWidth: error == nil ? 1 : 1.5)
            )
            if let error {
                Text(error)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
            }
        }
    }
}

// MARK: - GlassToggleRow

/// T&C / Privacy acceptance row with a custom gradient checkbox.
struct GlassToggleRow: View {
    @Environment(\.palette) var palette
    @Binding var isOn: Bool
    let title: String
    let linkTitle: String?
    let linkTapped: (() -> Void)?

    init(isOn: Binding<Bool>, title: String,
         linkTitle: String? = nil,
         linkTapped: (() -> Void)? = nil) {
        self._isOn = isOn
        self.title = title
        self.linkTitle = linkTitle
        self.linkTapped = linkTapped
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) { isOn.toggle() }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isOn ? Color.clear : palette.borderSoft, lineWidth: 1.2)
                    if isOn {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient.diagonal)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                if let linkTitle, let linkTapped {
                    Button(linkTitle, action: linkTapped)
                        .font(EType.caption)
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - eSangMark (neural-network logo)

/// Canonical EusoTrip / ESANG AI mark — outer iridescent ring plus a neural
/// constellation on an iridescent inner fill. Ported 1:1 from the web platform
/// `esang-ai-logo-hires.svg` (1024×1024 viewBox) and sized for any diameter.
struct eSangMark: View {
    var diameter: CGFloat = 96

    /// Scale from the SVG's 1024-unit coordinate system to the target diameter.
    private var s: CGFloat { diameter / 1024 }

    private var ringGradient: LinearGradient {
        LinearGradient(
            colors: [Brand.blue,
                     Color(red: 0.545, green: 0.361, blue: 0.965),
                     Brand.magenta],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var innerFill: RadialGradient {
        RadialGradient(
            colors: [
                Color(red: 0.545, green: 0.361, blue: 0.965).opacity(0.25),
                Brand.blue.opacity(0.12),
                Brand.magenta.opacity(0.05)
            ],
            center: .center,
            startRadius: 0, endRadius: 385 * s
        )
    }

    /// SVG neural-net node positions in native 1024-unit space, centered on (0,0).
    private struct Node { let x, y, r: CGFloat; let opacity: Double }
    private var nodes: [Node] {
        [
            // Cardinal (top/bottom — brightest)
            .init(x:    0, y: -180, r: 30, opacity: 1.00),
            .init(x:    0, y:  180, r: 30, opacity: 1.00),
            // Cardinal (left/right — slightly muted)
            .init(x: -205, y:    0, r: 22, opacity: 0.85),
            .init(x:  205, y:    0, r: 22, opacity: 0.85),
            // Diagonals
            .init(x: -155, y: -103, r: 26, opacity: 0.92),
            .init(x:  155, y: -103, r: 26, opacity: 0.92),
            .init(x: -155, y:  103, r: 26, opacity: 0.92),
            .init(x:  155, y:  103, r: 26, opacity: 0.92)
        ]
    }

    /// SVG line segments: (x1,y1) → (x2,y2), stroke width, opacity.
    private struct Edge { let x1, y1, x2, y2, w: CGFloat; let opacity: Double }
    private var edges: [Edge] {
        [
            // Primary spokes from center
            .init(x1: 0, y1: 0, x2:    0, y2: -180, w: 4.0, opacity: 0.65),
            .init(x1: 0, y1: 0, x2:    0, y2:  180, w: 4.0, opacity: 0.65),
            .init(x1: 0, y1: 0, x2: -155, y2: -103, w: 3.5, opacity: 0.55),
            .init(x1: 0, y1: 0, x2:  155, y2: -103, w: 3.5, opacity: 0.55),
            .init(x1: 0, y1: 0, x2: -155, y2:  103, w: 3.5, opacity: 0.55),
            .init(x1: 0, y1: 0, x2:  155, y2:  103, w: 3.5, opacity: 0.55),
            .init(x1: 0, y1: 0, x2: -205, y2:    0, w: 3.0, opacity: 0.45),
            .init(x1: 0, y1: 0, x2:  205, y2:    0, w: 3.0, opacity: 0.45),
            // Cross-links
            .init(x1: -155, y1: -103, x2:    0, y2: -180, w: 2.0, opacity: 0.32),
            .init(x1:  155, y1: -103, x2:    0, y2: -180, w: 2.0, opacity: 0.32),
            .init(x1: -155, y1:  103, x2:    0, y2:  180, w: 2.0, opacity: 0.32),
            .init(x1:  155, y1:  103, x2:    0, y2:  180, w: 2.0, opacity: 0.32),
            .init(x1: -205, y1:    0, x2: -155, y2: -103, w: 2.0, opacity: 0.32),
            .init(x1: -205, y1:    0, x2: -155, y2:  103, w: 2.0, opacity: 0.32),
            .init(x1:  205, y1:    0, x2:  155, y2: -103, w: 2.0, opacity: 0.32),
            .init(x1:  205, y1:    0, x2:  155, y2:  103, w: 2.0, opacity: 0.32),
            // Outer ring links
            .init(x1: -155, y1: -103, x2:  155, y2: -103, w: 1.5, opacity: 0.20),
            .init(x1: -155, y1:  103, x2:  155, y2:  103, w: 1.5, opacity: 0.20)
        ]
    }

    var body: some View {
        ZStack {
            // Outer iridescent ring (r=460, stroke 14, opacity 0.55)
            Circle()
                .strokeBorder(ringGradient, lineWidth: 14 * s)
                .opacity(0.55)
                .frame(width: 920 * s, height: 920 * s)

            // Dashed mid ring (r=420, stroke 2, opacity 0.25)
            Circle()
                .stroke(ringGradient,
                        style: StrokeStyle(lineWidth: 2 * s,
                                           dash: [4 * s, 10 * s]))
                .opacity(0.25)
                .frame(width: 840 * s, height: 840 * s)

            // Inner iridescent wash (r=385)
            Circle()
                .fill(innerFill)
                .frame(width: 770 * s, height: 770 * s)

            // Living particle swarm — replaces the static neural-net
            // constellation with the same additively-blended physics field
            // used in the BottomNav orb. Sized to the inner wash so the
            // outer rings frame it exactly as the SVG does.
            eSangParticleField(diameter: 770 * s)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("EusoTrip")
    }
}

// MARK: - GradientLogo

/// Centered EusoTrip lockup — flame/teardrop brand mark stacked above the wordmark.
/// Matches the web platform `/login` and `/register` headers. Uses the bundled
/// `EusoTripLogo` image asset (blue→purple→magenta flame with spiral core).
struct GradientLogo: View {
    @Environment(\.palette) var palette
    /// Diameter of the brand mark. Wordmark scales proportionally.
    var size: CGFloat = 96

    var body: some View {
        VStack(spacing: size * 0.14) {
            Image("EusoTripLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .shadow(color: Brand.magenta.opacity(0.35),
                        radius: size * 0.18, x: 0, y: size * 0.04)
                .accessibilityLabel("EusoTrip")
            VStack(spacing: 2) {
                Text("EusoTrip")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("BY EUSORONE TECHNOLOGIES")
                    .font(.system(size: size * 0.105, weight: .medium))
                    .tracking(size * 0.02)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - AuroraBackground

/// Multi-stop radial gradient backdrop with soft blue→magenta aurora blobs,
/// used behind auth surfaces.
struct AuroraBackground: View {
    @Environment(\.palette) var palette
    var body: some View {
        ZStack {
            palette.bgPage.ignoresSafeArea()

            Circle()
                .fill(Brand.blue.opacity(0.55))
                .frame(width: 380, height: 380)
                .blur(radius: 140)
                .offset(x: -120, y: -260)

            Circle()
                .fill(Brand.magenta.opacity(0.45))
                .frame(width: 340, height: 340)
                .blur(radius: 140)
                .offset(x: 150, y: 240)

            Rectangle()
                .fill(LinearGradient(
                    colors: [Color.black.opacity(0.35), Color.clear],
                    startPoint: .bottom, endPoint: .top))
                .ignoresSafeArea()
        }
    }
}
