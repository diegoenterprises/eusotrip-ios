//
//  VesselTriCountryAuthorityBand.swift
//  EusoTrip 2027 · 06 Vessel · COUNTRY-DONE shared component (ported from staging, compile lane)
//
//  Reusable 1:1 Swift mirror of the SVG "country segment + tri-country authority band" added to the
//  vessel customs/port cluster (672 USCG Port Entry · 678 Port State Control · 748 Cross-Border
//  Clearance · 814 Customs Entry Filing) and reused by the money band (658 · 684 · 700 · 665 · 741).
//  One country is ACTIVE; all three are encoded + gated, which is what takes a US-only screen to
//  COUNTRY-DONE.
//
//  Backing (named-gap, surfaced to the-oath): vessel.getArrivalRegime / getPscRegime /
//  getClearanceRegime / getEntryRegime ({id, country}) -> {authority, instrument, timing/levy,
//  consequence, currency}. Until those land, the rows render the screen's regime reference model
//  (same as the certified SVG). US row data is real today (vessel-native procedures); CA/MX exist
//  only in the cross-border router, so they paint STANDBY.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Model

enum RegimeState { case active, standby }

struct CountryRegime: Identifiable {
    let id = UUID()
    let code: String          // "US" | "CA" | "MX"
    let authority: String     // e.g. "USCG · NVMC eNOA"
    let detail: String        // e.g. "−96h pre-arrival · 33 CFR 160 · USD"
    let consequence: String?  // right-top accent, e.g. "$25k+/day" (nil to hide)
    let state: RegimeState
}

struct CountryChip: Identifiable {
    let id = UUID()
    let code: String          // "US · USCG"
    let instrument: String    // "eNOA 96-HR"
    let active: Bool
}

// MARK: - Country segment (3 capsules, drives the active regime)

struct CountrySegment: View {
    @Environment(\.palette) private var palette
    let chips: [CountryChip]
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(chips) { chip in
                VStack(spacing: 2) {
                    Text(chip.code).font(.system(size: 11, weight: .heavy))
                    Text(chip.instrument).font(.system(size: 8, weight: .bold))
                        .opacity(chip.active ? 0.85 : 1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .foregroundStyle(chip.active ? Color.white : palette.textSecondary)
                .background {
                    if chip.active {
                        Capsule().fill(LinearGradient.primary)
                    } else {
                        Capsule().fill(palette.bgCard)
                            .overlay(Capsule().stroke(palette.borderFaint, lineWidth: 1))
                    }
                }
                .contentShape(Capsule())
                .onTapGesture { onSelect(chip.code) }
            }
        }
    }
}

// MARK: - Tri-country authority band (one card, 3 rows, active row tinted)

struct TriCountryAuthorityBand: View {
    @Environment(\.palette) private var palette
    let title: String              // section eyebrow, e.g. "TRI-COUNTRY PORT ENTRY · ARRIVAL AUTHORITY"
    let regimes: [CountryRegime]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).kerning(1)
                .foregroundStyle(palette.textSecondary)
            VStack(spacing: 0) {
                ForEach(Array(regimes.enumerated()), id: \.element.id) { idx, r in
                    row(r)
                    if idx < regimes.count - 1 {
                        Divider().overlay(palette.borderFaint.opacity(0.6))
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.borderFaint, lineWidth: 1)))
        }
    }

    @ViewBuilder private func row(_ r: CountryRegime) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(r.code)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(r.state == .active ? Color.white : palette.textSecondary)
                .frame(width: 26, height: 24)
                .background {
                    if r.state == .active { RoundedRectangle(cornerRadius: 7).fill(LinearGradient.primary) }
                    else { RoundedRectangle(cornerRadius: 7).fill(palette.textPrimary.opacity(0.06)) }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(r.authority).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(r.detail).font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let c = r.consequence {
                    Text(c).font(.system(size: 10.5, weight: .heavy))
                        .foregroundStyle(r.state == .active ? Brand.danger : palette.textSecondary)
                }
                if r.state == .active {
                    Text("● ACTIVE").font(.system(size: 8.5, weight: .heavy)).kerning(0.4)
                        .foregroundStyle(Brand.blue)
                } else {
                    Text("STANDBY").font(.system(size: 8.5, weight: .heavy)).kerning(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(r.state == .active ? AnyShapeStyle(LinearGradient.primary.opacity(0.10))
                                       : AnyShapeStyle(Color.clear))
    }
}

// MARK: - Mutual-recognition moat strip (customs/filing surfaces only — 814, advance-filing 751/663)

struct AeoMutualRecognitionStrip: View {
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MUTUAL RECOGNITION · USMCA AEO FAST-LANE")
                .font(.system(size: 9, weight: .heavy)).kerning(1)
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: 8) {
                aeoChip("CTPAT", "US · Tier 2", active: true)
                Text("⇄").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textSecondary)
                aeoChip("PIP", "CA · CBSA", active: false)
                Text("⇄").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textSecondary)
                aeoChip("OEA", "MX · SAT", active: false)
                Spacer(minLength: 6)
                VStack(spacing: 2) {
                    Text("−40% EXAM").font(.system(size: 9, weight: .heavy))
                    Text("priority lane").font(.system(size: 7.5, weight: .bold))
                }
                .foregroundStyle(Brand.success)
                .frame(width: 84, height: 28)
                .background(RoundedRectangle(cornerRadius: 9).fill(Brand.success.opacity(0.12)))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 15).fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(palette.borderFaint, lineWidth: 1)))
        }
    }

    @ViewBuilder private func aeoChip(_ t: String, _ s: String, active: Bool) -> some View {
        VStack(spacing: 1) {
            Text(t).font(.system(size: 9.5, weight: .heavy))
            Text(s).font(.system(size: 7.5, weight: .bold)).opacity(active ? 0.85 : 1)
        }
        .foregroundStyle(active ? Color.white : palette.textSecondary)
        .frame(width: 74, height: 28)
        .background {
            if active { RoundedRectangle(cornerRadius: 9).fill(LinearGradient.primary) }
            else { RoundedRectangle(cornerRadius: 9).fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.borderFaint, lineWidth: 1)) }
        }
    }
}

// MARK: - Previews

#Preview("Tri-country band · Dark") {
    VStack(spacing: 16) {
        CountrySegment(chips: [
            .init(code: "US · USCG", instrument: "eNOA 96-HR", active: true),
            .init(code: "CA · TC MARINE", instrument: "PAIR 96-HR", active: false),
            .init(code: "MX · SEMAR", instrument: "ARRIBO · DESPACHO", active: false)])
        TriCountryAuthorityBand(title: "TRI-COUNTRY PORT ENTRY · ARRIVAL AUTHORITY", regimes: [
            .init(code: "US", authority: "USCG · NVMC eNOA", detail: "−96h pre-arrival · 33 CFR 160 · USD", consequence: "$25k+/day", state: .active),
            .init(code: "CA", authority: "TC Marine · 96-hr PAIR", detail: "MTSR + CBSA ACI · pre-arrival · CAD", consequence: "C$ penalty", state: .standby),
            .init(code: "MX", authority: "SEMAR · Arribo / Despacho", detail: "Ley Nav. · Capitania · agente naval · MXN", consequence: "agente naval", state: .standby)])
        AeoMutualRecognitionStrip()
    }
    .padding()
    .background(Theme.dark.bgPage)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("Tri-country band · Light") {
    VStack(spacing: 16) {
        CountrySegment(chips: [
            .init(code: "US · CBP", instrument: "7501 · HTSUS", active: true),
            .init(code: "CA · CBSA", instrument: "B3 · CARM", active: false),
            .init(code: "MX · SAT", instrument: "PEDIMENTO A1", active: false)])
        TriCountryAuthorityBand(title: "TRI-COUNTRY ENTRY · DUTY + TAX REGIME", regimes: [
            .init(code: "US", authority: "CBP · 7501 · HTSUS", detail: "2.8% ad val · MPF/HMF · USD", consequence: nil, state: .active),
            .init(code: "CA", authority: "CBSA · B3 · CARM", detail: "duty + 5% GST · CAD", consequence: nil, state: .standby),
            .init(code: "MX", authority: "SAT · Pedimento A1", detail: "IGI + 16% IVA + DTA · MXN", consequence: nil, state: .standby)])
        AeoMutualRecognitionStrip()
    }
    .padding()
    .background(Theme.light.bgPage)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
