//
//  521_DispatcherBhDockedLoadingCard.swift
//  EusoTrip — Dispatcher · BH lifecycle 521 · Docked loading (trailer-fill progress).
//
//  Wireframe slot: 04 Dispatcher / 521 Dispatcher BH Docked Loading Card (Light+Dark SVG,
//  golden re-port 2026-06-21 — replaces the stamped Dpch800 duodecet body for this id).
//  Composition (SVG-verbatim): trailer-fill loading hero (side-view trailer + pallet
//  readout + depart chip + progress bar) → DWELL / ETA CLEAR / HOS KPI triple →
//  loading-detail card → detention-watch strip → CTA pair (Update loading / Mark loaded).
//
//  Wiring manifest (code-traced against frontend/server/routers):
//    READ  loads.getById                        — load + pallet denominator + parties.
//    READ  location.tracking.getLoadTracking    — dwell (detention record) + geofences.
//    READ  dispatch.getDriverStatuses           — driver HOS hours + drivers.id.
//    WRITE dispatch.sendDriverMessage           — Update loading (progress ask to the cab).
//    WRITE dispatch.updateLoadStatus            — Mark loaded (status → loaded).
//  Honest gaps (no server proc — rendered as data-absence states, never faked):
//    · live pallet count / loading rate / forklift + spot ids (facility feed)
//    · dock schedule keyed to this load's receiving facility (depart countdown)
//
//  Dispatcher nav HOME·BOARD·[orb]·COMMS·ME, BOARD active. Light+Dark palette tokens only.
//

import SwiftUI
import Combine

// MARK: - Screen

struct DispatcherBHDockedLoading521Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            BH521Body(loadId: loadId)
        } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct BH521Body: View {
    let loadId: String

    @Environment(\.palette) private var palette
    @Environment(\.dispatchNavHandler) private var navHandler

    @State private var load: LoadsAPI.LoadDetail?
    @State private var tracking: BH521Tracking?
    @State private var loadFailed = false
    @State private var driverRow: BH521DriverRow?
    @State private var updateInFlight = false
    @State private var loadedInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?
    @State private var now = Date()
    @State private var palletCount: Int? = nil
    @State private var loadingRate: Double? = nil
    @State private var forkliftId: String? = nil
    @State private var spotId: String? = nil
    @State private var dockDepartDate: Date? = nil

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrowRow
                titleRow
                Rectangle().fill(palette.iridescentHairline).frame(height: 1)
                heroCard
                kpiTriple
                sectionLabel("LOADING DETAIL")
                loadingDetail
                detentionStrip
                if let ack = actionAck {
                    LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(Brand.success) }
                }
                if let err = actionError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                }
                if loadFailed {
                    LifecycleCard(accentWarning: true) {
                        Text("Couldn't reach the board for this load. Everything shown is the last loaded state — pull to refresh.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await refresh() }
        .eusoRefreshable { await refresh() }
        .onReceive(clock) { now = $0 }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · BACKHAUL · DOCKED LOADING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text("\(load?.loadNumber ?? "—") · \(load?.rateDisplay ?? "—")")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
        }
    }

    private var titleRow: some View {
        HStack(spacing: Space.s3) {
            Button { navHandler?("board") } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            Text("Docked").font(.system(size: 26, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                Button("Refresh") { Task { await refresh() } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero — trailer fill

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Brand.magenta).frame(width: 6, height: 6)
                    Text(isDockedStage ? "LOADING · AT THE DOCK" : "STAGE · \(bh521Humanize(load?.status).uppercased())")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.magenta)
                }
                Spacer()
                Text(dwellHeaderLabel)
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            BH521TrailerFill()
                .frame(height: 90)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(palletCount.map { "\($0)" } ?? "—").font(.system(size: 34, weight: .heavy).monospacedDigit()).foregroundStyle(palette.textPrimary)
                        Text(palletDenominatorText)
                            .font(.system(size: 16, weight: .heavy).monospacedDigit()).foregroundStyle(palette.textTertiary)
                    }
                    Text(palletCount == nil ? "PALLETS LOADED · live counts post from the dock; none received" : "PALLETS LOADED · current count from the facility feed")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("DEPART").font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(departCountdownText).font(.system(size: 20, weight: .heavy).monospacedDigit()).foregroundStyle(palette.textPrimary)
                    Text(dockDepartDate == nil ? "no dock appointment on file" : "scheduled release").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.5), Brand.magenta.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }

    // MARK: KPI triple — DWELL / ETA CLEAR / HOS

    private var kpiTriple: some View {
        HStack(spacing: Space.s2) {
            BH521Kpi(label: "DWELL",
                     value: dwellText,
                     sub: dwellText == "—" ? "no gate-in recorded" : "at this dock",
                     tint: nil)
            BH521Kpi(label: "ETA CLEAR",
                     value: departCountdownText,
                     sub: dockDepartDate == nil ? "dock schedule not linked to this load" : "until scheduled release",
                     tint: nil)
            BH521Kpi(label: "HOS LEFT",
                     value: hosText,
                     sub: hosText == "—" ? "driver hours not reported" : "reported · freshness unavailable",
                     tint: nil)
        }
    }

    // MARK: Loading detail

    private var loadingDetail: some View {
        LifecycleCard {
            VStack(spacing: 0) {
                BH521DetailRow(title: "Spot position",
                               value: spotId ?? "not posted",
                               sub: spotId == nil ? "spot assignments post from the facility" : "assigned loading bay")
                Divider().overlay(palette.borderFaint)
                BH521DetailRow(title: "Forklift / loader",
                               value: forkliftId ?? "not posted",
                               sub: forkliftId == nil ? "loader activity posts from the facility" : "assigned facility asset")
                Divider().overlay(palette.borderFaint)
                BH521DetailRow(title: "Est. complete",
                               value: isDockedStage ? "in progress" : "—",
                               sub: isDockedStage ? "advances when the driver marks loaded" : "arms when loading starts")
            }
        }
    }

    // MARK: Detention-watch strip

    private var detentionStrip: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: Space.s2) {
                Image(systemName: "pause.circle")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(watchTitle)
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(watchSub)
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                BH521Chip(text: watchChip, tint: watchChip == "PAUSED" ? Brand.warning : Brand.neutral)
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await updateLoading() } } label: {
                HStack(spacing: 6) {
                    if updateInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Image(systemName: "square.and.pencil").font(.system(size: 13, weight: .bold)) }
                    Text(updateInFlight ? "Asking…" : "Update loading").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(updateInFlight)

            Button { Task { await markLoaded() } } label: {
                HStack(spacing: 6) {
                    if loadedInFlight { ProgressView().scaleEffect(0.8) }
                    Text(loadedInFlight ? "Posting…" : "Mark loaded").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(palette.textPrimary)
                .background(Capsule().fill(palette.bgCard))
                .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(loadedInFlight)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Derived display

    private var isDockedStage: Bool {
        ["loading", "loading_exception", "at_pickup", "pickup_checkin", "at_delivery", "delivery_checkin", "unloading"].contains(load?.status ?? "")
    }

    private var activeDetention: BH521Tracking.Detention? {
        (tracking?.detention ?? []).last(where: { $0.exitAt == nil }) ?? (tracking?.detention ?? []).last
    }

    private var dwellHeaderLabel: String {
        if activeDetention != nil { return "DWELL CLOCK LIVE" }
        return "WATCH —"
    }

    private var departCountdownText: String {
        guard let d = dockDepartDate else { return "—" }
        let diff = Int(d.timeIntervalSince(now))
        guard diff > 0 else { return "LATE" }
        return String(format: "%d:%02d", diff / 60, diff % 60)
    }

    private var dwellText: String {
        guard let rec = activeDetention else { return "—" }
        if rec.exitAt == nil, let enter = bh521ISODate(rec.enterAt) {
            let m = max(0, Int(now.timeIntervalSince(enter) / 60))
            return String(format: "%d:%02d", m / 60, m % 60)
        }
        if let m = rec.totalDwellMinutes { return String(format: "%d:%02d", m / 60, m % 60) }
        return "—"
    }

    private var palletDenominatorText: String {
        if let p = load?.palletCount, p > 0 { return "/\(p)" }
        return "/—"
    }

    private var hosText: String {
        guard let h = driverRow?.hoursRemaining else { return "—" }
        let whole = Int(h)
        let mins = Int((h - Double(whole)) * 60)
        return "\(whole)h \(String(format: "%02d", mins))"
    }

    private var watchTitle: String {
        isDockedStage ? "Detention watch paused" : "Detention watch"
    }

    private var watchSub: String {
        if isDockedStage { return "the clock idles while work is active at the dock · gross \(load?.rateDisplay ?? "—") locked" }
        if activeDetention != nil { return "a dwell record is open on this load" }
        return "no dwell record is open on this load"
    }

    private var watchChip: String { isDockedStage ? "PAUSED" : "—" }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            .padding(.top, Space.s1)
    }

    // MARK: Data

    private func refresh() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
            loadFailed = false
        } catch { loadFailed = load == nil }
        await fetchTracking()
        await fetchDriverRow()
        now = Date()
    }

    private func fetchTracking() async {
        struct In: Encodable { let loadId: Int }
        guard let numeric = Int((load?.id ?? loadId).replacingOccurrences(of: "load_", with: "")) else { return }
        do {
            let res: BH521Tracking = try await EusoTripAPI.shared.query("location.tracking.getLoadTracking", input: In(loadId: numeric))
            tracking = res
            palletCount = res.palletCount
            loadingRate = res.loadingRate
            forkliftId = res.forkliftId
            spotId = res.spotId
            dockDepartDate = bh521ISODate(res.dockDepartDate)
        } catch { tracking = nil }
    }

    private func fetchDriverRow() async {
        struct In: Encodable { let limit: Int }
        do {
            let rows: [BH521DriverRow] = try await EusoTripAPI.shared.query("dispatch.getDriverStatuses", input: In(limit: 50))
            let ln = load?.loadNumber
            let dn = load?.driver?.name
            driverRow = rows.first(where: { $0.load != nil && $0.load == ln })
                ?? rows.first(where: { dn != nil && $0.name == dn })
        } catch { driverRow = nil }
    }

    private func updateLoading() async {
        guard !updateInFlight else { return }
        updateInFlight = true; actionAck = nil; actionError = nil
        defer { updateInFlight = false }
        guard let driverId = driverRow?.id else {
            actionError = "No driver row for this load is on the company board, so the progress ask wasn't sent."
            return
        }
        struct In: Encodable { let driverId: String; let message: String; let priority: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.sendDriverMessage",
                input: In(driverId: driverId,
                          message: "Loading check on \(load?.loadNumber ?? "your load") — post your pallet count and estimated finish when you can.",
                          priority: "normal"))
            if out.success == true {
                actionAck = "Progress ask sent to \(driverRow?.name ?? "the driver") — their reply lands in Comms."
            } else {
                actionError = "The progress ask didn't send. The dock card stays live — try again."
            }
        } catch {
            actionError = "The progress ask didn't send. The dock card stays live — check the connection and try again."
        }
    }

    private func markLoaded() async {
        guard !loadedInFlight else { return }
        loadedInFlight = true; actionAck = nil; actionError = nil
        defer { loadedInFlight = false }
        struct In: Encodable { let loadId: String; let status: String }
        struct Out: Decodable { let success: Bool?; let newStatus: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation("dispatch.updateLoadStatus",
                                                                 input: In(loadId: loadId, status: "loaded"))
            if out.success == true {
                actionAck = "Marked loaded — the board advances this card off the dock."
                await refresh()
            } else {
                actionError = "The stage didn't advance. The board still shows the last saved stage — try again."
            }
        } catch {
            actionError = "The stage didn't post. The board still shows the last saved stage — check the connection and try again."
        }
    }
}

// MARK: - Trailer-fill canvas (honest: outline only until a live count posts)

private struct BH521TrailerFill: View {
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let boxRect = CGRect(x: w * 0.06, y: h * 0.12, width: w * 0.66, height: h * 0.52)
            ZStack {
                // Trailer box
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(palette.borderStrong, lineWidth: 1.5)
                    .frame(width: boxRect.width, height: boxRect.height)
                    .position(x: boxRect.midX, y: boxRect.midY)
                // Cab
                Path { p in
                    let cx = w * 0.74, cy = h * 0.30
                    p.move(to: CGPoint(x: cx, y: cy))
                    p.addLine(to: CGPoint(x: cx + w * 0.12, y: cy + h * 0.06))
                    p.addLine(to: CGPoint(x: cx + w * 0.14, y: h * 0.64))
                    p.addLine(to: CGPoint(x: cx, y: h * 0.64))
                    p.closeSubpath()
                }
                .stroke(palette.borderStrong, lineWidth: 1.5)
                // Wheels
                ForEach([0.16, 0.24, 0.62, 0.80], id: \.self) { fx in
                    Circle().strokeBorder(palette.borderStrong, lineWidth: 1.5)
                        .frame(width: h * 0.18, height: h * 0.18)
                        .position(x: w * fx, y: h * 0.74)
                }
                // Honest availability copy inside the trailer
                Text("Live fill paints when the dock posts a pallet count")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: boxRect.width - 12)
                    .position(x: boxRect.midX, y: boxRect.midY)
            }
        }
    }
}

// MARK: - Small primitives

private struct BH521Chip: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
    }
}

private struct BH521Kpi: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let sub: String
    let tint: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundStyle(tint ?? palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

private struct BH521DetailRow: View {
    @Environment(\.palette) private var palette
    let title: String
    let value: String
    let sub: String
    var body: some View {
        HStack(alignment: .center, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text(sub).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Text(value).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - File-local decode + helpers

private struct BH521Tracking: Decodable {
    struct Detention: Decodable {
        let id: Int?
        let enterAt: String?
        let exitAt: String?
        let totalDwellMinutes: Int?
        let detentionMinutes: Int?
        let detentionCharge: Double?
        let isBillable: Bool?
        let freeTimeMinutes: Int?
    }
    let loadId: Int?
    let status: String?
    let detention: [Detention]?
    let palletCount: Int?
    let loadingRate: Double?
    let forkliftId: String?
    let spotId: String?
    let dockDepartDate: String?
}

private struct BH521DriverRow: Decodable {
    let id: String?
    let name: String?
    let status: String?
    let load: String?
    let hoursRemaining: Double?
}

private func bh521Humanize(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    return raw.replacingOccurrences(of: "_", with: " ").capitalized
}

private func bh521ISODate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    return ISO8601DateFormatter().date(from: s)
}

// MARK: - Previews

#Preview("521 Docked · Dark") {
    DispatcherBHDockedLoading521Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("521 Docked · Light") {
    DispatcherBHDockedLoading521Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
