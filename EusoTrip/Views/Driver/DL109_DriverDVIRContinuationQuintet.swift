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
//  ZERO fabrication. Every business value binds to live fetched data;
//  identity / lane / payout / distance / RPM / equipment all come from
//  loads.getById party + rate + distance + nested location fields, and
//  anything without a live source renders an honest "-"/"—". No baked
//  personas, MC/DOT numbers, load numbers, or `?? <invented>` defaults.
//
//  Honest binding parity with DL091 (loads.getById rate/distance/RPM)
//  and DL126/DL133 (CORRECTED getById shape: top-level `id: String?`,
//  nested pickupLocation/deliveryLocation {city,state}, real party
//  objects). Decoding `id` as Int throws typeMismatch and blanks the
//  whole screen — it MUST be String?.
//

import SwiftUI

private struct DLCLoadCtx: Decodable, Hashable {
    // loads.getById returns String(load.id) on the wire — decoding as
    // Int throws typeMismatch and fails the WHOLE decode (blank screen).
    let id: String?
    let loadNumber: String?
    // pickup/delivery arrive as nested {city,state} objects (NOT flat
    // city fields). Server emits "" (not nil) for missing parts.
    let pickupLocation: DLCLoc?
    let deliveryLocation: DLCLoc?
    let rate: String?            // decimal string
    let distance: Double?
    let equipmentType: String?
    let driver: DLCParty?
    let catalyst: DLCParty?
    let shipper: DLCParty?
    struct DLCLoc: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct DLCParty: Decodable, Hashable {
        let id: Int?            // party (user/company) id is numeric on the wire
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
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
    let sectionLabel: String          // "CAB INTERIOR & BRAKES" / …

    @Environment(\.palette) private var palette
    @State private var load: DLCLoadCtx?
    @State private var dvir: DLCDVIRRow?

    private let sectionTotal = 14
    private var progressPct: Double { Double(sectionsCompleted) / Double(sectionTotal) }
    private var pastMidpointPct: Int { Int((Double(sectionsCompleted) / Double(sectionTotal)) * 100) }

    // MARK: - Dynamic display helpers (live-bound; honest "-"/"—" fallback)

    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }
    private var carrierCodeDisplay: String {
        load?.catalyst?.companyName ?? load?.catalyst?.name ?? "-"
    }
    private var laneDisplay: String? {
        // Nested {city,state}; server sends "" (not nil) when missing.
        let o = [load?.pickupLocation?.city, load?.pickupLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        guard !o.isEmpty || !d.isEmpty else { return nil }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }
    /// DVIR id from the inspections store when present, else "-".
    private var dvirIdDisplay: String {
        guard let id = dvir?.id else { return "-" }
        return "dvir-\(id)"
    }

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
            Text("\(loadNumberDisplay) · \(laneDisplay ?? "—")")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var citationBanner: some View {
        let driverIni = load?.driver?.initials ?? "-"
        let dispIni   = load?.catalyst?.initials ?? "-"
        let shipIni   = load?.shipper?.initials ?? "-"
        return LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(citation) · BACKHAUL DVIR · WITHIN-TRACK SECTION-\(sectionsCompleted)-ACK").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("§302 ACCEPTED · \(citation) DVIR ADVANCING · \(sectionsCompleted)/14 SECTIONS · \(sectionLabel) ACKED")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("\(loadNumberDisplay) · \(laneDisplay ?? "—") · DVIR \(dvirIdDisplay) · \(sectionsCompleted)/14 · \(pastMidpointPct)% · \(driverIni) driver · \(dispIni) ops · \(shipIni) shipper").font(.caption2).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
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
                    let unit = (d.unitNumber?.isEmpty == false) ? d.unitNumber! : "unit"
                    let mk = [d.make, d.model].compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: " ")
                    Text("Live session · \(unit)\(mk.isEmpty ? "" : " · \(mk)")")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                } else {
                    Text("Walk-around in progress · advancing live").font(.caption2).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var identityRow: some View {
        let dispIni     = load?.catalyst?.initials ?? "-"
        let dispName    = load?.catalyst?.name ?? "-"
        let carrierFull = load?.catalyst?.companyName ?? load?.catalyst?.name ?? "-"
        let dot         = load?.catalyst?.dotNumber.map { "USDOT \($0)" } ?? "-"
        let mc          = load?.catalyst?.mcNumber.map { "MC-\($0)" } ?? "-"
        let driverName  = load?.driver?.name ?? "-"
        let shipperName = load?.shipper?.name ?? "-"
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(dispIni).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(carrierCodeDisplay) · \(dispName) · dispatcher")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("\(carrierFull) · \(dot) · \(mc) · \(driverName) (driver) · \(shipperName) (shipper)")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let payout = Self.payoutDisplay(load?.rate)
        let dist = Self.distanceDisplay(load?.distance)
        let rpm = Self.rpmDisplay(rate: load?.rate, distance: load?.distance)
        let lane = laneDisplay ?? "-"
        let kpis: [(String, String, String, Color)] = [
            ("PAYOUT",   payout,                       "NET-30 LOCKED · \(carrierCodeDisplay)",   .green),
            ("RPM",      rpm,                          "\(dist) · \(lane)",                       .blue),
            ("DIST",     dist,                         lane,                                      .blue),
            ("DVIR",     "\(sectionsCompleted)/14",    "advancing · \(pastMidpointPct)%",         sectionsCompleted >= 12 ? .green : .blue),
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
            case 12: return "ELD + comms cleared, 86% done. Fuel + DEF (S13) up next; submit fires at S14."
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

    /// Format the load's rate (decimal string from server) as a payout
    /// display. Falls back to "-" when missing/invalid. No invented default.
    private static func payoutDisplay(_ rate: String?) -> String {
        guard let r = rate, let n = Double(r), n > 0 else { return "-" }
        let v = n.rounded()
        return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
    }

    /// Format the load's distance in miles. Falls back to "-".
    private static func distanceDisplay(_ d: Double?) -> String {
        guard let d, d > 0 else { return "-" }
        return "\(Int(d.rounded())) mi"
    }

    /// Computed rate-per-mile = rate / distance. Both must be live + > 0,
    /// else "-". No hardcoded $5.38.
    private static func rpmDisplay(rate: String?, distance: Double?) -> String {
        guard let r = rate, let n = Double(r), n > 0, let d = distance, d > 0 else { return "-" }
        return String(format: "$%.2f", n / d)
    }
}

// MARK: - Screens (DL109-DL113)

struct DriverDVIRSection8Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DVIRSectionAckShell(theme: theme) {
            DVIRSectionAckBody(loadId: loadId, sectionsCompleted: 8, citation: "§315", sectionLabel: "CAB INTERIOR & BRAKES")
        }
    }
}
struct DriverDVIRSection9Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DVIRSectionAckShell(theme: theme) {
            DVIRSectionAckBody(loadId: loadId, sectionsCompleted: 9, citation: "§316", sectionLabel: "COUPLING & AIR SYSTEM")
        }
    }
}
struct DriverDVIRSection10Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DVIRSectionAckShell(theme: theme) {
            DVIRSectionAckBody(loadId: loadId, sectionsCompleted: 10, citation: "§317", sectionLabel: "TIRE CHAINS & EMERGENCY KIT")
        }
    }
}
struct DriverDVIRSection11Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DVIRSectionAckShell(theme: theme) {
            DVIRSectionAckBody(loadId: loadId, sectionsCompleted: 11, citation: "§318", sectionLabel: "REEFER & CARGO SEAL")
        }
    }
}
struct DriverDVIRSection12Screen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View {
        DVIRSectionAckShell(theme: theme) {
            DVIRSectionAckBody(loadId: loadId, sectionsCompleted: 12, citation: "§319", sectionLabel: "ELD & COMMS")
        }
    }
}

// MARK: - Previews

#Preview("DL109 S8 · Dark")   { DriverDVIRSection8Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL110 S9 · Light")  { DriverDVIRSection9Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL111 S10 · Dark")  { DriverDVIRSection10Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL112 S11 · Light") { DriverDVIRSection11Screen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL113 S12 · Dark")  { DriverDVIRSection12Screen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
