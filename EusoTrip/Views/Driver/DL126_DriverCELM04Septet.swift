//
//  DL126_DriverCELM04Septet.swift
//  EusoTrip — Driver · CEL M-04 septet (DL126-DL132).
//
//  Pixel-match to:
//    126 Driver Assigned Receipt Cel M04
//    127 Driver Pretrip DVIR Section 1 Ack Cel M04
//    128 Driver Pretrip DVIR Section 2 Ack Cel M04
//    129 Driver Pretrip DVIR Section 3 Ack Cel M04
//    130 Driver Pretrip DVIR Section 4 Ack Cel M04
//    131 Driver Pretrip DVIR Section 5 Ack Cel M04
//    132 Driver Pretrip DVIR Section 6 Ack Cel M04
//
//  Carrier-side counterpart to the SH261-SH269 M-04 scenario, framed
//  from the driver's vantage. Cast: JR (driver) / NC (CEL dispatcher
//  Naomi Chen) / DU (shipper). Atlanta → Charlotte · 245 mi · 53'
//  Dry Van · CEL fleet. Single bundled file. All 7 share
//  `CELM04Body`. Body reads `loads.getById`. Bottom nav frozen.
//

import SwiftUI

private struct CMELoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let rate: String?
    let distance: Double?
    let equipmentType: String?
    let driver: CMEParty?
    let catalyst: CMEParty?
    let shipper: CMEParty?
    struct CMEParty: Decodable, Hashable {
        let id: Int?
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
    }
}

enum CELM04Kind: String {
    case assignedReceipt, s1, s2, s3, s4, s5, s6
}

/// Stage-only labels — no scenario data baked in. The view body
/// composes these with `load.loadNumber` / `load.driver` / etc.
/// at render time.
private struct CEConfig {
    let eyebrowStage: String     // "ASSIGNED" / "DVIR · S1" / …
    let citation: String         // §number canonical stage citation
    let title: String            // UX title
    let subhead: String          // stage state line
    let stageNote: String        // composed after carrier + loadNumber
    let chainNote: String        // composed after loadNumber + parties
    let sectionsCompleted: Int   // 0 (assigned) / 1-6 (DVIR)
}

private extension CELM04Kind {
    var config: CEConfig {
        switch self {
        case .assignedReceipt:
            return .init(eyebrowStage: "ASSIGNED",
                         citation: "§371 · AWARDED QUARTET CLOSED · DVIR SUB-AXIS OPENED 0/14",
                         title: "Load assigned",
                         subhead: "AWARDED · accepted",
                         stageNote: "lane awarded · dispatch assigned · accepted",
                         chainNote: "driver assigned · dispatcher monitors · shipper of record",
                         sectionsCompleted: 0)
        case .s1:
            return .init(eyebrowStage: "DVIR · S1",
                         citation: "§372 · DVIR ADVANCING · 1/14 · LIGHTS & REFLECTORS ACKED",
                         title: "Section 1 · acked",
                         subhead: "DVIR · 1/14 · ADVANCING",
                         stageNote: "DVIR section 1 acked · advancing",
                         chainNote: "DVIR walk-around running · dispatcher monitors",
                         sectionsCompleted: 1)
        case .s2:
            return .init(eyebrowStage: "DVIR · S2",
                         citation: "§373 · DVIR ADVANCING · 2/14 · BRAKES & AIR ACKED",
                         title: "Section 2 · acked",
                         subhead: "DVIR · 2/14 · ADVANCING",
                         stageNote: "DVIR section 2 acked · advancing",
                         chainNote: "DVIR walk-around running · dispatcher monitors",
                         sectionsCompleted: 2)
        case .s3:
            return .init(eyebrowStage: "DVIR · S3",
                         citation: "§374 · DVIR ADVANCING · 3/14 · TIRES & WHEELS ACKED",
                         title: "Section 3 · acked",
                         subhead: "DVIR · 3/14 · ADVANCING",
                         stageNote: "DVIR section 3 acked · advancing",
                         chainNote: "DVIR walk-around running · dispatcher monitors",
                         sectionsCompleted: 3)
        case .s4:
            return .init(eyebrowStage: "DVIR · S4",
                         citation: "§375 · DVIR ADVANCING · 4/14 · COUPLING DEVICES ACKED",
                         title: "Section 4 · acked",
                         subhead: "DVIR · 4/14 · ADVANCING",
                         stageNote: "DVIR section 4 acked · advancing",
                         chainNote: "DVIR walk-around running · dispatcher monitors",
                         sectionsCompleted: 4)
        case .s5:
            return .init(eyebrowStage: "DVIR · S5",
                         citation: "§376 · DVIR ADVANCING · 5/14 · WINDSHIELD & WIPERS ACKED",
                         title: "Section 5 · acked",
                         subhead: "DVIR · 5/14 · ADVANCING",
                         stageNote: "DVIR section 5 acked · advancing",
                         chainNote: "DVIR walk-around running · dispatcher monitors",
                         sectionsCompleted: 5)
        case .s6:
            return .init(eyebrowStage: "DVIR · S6",
                         citation: "§377 · DVIR ADVANCING · 6/14 · STEERING & LINKAGE ACKED",
                         title: "Section 6 · acked",
                         subhead: "DVIR · 6/14 · ADVANCING",
                         stageNote: "DVIR section 6 acked · advancing",
                         chainNote: "DVIR walk-around running · dispatcher monitors",
                         sectionsCompleted: 6)
        }
    }
}

private struct CELM04Shell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Trips", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct CELM04Body: View {
    let loadId: String
    let kind: CELM04Kind

    @Environment(\.palette) private var palette
    @State private var load: CMELoadCtx?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                if c.sectionsCompleted > 0 { progressCard(c) }
                identityRow
                kpiGrid(c)
                nextStepCard(c)
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    // MARK: - Dynamic display helpers

    private var loadNumberDisplay: String { load?.loadNumber ?? "—" }
    private var carrierCodeDisplay: String {
        load?.catalyst?.companyName ?? load?.catalyst?.name ?? "—"
    }
    private var laneDisplay: String? {
        guard let p = load?.pickupCity, let d = load?.destCity else { return nil }
        return "\(p) → \(d)"
    }

    private func header(_ c: CEConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DRIVER · TRIPS · \(c.eyebrowStage) · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CEConfig) -> some View {
        let driverIni = load?.driver?.initials ?? "—"
        let dispIni   = load?.catalyst?.initials ?? "—"
        let shipIni   = load?.shipper?.initials ?? "—"
        return LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(carrierCodeDisplay) · \(loadNumberDisplay) · \(c.stageNote)")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(loadNumberDisplay) · \(laneDisplay ?? "—") · \(c.chainNote) · \(driverIni) driver · \(dispIni) ops · \(shipIni) shipper")
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func progressCard(_ c: CEConfig) -> some View {
        let pct = Double(c.sectionsCompleted) / 14.0
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("DVIR PROGRESS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(c.sectionsCompleted)/14 sections").font(.caption2).foregroundStyle(palette.textSecondary)
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
                Text("\(carrierCodeDisplay) walk-around live").font(.caption2).foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var identityRow: some View {
        let dispIni    = load?.catalyst?.initials ?? "—"
        let dispName   = load?.catalyst?.name ?? "—"
        let carrierFull = load?.catalyst?.companyName ?? load?.catalyst?.name ?? "—"
        let mc         = load?.catalyst?.mcNumber.map { "MC-\($0)" } ?? "—"
        let driverName = load?.driver?.name ?? "—"
        let shipperName = load?.shipper?.name ?? "—"
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(dispIni).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(carrierCodeDisplay) · \(dispName) · dispatcher")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("\(carrierFull) · \(mc) · \(driverName) (driver) · \(shipperName) (shipper-of-record)")
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: CEConfig) -> some View {
        let payout = Self.payoutDisplay(load?.rate)
        let dist = Self.distanceDisplay(load?.distance)
        let lane = laneDisplay ?? "—"
        let equip = load?.equipmentType ?? "—"
        let driverIni = load?.driver?.initials ?? "—"
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .assignedReceipt:
                return [
                    ("PAYOUT",   payout,                              "\(carrierCodeDisplay) · \(loadNumberDisplay)", .green),
                    ("DIST",     dist,                                lane,                                            .blue),
                    ("EQUIP",    equip,                               "\(carrierCodeDisplay) fleet · \(driverIni)",   .blue),
                    ("STATE",    "AWARDED",                           "DVIR opens next",                              .green),
                ]
            default:
                let labels: [Int: String] = [
                    1: "LIGHTS & REFLECTORS",
                    2: "BRAKES & AIR",
                    3: "TIRES & WHEELS",
                    4: "COUPLING DEVICES",
                    5: "WINDSHIELD & WIPERS",
                    6: "STEERING & LINKAGE",
                ]
                return [
                    ("DVIR",    "\(c.sectionsCompleted)/14",          labels[c.sectionsCompleted] ?? "ADVANCING",     .green),
                    ("PAYOUT",  payout,                               "LOCKED · \(carrierCodeDisplay)",               .green),
                    ("DIST",    dist,                                 lane,                                            .blue),
                    ("HOS",     "10h 30m",                            "headroom · clean",                             .green),
                ]
            }
        }()
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

    private func nextStepCard(_ c: CEConfig) -> some View {
        let copy: String = {
            switch kind {
            case .assignedReceipt: return "M-04 tender awarded to CEL at $1,610. Naomi (dispatcher) opens DVIR sub-axis; pretrip begins immediately."
            case .s1: return "Lights & reflectors cleared. Brakes + air system (S2) up next."
            case .s2: return "Brakes & air system passed. Tires + wheels (S3) next."
            case .s3: return "Tires & wheels logged. Coupling devices (S4) next."
            case .s4: return "Coupling devices cleared. Windshield + wipers (S5) next."
            case .s5: return "Windshield & wipers ack'd. Steering + linkage (S6) next."
            case .s6: return "Steering & linkage logged — 43% done. Suspension (S7) up next at midpoint."
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

    /// Format the load's rate (decimal string from server) as a
    /// payout display. Falls back to "—" when missing/invalid.
    private static func payoutDisplay(_ rate: String?) -> String {
        guard let r = rate, let n = Double(r), n > 0 else { return "—" }
        let v = n.rounded()
        return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
    }

    /// Format the load's distance in miles. Falls back to "—".
    private static func distanceDisplay(_ d: Double?) -> String {
        guard let d, d > 0 else { return "—" }
        return "\(Int(d.rounded())) mi"
    }
}

// MARK: - Screens (DL126-DL132)

struct DriverCELM04AssignedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELM04Shell(theme: theme) { CELM04Body(loadId: loadId, kind: .assignedReceipt) } }
}
struct DriverCELM04S1Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELM04Shell(theme: theme) { CELM04Body(loadId: loadId, kind: .s1) } }
}
struct DriverCELM04S2Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELM04Shell(theme: theme) { CELM04Body(loadId: loadId, kind: .s2) } }
}
struct DriverCELM04S3Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELM04Shell(theme: theme) { CELM04Body(loadId: loadId, kind: .s3) } }
}
struct DriverCELM04S4Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELM04Shell(theme: theme) { CELM04Body(loadId: loadId, kind: .s4) } }
}
struct DriverCELM04S5Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELM04Shell(theme: theme) { CELM04Body(loadId: loadId, kind: .s5) } }
}
struct DriverCELM04S6Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CELM04Shell(theme: theme) { CELM04Body(loadId: loadId, kind: .s6) } }
}

// MARK: - Previews

#Preview("DL126 Assign · Dark") { DriverCELM04AssignedScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL127 S1 · Light")    { DriverCELM04S1Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL128 S2 · Dark")     { DriverCELM04S2Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL129 S3 · Light")    { DriverCELM04S3Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL130 S4 · Dark")     { DriverCELM04S4Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL131 S5 · Light")    { DriverCELM04S5Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL132 S6 · Dark")     { DriverCELM04S6Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
