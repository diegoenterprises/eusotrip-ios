//
//  VesselCustomsKit.swift
//  EusoTrip — shared chrome for the Vessel Operator customs / booking band
//  (screens 826 / 827 / 828 / 829 / 830 / 831 / 832 / 833).
//
//  Two repeated primitives every screen in this band shares: the small
//  section header (label + right-aligned mono wiring caption, e.g.
//  "STUB · getSlotAllocation") and the tri-country REGULATOR band (US / CA /
//  MX authority rows, exactly one ACTIVE and two STANDBY). Extracted so the
//  eight customs screens read as one designer's work — the header (✦ eyebrow
//  + back chevron + title + hairline), error card, and honest-gap note come
//  from VesselTradeKit.swift.
//

import SwiftUI

// NOTE: the section header (`VesselSectionHeader(label:right:)`) is shared —
// it lives in VesselDocKit.swift; this band reuses it.

// MARK: - Regulator row model + tri-country band

/// One authority row in the REGULATOR band. Exactly one row per band is
/// `active` (the country whose regime governs this screen); the other two
/// sit on STANDBY. Country is content inside the screen, never a file fork
/// (single-country-per-screen doctrine).
struct VesselRegulatorRow: Identifiable {
    let id = UUID()
    let country: String   // "US" / "CA" / "MX"
    let text: String      // authority + regulation summary
    let active: Bool

    init(_ country: String, _ text: String, active: Bool = false) {
        self.country = country
        self.text = text
        self.active = active
    }
}

/// Tri-country regulator band — the "single active gated" footer every
/// customs screen carries. Renders a country chip, the authority line, and an
/// ACTIVE (green dot) / STANDBY status per row.
struct VesselRegulatorBand: View {
    @Environment(\.palette) private var palette
    let title: String
    var reference: String? = nil
    let rows: [VesselRegulatorRow]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: title, right: reference)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    if idx > 0 { Divider().overlay(palette.borderFaint) }
                    regulatorRow(row)
                }
            }
            .padding(.vertical, Space.s2)
            .padding(.horizontal, Space.s4)
            .frame(maxWidth: .infinity)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func regulatorRow(_ row: VesselRegulatorRow) -> some View {
        HStack(spacing: Space.s3) {
            Text(row.country)
                .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                .foregroundStyle(row.active ? .white : palette.textTertiary)
                .frame(width: 26, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(row.active ? AnyShapeStyle(LinearGradient.primary)
                              : AnyShapeStyle(palette.tintNeutral))
                )
            Text(row.text)
                .font(.system(size: 11, weight: row.active ? .semibold : .regular))
                .foregroundStyle(row.active ? palette.textPrimary : palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            if row.active {
                HStack(spacing: 5) {
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                    Text("ACTIVE")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.success)
                }
            } else {
                Text("STANDBY")
                    .font(.system(size: 8, weight: .bold)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, Space.s3)
    }
}

// MARK: - Hero shell (cardRim gradient rim + inset fill)

/// The golden hero surface: a blue→magenta gradient rim with an inset card
/// fill, matching the canonical SVG `url(#cardRim)` outer + `#141928` inset.
/// Feature-weight so it reads as the screen's anchor.
struct VesselHeroCard<Content: View>: View {
    @Environment(\.palette) private var palette
    var cornerRadius: CGFloat = Radius.xl
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
    }
}

// MARK: - Plain card group (bgCard + faint border) for ledgers / queues

struct VesselGroupCard<Content: View>: View {
    @Environment(\.palette) private var palette
    var cornerRadius: CGFloat = Radius.lg
    var padded: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padded ? Space.s4 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Summary strip (the slate footer bar every ledger closes with)

/// The `#232932` full-width strip a ledger closes with — a left label and a
/// right emphasis figure (e.g. "Zone balance · 92 TEU" / "9 withdrawn").
struct VesselSummaryStrip: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                .foregroundStyle(valueColor ?? palette.textPrimary)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Secondary (ghost) CTA — pairs with CTAButton in the action row

struct VesselGhostButton: View {
    @Environment(\.palette) private var palette
    let title: String
    var width: CGFloat? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: width ?? .infinity, minHeight: 52)
                .padding(.horizontal, width == nil ? 0 : Space.s3)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
