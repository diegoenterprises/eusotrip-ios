//
//  CV350_CatalystLifecycleSeptet.swift
//  EusoTrip — Catalyst · Outbound lifecycle septet (CV350-CV356).
//
//  2026-07-03 SUPERSEDING PORT — staged designs from
//  "EusoTrip 2027 UI Wireframes/03 Catalyst" (Light-SVG/Dark-SVG 350-356 +
//  Code twins) replace the prior stamped parameterized body. Each of the
//  seven screens is now a purpose-built archetype:
//    350 At Gate       — GATE / YARD CHECK-IN (yard schematic + 4-station stepper)
//    351 At Dock       — LOADING / DOCK PROGRESS (bay hero + dwell clock)
//    352 Departing     — MAP / GEOFENCE ROLL-OFF (route hero + detention close)
//    353 Pre-Delivery  — METRO ARRIVAL (destination zoom + readiness gate)
//    354 At Delivery   — RECEIVING / INSPECTION GATE (unload + proof checks)
//    355 POD Receipt   — DOCUMENT / PROOF-OF-DELIVERY (certificate + custody)
//    356 Load Closed   — MONEY / SETTLEMENT ROLLUP (split bar + backhaul arm)
//
//  Registration type names + signatures preserved verbatim
//  (ContentView CV350-CV356 entries keep compiling untouched):
//    CatalystAtGateScreen / CatalystAtDockScreen / CatalystDepartingScreen /
//    CatalystPreDeliveryScreen / CatalystAtDeliveryScreen /
//    CatalystPODReceiptScreen / CatalystLoadClosedScreen — all
//    (theme: Theme.Palette, loadId: String).
//
//  ── LIVE WIRING (line-confirmed, frontend/server/routers/) ──────────
//  • loads.getById              loads.ts:1219      load spine + parties
//  • catalysts.getMyDrivers     catalysts.ts:431   roster row + HOS remaining
//  • accessorial.getFeeSchedule accessorial.ts:409 detention free window + rate
//  • pod.getPODForLoad          pod.ts:49          receiver sign / photo / status
//  • loads.getCloseoutSummary   loads.ts:1544      BOL# / arrived / detention billed
//  • earnings.previewSettlement earnings.ts:485    rollup money (carrier-gated)
//  • capacityPlanning.getBackhaulOptimizer capacityPlanning.ts:690 return matches
//  • tracking.getGeofenceEvents tracking.ts:465    live dwell at the fence
//  • esangCoach.forScreen       esangCoach.ts:264  one-line coach strip
//  • settlementBatching.createBatch settlementBatching.ts:42 stage driver payout
//
//  Honest unavailable states (no source → "—" / labeled copy, never faked):
//    gate queue depth · dock/bay assignment · pallet counts · reefer
//    telemetry · temp-at-receipt · seal record · OS&D counts · shipper
//    co-sign — each renders an em-dash or a data-presence-keyed line.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import UIKit

// MARK: - Wire shapes (decode ONLY confirmed-type fields)

/// `loads.getById` — top-level `id` is a String on the wire; pickup/delivery
/// are nested {city,state}; parties are resolved objects.
private struct CL350Load: Decodable {
    let id: String?
    let loadNumber: String?
    let status: String?
    let rate: String?
    let equipmentType: String?
    let cargoType: String?
    let distance: Double?
    let pickupDate: String?
    let deliveryDate: String?
    let createdAt: String?
    let biddingEnds: String?
    let pickupLocation: Loc?
    let deliveryLocation: Loc?
    let shipper: Party?
    let catalyst: Party?
    let driver: Party?

    struct Loc: Decodable { let city: String?; let state: String? }
    struct Party: Decodable {
        let id: Int?
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
}

/// `catalysts.getMyDrivers` row.
private struct CL350Driver: Decodable, Identifiable {
    let id: String
    let name: String
    let status: String?
    let currentLoad: String?
    let hoursRemaining: Double?
    let location: String?
}

/// `accessorial.getFeeSchedule` — detention slice only.
private struct CL350Fee: Decodable {
    let schedule: Schedule?
    struct Schedule: Decodable { let detention: Detention? }
    struct Detention: Decodable { let freeTimeMinutes: Int?; let ratePerHour: Double? }
}

/// `pod.getPODForLoad` — null when no proof yet.
private struct CL350Pod: Decodable {
    let id: Int?
    let receiverName: String?
    let photoBase64: String?
    let signatureBase64: String?
    let photoUrl: String?
    let signatureUrl: String?
    let notes: String?
    let status: String?
    let rejectionReason: String?
    let submittedAt: String?

    var hasPhotoEvidence: Bool {
        photoBase64?.cl350NilIfEmpty != nil || photoUrl?.cl350NilIfEmpty != nil
    }

    var hasSignatureEvidence: Bool {
        signatureBase64?.cl350NilIfEmpty != nil || signatureUrl?.cl350NilIfEmpty != nil
    }
}

private struct CL350EvidenceImage: View {
    let base64: String?
    let urlString: String?

    var body: some View {
        if let base64,
           let data = Data(base64Encoded: base64),
           let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit()
        } else if let urlString,
                  let url = URL(string: urlString),
                  url.scheme == "https" {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    Label("Evidence unavailable", systemImage: "exclamationmark.triangle")
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                case .empty:
                    ProgressView()
                @unknown default:
                    ProgressView()
                }
            }
        }
    }
}

/// `loads.getCloseoutSummary` — every field honestly nullable on the wire.
private struct CL350Closeout: Decodable {
    let bolNumber: String?
    let departedAt: String?
    let arrivedAt: String?
    let actualDeliveryDate: String?
    let sealNumbers: String?
    let detentionCharge: Double?
    let signedBy: String?
    let signedAt: String?
}

/// `earnings.previewSettlement` — carrier rollup money.
private struct CL350Settlement: Decodable {
    let loadNumber: String?
    let lane: String?
    let currency: String?
    let hasSettlement: Bool?
    let settlementStatus: String?
    let documentStatus: String?
    let settledAt: String?
    let linehaul: Double?
    let hazmatSurcharge: Double?
    let detention: Double?
    let accessorialTotal: Double?
    let platformFee: Double?
    let catalystShare: Double?
    let carrierPayment: Double?
    let grossPay: Double?
    let driverNet: Double?
}

/// `capacityPlanning.getBackhaulOptimizer`.
private struct CL350Backhaul: Decodable {
    let opportunities: [Opp]
    let emptyMileReduction: Double?
    let potentialSavings: Double?
    struct Opp: Decodable {
        let deliveryLoad: String
        let backhaulLoad: String
        let fromState: String
        let toState: String
        let estimatedSavings: Double
    }
}

/// `tracking.getGeofenceEvents` row.
private struct CL350Fence: Decodable {
    let id: String?
    let geofenceName: String?
    let eventType: String?
    let dwellSeconds: Int?
    let timestamp: String?
}

/// `esangCoach.forScreen`.
private struct CL350Esang: Decodable { let tip: String?; let mode: String? }

/// `settlementBatching.createBatch` result.
private struct CL350BatchResult: Decodable {
    let batchId: Int?
    let batchNumber: String?
    let totalLoads: Int?
    let totalAmount: Double?
}

// MARK: - Formatting helpers

private enum CL350Fmt {
    static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
    static func clock(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    static func dayClock(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"
        return f.string(from: d)
    }
    /// Relative "5h 28m" / "22m" until a date; nil when past or absent.
    static func until(_ d: Date?) -> String? {
        guard let d else { return nil }
        let s = d.timeIntervalSinceNow
        guard s > 0 else { return nil }
        let m = Int(s / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
    /// Elapsed "1:52" style h:mm since a date.
    static func elapsed(since d: Date?) -> String? {
        guard let d else { return nil }
        let s = Date().timeIntervalSince(d)
        guard s >= 0 else { return nil }
        let m = Int(s / 60)
        return String(format: "%d:%02d", m / 60, m % 60)
    }
    static func hmm(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
    static func money(_ v: Double?, code: String? = nil) -> String {
        guard let v else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = (code?.isEmpty == false ? code! : "USD")
        f.maximumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
    static func moneyString(_ s: String?) -> String {
        guard let s, let v = Double(s), v > 0 else { return "—" }
        return money(v)
    }
}

private extension String {
    var cl350NilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Shared live context store

@MainActor
private final class CL350Store: ObservableObject {
    @Published var load: CL350Load?
    @Published var loadFailed = false
    @Published var loading = true
    @Published var drivers: [CL350Driver] = []
    @Published var fee: CL350Fee.Detention?
    @Published var pod: CL350Pod?
    @Published var closeout: CL350Closeout?
    @Published var settlement: CL350Settlement?
    @Published var settlementDenied = false
    @Published var backhaul: CL350Backhaul?
    @Published var fenceEvent: CL350Fence?
    @Published var esangTip: String?

    struct Needs: OptionSet {
        let rawValue: Int
        static let drivers    = Needs(rawValue: 1 << 0)
        static let fee        = Needs(rawValue: 1 << 1)
        static let pod        = Needs(rawValue: 1 << 2)
        static let closeout   = Needs(rawValue: 1 << 3)
        static let settlement = Needs(rawValue: 1 << 4)
        static let backhaul   = Needs(rawValue: 1 << 5)
        static let fence      = Needs(rawValue: 1 << 6)
        static let esang      = Needs(rawValue: 1 << 7)
    }

    private struct IdIn: Encodable { let id: String }
    private struct LimitIn: Encodable { let limit: Int }
    private struct LoadIdIn: Encodable { let loadId: Int }
    private struct FenceIn: Encodable { let userId: String; let limit: Int }
    private struct EsangIn: Encodable {
        let screen: String
        let contextIds: [String: String]
    }
    private struct EmptyIn: Encodable {}

    func refresh(loadId: String, needs: Needs) async {
        loading = true
        defer { loading = false }
        let api = EusoTripAPI.shared

        do {
            let l: CL350Load = try await api.query("loads.getById", input: IdIn(id: loadId))
            load = l
            loadFailed = false
        } catch {
            loadFailed = (load == nil)
        }

        let numericId = Int(load?.id ?? "") ?? Int(loadId.replacingOccurrences(of: "load_", with: "")) ?? 0
        let driverUserId = load?.driver?.id

        await withTaskGroup(of: Void.self) { group in
            if needs.contains(.drivers) {
                group.addTask { @MainActor in
                    if let d: [CL350Driver] = try? await api.query("catalysts.getMyDrivers", input: LimitIn(limit: 25)) {
                        self.drivers = d
                    }
                }
            }
            if needs.contains(.fee) {
                group.addTask { @MainActor in
                    if let f: CL350Fee = try? await api.queryNoInput("accessorial.getFeeSchedule") {
                        self.fee = f.schedule?.detention
                    }
                }
            }
            if needs.contains(.pod), numericId > 0 {
                group.addTask { @MainActor in
                    self.pod = try? await api.query("pod.getPODForLoad", input: LoadIdIn(loadId: numericId))
                }
            }
            if needs.contains(.closeout), numericId > 0 {
                group.addTask { @MainActor in
                    self.closeout = try? await api.query("loads.getCloseoutSummary", input: LoadIdIn(loadId: numericId))
                }
            }
            if needs.contains(.settlement), numericId > 0 {
                group.addTask { @MainActor in
                    do {
                        let s: CL350Settlement = try await api.query("earnings.previewSettlement", input: LoadIdIn(loadId: numericId))
                        self.settlement = s
                        self.settlementDenied = false
                    } catch {
                        self.settlementDenied = true
                    }
                }
            }
            if needs.contains(.backhaul) {
                group.addTask { @MainActor in
                    self.backhaul = try? await api.query("capacityPlanning.getBackhaulOptimizer", input: EmptyIn())
                }
            }
            if needs.contains(.fence), let uid = driverUserId {
                group.addTask { @MainActor in
                    if let rows: [CL350Fence] = try? await api.query("tracking.getGeofenceEvents", input: FenceIn(userId: String(uid), limit: 5)) {
                        self.fenceEvent = rows.first
                    }
                }
            }
            if needs.contains(.esang) {
                group.addTask { @MainActor in
                    if let e: CL350Esang = try? await api.query(
                        "esangCoach.forScreen",
                        input: EsangIn(screen: "active-trip", contextIds: ["loadId": loadId])
                    ) {
                        self.esangTip = e.tip?.cl350NilIfEmpty
                    }
                }
            }
        }
    }

    // MARK: Derived (honest "—" when no source)

    var loadNumberDisplay: String { load?.loadNumber?.cl350NilIfEmpty ?? "—" }
    var statusRaw: String { load?.status?.cl350NilIfEmpty ?? "" }

    var originCity: String? { load?.pickupLocation?.city?.cl350NilIfEmpty }
    var destCity: String? { load?.deliveryLocation?.city?.cl350NilIfEmpty }

    var laneDisplay: String {
        let o = [load?.pickupLocation?.city, load?.pickupLocation?.state]
            .compactMap { $0?.cl350NilIfEmpty }.joined(separator: ", ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state]
            .compactMap { $0?.cl350NilIfEmpty }.joined(separator: ", ")
        guard !o.isEmpty || !d.isEmpty else { return "—" }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }

    var equipmentDisplay: String { load?.equipmentType?.cl350NilIfEmpty ?? "—" }
    var payoutDisplay: String { CL350Fmt.moneyString(load?.rate) }
    var milesDisplay: String {
        guard let d = load?.distance, d > 0 else { return "—" }
        return "\(Int(d.rounded()))"
    }

    /// Roster row matched to this load (load number first, then the load's
    /// resolved driver-party name). nil = honest "no driver on this load".
    var matchedDriver: CL350Driver? {
        let ln = load?.loadNumber?.cl350NilIfEmpty
        if let ln, let hit = drivers.first(where: { $0.currentLoad == ln }) { return hit }
        if let pn = load?.driver?.name?.cl350NilIfEmpty,
           let hit = drivers.first(where: { $0.name.caseInsensitiveCompare(pn) == .orderedSame }) { return hit }
        return nil
    }

    var driverName: String {
        matchedDriver?.name.cl350NilIfEmpty
            ?? load?.driver?.name?.cl350NilIfEmpty
            ?? "—"
    }
    var driverInitials: String { load?.driver?.initials?.cl350NilIfEmpty ?? "—" }

    var hosDisplay: String {
        guard let h = matchedDriver?.hoursRemaining else { return "—" }
        return String(format: "%.1fh", h)
    }

    /// Live dwell — real only when the newest fence event is an ENTER.
    var liveDwell: String? {
        guard let e = fenceEvent,
              (e.eventType ?? "").lowercased().contains("enter"),
              let t = CL350Fmt.date(e.timestamp) else { return nil }
        return CL350Fmt.elapsed(since: t)
    }
    var liveDwellMinutes: Int? {
        guard let e = fenceEvent,
              (e.eventType ?? "").lowercased().contains("enter"),
              let t = CL350Fmt.date(e.timestamp) else { return nil }
        return max(0, Int(Date().timeIntervalSince(t) / 60))
    }
    var fenceName: String? { fenceEvent?.geofenceName?.cl350NilIfEmpty }

    var freeLeftDisplay: String {
        guard let free = fee?.freeTimeMinutes, let dwell = liveDwellMinutes else { return "—" }
        let left = free - dwell
        return left >= 0 ? CL350Fmt.hmm(minutes: left) : "over"
    }

    var detentionRateDisplay: String {
        guard let r = fee?.ratePerHour, r > 0 else { return "—" }
        return "\(CL350Fmt.money(r))/hr"
    }
    var freeWindowDisplay: String {
        guard let f = fee?.freeTimeMinutes, f > 0 else { return "—" }
        return "\(f)m free"
    }

    var pickupWindowDisplay: String {
        guard let d = CL350Fmt.date(load?.pickupDate) else { return "—" }
        return CL350Fmt.dayClock(d)
    }
    var deliveryWindowDisplay: String {
        guard let d = CL350Fmt.date(load?.deliveryDate) else { return "—" }
        return CL350Fmt.dayClock(d)
    }
    var etaRelDisplay: String { CL350Fmt.until(CL350Fmt.date(load?.deliveryDate)) ?? "—" }
}

// MARK: - Shell (Catalyst chrome: Home / Dispatch / [orb] / Wallet / Me)

private struct CatalystLifecycleShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",                     isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill",  isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Shared building blocks

private struct CL350TopBar: View {
    @Environment(\.palette) private var palette
    let eyebrow: String
    let kicker: String
    let title: String
    let sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ \(eyebrow)")
                    .font(.system(size: 9, weight: .heavy)).kerning(1)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(kicker)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
            }
            .padding(.top, 6)
            Text(sub)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 4)
        }
    }
}

private struct CL350KpiStrip: View {
    @Environment(\.palette) private var palette
    let cells: [(k: String, v: String, s: String, hi: Bool, c: Color)]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                VStack(alignment: .leading, spacing: 3) {
                    Text(cell.k)
                        .font(.system(size: 8, weight: .heavy)).kerning(0.5)
                        .foregroundStyle(cell.hi ? Color.white.opacity(0.85) : palette.textSecondary)
                    Text(cell.v)
                        .font(.system(size: cell.v.count > 6 ? 15 : 20, weight: .bold))
                        .foregroundStyle(cell.hi ? Color.white : cell.c)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(cell.s)
                        .font(.system(size: 8))
                        .foregroundStyle(cell.hi ? Color.white.opacity(0.85) : palette.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                .padding(.leading, 11).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(cell.hi ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                )
                .overlay(
                    cell.hi ? nil :
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
            }
        }
    }
}

private struct CL350SectionLabel: View {
    @Environment(\.palette) private var palette
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).kerning(1)
            .foregroundStyle(palette.textSecondary)
    }
}

/// Driver roster row — bound to the load's resolved driver party + the live
/// roster match. Honest empty row when the load has no driver.
private struct CL350DriverRow: View {
    @Environment(\.palette) private var palette
    @ObservedObject var store: CL350Store
    let contextLine: String
    let chip: (text: String, color: Color)
    var body: some View {
        Group {
            if store.load?.driver == nil && store.matchedDriver == nil {
                HStack(spacing: 12) {
                    Circle().fill(palette.bgCardSoft).frame(width: 34, height: 34)
                        .overlay(Image(systemName: "person.slash")
                            .font(.system(size: 13)).foregroundStyle(palette.textTertiary))
                    Text("No driver is on this load yet.")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16).frame(height: 60)
            } else {
                HStack(spacing: 0) {
                    Circle().fill(LinearGradient.diagonal).frame(width: 34, height: 34)
                        .overlay(Text(store.driverInitials)
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(store.driverName) · \(contextLine)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary).lineLimit(1)
                        Text("\(store.loadNumberDisplay) · \(store.equipmentDisplay)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(palette.textSecondary).lineLimit(1)
                        Text("drive time left \(store.hosDisplay) · \(store.matchedDriver?.location?.cl350NilIfEmpty ?? "position —")")
                            .font(.system(size: 9.5))
                            .foregroundStyle(palette.textTertiary).lineLimit(1)
                    }
                    .padding(.leading, 12)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(chip.color).frame(width: 6, height: 6)
                        Text(chip.text).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(chip.color)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(chip.color.opacity(0.13)))
                }
                .padding(.horizontal, 16).frame(height: 60)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

/// ESANG one-liner — live from the coach feed; honest quiet line otherwise.
private struct CL350EsangCard: View {
    @Environment(\.palette) private var palette
    let label: String
    let tip: String?
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(LinearGradient.diagonal).frame(width: 30, height: 30)
                .overlay(Text("E").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 8.5, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(LinearGradient.primary)
                Text(tip ?? "ESANG has no cue for this stop yet — pull to refresh.")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(tip == nil ? palette.textSecondary : palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(LinearGradient.primary.opacity(0.85), lineWidth: 1.3))
    }
}

/// CTA pair — primary opens the full load detail (real screen, sheet);
/// secondary routes into the canonical ESANG message funnel.
private struct CL350CTAPair: View {
    @Environment(\.palette) private var palette
    let theme: Theme.Palette
    let loadId: String
    let primaryLabel: String
    @State private var showDetail = false
    var body: some View {
        HStack(spacing: 12) {
            Button {
                showDetail = true
            } label: {
                Text(primaryLabel)
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            Button {
                NotificationCenter.default.post(
                    name: .esangOpenMeDetail,
                    object: "messages",
                    userInfo: ["loadId": loadId]
                )
            } label: {
                Text("Message driver")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 136, height: 48)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showDetail) {
            CatalystLoadDetailScreen(theme: theme, loadId: loadId)
        }
    }
}

/// Loading skeleton + fetch-failure banner.
private struct CL350LoadGate<Content: View>: View {
    @Environment(\.palette) private var palette
    @ObservedObject var store: CL350Store
    let retry: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        if store.load == nil && store.loading {
            VStack(spacing: Space.s4) {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard).frame(height: 160)
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 62)
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard).frame(height: 120)
            }
            .redacted(reason: .placeholder)
        } else if store.load == nil && store.loadFailed {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .heavy)).foregroundStyle(Brand.danger)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't load this stop's live view. The rest of dispatch still works.")
                        .font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { retry() } label: {
                        Text("Retry").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.45), lineWidth: 1))
        } else {
            content()
        }
    }
}

/// Honest telemetry strip — used wherever the design calls for a live meter
/// that has no data source yet (pallet counts, reefer band, queue depth).
private struct CL350HonestStrip: View {
    @Environment(\.palette) private var palette
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
            Text(text)
                .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.bgCardSoft))
    }
}

/// Equipment kind mapping for the canonical animated rig asset.
private func cl350EquipmentKind(_ raw: String?) -> EquipmentKind {
    let s = (raw ?? "").lowercased()
    if s.contains("reefer") || s.contains("refrig") { return .reefer }
    if s.contains("flat") { return .flatbed }
    if s.contains("step") { return .stepDeck }
    if s.contains("container") || s.contains("intermodal") { return .container }
    if s.contains("tank") { return .tankerLiquid }
    if s.contains("lowboy") { return .lowboy }
    return .dryVan
}
private func cl350CargoKind(_ raw: String?) -> CargoKind {
    let s = (raw ?? "").lowercased()
    if s.contains("hazmat") || s.contains("hazard") { return .hazmat }
    if s.contains("reefer") || s.contains("refrig") || s.contains("produce") || s.contains("food") { return .refrigerated }
    if s.contains("liquid") { return .liquid }
    if s.contains("gas") { return .gas }
    if s.contains("oversize") { return .oversized }
    return .general
}

// MARK: - 350 · AT GATE — yard check-in

private struct CatalystAtGateBody350: View {
    let theme: Theme.Palette
    let loadId: String
    @Environment(\.palette) private var palette
    @StateObject private var store = CL350Store()

    private var needs: CL350Store.Needs { [.drivers, .fee, .fence, .esang] }

    /// 4-station stepper index derived from the real load status only.
    private var stationIndex: Int {
        switch store.statusRaw {
        case "at_pickup", "pickup_checkin": return 1
        case "loading", "loading_exception": return 3
        case "loaded", "in_transit": return 4
        default: return 0
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                CL350TopBar(
                    eyebrow: "CATALYST · DISPATCH · AT GATE",
                    kicker: "CHECK-IN",
                    title: store.fenceName ?? store.originCity ?? "Pickup gate",
                    sub: "\(store.loadNumberDisplay) · \(store.laneDisplay)"
                )
                Rectangle().fill(LinearGradient.primary.opacity(0.55)).frame(height: 1.5)
                CL350LoadGate(store: store, retry: { Task { await store.refresh(loadId: loadId, needs: needs) } }) {
                    yardHero
                    CL350KpiStrip(cells: [
                        ("GATE", stationIndex >= 1 ? "IN" : "—",
                         store.liveDwell.map { "on site \($0)" } ?? "arrival pending", stationIndex >= 1, palette.textPrimary),
                        ("QUEUE", "—", "no gate feed", false, palette.textPrimary),
                        ("APPT", CL350Fmt.clock(CL350Fmt.date(store.load?.pickupDate)), "pickup window", false, palette.textPrimary),
                        ("EQUIP", store.equipmentDisplay, "trailer", false, Brand.info),
                    ])
                    apptCard
                    CL350DriverRow(store: store, contextLine: "at the gate",
                                   chip: (stationIndex >= 1 ? "AT GATE" : "INBOUND", Brand.blue))
                    CL350EsangCard(label: "ESANG · GATE PLAN", tip: store.esangTip)
                    CL350CTAPair(theme: theme, loadId: loadId, primaryLabel: "Open load detail")
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
        }
        .task { await store.refresh(loadId: loadId, needs: needs) }
        .refreshable { await store.refresh(loadId: loadId, needs: needs) }
    }

    private var yardHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("YARD · GATE → SCALE → STAGE → DOCK")
                    .font(.system(size: 9, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Brand.blue).frame(width: 6, height: 6)
                    Text(stationIndex >= 1 ? "AT GATE" : "INBOUND")
                        .font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Brand.blue)
                }
                .padding(.horizontal, 9).frame(height: 20)
                .background(Capsule().fill(Brand.blue.opacity(0.12)))
            }
            yardSchematic.frame(height: 98).padding(.top, 12)
            stepper.padding(.top, 14)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var yardSchematic: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(palette.bgCardSoft)
                // drive lane
                Path { p in p.move(to: .init(x: w * 0.11, y: h * 0.7)); p.addLine(to: .init(x: w * 0.82, y: h * 0.7)) }
                    .stroke(palette.borderStrong, style: .init(lineWidth: 14, lineCap: .round))
                Path { p in p.move(to: .init(x: w * 0.11, y: h * 0.7)); p.addLine(to: .init(x: w * 0.82, y: h * 0.7)) }
                    .stroke(palette.bgCard.opacity(0.9), style: .init(lineWidth: 1.6, dash: [7, 9]))
                // gatehouse
                RoundedRectangle(cornerRadius: 3).fill(palette.textTertiary.opacity(0.5))
                    .frame(width: 18, height: 26).position(x: w * 0.06, y: h * 0.55)
                // rig token at gate (pulsing)
                CL350GateRig().position(x: w * 0.18, y: h * 0.7)
                if store.driverInitials != "—" {
                    Text("\(store.driverInitials) · \(stationIndex >= 1 ? "IN" : "DUE")")
                        .font(.system(size: 7, weight: .heavy)).foregroundStyle(Brand.blue)
                        .position(x: w * 0.18, y: h * 0.98)
                }
                // scale station
                Text("SCALE").font(.system(size: 7, weight: .heavy)).foregroundStyle(palette.textSecondary)
                    .frame(width: 34, height: 20)
                    .background(RoundedRectangle(cornerRadius: 3).strokeBorder(palette.textTertiary.opacity(0.5), lineWidth: 1))
                    .position(x: w * 0.58, y: h * 0.7)
                // dock doors — assignment has no live feed, doors stay unnumbered
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).strokeBorder(palette.textTertiary.opacity(0.4)).frame(width: 42, height: 13)
                    Text("DOCK").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 42, height: 13)
                        .background(RoundedRectangle(cornerRadius: 2).fill(LinearGradient.diagonal))
                    RoundedRectangle(cornerRadius: 2).strokeBorder(palette.textTertiary.opacity(0.4)).frame(width: 42, height: 13)
                }
                .position(x: w * 0.9, y: h * 0.5)
            }
        }
    }

    private var stepper: some View {
        let steps = ["GATE", "SCALE", "STAGE", "DOCK"]
        let idx = stationIndex
        return GeometryReader { g in
            let w = g.size.width
            ZStack {
                Path { p in p.move(to: .init(x: 7, y: 6)); p.addLine(to: .init(x: w - 7, y: 6)) }
                    .stroke(palette.borderSoft, lineWidth: 2)
                if idx > 0 {
                    Path { p in p.move(to: .init(x: 7, y: 6)); p.addLine(to: .init(x: max(7, w * CGFloat(idx) / CGFloat(steps.count)), y: 6)) }
                        .stroke(Brand.blue, lineWidth: 2)
                }
                HStack(spacing: 0) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        VStack(spacing: 4) {
                            if i < idx {
                                Circle().fill(LinearGradient.primary).frame(width: 14, height: 14)
                                    .overlay(Image(systemName: "checkmark").font(.system(size: 7, weight: .black)).foregroundStyle(.white))
                            } else if i == idx {
                                Circle().strokeBorder(LinearGradient.primary, lineWidth: 2.4).frame(width: 16, height: 16)
                                    .overlay(Circle().fill(Brand.blue).frame(width: 6, height: 6))
                            } else {
                                Circle().strokeBorder(palette.borderSoft, lineWidth: 2).frame(width: 12, height: 12)
                            }
                            Text(steps[i])
                                .font(.system(size: 7.5, weight: i > idx ? .bold : .heavy))
                                .foregroundStyle(i < idx ? palette.textPrimary : (i == idx ? Brand.blue : palette.textSecondary))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(height: 26)
    }

    private var apptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            CL350SectionLabel(text: "PICKUP APPOINTMENT · DETENTION ARMS AT DOCK")
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10).fill(Brand.blue.opacity(0.12)).frame(width: 40, height: 40)
                    .overlay(Image(systemName: "clock").font(.system(size: 17, weight: .semibold)).foregroundStyle(Brand.blue))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pickup \(store.pickupWindowDisplay)")
                        .font(.system(size: 13.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text("\(store.freeWindowDisplay) · then \(store.detentionRateDisplay)")
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    Text("clock starts at dock-in, not at the gate")
                        .font(.system(size: 9.5)).foregroundStyle(Brand.blue)
                }
                Spacer()
                Text("ARMS @ DOCK").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Capsule().fill(Brand.warning.opacity(0.15)))
            }
            .padding(.horizontal, 14).frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }
}

private struct CL350GateRig: View {
    @Environment(\.palette) private var palette
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(Brand.blue.opacity(pulse ? 0.1 : 0.3))
                .frame(width: pulse ? 38 : 24, height: pulse ? 38 : 24)
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.2)
                    .fill(LinearGradient(colors: [Brand.info, Brand.blue], startPoint: .top, endPoint: .bottom))
                    .frame(width: 5, height: 11)
                RoundedRectangle(cornerRadius: 2).fill(palette.bgCard).frame(width: 15, height: 11)
                Rectangle().fill(Brand.magenta.opacity(0.8)).frame(width: 6, height: 10)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

// MARK: - 351 · AT DOCK — loading progress + dwell clock

private struct CatalystAtDockBody351: View {
    let theme: Theme.Palette
    let loadId: String
    @Environment(\.palette) private var palette
    @StateObject private var store = CL350Store()

    private var needs: CL350Store.Needs { [.drivers, .fee, .fence, .esang] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                CL350TopBar(
                    eyebrow: "CATALYST · DISPATCH · AT DOCK",
                    kicker: "LOADING",
                    title: store.fenceName ?? store.originCity ?? "Pickup dock",
                    sub: "\(store.loadNumberDisplay) · dwell \(store.liveDwell ?? "—")"
                )
                Rectangle().fill(LinearGradient.primary.opacity(0.55)).frame(height: 1.5)
                CL350LoadGate(store: store, retry: { Task { await store.refresh(loadId: loadId, needs: needs) } }) {
                    dockHero
                    CL350KpiStrip(cells: [
                        ("LOADED", "—", "no dock feed", true, palette.textPrimary),
                        ("DWELL", store.liveDwell ?? "—",
                         store.fee?.freeTimeMinutes.map { "of \(CL350Fmt.hmm(minutes: $0)) free" } ?? "clock —",
                         false, palette.textPrimary),
                        ("FREE LEFT", store.freeLeftDisplay, "to detention", false, Brand.success),
                        ("EQUIP", store.equipmentDisplay, "at the door", false, Brand.info),
                    ])
                    CL350SectionLabel(text: "APPOINTMENT · DETENTION CLOCK")
                    detentionCard
                    CL350DriverRow(store: store, contextLine: "on the dock",
                                   chip: ("ON DOCK", Brand.info))
                    CL350EsangCard(label: "ESANG · DOCK PLAN", tip: store.esangTip)
                    CL350CTAPair(theme: theme, loadId: loadId, primaryLabel: "Open load detail")
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
        }
        .task { await store.refresh(loadId: loadId, needs: needs) }
        .refreshable { await store.refresh(loadId: loadId, needs: needs) }
    }

    private var dockHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DOCK · \(store.laneDisplay)")
                    .font(.system(size: 9, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(palette.textSecondary).lineLimit(1)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Brand.info).frame(width: 6, height: 6)
                    Text("LOADING").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Brand.info)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Brand.info.opacity(0.13)))
            }
            // Canonical brand equipment asset — never a hand-drawn box.
            ZStack(alignment: .trailing) {
                EquipmentAnimation(
                    equipment: cl350EquipmentKind(store.load?.equipmentType),
                    cargo: cl350CargoKind(store.load?.cargoType ?? store.load?.equipmentType),
                    weightUnit: "lb"
                )
                .frame(height: 96).frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 6).fill(palette.borderFaint)
                        .overlay(
                            VStack(spacing: 8) {
                                ForEach(0..<4, id: \.self) { _ in
                                    Rectangle().fill(palette.borderSoft).frame(height: 1)
                                }
                            }
                            .padding(8)
                        )
                        .frame(width: 58, height: 96)
                    Text("DOCK").font(.system(size: 8, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            // Loading meter has no live pallet source — honest strip, no fake %.
            CL350HonestStrip(
                icon: "shippingbox",
                text: "No live count from this dock yet — pallet progress posts when the crew scans the load."
            )
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var detentionCard: some View {
        let overFree: Bool = {
            guard let free = store.fee?.freeTimeMinutes, let dwell = store.liveDwellMinutes else { return false }
            return dwell > free
        }()
        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 10)
                .fill((overFree ? Brand.danger : Brand.warning).opacity(0.13))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "clock").font(.system(size: 16))
                    .foregroundStyle(overFree ? Brand.danger : Brand.warning))
            VStack(alignment: .leading, spacing: 2) {
                Text("Pickup window \(store.pickupWindowDisplay)")
                    .font(.system(size: 13.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("on site \(store.liveDwell ?? "—") · \(store.freeWindowDisplay) · then \(store.detentionRateDisplay)")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                Text(overFree
                     ? "free time is used up — detention is accruing"
                     : (store.liveDwell == nil
                        ? "dwell clock starts on the fence crossing"
                        : "inside the free window"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(overFree ? Brand.danger : Brand.success)
            }
            .padding(.leading, 12)
            Spacer(minLength: 0)
            Text(overFree ? "ACCRUING" : "NO CHARGE")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(overFree ? Brand.danger : Brand.success)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill((overFree ? Brand.danger : Brand.success).opacity(0.13)))
        }
        .padding(.horizontal, 16).frame(height: 64)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

// MARK: - 352 · DEPARTING — geofence roll-off map

private struct CatalystDepartingBody352: View {
    let theme: Theme.Palette
    let loadId: String
    @Environment(\.palette) private var palette
    @StateObject private var store = CL350Store()

    private var needs: CL350Store.Needs { [.drivers, .closeout, .esang] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                CL350TopBar(
                    eyebrow: "CATALYST · DISPATCH · DEPARTING",
                    kicker: "ROLLING",
                    title: store.laneDisplay,
                    sub: "\(store.loadNumberDisplay) · departed \(CL350Fmt.clock(CL350Fmt.date(store.closeout?.departedAt)))"
                )
                Rectangle().fill(LinearGradient.primary.opacity(0.55)).frame(height: 1.5)
                CL350LoadGate(store: store, retry: { Task { await store.refresh(loadId: loadId, needs: needs) } }) {
                    mapHero
                    detentionClosedBanner
                    CL350KpiStrip(cells: [
                        ("ETA", store.etaRelDisplay, "to the window", true, palette.textPrimary),
                        ("LANE", store.milesDisplay, "miles total", false, palette.textPrimary),
                        ("BOL", store.closeout?.bolNumber?.cl350NilIfEmpty != nil ? "ON FILE" : "—",
                         store.closeout?.bolNumber?.cl350NilIfEmpty ?? "not filed yet", false, Brand.success),
                        ("STATUS", store.statusRaw.isEmpty ? "—" : store.statusRaw.replacingOccurrences(of: "_", with: " ").uppercased(),
                         "load state", false, Brand.success),
                    ])
                    CL350DriverRow(store: store, contextLine: "rolling to delivery",
                                   chip: ("ROLLING", Brand.success))
                    CL350EsangCard(label: "ESANG · DRIVE PLAN", tip: store.esangTip)
                    CL350CTAPair(theme: theme, loadId: loadId, primaryLabel: "Open load detail")
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
        }
        .task { await store.refresh(loadId: loadId, needs: needs) }
        .refreshable { await store.refresh(loadId: loadId, needs: needs) }
    }

    private var mapHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(palette.bgCardSoft)
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    Path { p in
                        p.move(to: .init(x: w * 0.16, y: h * 0.46))
                        p.addQuadCurve(to: .init(x: w * 0.88, y: h * 0.32), control: .init(x: w * 0.5, y: h * 0.66))
                    }
                    .stroke(LinearGradient.primary, style: .init(lineWidth: 3.2, lineCap: .round))
                    // origin geofence ring — the rig just rolled off it
                    Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
                        .foregroundStyle(Brand.blue.opacity(0.55))
                        .frame(width: 60, height: 60).position(x: w * 0.16, y: h * 0.46)
                    Circle().fill(LinearGradient.primary).frame(width: 13, height: 13)
                        .position(x: w * 0.16, y: h * 0.46)
                    Text((store.originCity ?? "Origin").uppercased())
                        .font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        .position(x: w * 0.16, y: h * 0.46 + 46)
                    Image(systemName: "mappin.circle.fill").font(.system(size: 22))
                        .foregroundStyle(palette.textPrimary).position(x: w * 0.88, y: h * 0.32)
                    Text((store.destCity ?? "Destination").uppercased())
                        .font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        .position(x: w * 0.88, y: h * 0.32 + 26)
                    EquipmentAnimation(
                        equipment: cl350EquipmentKind(store.load?.equipmentType),
                        cargo: cl350CargoKind(store.load?.cargoType ?? store.load?.equipmentType),
                        weightUnit: "lb"
                    )
                    .frame(width: 132, height: 50)
                    .position(x: w * 0.30, y: h * 0.50)
                }
            }
            .padding(2)
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(Brand.success).frame(width: 7, height: 7)
                        Text(store.statusRaw == "in_transit" ? "EN ROUTE" : "DEPARTING")
                            .font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    }
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(palette.bgCard))
                    Spacer()
                }
                .padding(12)
                Spacer()
            }
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DELIVERY WINDOW").font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textSecondary)
                        Text(store.deliveryWindowDisplay)
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(LinearGradient.primary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 11).fill(palette.bgCard))
                }
                .padding(12)
            }
        }
        .frame(height: 258)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    /// Pickup detention at the close of the pickup stop — the billed figure is
    /// the sum of real detention records; no record = a $0.00 close.
    private var detentionClosedBanner: some View {
        let billed = store.closeout?.detentionCharge ?? 0
        return HStack(spacing: 10) {
            Image(systemName: billed > 0 ? "exclamationmark.circle" : "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(billed > 0 ? Brand.warning : Brand.success)
            VStack(alignment: .leading, spacing: 1) {
                Text(billed > 0 ? "Pickup detention billed" : "Pickup detention closed")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(billed > 0 ? "billable detention recorded on this stop" : "no billable detention on this stop")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(CL350Fmt.money(billed))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(billed > 0 ? Brand.warning : Brand.success)
        }
        .padding(.horizontal, 16).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill((billed > 0 ? Brand.warning : Brand.success).opacity(0.13)))
    }
}

// MARK: - 353 · PRE-DELIVERY — metro arrival + readiness gate

private struct CatalystPreDeliveryBody353: View {
    let theme: Theme.Palette
    let loadId: String
    @Environment(\.palette) private var palette
    @StateObject private var store = CL350Store()

    private var needs: CL350Store.Needs { [.drivers, .closeout, .esang] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                CL350TopBar(
                    eyebrow: "CATALYST · DISPATCH · PRE-DELIVERY",
                    kicker: "APPROACHING",
                    title: store.destCity.map { "Approaching \($0)" } ?? "Approaching delivery",
                    sub: "\(store.loadNumberDisplay) · window \(store.deliveryWindowDisplay)"
                )
                Rectangle().fill(LinearGradient.primary.opacity(0.55)).frame(height: 1.5)
                CL350LoadGate(store: store, retry: { Task { await store.refresh(loadId: loadId, needs: needs) } }) {
                    metroHero
                    CL350KpiStrip(cells: [
                        ("ETA", store.etaRelDisplay, "to the window", true, palette.textPrimary),
                        ("LANE", store.milesDisplay, "miles total", false, palette.textPrimary),
                        ("EQUIP", store.equipmentDisplay, "trailer", false, Brand.info),
                        ("DELIVER BY", CL350Fmt.clock(CL350Fmt.date(store.load?.deliveryDate)), "appt window", false, palette.textPrimary),
                    ])
                    readinessCard
                    CL350DriverRow(store: store, contextLine: "inbound to delivery",
                                   chip: ("APPROACH", Brand.success))
                    CL350EsangCard(label: "ESANG · ARRIVAL PLAN", tip: store.esangTip)
                    CL350CTAPair(theme: theme, loadId: loadId, primaryLabel: "Open load detail")
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
        }
        .task { await store.refresh(loadId: loadId, needs: needs) }
        .refreshable { await store.refresh(loadId: loadId, needs: needs) }
    }

    private var metroHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(palette.bgCardSoft)
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    // inbound highway
                    Path { p in
                        p.move(to: .init(x: w * 0.05, y: h * 0.08))
                        p.addQuadCurve(to: .init(x: w * 0.58, y: h * 0.62), control: .init(x: w * 0.33, y: h * 0.17))
                    }
                    .stroke(palette.borderStrong, style: .init(lineWidth: 11, lineCap: .round))
                    // receiver footprint
                    RoundedRectangle(cornerRadius: 6).fill(palette.bgCard)
                        .frame(width: w * 0.30, height: h * 0.36).position(x: w * 0.78, y: h * 0.62)
                    Text((store.destCity ?? "Receiver").uppercased())
                        .font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textSecondary)
                        .position(x: w * 0.78, y: h * 0.42)
                    // delivery fence — arms when the rig crosses it
                    Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
                        .foregroundStyle(Brand.warning.opacity(0.6))
                        .frame(width: 108, height: 108).position(x: w * 0.74, y: h * 0.62)
                    Text("ARRIVAL WATCH").font(.system(size: 7.5, weight: .heavy))
                        .foregroundStyle(Brand.warning).position(x: w * 0.74, y: h * 0.30)
                    // receiving pin
                    Image(systemName: "mappin.circle.fill").font(.system(size: 20))
                        .foregroundStyle(LinearGradient.primary).position(x: w * 0.58, y: h * 0.66)
                    Text("RECEIVING").font(.system(size: 7.5, weight: .heavy))
                        .foregroundStyle(palette.textPrimary).position(x: w * 0.58, y: h * 0.84)
                    // inbound rig
                    EquipmentAnimation(
                        equipment: cl350EquipmentKind(store.load?.equipmentType),
                        cargo: cl350CargoKind(store.load?.cargoType ?? store.load?.equipmentType),
                        weightUnit: "lb"
                    )
                    .frame(width: 110, height: 42)
                    .position(x: w * 0.30, y: h * 0.30)
                }
            }
            .padding(2)
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(Brand.success).frame(width: 7, height: 7)
                        Text("INBOUND").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    }
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(palette.bgCard))
                    Spacer()
                }
                .padding(12)
                Spacer()
            }
        }
        .frame(height: 228)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var readinessCard: some View {
        // Each row keyed to a real source; no fabricated confirmations.
        let bol = store.closeout?.bolNumber?.cl350NilIfEmpty
        let rows: [(String, String, Bool)] = [
            ("Delivery paperwork \(bol ?? "")", bol != nil ? "ON FILE" : "NOT FILED", bol != nil),
            ("Delivery window \(store.deliveryWindowDisplay)", store.load?.deliveryDate != nil ? "SET" : "UNSET", store.load?.deliveryDate != nil),
            ("Dock pre-assignment", "NO FEED", false),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            CL350SectionLabel(text: "DELIVERY READINESS")
            VStack(spacing: 0) {
                ForEach(0..<rows.count, id: \.self) { i in
                    HStack(spacing: 12) {
                        Image(systemName: rows[i].2 ? "checkmark" : "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(rows[i].2 ? Brand.success : palette.textTertiary)
                        Text(rows[i].0)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(rows[i].2 ? palette.textPrimary : palette.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Text(rows[i].1)
                            .font(.system(size: 9, weight: .heavy)).kerning(0.3)
                            .foregroundStyle(rows[i].2 ? Brand.success : palette.textTertiary)
                    }
                    .frame(height: 28)
                    if i < rows.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }
}

// MARK: - 354 · AT DELIVERY — receiving + inspection gate

private struct CatalystAtDeliveryBody354: View {
    let theme: Theme.Palette
    let loadId: String
    @Environment(\.palette) private var palette
    @StateObject private var store = CL350Store()
    @State private var showPod = false

    private var needs: CL350Store.Needs { [.drivers, .fee, .pod, .fence, .esang] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                CL350TopBar(
                    eyebrow: "CATALYST · DISPATCH · AT DELIVERY",
                    kicker: "RECEIVING",
                    title: store.fenceName ?? store.destCity ?? "Receiving dock",
                    sub: "\(store.loadNumberDisplay) · dwell \(store.liveDwell ?? "—")"
                )
                Rectangle().fill(LinearGradient.primary.opacity(0.55)).frame(height: 1.5)
                CL350LoadGate(store: store, retry: { Task { await store.refresh(loadId: loadId, needs: needs) } }) {
                    receivingHero
                    CL350KpiStrip(cells: [
                        ("UNLOADED", "—", "no dock feed", true, palette.textPrimary),
                        ("DWELL", store.liveDwell ?? "—",
                         store.fee?.freeTimeMinutes.map { "of \(CL350Fmt.hmm(minutes: $0)) free" } ?? "clock —",
                         false, palette.textPrimary),
                        ("PROOF", store.pod != nil ? "IN" : "—",
                         store.pod != nil ? "signature captured" : "not captured yet", false, Brand.escort),
                        ("EQUIP", store.equipmentDisplay, "at the door", false, Brand.info),
                    ])
                    inspectionGate
                    receiverRow
                    CL350EsangCard(label: "ESANG · UNLOAD PLAN", tip: store.esangTip)
                    ctaRow.padding(.top, 4)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
        }
        .task { await store.refresh(loadId: loadId, needs: needs) }
        .refreshable { await store.refresh(loadId: loadId, needs: needs) }
        .sheet(isPresented: $showPod) { CL350PodSheet(store: store) }
    }

    private var receivingHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECEIVING · \(store.laneDisplay)")
                    .font(.system(size: 9, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(palette.textSecondary).lineLimit(1)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Brand.escort).frame(width: 6, height: 6)
                    Text("RECEIVING").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Brand.escort)
                }
                .padding(.horizontal, 9).frame(height: 20)
                .background(Capsule().fill(Brand.escort.opacity(0.12)))
            }
            EquipmentAnimation(
                equipment: cl350EquipmentKind(store.load?.equipmentType),
                cargo: cl350CargoKind(store.load?.cargoType ?? store.load?.equipmentType),
                weightUnit: "lb"
            )
            .frame(height: 84).frame(maxWidth: .infinity, alignment: .leading)
            CL350HonestStrip(
                icon: "shippingbox",
                text: "No live count from this dock yet — unload progress posts when the receiver scans pallets off."
            )
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var inspectionGate: some View {
        let pod = store.pod
        let rejected = (pod?.status ?? store.statusRaw) == "pod_rejected"
        let verdict: (String, Color) = pod == nil
            ? ("IN PROGRESS", Brand.warning)
            : (rejected ? ("EXCEPTION", Brand.danger) : ("PASS", Brand.success))
        let rows: [(String, Bool)] = [
            ("Receiver signature \(pod?.receiverName?.cl350NilIfEmpty ?? "")", pod?.hasSignatureEvidence == true),
            ("Delivery photo on file", pod?.hasPhotoEvidence == true),
            ("Receiving notes \(pod?.notes?.cl350NilIfEmpty ?? "")", pod?.notes?.cl350NilIfEmpty != nil),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            CL350SectionLabel(text: "RECEIVING INSPECTION")
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(verdict.1).frame(width: 6, height: 6)
                        Text(verdict.0).font(.system(size: 9, weight: .heavy)).foregroundStyle(verdict.1)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(verdict.1.opacity(0.13)))
                }
                ForEach(0..<rows.count, id: \.self) { i in
                    HStack(spacing: 12) {
                        Image(systemName: rows[i].1 ? "checkmark" : "minus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(rows[i].1 ? Brand.success : palette.textTertiary)
                        Text(rows[i].0)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(rows[i].1 ? palette.textPrimary : palette.textSecondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .frame(height: 22)
                    if i < rows.count - 1 { Divider().overlay(palette.borderFaint) }
                }
                if rejected, let reason = pod?.rejectionReason?.cl350NilIfEmpty {
                    Divider().overlay(palette.borderFaint)
                    HStack(spacing: 12) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.danger)
                        Text(reason).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Brand.danger)
                            .lineLimit(2)
                        Spacer()
                    }
                    .frame(minHeight: 22)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private var receiverRow: some View {
        let name = store.pod?.receiverName?.cl350NilIfEmpty
        return HStack(spacing: 0) {
            Circle().fill(Brand.escort).frame(width: 34, height: 34)
                .overlay(Image(systemName: "person.crop.square.filled.and.at.rectangle")
                    .font(.system(size: 12)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(name.map { "\($0) · receiving" } ?? "Receiver not on record yet")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(name != nil ? "signature on the delivery record" : "the co-sign posts when the driver captures it")
                    .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            .padding(.leading, 12)
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(Brand.escort).frame(width: 6, height: 6)
                Text(name != nil ? "CO-SIGNED" : "PENDING")
                    .font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Brand.escort)
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Brand.escort.opacity(0.12)))
        }
        .padding(.horizontal, 16).frame(height: 60)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var ctaRow: some View {
        HStack(spacing: 12) {
            Button { showPod = true } label: {
                Text("Open delivery proof")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            Button {
                NotificationCenter.default.post(
                    name: .esangOpenMeDetail, object: "messages", userInfo: ["loadId": loadId])
            } label: {
                Text("Message driver")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 136, height: 48)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Delivery-proof sheet — renders the REAL captured photo / signature /
/// notes; honest empty state before the driver submits.
private struct CL350PodSheet: View {
    @Environment(\.palette) private var palette
    @ObservedObject var store: CL350Store
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Delivery proof")
                    .font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                if let pod = store.pod {
                    if pod.hasPhotoEvidence {
                        CL350EvidenceImage(base64: pod.photoBase64, urlString: pod.photoUrl)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    }
                    if pod.hasSignatureEvidence {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("RECEIVER SIGNATURE")
                                .font(.system(size: 9, weight: .heavy)).kerning(0.8)
                                .foregroundStyle(palette.textTertiary)
                            CL350EvidenceImage(base64: pod.signatureBase64, urlString: pod.signatureUrl)
                                .frame(maxHeight: 90)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                    }
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Signed by \(pod.receiverName?.cl350NilIfEmpty ?? "—")")
                                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text("submitted \(CL350Fmt.dayClock(CL350Fmt.date(pod.submittedAt)))")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                            if let notes = pod.notes?.cl350NilIfEmpty {
                                Text(notes).font(EType.caption).foregroundStyle(palette.textSecondary)
                            }
                        }
                    }
                } else {
                    EusoEmptyState(
                        systemImage: "signature",
                        title: "No delivery proof yet",
                        subtitle: "The proof posts here the moment the driver captures the receiver's signature at the dock."
                    )
                }
                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .background(palette.bgPrimary.ignoresSafeArea())
    }
}

// MARK: - 355 · POD RECEIPT — proof-of-delivery certificate

private struct CatalystPodReceiptBody355: View {
    let theme: Theme.Palette
    let loadId: String
    @Environment(\.palette) private var palette
    @StateObject private var store = CL350Store()
    @State private var showPod = false

    private var needs: CL350Store.Needs { [.drivers, .pod, .closeout, .settlement, .esang] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                CL350TopBar(
                    eyebrow: "CATALYST · DISPATCH · DELIVERY PROOF",
                    kicker: store.pod != nil ? "DELIVERED" : "PAPERWORK",
                    title: store.destCity ?? "Delivery proof",
                    sub: "\(store.loadNumberDisplay) · \(CL350Fmt.dayClock(CL350Fmt.date(store.pod?.submittedAt ?? store.closeout?.arrivedAt)))"
                )
                Rectangle().fill(LinearGradient.primary.opacity(0.55)).frame(height: 1.5)
                CL350LoadGate(store: store, retry: { Task { await store.refresh(loadId: loadId, needs: needs) } }) {
                    certHero
                    CL350SectionLabel(text: "CHAIN OF CUSTODY")
                    custodyChain
                    CL350SectionLabel(text: "DOCUMENTS")
                    docTiles
                    reconStrip
                    CL350EsangCard(label: "ESANG · SETTLEMENT", tip: store.esangTip)
                    ctaRow.padding(.top, 4)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
        }
        .task { await store.refresh(loadId: loadId, needs: needs) }
        .refreshable { await store.refresh(loadId: loadId, needs: needs) }
        .sheet(isPresented: $showPod) { CL350PodSheet(store: store) }
    }

    private var certHero: some View {
        let issued = store.pod?.hasSignatureEvidence == true
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(issued ? AnyShapeStyle(Brand.success) : AnyShapeStyle(palette.bgCardSoft))
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: issued ? "checkmark.shield.fill" : "hourglass")
                        .font(.system(size: 16))
                        .foregroundStyle(issued ? Color.white : palette.textTertiary))
                VStack(alignment: .leading, spacing: 3) {
                    Text(issued ? "DELIVERY PROOF · ON FILE" : "DELIVERY PROOF · PENDING")
                        .font(.system(size: 9, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(issued ? Brand.success : palette.textTertiary)
                    Text(issued ? "Delivered & signed" : "Awaiting the receiver's ink")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(palette.textPrimary)
                }
                .padding(.leading, 10)
                Spacer()
                Text(issued ? "CHAIN CLOSED" : "CHAIN OPEN")
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(issued ? Brand.success : Brand.warning)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill((issued ? Brand.success : Brand.warning).opacity(0.13)))
            }
            Divider().padding(.vertical, 12)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.laneDisplay)
                        .font(.system(size: 13.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text("\(store.loadNumberDisplay) · \(store.closeout?.bolNumber?.cl350NilIfEmpty ?? "paperwork —")")
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    Text(issued
                         ? "signed \(CL350Fmt.dayClock(CL350Fmt.date(store.pod?.submittedAt)))"
                         : "the certificate seals when the signature lands")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                if issued {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RECEIVER SIGN").font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textSecondary)
                        if store.pod?.hasSignatureEvidence == true {
                            CL350EvidenceImage(
                                base64: store.pod?.signatureBase64,
                                urlString: store.pod?.signatureUrl
                            )
                            .frame(width: 110, height: 26)
                        } else {
                            Text("on record").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        }
                        Text(store.pod?.receiverName?.cl350NilIfEmpty ?? "—")
                            .font(.system(size: 9)).foregroundStyle(palette.textSecondary)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CL350Fmt.money(store.settlement?.carrierPayment, code: store.settlement?.currency))
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(LinearGradient.diagonal)
                Text(store.settlement?.carrierPayment != nil
                     ? "carrier receivable on this load"
                     : "receivable posts with the settlement")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 10)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(issued ? AnyShapeStyle(LinearGradient.primary.opacity(0.85)) : AnyShapeStyle(palette.borderFaint), lineWidth: 1.5))
    }

    private var custodyChain: some View {
        let pod = store.pod
        let nodes: [(name: String, role: String, done: Bool)] = [
            (pod?.receiverName?.cl350NilIfEmpty ?? "Receiver", "receiver", pod != nil),
            (store.driverName == "—" ? "Driver" : store.driverName, "driver", pod != nil),
            (store.load?.shipper?.name?.cl350NilIfEmpty ?? "Shipper", "shipper", false),
        ]
        return HStack(spacing: 0) {
            ForEach(0..<nodes.count, id: \.self) { i in
                VStack(spacing: 4) {
                    Circle().fill((nodes[i].done ? Brand.success : Brand.neutral).opacity(0.13))
                        .frame(width: 28, height: 28)
                        .overlay(Image(systemName: nodes[i].done ? "checkmark" : "hourglass")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(nodes[i].done ? Brand.success : palette.textTertiary))
                    Text(nodes[i].name)
                        .font(.system(size: 9.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("\(nodes[i].role) · \(nodes[i].done ? "signed" : "pending")")
                        .font(.system(size: 8)).foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                if i < nodes.count - 1 {
                    Rectangle()
                        .fill(nodes[i].done ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.borderSoft))
                        .frame(height: 2).frame(maxWidth: 40).offset(y: -22)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var docTiles: some View {
        let tiles: [(badge: String, title: String, sub: String, present: Bool, style: AnyShapeStyle)] = [
            ("POD", "Delivery photo",
             store.pod?.hasPhotoEvidence == true ? "on file" : "not attached",
             store.pod?.hasPhotoEvidence == true,
             AnyShapeStyle(Brand.success)),
            ("BOL", "Bill of lading",
             store.closeout?.bolNumber?.cl350NilIfEmpty ?? "not filed",
             store.closeout?.bolNumber?.cl350NilIfEmpty != nil,
             AnyShapeStyle(LinearGradient.diagonal)),
            ("ARR", "Arrival record",
             store.closeout?.arrivedAt != nil ? CL350Fmt.clock(CL350Fmt.date(store.closeout?.arrivedAt)) : "not stamped",
             store.closeout?.arrivedAt != nil,
             AnyShapeStyle(Brand.info)),
        ]
        return HStack(spacing: 8) {
            ForEach(0..<tiles.count, id: \.self) { i in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tiles[i].present ? tiles[i].style : AnyShapeStyle(palette.bgCardSoft))
                        .frame(width: 32, height: 32)
                        .overlay(Text(tiles[i].badge)
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(tiles[i].present ? Color.white : palette.textTertiary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tiles[i].title)
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text(tiles[i].sub)
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .padding(.leading, 8)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).frame(height: 60).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }
        }
    }

    private var reconStrip: some View {
        CL350KpiStrip(cells: [
            ("DELIVERED", CL350Fmt.clock(CL350Fmt.date(store.closeout?.arrivedAt ?? store.closeout?.actualDeliveryDate)),
             "arrival stamp", true, palette.textPrimary),
            ("SEAL", store.closeout?.sealNumbers?.cl350NilIfEmpty ?? "—", "no seal record", false, palette.textPrimary),
            ("DETENTION", CL350Fmt.money(store.closeout?.detentionCharge ?? 0), "billed", false, Brand.success),
            ("NET", CL350Fmt.money(store.settlement?.carrierPayment, code: store.settlement?.currency),
             "carrier receivable", false, Brand.blue),
        ])
    }

    private var ctaRow: some View {
        HStack(spacing: 12) {
            CL350StagePayoutButton(store: store, loadId: loadId)
            Button { showPod = true } label: {
                Text("View proof")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 126, height: 48)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Stage-driver-payout button (settlementBatching.createBatch)

private struct CL350StagePayoutButton: View {
    @Environment(\.palette) private var palette
    @ObservedObject var store: CL350Store
    let loadId: String

    @State private var staging = false
    @State private var stagedBatch: String?
    @State private var stageError: String?
    @State private var showNoSettlement = false

    private struct BatchIn: Encodable {
        let batchType: String
        let periodStart: String
        let periodEnd: String
        let loadIds: [Int]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if store.settlement?.hasSettlement == true {
                    Task { await stage() }
                } else {
                    showNoSettlement = true
                }
            } label: {
                HStack(spacing: 8) {
                    if staging { ProgressView().tint(.white) }
                    Text(stagedBatch != nil ? "Payout staged · \(stagedBatch!)" : "Stage driver payout")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Capsule().fill(stagedBatch != nil ? AnyShapeStyle(Brand.success) : AnyShapeStyle(LinearGradient.primary)))
            }
            .buttonStyle(.plain)
            .disabled(staging || stagedBatch != nil)
            if let err = stageError {
                Text(err)
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert("No settlement yet", isPresented: $showNoSettlement) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A settlement for this load hasn't posted yet — it appears when the delivery paperwork clears. The proof and documents on this screen still work.")
        }
    }

    private func stage() async {
        guard let numericId = Int(store.load?.id ?? "") else { return }
        staging = true
        stageError = nil
        defer { staging = false }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let start = CL350Fmt.date(store.load?.pickupDate) ?? Date()
        let end = CL350Fmt.date(store.load?.deliveryDate) ?? Date()
        do {
            let out: CL350BatchResult = try await EusoTripAPI.shared.mutation(
                "settlementBatching.createBatch",
                input: BatchIn(
                    batchType: "driver_payable",
                    periodStart: df.string(from: min(start, end)),
                    periodEnd: df.string(from: max(start, end)),
                    loadIds: [numericId]
                )
            )
            stagedBatch = out.batchNumber?.cl350NilIfEmpty ?? "batch \(out.batchId ?? 0)"
        } catch {
            stageError = "Couldn't stage the payout — the settlement stays untouched. Try again from the Wallet."
        }
    }
}

// MARK: - 356 · LOAD CLOSED — money rollup + backhaul arm

private struct CatalystLoadClosedBody356: View {
    let theme: Theme.Palette
    let loadId: String
    @Environment(\.palette) private var palette
    @StateObject private var store = CL350Store()
    @State private var backhaulSheet: CL350BackhaulSheetItem?

    private struct CL350BackhaulSheetItem: Identifiable { let id: String }

    private var needs: CL350Store.Needs { [.drivers, .pod, .settlement, .backhaul, .esang] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                CL350TopBar(
                    eyebrow: "CATALYST · DISPATCH · CLOSED",
                    kicker: "ROLLUP",
                    title: "Load closed · rollup",
                    sub: "\(store.loadNumberDisplay) · \(store.laneDisplay)"
                )
                Rectangle().fill(LinearGradient.primary.opacity(0.55)).frame(height: 1.5)
                CL350LoadGate(store: store, retry: { Task { await store.refresh(loadId: loadId, needs: needs) } }) {
                    settledHero
                    CL350SectionLabel(text: "SETTLEMENT LIFECYCLE")
                    settlementStages.padding(.horizontal, 8)
                    CL350SectionLabel(text: "CARRIER ROLLUP · WHERE THE MONEY GOES")
                    rollupSplit
                    CL350SectionLabel(text: "BACKHAUL · RETURN MATCHES")
                    backhaulCard
                    CL350EsangCard(label: "ESANG · NEXT MOVE", tip: store.esangTip)
                    ctaRow.padding(.top, 4)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
        }
        .task { await store.refresh(loadId: loadId, needs: needs) }
        .refreshable { await store.refresh(loadId: loadId, needs: needs) }
        .sheet(item: $backhaulSheet) { item in
            CatalystBackhaulTenderScreen(theme: theme, loadId: item.id)
        }
    }

    private var settledHero: some View {
        let s = store.settlement
        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(Brand.blue).frame(width: 3.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(store.loadNumberDisplay)
                        .font(.system(size: 9, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(s?.settledAt != nil ? "SETTLED · CLOSED" : (s?.hasSettlement == true ? "SETTLEMENT OPEN" : "AWAITING SETTLEMENT"))
                        .font(.system(size: 8.5, weight: .heavy)).kerning(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(s?.settledAt != nil || s?.hasSettlement == true
                                                   ? AnyShapeStyle(Brand.success) : AnyShapeStyle(Brand.neutral)))
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(CL350Fmt.money(s?.carrierPayment, code: s?.currency))
                        .font(.system(size: 34, weight: .bold)).foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s?.carrierPayment != nil ? "carrier receivable" : "posts with the settlement")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text(store.pod != nil ? "delivery proof on file" : "delivery proof pending")
                            .font(.system(size: 10.5)).foregroundStyle(palette.textTertiary)
                    }
                }
                .padding(.top, 6)
                Text("\(store.laneDisplay) · \(store.equipmentDisplay) · \(store.milesDisplay) mi")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary).padding(.top, 8)
                if let shipper = store.load?.shipper {
                    HStack(spacing: 6) {
                        Circle().fill(Brand.blue).frame(width: 12, height: 12)
                            .overlay(Text(shipper.initials?.cl350NilIfEmpty ?? "•")
                                .font(.system(size: 6, weight: .heavy)).foregroundStyle(.white))
                        Text("\(shipper.companyName?.cl350NilIfEmpty ?? shipper.name?.cl350NilIfEmpty ?? "Shipper") · shipper-of-record")
                            .font(.system(size: 9.5)).foregroundStyle(palette.textSecondary).lineLimit(1)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.leading, 14).padding(.vertical, 14).padding(.trailing, 16)
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    /// 5-stage strip keyed to real settlement facts only.
    private var settlementStages: some View {
        let s = store.settlement
        let status = (s?.settlementStatus ?? "none").lowercased()
        let stages: [(String, Bool, Bool)] = {
            let podDone = store.pod != nil
            let audit = s?.hasSettlement == true
            let approved = ["approved", "processing", "paid", "completed"].contains(status)
            let funded = ["paid", "completed"].contains(status)
            let cleared = s?.settledAt != nil
            return [
                ("PROOF",    podDone,  !podDone),
                ("AUDIT",    audit,    podDone && !audit),
                ("APPROVED", approved, audit && !approved),
                ("FUNDED",   funded,   approved && !funded),
                ("CLEARED",  cleared,  funded && !cleared),
            ]
        }()
        return HStack(spacing: 0) {
            ForEach(0..<stages.count, id: \.self) { i in
                VStack(spacing: 4) {
                    if stages[i].1 {
                        Circle().fill(Brand.blue).frame(width: 9, height: 9)
                    } else if stages[i].2 {
                        Circle().strokeBorder(LinearGradient.primary, lineWidth: 2).frame(width: 13, height: 13)
                            .overlay(Circle().fill(LinearGradient.primary).frame(width: 7, height: 7))
                    } else {
                        Circle().fill(palette.borderSoft).frame(width: 9, height: 9)
                    }
                    Text(stages[i].0)
                        .font(.system(size: 7, weight: .bold)).kerning(0.3)
                        .foregroundStyle(stages[i].2 ? Brand.blue : palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                if i < stages.count - 1 {
                    Rectangle().fill(stages[i].1 ? Brand.blue : palette.borderSoft)
                        .frame(height: 2).frame(maxWidth: 30).offset(y: -8)
                }
            }
        }
    }

    private var rollupSplit: some View {
        let s = store.settlement
        let driver = s?.driverNet
        let carrier = s?.catalystShare
        let hasSplit = driver != nil && carrier != nil && ((driver ?? 0) + (carrier ?? 0)) > 0
        return VStack(spacing: 0) {
            if hasSplit, let d = driver, let c = carrier {
                let total = d + c
                GeometryReader { g in
                    HStack(spacing: 2) {
                        Capsule().fill(LinearGradient.primary)
                            .frame(width: max(4, g.size.width * CGFloat(d / total)))
                        Capsule().fill(LinearGradient(colors: [Brand.hazmat, Brand.warning],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .frame(height: 10).padding(.bottom, 14)
            } else if store.settlementDenied || s == nil {
                CL350HonestStrip(icon: "banknote",
                                 text: "No settlement split for this load yet — the rollup posts when the delivery paperwork clears.")
                    .padding(.bottom, 12)
            }
            splitRow(dot: Brand.blue, name: "Driver payout", sub: "net of deductions",
                     amt: CL350Fmt.money(driver, code: s?.currency),
                     pct: pctText(driver, of: (driver ?? 0) + (carrier ?? 0)))
            Divider().padding(.vertical, 8)
            splitRow(dot: Brand.warning, name: "Carrier margin", sub: "kept after driver pay",
                     amt: CL350Fmt.money(carrier, code: s?.currency),
                     pct: pctText(carrier, of: (driver ?? 0) + (carrier ?? 0)))
            Divider().padding(.vertical, 8)
            HStack {
                Text("LINE \(CL350Fmt.money(s?.linehaul, code: s?.currency)) · ACCESSORIAL \(CL350Fmt.money(s?.accessorialTotal, code: s?.currency)) · FEE \(CL350Fmt.money(s?.platformFee, code: s?.currency))")
                    .font(.system(size: 9, weight: .heavy)).kerning(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text(CL350Fmt.money(s?.carrierPayment, code: s?.currency))
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Brand.blue)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private func pctText(_ v: Double?, of total: Double) -> String {
        guard let v, total > 0 else { return "—" }
        return String(format: "%.1f%%", v / total * 100)
    }

    private func splitRow(dot: Color, name: String, sub: String, amt: String, pct: String) -> some View {
        HStack(spacing: 0) {
            Circle().fill(dot).frame(width: 10, height: 10)
            Text(name).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary).padding(.leading, 8)
            Text(sub).font(.system(size: 10)).foregroundStyle(palette.textSecondary).padding(.leading, 6)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(amt).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(pct).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    /// Live return-leg match from the state-level optimizer feed.
    private var matchedBackhaul: CL350Backhaul.Opp? {
        guard let opps = store.backhaul?.opportunities, !opps.isEmpty else { return nil }
        if let ln = store.load?.loadNumber?.cl350NilIfEmpty,
           let hit = opps.first(where: { $0.deliveryLoad == ln }) { return hit }
        return opps.first
    }

    private var backhaulCard: some View {
        Group {
            if let opp = matchedBackhaul {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 10).fill(Brand.blue.opacity(0.13)).frame(width: 40, height: 40)
                        .overlay(Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16)).foregroundStyle(Brand.info))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(opp.fromState) → \(opp.toState)")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text("return for \(opp.deliveryLoad) · candidate \(opp.backhaulLoad)")
                            .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text("covers the empty leg back")
                            .font(.system(size: 9.5)).foregroundStyle(Brand.success)
                    }
                    .padding(.leading, 12)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("EST SAVINGS").font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textSecondary)
                        Text(CL350Fmt.money(opp.estimatedSavings))
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(Brand.blue)
                    }
                }
                .padding(.horizontal, 16).frame(height: 78)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Brand.blue.opacity(0.45), lineWidth: 1.3))
            } else {
                CL350HonestStrip(icon: "arrow.uturn.backward",
                                 text: "No return-leg match on the board right now — the optimizer re-scans as new loads post near this delivery.")
            }
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 12) {
            CL350StagePayoutButton(store: store, loadId: loadId)
            Button {
                if let opp = matchedBackhaul { backhaulSheet = CL350BackhaulSheetItem(id: opp.backhaulLoad) }
            } label: {
                Text("Take backhaul")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(matchedBackhaul != nil ? palette.textPrimary : palette.textTertiary)
                    .frame(width: 126, height: 48)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(matchedBackhaul == nil)
        }
    }
}

// MARK: - Screens (CV350-CV356 — registered type names preserved)

struct CatalystAtGateScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystAtGateBody350(theme: theme, loadId: loadId) } }
}
struct CatalystAtDockScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystAtDockBody351(theme: theme, loadId: loadId) } }
}
struct CatalystDepartingScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystDepartingBody352(theme: theme, loadId: loadId) } }
}
struct CatalystPreDeliveryScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystPreDeliveryBody353(theme: theme, loadId: loadId) } }
}
struct CatalystAtDeliveryScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystAtDeliveryBody354(theme: theme, loadId: loadId) } }
}
struct CatalystPODReceiptScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystPodReceiptBody355(theme: theme, loadId: loadId) } }
}
struct CatalystLoadClosedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystLifecycleShell(theme: theme) { CatalystLoadClosedBody356(theme: theme, loadId: loadId) } }
}

// MARK: - Previews (Dark + Light per screen)

#Preview("CV350 Gate · Dark")       { CatalystAtGateScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV350 Gate · Light")      { CatalystAtGateScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV351 Dock · Dark")       { CatalystAtDockScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV351 Dock · Light")      { CatalystAtDockScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV352 Departing · Dark")  { CatalystDepartingScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV352 Departing · Light") { CatalystDepartingScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV353 PreDel · Dark")     { CatalystPreDeliveryScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV353 PreDel · Light")    { CatalystPreDeliveryScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV354 AtDel · Dark")      { CatalystAtDeliveryScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV354 AtDel · Light")     { CatalystAtDeliveryScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV355 POD · Dark")        { CatalystPODReceiptScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV355 POD · Light")       { CatalystPODReceiptScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV356 Closed · Dark")     { CatalystLoadClosedScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV356 Closed · Light")    { CatalystLoadClosedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
