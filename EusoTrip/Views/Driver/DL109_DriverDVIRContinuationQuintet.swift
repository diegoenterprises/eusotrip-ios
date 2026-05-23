//
//  DL109_DriverDVIRContinuationQuintet.swift
//  EusoTrip — Driver · DVIR continuation quintet (DL109-DL113).
//
//  Pixel-match to:
//    109 Driver Pretrip DVIR Section 8 Ack
//    110 Driver Pretrip DVIR Section 9 Ack
//    111 Driver Pretrip DVIR Section 10 Ack
//    112 Driver Pretrip DVIR Section 11 Ack
//    113 Driver Pretrip DVIR Section 12 Ack
//
//  Continues the DVIR ack series begun at DL103-DL108 (S3-S7). All 5
//  share `DVIRSectionAckBody` parameterized by sectionsCompleted. Body
//  reads `loads.getById` + `inspections.getDVIRHistory`. Bottom nav
//  frozen.
//

import SwiftUI

private struct DLCLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let rate: String?
    let distance: Double?
}

private struct DLCDVIRRow: Decodable, Hashable {
    let id: Int?
    let status: String?
    let unitNumber: String?
    let make: String?
    let model: String?
}

private struct DVIRSectionAckShell<Content: View>: View {
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

private struct DVIRSectionAckBody: View {
    let loadId: String
    let sectionsCompleted: Int       // 8 / 9 / 10 / 11 / 12
    let citation: String              // "§315" / "§316" / …
    let elapsedSinceAccept: String    // "6:12" / "7:14" / …
    let pickupCountdownText: String   // "8h 00m" / "6h 58m" / …

    @Environment(\.palette) private var palette
    @State private var load: DLCLoadCtx?
    @State private var dvir: DLCDVIRRow?

    private let sectionTotal = 14
    private var progressPct: Double { Double(sectionsCompleted) / Double(sectionTotal) }
    private var pastMidpointPct: Int { Int((Double(sectionsCompleted) / Double(sectionTotal)) * 100) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                citationBanner
                progressCard
                identityRow
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx(); await loadDvir() }
        .refreshable { await loadCtx(); await loadDvir() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DRIVER · TRIPS · BACKHAUL · DVIR · S\(sectionsCompleted)").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Section \(sectionsCompleted) · acked").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            if let l = load {
                Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · \(l.pickupCity ?? "—") → \(l.destCity ?? "—")")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var citationBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(citation) · BACKHAUL DVIR · WITHIN-TRACK SECTION-\(sectionsCompleted)-ACK").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("§302 ACCEPTED · §\(citation.replacingOccurrences(of: "§", with: "")) DVIR ADVANCING · \(sectionsCompleted)/14 SECTIONS · \(elapsedSinceAccept) SINCE ACCEPT")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("LD-BH7C3A · PHX-LA · AWARDED · DVIR \(sectionsCompleted)/14 · \(pastMidpointPct)% PAST MIDPOINT").font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var progressCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("DVIR PROGRESS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(sectionsCompleted)/14 sections · \(pastMidpointPct)%").font(.caption2).foregroundStyle(palette.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(palette.bgPage).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient.diagonal)
                            .frame(width: max(8, geo.size.width * progressPct), height: 8)
                    }
                }
                .frame(height: 8)
                if let d = dvir {
                    Text("Live session · \(d.unitNumber ?? "unit") · \((d.make ?? "") + " " + (d.model ?? ""))")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                } else {
                    Text("Walk-around in progress · advancing live").font(.caption2).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("RM").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aurora Freight Lines · Renée Marquette").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("USDOT 3 482 119 · MC-942 008 · Cedar Rapids IA · senior dispatcher").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(String, String, String, Color)] = [
            ("PAYOUT",   "$\(load?.rate ?? "2,128")", "NET-30 LOCKED",                .green),
            ("RPM",      "$5.38",                      "\(Int(load?.distance ?? 372)) mi LOCKED", .blue),
            ("PICKUP",   pickupCountdownText,             "04:00 MST",                  .orange),
            ("DVIR",     "\(sectionsCompleted)/14",        "advancing · \(pastMidpointPct)%", sectionsCompleted >= 12 ? .green : .blue),
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
            switch sectionsCompleted {
            case 8:  return "Cab interior + brakes (S8) cleared. Coupling + air system (S9) up next."
            case 9:  return "Coupling + air system passed. Tire chains + emergency kit (S10) next."
            case 10: return "Emergency kit verified. Reefer + cargo seal (S11) next."
            case 11: return "Reefer + cargo seal logged. ELD + comms (S12) next."
            case 12: return "ELD + comms cleared — 86% done. Fuel + DEF (S13) up next; submit fires at S14."
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
    private func loadDvir() async {
        struct In: Encodable { let vehicleId: Int?; let limit: Int }
        do {
            let rows: [DLCDVIRRow] = try await EusoTripAPI.shared.query("inspections.getDVIRHistory", input: In(vehicleId: nil, limit: 1))
            dvir = rows.first
        } catch { /* */ }
    }
}

// MARK: - Screens (DL109-DL113)

struct DriverDVIRSection8Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DVIRSectionAckShell(theme: theme) {
            DVIRSectionAckBody(loadId: loadId, sectionsCompleted: 8, citation: "§315", elapsedSinceAccept: "6:12", pickupCountdownText: "8h 00m")
        }
    }
}
struct DriverDVIRSection9Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DVIRSectionAckShell(theme: theme) {
            DVIRSectionAckBody(loadId: loadId, sectionsCompleted: 9, citation: "§316", elapsedSinceAccept: "7:14", pickupCountdownText: "6h 58m")
        }
    }
}
struct DriverDVIRSection10Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DVIRSectionAckShell(theme: theme) {
            DVIRSectionAckBody(loadId: loadId, sectionsCompleted: 10, citation: "§317", elapsedSinceAccept: "8:16", pickupCountdownText: "5h 56m")
        }
    }
}
struct DriverDVIRSection11Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DVIRSectionAckShell(theme: theme) {
            DVIRSectionAckBody(loadId: loadId, sectionsCompleted: 11, citation: "§318", elapsedSinceAccept: "9:18", pickupCountdownText: "4h 54m")
        }
    }
}
struct DriverDVIRSection12Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DVIRSectionAckShell(theme: theme) {
            DVIRSectionAckBody(loadId: loadId, sectionsCompleted: 12, citation: "§319", elapsedSinceAccept: "10:20", pickupCountdownText: "3h 52m")
        }
    }
}

// MARK: - Previews

#Preview("DL109 S8 · Dark")   { DriverDVIRSection8Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL110 S9 · Light")  { DriverDVIRSection9Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL111 S10 · Dark")  { DriverDVIRSection10Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL112 S11 · Light") { DriverDVIRSection11Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL113 S12 · Dark")  { DriverDVIRSection12Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
