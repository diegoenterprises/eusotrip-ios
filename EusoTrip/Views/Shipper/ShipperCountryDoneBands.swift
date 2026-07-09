//
//  ShipperCountryDoneBands.swift
//  EusoTrip 2027 UI — Shipper TRUCK lane · tri-country COUNTRY-DONE band views
//  Ported from staging §shipper-countrydone-298B-222-220 (compile lane).
//
//  1:1 SwiftUI mirrors of the tri-country regime bands added to the Shipper
//  detention / live-tracking / rate-board SVG twins (Light + Dark).
//  DesignSystem primitives only (Theme.Palette, Brand, EType, Space,
//  LinearGradient.diagonal). Light/Dark resolve from the passed `theme`.
//
//  Data contracts:
//   • FreeTimeRegimeBand — per-country detention regime. US/CA/MX rows are
//     regime reference constants (OOIDA/TIA practice · CTA carrier tariff ·
//     SAT estadías). Live per-load recompute is a named gap handed to
//     the-oath: detentionAccessorials.getFreeTimeRegime(loadId, country).
//   • BorderWaitCorridorBand — nodes are REQUIRED (no static default):
//     callers build them from the live crossBorder.getBorderWaitTimes feed
//     and render an honest unavailable state when the feed is down.
//   • RateBasisByCorridorBand — rows are REQUIRED (no static default):
//     callers build FX lines from the live crossBorder.getExchangeRates feed.
//

import SwiftUI

// MARK: - model

struct CountryRegimeRow: Identifiable {
    let id = UUID()
    let code: String          // "US" | "CA" | "MX"
    let figure: String        // "2h · $75/hr" | "~1h · CAD" | "var · MXN"
    let basis: String         // "OOIDA / TIA · USD · active"
    let weight: CGFloat       // 0...1 — proportional grace bar fill (detention band only)
    let active: Bool
}

/// Canonical US/CA/MX detention-regime snapshot (regime reference constants,
/// mirrors the certified SVG). Live per-load figures land with
/// detentionAccessorials.getFreeTimeRegime (named gap).
let kFreeTimeRegime: [CountryRegimeRow] = [
    .init(code: "US", figure: "2h · $75/hr", basis: "OOIDA / TIA · USD · active", weight: 1.00, active: true),
    .init(code: "CA", figure: "~1h · CAD",   basis: "carrier tariff · CTA",       weight: 0.54, active: false),
    .init(code: "MX", figure: "var · MXN",   basis: "estadías · SAT/contrato",    weight: 0.77, active: false),
]

// MARK: - 298 · FREE-TIME REGIME · BY COUNTRY (proportional grace-bar ladder)

struct FreeTimeRegimeBand: View {
    let theme: Theme.Palette
    var rows: [CountryRegimeRow] = kFreeTimeRegime
    var trailing: String = "ACTIVE · US"

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("FREE-TIME REGIME · BY COUNTRY")
                    .font(EType.micro).tracking(0.7)
                    .foregroundColor(theme.textTertiary)
                Spacer()
                Text(trailing)
                    .font(EType.micro).tracking(0.4)
                    .foregroundColor(Brand.success)
            }
            HStack(alignment: .top, spacing: Space.s3) {
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(r.code)
                                .font(EType.micro)
                                .foregroundStyle(r.active ? AnyShapeStyle(LinearGradient.diagonal)
                                                          : AnyShapeStyle(theme.textSecondary))
                            Text(r.figure)
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundColor(theme.textPrimary)
                        }
                        Text(r.basis)
                            .font(.system(size: 8))
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(theme.textPrimary.opacity(0.16))
                                Capsule()
                                    .fill(r.active ? AnyShapeStyle(LinearGradient(
                                            colors: [Brand.warning, Brand.danger],
                                            startPoint: .leading, endPoint: .trailing))
                                                   : AnyShapeStyle(theme.textPrimary.opacity(0.16)))
                                    .frame(width: max(0, geo.size.width * r.weight))
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.bgCardSoft))
    }
}

// MARK: - 222 · BORDER-WAIT CORRIDOR (node-rail map overlay)

struct CrossingNode: Identifiable {
    let id = UUID()
    let label: String      // "US · CBP/ACE"
    let wait: String?      // "11 min" — nil for the origin node
    let tint: Color        // Brand.blue (CA) / Brand.warning-ish (MX) / gradient (US origin)
    let isDiamond: Bool
}

struct BorderWaitCorridorBand: View {
    let theme: Theme.Palette
    let nodes: [CrossingNode]   // live crossBorder.getBorderWaitTimes — no static default
    var live: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Text("BORDER-WAIT CORRIDOR · LAND CROSSINGS")
                    .font(EType.micro).tracking(0.6)
                    .foregroundColor(theme.textTertiary)
                Spacer()
                Circle().fill(live ? Brand.success : theme.textTertiary).frame(width: 5, height: 5)
                Text(live ? "LIVE" : "FEED DOWN")
                    .font(EType.micro)
                    .foregroundColor(live ? Brand.success : theme.textTertiary)
            }
            ZStack {
                Rectangle().fill(theme.textPrimary.opacity(0.12)).frame(height: 2)
                HStack {
                    ForEach(nodes) { n in
                        VStack(spacing: 4) {
                            if let w = n.wait {
                                Text(w)
                                    .font(.system(size: 8.5, weight: .heavy))
                                    .foregroundColor(n.tint)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(n.tint.opacity(0.14)))
                            } else {
                                Spacer().frame(height: 17)
                            }
                            nodeGlyph(n)
                            Text(n.label)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(theme.textSecondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(RoundedRectangle(cornerRadius: 16)
            .fill(theme.bgCard.opacity(0.96))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.borderFaint)))
    }

    @ViewBuilder private func nodeGlyph(_ n: CrossingNode) -> some View {
        if n.isDiamond {
            RoundedRectangle(cornerRadius: 2)
                .stroke(n.tint, lineWidth: 1.6)
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(45))
                .background(RoundedRectangle(cornerRadius: 2).fill(theme.bgCard).rotationEffect(.degrees(45)))
        } else {
            Circle().stroke(LinearGradient.primary, lineWidth: 1.8)
                .frame(width: 10, height: 10)
                .background(Circle().fill(theme.bgCard))
        }
    }
}

// MARK: - 220 · RATE BASIS · BY CORRIDOR (label/figure ledger)

struct CorridorBasisRow: Identifiable {
    let id = UUID()
    let corridor: String   // "US dom"
    let basis: String      // "USD · DOE diesel FSC"
    let tint: Color
    let trailing: String?  // real savings figure when one exists — nil otherwise
}

struct RateBasisByCorridorBand: View {
    let theme: Theme.Palette
    let rows: [CorridorBasisRow]   // live FX from crossBorder.getExchangeRates — no static default

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("RATE BASIS · BY CORRIDOR")
                .font(EType.micro).tracking(0.7)
                .foregroundColor(theme.textTertiary)
            ForEach(rows) { r in
                HStack(spacing: 8) {
                    Circle()
                        .fill(r.trailing != nil ? AnyShapeStyle(LinearGradient.diagonal)
                                                : AnyShapeStyle(r.tint))
                        .frame(width: 6, height: 6)
                    Text(r.corridor)
                        .font(EType.micro)
                        .foregroundColor(theme.textPrimary)
                    Text(r.basis)
                        .font(.system(size: 10))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer()
                    if let t = r.trailing {
                        Text(t)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(Brand.success)
                    }
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(RoundedRectangle(cornerRadius: 16).fill(Brand.success.opacity(0.10)))
    }
}

// MARK: - Previews

#Preview("Shipper country bands · Dark") {
    VStack(spacing: 14) {
        FreeTimeRegimeBand(theme: Theme.dark)
        BorderWaitCorridorBand(theme: Theme.dark, nodes: [
            .init(label: "US · CBP/ACE",           wait: nil,      tint: .clear,                isDiamond: false),
            .init(label: "Detroit–Windsor · CBSA", wait: "11 min", tint: Color(hex: 0x1473FF),  isDiamond: true),
            .init(label: "Laredo · SAT",           wait: "24 min", tint: Color(hex: 0xFF7A00),  isDiamond: true),
        ])
        RateBasisByCorridorBand(theme: Theme.dark, rows: [
            .init(corridor: "US dom",  basis: "USD · DOE diesel FSC",            tint: Color(hex: 0x1473FF), trailing: nil),
            .init(corridor: "US ↔ CA", basis: "CAD · Bank of Canada FX · NSC",   tint: Color(hex: 0x1473FF), trailing: nil),
            .init(corridor: "US → MX", basis: "MXN · Banxico FX · +IGI/IVA",     tint: Color(hex: 0xFF7A00), trailing: nil),
        ])
    }
    .padding()
    .background(Theme.dark.bgPage)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("Shipper country bands · Light") {
    VStack(spacing: 14) {
        FreeTimeRegimeBand(theme: Theme.light)
        BorderWaitCorridorBand(theme: Theme.light, nodes: [
            .init(label: "US · CBP/ACE",           wait: nil,     tint: .clear,               isDiamond: false),
            .init(label: "Detroit–Windsor · CBSA", wait: "8 min", tint: Color(hex: 0x1473FF), isDiamond: true),
        ], live: false)
        RateBasisByCorridorBand(theme: Theme.light, rows: [
            .init(corridor: "US dom",  basis: "USD · DOE diesel FSC",          tint: Color(hex: 0x1473FF), trailing: nil),
            .init(corridor: "US ↔ CA", basis: "CAD · Bank of Canada FX · NSC", tint: Color(hex: 0x1473FF), trailing: nil),
            .init(corridor: "US → MX", basis: "MXN · Banxico FX · +IGI/IVA",   tint: Color(hex: 0xFF7A00), trailing: nil),
        ])
    }
    .padding()
    .background(Theme.light.bgPage)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
