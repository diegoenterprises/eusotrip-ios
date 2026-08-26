//
//  VesselDetentionKit.swift
//  EusoTrip — Vessel Operator · shared chrome for the detention / demurrage
//  cluster (783 / 785 / 786 / 787 / 788 / 790 / 791 / 793).
//
//  This Kit holds ONLY the invariant chrome those eight screens share — the
//  Compliance-active bottom nav, the ✦ eyebrow, the KPI tile, the tri-country
//  free-time-regime footer, and the money/time formatters. Every screen's
//  HERO and LEDGER composition stays bespoke to its own job (a live clock, an
//  aged worklist, a rules engine, a ranked bar chart, a selectable batch); the
//  Kit is the shared VOCABULARY, never a shared skeleton. All symbols are
//  `VDetn`-prefixed so they never collide with per-screen file-scoped helpers.
//
//  No data, no networking — pure presentation primitives bound to the real
//  DesignSystem tokens (Brand / Theme.Palette / EType / Space / Radius).
//

import SwiftUI

// MARK: - Bottom nav (Vessel Operator · Compliance/Shipments active)

/// The canonical Vessel-Operator dock for the detention cluster. Only which
/// tab reads current varies across the eight screens, so it is the single
/// parameter. Slot taps resolve through the env-injected
/// `vesselOperatorNavHandler` exactly like every other Vessel surface.
struct VesselDetnNav: View {
    enum Tab { case shipments, compliance }
    let active: Tab
    var body: some View {
        BottomNav(
            leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                      NavSlot(label: "Shipments", systemImage: "shippingbox",  isCurrent: active == .shipments)],
            trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: active == .compliance),
                       NavSlot(label: "Me",          systemImage: "person",           isCurrent: false)],
            orbState: .idle
        )
    }
}

// MARK: - Eyebrow (✦ VESSEL OPERATOR · SECTION  —  caption)

struct VDetnEyebrow: View {
    let section: String
    let caption: String
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text("VESSEL OPERATOR · \(section)")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text(caption)
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }
}

// MARK: - Section label (small-caps header + trailing meta)

struct VDetnSectionLabel: View {
    let title: String
    var trailing: String? = nil
    var trailingTint: Color? = nil
    @Environment(\.palette) private var palette
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: trailingTint == nil ? .regular : .bold))
                    .foregroundStyle(trailingTint ?? palette.textSecondary)
            }
        }
    }
}

// MARK: - KPI tile (shared vocabulary — content drives the layout)

/// A single KPI cell. The first + one accent cell in each strip fill with the
/// diagonal brand gradient (the "this is the number that matters" signal); the
/// rest are slate cards. `sub` is the tiny caption under the value.
struct VDetnKPICell: View {
    let label: String
    let value: String
    var sub: String? = nil
    var gradient: Bool = false
    var valueTint: Color? = nil
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(gradient ? AnyShapeStyle(Color.white)
                                          : AnyShapeStyle(valueTint ?? palette.textPrimary))
                .lineLimit(1).minimumScaleFactor(0.6)
            if let sub {
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(gradient ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(gradient ? Color.clear : palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Chips + pills

struct VDetnChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.18)))
    }
}

struct VDetnPill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
    }
}

/// 40×40 rounded status icon chip used at the head of every ledger row.
struct VDetnIconChip: View {
    let systemImage: String
    let color: Color
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.18)))
    }
}

// MARK: - Tri-country free-time-regime footer

/// The "COUNTRY-DONE" band the money boards close on: the active discharge
/// jurisdiction's per-diem regime plus the two standby alternates. Content
/// varies per screen (FMC vs CTA vs SAT wording, USD/CAD/MXN) — the layout is
/// the shared chrome.
struct VDetnRegimeStrip: View {
    struct Regime: Identifiable {
        let id = UUID()
        let code: String     // "US" / "CA" / "MX"
        let name: String     // "FMC · per-diem per carrier tariff"
        let money: String    // "USD"
    }
    let title: String
    let active: Regime
    let standby: [Regime]
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            regimeRow(active, isActive: true)
            HStack(spacing: 8) {
                ForEach(standby) { regimeRow($0, isActive: false) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func regimeRow(_ r: Regime, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Text(r.code)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(isActive ? Color.white : palette.textSecondary)
                .frame(width: 22, height: 14)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? AnyShapeStyle(LinearGradient.primary)
                                   : AnyShapeStyle(Color.white.opacity(0.08))))
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name)
                    .font(.system(size: isActive ? 9.5 : 8.5, weight: isActive ? .bold : .regular))
                    .foregroundStyle(isActive ? palette.textPrimary : palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if isActive {
                    Text(r.money)
                        .font(.system(size: 8))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if !isActive { Spacer(minLength: 0) }
            if isActive {
                Spacer(minLength: 0)
                Text("● ACTIVE")
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.info)
            }
        }
        .padding(.horizontal, isActive ? 8 : 8).padding(.vertical, isActive ? 6 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(isActive ? AnyShapeStyle(LinearGradient.esangSoft) : AnyShapeStyle(Color.white.opacity(0.03))))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(palette.borderFaint, lineWidth: isActive ? 0 : 1))
    }
}

// MARK: - Formatters

enum VDetn {
    static func money(_ v: Double) -> String {
        "$" + Int(v.rounded()).formatted(.number.grouping(.automatic))
    }
    /// Compact "$6.8K" for tight KPI cells.
    static func moneyK(_ v: Double) -> String {
        if abs(v) >= 1000 {
            let k = (v / 1000)
            return "$" + String(format: "%.1fK", k)
        }
        return money(v)
    }
    /// Minutes → "7h 20m" / "35m".
    static func hoursMin(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h \(String(format: "%02dm", m % 60))"
    }
    /// Minutes → compact "6.3h" for averages.
    static func avgHours(_ minutes: Int) -> String {
        String(format: "%.1fh", Double(max(0, minutes)) / 60.0)
    }
    static func days(_ d: Int) -> String { "\(max(0, d))d" }
}
