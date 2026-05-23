//
//  DL133_DriverCELM04DVIRContinuationOctet.swift
//  EusoTrip — Driver · CEL M-04 DVIR continuation octet (DL133-DL140).
//
//  Pixel-match to:
//    133 Driver Pretrip DVIR Section 7 Ack Cel M04
//    134 Driver Pretrip DVIR Section 8 Ack Cel M04
//    135 Driver Pretrip DVIR Section 9 Ack Cel M04
//    136 Driver Pretrip DVIR Section 10 Ack Cel M04
//    137 Driver Pretrip DVIR Section 11 Ack Cel M04
//    138 Driver Pretrip DVIR Section 12 Ack Cel M04
//    139 Driver Pretrip DVIR Section 13 Ack Cel M04
//    140 Driver Pretrip DVIR Section 14 Submit Cel M04
//
//  Continues the CEL M-04 DVIR sequence (DL126-DL132 → DL133-DL140).
//  Single bundled file. Body reads `loads.getById`. Bottom nav frozen.
//

import SwiftUI

private struct CMDLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
}

private struct CELDVIRSection {
    let n: Int             // 7..14
    let citation: String   // "§378" …
    let label: String      // "EXHAUST & EMISSIONS"
    let isSubmit: Bool
}

private let CEL_SECTIONS: [Int: CELDVIRSection] = [
    7:  .init(n: 7,  citation: "§378", label: "EXHAUST & EMISSIONS",  isSubmit: false),
    8:  .init(n: 8,  citation: "§379", label: "FUEL SYSTEM",          isSubmit: false),
    9:  .init(n: 9,  citation: "§380", label: "ELECTRICAL & WIRING",  isSubmit: false),
    10: .init(n: 10, citation: "§381", label: "SUSPENSION & FRAME",   isSubmit: false),
    11: .init(n: 11, citation: "§382", label: "CARGO SECUREMENT",     isSubmit: false),
    12: .init(n: 12, citation: "§383", label: "DRIVER SEAT & BELTS",  isSubmit: false),
    13: .init(n: 13, citation: "§384", label: "CERTIFY",              isSubmit: false),
    14: .init(n: 14, citation: "§385", label: "SUBMITTED",            isSubmit: true),
]

private struct CELDVIRShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: DriverTab.home.label,  systemImage: DriverTab.home.systemImage,  isCurrent: false),
                          NavSlot(label: DriverTab.trips.label, systemImage: DriverTab.trips.systemImage, isCurrent: true)],
                trailing: [NavSlot(label: DriverTab.wallet.label, systemImage: DriverTab.wallet.systemImage, isCurrent: false),
                           NavSlot(label: DriverTab.me.label,     systemImage: DriverTab.me.systemImage,     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct CELDVIRBody: View {
    let loadId: String
    let sectionIndex: Int

    @Environment(\.palette) private var palette
    @State private var load: CMDLoadCtx?

    private var section: CELDVIRSection { CEL_SECTIONS[sectionIndex] ?? CEL_SECTIONS[7]! }
    private var pct: Double { Double(sectionIndex) / 14.0 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                citationPill
                progressCard
                identityRow
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DRIVER · TRIPS · DVIR · S\(sectionIndex) · CEL · M-04").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(section.isSubmit ? "Section \(sectionIndex) · submit" : "Section \(sectionIndex) · acked")
                .font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("DVIR · \(sectionIndex)/14 · \(section.isSubmit ? "COMPLETE" : "ADVANCING")")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var citationPill: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(section.citation) · DVIR \(section.isSubmit ? "COMPLETE" : "ADVANCING") · \(sectionIndex)/14 · \(section.label) \(section.isSubmit ? "" : "ACKED")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("CEL · DVIR dvir_t1747830000123 · \(sectionIndex)/14 sections · \(section.isSubmit ? "DVIR submitted" : "S\(sectionIndex) acked") 0:00 ago")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("LD-M-04 · ATL-CLT · JR runs DVIR · NC monitors · DU shipper").font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var progressCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("DVIR PROGRESS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(sectionIndex)/14 · \(Int(pct * 100))%").font(.caption2).foregroundStyle(palette.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(palette.bgPage).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient.diagonal)
                            .frame(width: max(8, geo.size.width * pct), height: 8)
                    }
                }
                .frame(height: 8)
                Text("dvir_t1747830000123 · CEL walk-around \(section.isSubmit ? "complete · submitted" : "in progress")").font(.caption2).foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("NC").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("CEL · Naomi Chen · dispatcher").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("Carolina Express Logistics · MC-712 944 · JR (driver) · DU (shipper)").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(String, String, String, Color)] = [
            ("DVIR",    "\(sectionIndex)/14",       section.label,           section.isSubmit ? .green : .blue),
            ("PAYOUT",  "$1,610",                    "LOCKED · CEL · §371",   .green),
            ("DIST",    "245 mi",                     "ATL → CLT · 53' Dry",  .blue),
            ("STATE",   section.isSubmit ? "COMPLETE" : "ADVANCING", section.isSubmit ? "submitted · §385" : section.citation, section.isSubmit ? .green : .blue),
        ]
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.0).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.1).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.3)
                    Text(k.2).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.3.opacity(0.3)))
            }
        }
    }

    private var nextStepCard: some View {
        let copy: String = {
            switch sectionIndex {
            case 7:  return "Exhaust & emissions cleared at the 50% midpoint. Fuel system (S8) up next."
            case 8:  return "Fuel system passed. Electrical & wiring (S9) next."
            case 9:  return "Electrical & wiring logged. Suspension & frame (S10) next."
            case 10: return "Suspension & frame cleared. Cargo securement (S11) next."
            case 11: return "Cargo securement passed. Driver seat & belts (S12) next."
            case 12: return "Driver seat & belts logged. Certify (S13) up next."
            case 13: return "Certify acked at 93%. S14 submits the full DVIR; ON-SITE arms on submission."
            case 14: return "DVIR submitted at §385. ON-SITE armed; gate-in fires next on dock 4A approach."
            default: return "Continue walk-around per §392."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
}

// MARK: - Screens (DL133-DL140)

struct DriverCELM04S7Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELDVIRShell(theme: theme) { CELDVIRBody(loadId: loadId, sectionIndex: 7) } }
}
struct DriverCELM04S8Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELDVIRShell(theme: theme) { CELDVIRBody(loadId: loadId, sectionIndex: 8) } }
}
struct DriverCELM04S9Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELDVIRShell(theme: theme) { CELDVIRBody(loadId: loadId, sectionIndex: 9) } }
}
struct DriverCELM04S10Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELDVIRShell(theme: theme) { CELDVIRBody(loadId: loadId, sectionIndex: 10) } }
}
struct DriverCELM04S11Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELDVIRShell(theme: theme) { CELDVIRBody(loadId: loadId, sectionIndex: 11) } }
}
struct DriverCELM04S12Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELDVIRShell(theme: theme) { CELDVIRBody(loadId: loadId, sectionIndex: 12) } }
}
struct DriverCELM04S13Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELDVIRShell(theme: theme) { CELDVIRBody(loadId: loadId, sectionIndex: 13) } }
}
struct DriverCELM04S14SubmitScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELDVIRShell(theme: theme) { CELDVIRBody(loadId: loadId, sectionIndex: 14) } }
}

// MARK: - Previews

#Preview("DL133 S7 · Dark")     { DriverCELM04S7Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL134 S8 · Light")    { DriverCELM04S8Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL135 S9 · Dark")     { DriverCELM04S9Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL136 S10 · Light")   { DriverCELM04S10Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL137 S11 · Dark")    { DriverCELM04S11Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL138 S12 · Light")   { DriverCELM04S12Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL139 S13 · Dark")    { DriverCELM04S13Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL140 Submit · Light"){ DriverCELM04S14SubmitScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
