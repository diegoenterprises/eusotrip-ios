//
//  430_IndustryVerticals.swift
//  EusoTrip — Shipper · Industry verticals (vertical-specific workflows).
//

import SwiftUI

struct IndustryVerticalsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VerticalsBody() } nav: { shipperLifecycleNav() }
    }
}

private struct VerticalsBody: View {
    @Environment(\.palette) private var palette

    private let verticals: [(key: String, label: String, icon: String, sub: String)] = [
        ("petroleum",   "Petroleum",   "drop.triangle",     "MC-306 / MC-307 / MC-331 · UN1203 / UN1075 / UN1005 · ERG #128 / #115 / #125"),
        ("chemicals",   "Chemicals",   "atom",                "Class 3 / 6.1 / 8 · CHEMTREC required · vapor recovery"),
        ("pharma",      "Pharma",      "cross.case.fill",     "Reefer 35–46°F · GxP audit trail · DSCSA · cold-chain temp log"),
        ("agriculture", "Agriculture", "leaf",                "Reefer 33–38°F · FSMA · pre-cool required · grain BOL"),
        ("automotive",  "Automotive",  "car.fill",            "VIN-tracked · auto rack · damage report on every leg"),
        ("retail",      "Retail",      "bag.fill",            "Big-box appointment compliance · OS&D claims · UPC scan"),
        ("construction","Construction","hammer.fill",         "Flatbed · oversize permits · J.J. Keller integration"),
        ("energy",      "Energy",      "bolt.fill",           "MC-331 NH₃ · escort · pilot car · 49 CFR 397 corridor"),
        ("food_grade",  "Food grade",  "fork.knife",          "Multi-temp reefer · sanitary BOL · FSMA chain-of-custody"),
        ("hazmat",      "Hazmat",      "triangle.fill",       "All hazmat verticals · USMCA / VUCEM / NOM / ADR / IMDG"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                ForEach(verticals, id: \.key) { v in
                    LifecycleCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: v.icon).font(.system(size: 22, weight: .heavy)).foregroundStyle(LinearGradient.diagonal).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(v.label).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                                Text(v.sub).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "building.2.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · INDUSTRY VERTICALS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Vertical workflows").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Each vertical sets defaults on Post-a-Load: equipment, hazmat fields, regulatory chips, BOL template, accessorial allow-list.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("430 · Verticals · Night") { IndustryVerticalsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("430 · Verticals · Afternoon") { IndustryVerticalsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
