//
//  ShipperCommodityKit.swift
//  EusoTrip 2027 — shared chrome for the Shipper commodity / cross-border
//  addenda ports (204D/E/F/G/H · 216C/E/G).
//
//  ANTI-GENERIC DOCTRINE: this kit carries ONLY the shared vocabulary that
//  every screen already shares with the golden flagships — the eyebrow +
//  back-chevron + 28pt title header, the single iridescent hairline, the
//  9/800 section label, the primary+secondary CTA pair, and the flat
//  card panel. Every HERO and every SECTION composition is drawn bespoke
//  inside each screen file (a dimension-envelope, a countdown dial, a
//  damage diagram, an inventory ledger, a WLL gauge, a fiscal-stamp, a
//  gate grid, a money ledger) — never templated. Composition follows
//  function; only the chrome is shared.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Header (eyebrow + id + back chevron + title + kebab + hairline)

/// The golden header block: `✦ ROLE · SECTION` eyebrow in the brand
/// gradient, the load id right-aligned in SF-Mono, a back chevron that
/// pops the shipper nav stack, the 28pt detail title, a kebab, then the
/// single iridescent hairline. Mirrors the SVG header (eyebrow @72,
/// chevron @90, title @116, hairline @138).
struct AddendaHeader: View {
    let eyebrow: String
    let idText: String
    let title: String
    /// Back action — defaults to the canonical shipper nav-stack pop.
    var onBack: () -> Void = {
        NotificationCenter.default.post(name: .eusoShipperNavBack, object: nil)
    }
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(eyebrow)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: Space.s3)
                Text(idText)
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)

            HStack(alignment: .center, spacing: Space.s2) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 24, height: 40, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text(title)
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: Space.s2)
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, 2)

            IridescentHairline()
                .padding(.top, Space.s3)
        }
    }
}

// MARK: - Section label (9/800 tracked tertiary)

struct SectionLabel: View {
    let text: String
    @Environment(\.palette) private var palette
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s5)
    }
}

// MARK: - Panel surface (flat card + hairline stroke)

extension View {
    /// Flat card surface reconciled to Theme.dark (`bgCardSoft` +
    /// `borderFaint`) — the port of the SVG `#1C2128 / white@0.08` panel.
    func addendaPanel(_ palette: Theme.Palette, radius: CGFloat = Radius.lg) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(palette.bgCardSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
    }
}

// MARK: - CTA pair (primary gradient + secondary glass)

/// The canonical bottom CTA pair. Primary is the brand `CTAButton`;
/// secondary is a glass button. "Message ESang" secondaries route through
/// the real `.eusoShippereSangTapped` channel (ESANG never fires a
/// mutation directly — it is the wake surface).
struct AddendaCTAPair: View {
    let primary: String
    let secondary: String
    var primaryLoading: Bool = false
    var onPrimary: () -> Void = {}
    /// Secondary defaults to opening the ESANG coach sheet.
    var onSecondary: () -> Void = {
        NotificationCenter.default.post(name: .eusoShippereSangTapped, object: nil)
    }
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: primary, action: onPrimary, isLoading: primaryLoading)
                .layoutPriority(1)
            Button(action: onSecondary) {
                Text(secondary)
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, Space.s3)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.s5)
    }
}

// MARK: - Degraded provider note

/// Honest "provider gap" strip — surfaces the live-fusion degraded copy
/// the SVG `<desc>` mandates (e.g. "clearance check pending (degraded)")
/// instead of a stale VERIFIED. Rendered only when a live call fails.
struct DegradedNote: View {
    let text: String
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.warning)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Brand.warning.opacity(0.10))
        )
        .padding(.horizontal, Space.s5)
    }
}

// MARK: - Shared status chip (SVG issued/pending/pass pill)

struct AddendaChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.18)))
    }
}

// MARK: - Icon chip (40×40 rounded tinted square)

struct AddendaIconChip: View {
    let systemImage: String
    let tint: Color
    var side: CGFloat = 40
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tint.opacity(0.18))
            .frame(width: side, height: side)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: side * 0.42, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

// MARK: - Monogram chip (40×40 rounded tinted square with initials)

struct AddendaMonogram: View {
    let text: String
    let tint: Color
    var side: CGFloat = 40
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tint.opacity(0.18))
            .frame(width: side, height: side)
            .overlay(
                Text(text)
                    .font(.system(size: side * 0.32, weight: .heavy))
                    .foregroundStyle(tint)
            )
    }
}
