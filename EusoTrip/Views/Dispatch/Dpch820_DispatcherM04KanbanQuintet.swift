//
//  Dpch820_DispatcherM04KanbanQuintet.swift
//  EusoTrip — Dispatcher · M-04 kanban quintet (526-530).
//
//  Pixel-match to:
//    526 Dispatcher Kanban Cel Awarded M04
//    527 Dispatcher Pickup On-Site Echo Cel M04
//    528 Dispatcher In Transit Kanban Cel M04
//    529 Dispatcher At Delivery Kanban Cel M04
//    530 Dispatcher Paperwork Kanban Cel M04
//
//  Kanban-board view of the bound load as it advances through lane
//  swimlanes (AWARDED → PICKUP → IN-TRANSIT → AT-DELIVERY → PAPERWORK).
//  All 5 share `DispatcherM04KanbanBody`. Bottom nav frozen.
//
//  Doctrine (honest-binding): every visible business value binds to
//  `loads.getById`. No scenario literals. The wireframe illustrated the
//  moment with canonical CEL/M-04/NC strings; production substitutes the
//  bound load and shows "-" / "—" for any field that has no live source
//  (card counts, dock/dwell, mileage progress, ETA/arrival/POD clocks,
//  assign-by window). Phase/lane labels are structural, not fabricated.
//

import SwiftUI

// MARK: - tRPC decode shape (mirrors Models/Load.swift LoadLocation)

private struct DKLoadCtx: Decodable, Hashable {
    // Top-level load id is a String on the wire (loads.getById returns
    // String(load.id)); decoding it as Int throws typeMismatch and fails the
    // WHOLE object decode, blanking the screen. Party ids below stay Int.
    let id: String?
    let loadNumber: String?
    let status: String?
    let rate: String?
    let distance: Double?
    let driverId: Int?
    let catalystId: Int?
    let shipperId: Int?
    let pickupLocation: DKCityState?
    let deliveryLocation: DKCityState?

    struct DKCityState: Decodable, Hashable {
        let city: String?
        let state: String?
        /// City + state space-joined (e.g. "City ST"), matching the pill format.
        var cityStateSpaced: String {
            [city, state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
}

enum DispatcherM04KanbanKind: String {
    case awardedShift, pickupOnSite, inTransitRolling, atDeliveryArrived, paperworkSettling
}

private struct DispatcherM04KanbanShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

private struct DispatcherM04KanbanBody: View {
    let loadId: String
    let kind: DispatcherM04KanbanKind

    @Environment(\.palette) private var palette
    @State private var load: DKLoadCtx?

    // MARK: Bound derivations (honest — "-" / "—" when no live source)

    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }

    /// "<origin city ST> → <dest city ST>" when both endpoints resolve, else nil.
    private var laneDisplay: String? {
        let p = load?.pickupLocation?.cityStateSpaced ?? ""
        let d = load?.deliveryLocation?.cityStateSpaced ?? ""
        guard !p.isEmpty, !d.isEmpty else { return nil }
        return "\(p) → \(d)"
    }

    /// Formatted USD from the DECIMAL rate string, else "-".
    private var rateDisplay: String {
        if let r = load?.rate, let n = Double(r), n > 0 {
            let v = n.rounded()
            return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
        }
        return "-"
    }

    private var statusDisplay: String { load?.status ?? "-" }

    /// Region eyebrow from the delivery state, else "-".
    private var dispatchRegionDisplay: String {
        load?.deliveryLocation?.state.map { $0.isEmpty ? "-" : "\($0) dispatching" } ?? "-"
    }

    /// 2-letter avatar seed from the delivery state, else "—".
    private var regionSeed: String {
        let s = load?.deliveryLocation?.state ?? ""
        return s.isEmpty ? "—" : String(s.prefix(2)).uppercased()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                pill
                boardPill
                identityRow
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .eusoRefreshable { await loadCtx() }
    }

    // MARK: Phase labels (structural, not fabricated)

    private var laneLabel: String {
        switch kind {
        case .awardedShift:      return "AWARDED"
        case .pickupOnSite:      return "PICKUP"
        case .inTransitRolling:  return "IN-TRANSIT"
        case .atDeliveryArrived: return "DELIVERY"
        case .paperworkSettling: return "PAPERWORK"
        }
    }

    private var eyebrowPhase: String {
        switch kind {
        case .awardedShift:      return "AWARDED"
        case .pickupOnSite:      return "PICKUP"
        case .inTransitRolling:  return "IN-TRANSIT"
        case .atDeliveryArrived: return "AT-DELIVERY"
        case .paperworkSettling: return "PAPERWORK"
        }
    }

    private var titleCopy: String {
        switch kind {
        case .awardedShift:      return "Kanban · BIDDING → AWARDED lane"
        case .pickupOnSite:      return "Kanban · PICKUP lane · on-site"
        case .inTransitRolling:  return "Kanban · IN-TRANSIT lane · rolling"
        case .atDeliveryArrived: return "Kanban · DELIVERY lane · arrived"
        case .paperworkSettling: return "Kanban · PAPERWORK lane · settling"
        }
    }

    private var subheadCopy: String {
        switch kind {
        case .awardedShift:      return "Card shifted BIDDING → AWARDED on the board"
        case .pickupOnSite:      return "On-site echo · card advances on receiver wave"
        case .inTransitRolling:  return "Rolling · card advances on geofence cross"
        case .atDeliveryArrived: return "Arrived · auto-advance to PAPERWORK on dock placement"
        case .paperworkSettling: return "POD captured · card archives on wallet credit"
        }
    }

    private var citationLabel: String {
        switch kind {
        case .awardedShift:      return "KANBAN · BIDDING → AWARDED · CARD SHIFTED"
        case .pickupOnSite:      return "KANBAN · PICKUP LANE · ON-SITE ECHO"
        case .inTransitRolling:  return "KANBAN · IN-TRANSIT LANE · ROLLING"
        case .atDeliveryArrived: return "KANBAN · DELIVERY LANE · ARRIVED"
        case .paperworkSettling: return "KANBAN · PAPERWORK LANE · SETTLING"
        }
    }

    /// Pill copy — bound lane + region + the one honest per-phase fact.
    private var pillCopy: String {
        let lane = laneDisplay ?? "-"
        switch kind {
        case .awardedShift:      return "\(lane) · \(dispatchRegionDisplay) · payout \(rateDisplay)"
        case .pickupOnSite:      return "\(lane) · \(dispatchRegionDisplay) · on-site · dwell —"
        case .inTransitRolling:  return "\(lane) · \(dispatchRegionDisplay) · rolling · ETA —"
        case .atDeliveryArrived: return "\(lane) · \(dispatchRegionDisplay) · on-site · arrived —"
        case .paperworkSettling: return "\(lane) · \(dispatchRegionDisplay) · delivered · POD —"
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · BOARD · \(eyebrowPhase) · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(titleCopy).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(subheadCopy).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var pill: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(citationLabel).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var boardPill: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("BOARD STATE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                // Card-count has no live source on this screen → "—".
                Text("\(loadNumberDisplay) · \(dispatchRegionDisplay) · \(laneLabel) lane · — cards")
                    .font(.caption2).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(regionSeed).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(load?.catalystId.map { "dispatcher · carrier #\($0)" } ?? "dispatcher")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text([
                        load?.driverId.map { "driver #\($0)" } ?? "driver —",
                        load?.shipperId.map { "shipper #\($0)" } ?? "shipper —"
                    ].joined(separator: " · "))
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        // Only LANE, PAYOUT, and STATE have live sources. Card counts,
        // dock/dwell, mileage progress, ETA/arrival/POD clocks, and the
        // assign-by window have NO live source on this screen → "—".
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .awardedShift:
                return [
                    ("LANE-IN",  laneLabel,    "from BIDDING",     .green),
                    ("CARDS",    "—",          "no live count",    .blue),
                    ("PAYOUT",   rateDisplay,  "load rate",        .green),
                    ("ASSIGN",   "—",          "to driver",        .blue),
                ]
            case .pickupOnSite:
                return [
                    ("LANE-IN",  laneLabel,    "on-site echo",     .green),
                    ("DOCK",     "—",          "dwell —",          .orange),
                    ("CARDS",    "—",          "no live count",    .blue),
                    ("STATE",    statusDisplay, "load status",     .green),
                ]
            case .inTransitRolling:
                return [
                    ("LANE",     laneLabel,    "rolling",          .blue),
                    ("DIST",     "—",          "no live progress", .blue),
                    ("ETA",      "—",          "no live clock",    .blue),
                    ("CARDS",    "—",          "no live count",    .blue),
                ]
            case .atDeliveryArrived:
                return [
                    ("LANE",     laneLabel,    "arrived",          .green),
                    ("DIST",     "—",          "no live progress", .green),
                    ("ARRIVED",  "—",          "no live clock",    .green),
                    ("CARDS",    "—",          "no live count",    .blue),
                ]
            case .paperworkSettling:
                return [
                    ("LANE",     laneLabel,    "settling",         .green),
                    ("POD",      "—",          "no live clock",    .green),
                    ("PAYOUT",   rateDisplay,  "settlement queued", .green),
                    ("CARDS",    "—",          "no live count",    .blue),
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

    private var nextStepCard: some View {
        let copy: String = {
            switch kind {
            case .awardedShift:      return "Card shifted from BIDDING to AWARDED lane. Assign a driver to advance it to PICKUP."
            case .pickupOnSite:      return "Driver on-site. Advance the kanban card to LOADING when the receiver waves to plate."
            case .inTransitRolling:  return "Driver rolling. ESang nudges the card if the ETA drifts past tolerance."
            case .atDeliveryArrived: return "Arrived at receiver. Auto-advance to PAPERWORK lane on dock placement."
            case .paperworkSettling: return "POD captured; settlement queued. Card auto-archives when wallet credit confirms."
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
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* read-only screen, tolerate */ }
    }
}

// MARK: - Screens (526-530)

struct DispatcherM04AwardedKanbanScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherM04KanbanShell(theme: theme) { DispatcherM04KanbanBody(loadId: loadId, kind: .awardedShift) } }
}
struct DispatcherM04PickupKanbanScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherM04KanbanShell(theme: theme) { DispatcherM04KanbanBody(loadId: loadId, kind: .pickupOnSite) } }
}
struct DispatcherM04InTransitKanbanScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherM04KanbanShell(theme: theme) { DispatcherM04KanbanBody(loadId: loadId, kind: .inTransitRolling) } }
}
struct DispatcherM04AtDeliveryKanbanScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherM04KanbanShell(theme: theme) { DispatcherM04KanbanBody(loadId: loadId, kind: .atDeliveryArrived) } }
}
struct DispatcherM04PaperworkKanbanScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { DispatcherM04KanbanShell(theme: theme) { DispatcherM04KanbanBody(loadId: loadId, kind: .paperworkSettling) } }
}

// MARK: - Previews

#Preview("526 Awarded · Dark")    { DispatcherM04AwardedKanbanScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("527 Pickup · Light")    { DispatcherM04PickupKanbanScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("528 Transit · Dark")    { DispatcherM04InTransitKanbanScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("529 AtDel · Light")     { DispatcherM04AtDeliveryKanbanScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("530 Paperwork · Dark")  { DispatcherM04PaperworkKanbanScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
