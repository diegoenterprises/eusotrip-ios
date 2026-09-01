//
//  518_DispatcherBhInTransitCard.swift
//  EusoTrip — Dispatcher · BH lifecycle 518 · In-transit tracking surface.
//
//  Wireframe slot: 04 Dispatcher / 518 Dispatcher BH In-Transit Card (Light+Dark SVG,
//  golden re-port 2026-06-21 — replaces the stamped Dpch800 duodecet body for this id).
//  Composition: live position-evidence hero (origin/destination labels +
//  source-truth state + remaining-miles readout + ETA chip) → HOS / DRIVE LEFT /
//  SEAL KPI triple → driver row with hail button → 3-row geotag breadcrumb → CTA pair
//  (Hail driver / Live position).
//
//  Wiring manifest (code-traced against frontend/server/routers):
//    READ  loads.getById                        — load + lane + parties + economics.
//    READ  location.tracking.getLoadTracking    — position / route / geotags / ETA.
//    READ  dispatch.getDriverStatuses           — driver HOS hours + drivers.id.
//    WRITE dispatch.sendDriverMessage           — Hail driver.
//  Honest gaps (no server proc — rendered as data-absence states, never faked):
//    · seal-check rollup on the dispatch board (SEAL KPI)
//    · push-fed breadcrumb stream (geotags render from the poll read)
//
//  Dispatcher nav HOME·BOARD·[orb]·COMMS·ME, BOARD active. Light+Dark palette tokens only.
//

import SwiftUI
import Combine

// MARK: - Screen

struct DispatcherBHInTransit518Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            BH518Body(loadId: loadId)
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

private struct BH518Body: View {
    let loadId: String

    @Environment(\.palette) private var palette
    @Environment(\.dispatchNavHandler) private var navHandler

    @State private var load: LoadsAPI.LoadDetail?
    @State private var tracking: BH518Tracking?
    @State private var loadFailed = false
    @State private var driverRow: BH518DriverRow?
    @State private var sealRollup: BH518SealRollup?
    @State private var hailInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?
    @State private var showMapSheet = false
    @State private var now = Date()

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrowRow
                titleRow
                Rectangle().fill(palette.iridescentHairline).frame(height: 1)
                heroCard
                kpiTriple
                driverCard
                sectionLabel("LAST BREADCRUMB · \(breadcrumbs.count) GEOTAGS")
                breadcrumbCard
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
        .sheet(isPresented: $showMapSheet) { BH518MapSheet(tracking: tracking) }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · BACKHAUL · IN-TRANSIT")
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
            Text("In transit").font(.system(size: 26, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                Button("Refresh") { Task { await refresh() } }
                Button("Live position") { showMapSheet = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero — position evidence (no inferred route geometry)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(hasFix ? Brand.success : Brand.warning).frame(width: 6, height: 6)
                    Text(hasFix ? "LIVE · \(driverStateLabel)" : "AWAITING GPS FIX")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(hasFix ? Brand.success : Brand.warning)
                }
                Spacer()
                Text(heartbeatLabel)
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            BH518PositionEvidence(hasFix: hasFix)
                .frame(height: 110)
            HStack {
                Text(originLabel).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                Spacer()
                Text(destinationLabel).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Divider().overlay(palette.borderFaint)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(remainingMilesText)
                            .font(.system(size: 34, weight: .heavy).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                        Text("mi").font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    Text(remainingMilesText == "—" ? "no distance prediction yet" : "remaining on the lane")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ETA").font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(etaClockText)
                        .font(.system(size: 20, weight: .heavy).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text(etaRemainderText).font(.caption2).foregroundStyle(palette.textTertiary)
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

    // MARK: KPI triple — HOS / DRIVE LEFT / SEAL

    private var kpiTriple: some View {
        HStack(spacing: Space.s2) {
            BH518Kpi(label: "HOS LEFT",
                     value: hosText,
                     sub: hosText == "—" ? "driver hours not reported" : "reported · freshness unavailable",
                     tint: nil)
            BH518Kpi(label: "DRIVE LEFT",
                     value: driveLeftText,
                     sub: driveLeftText == "—" ? "no delivery prediction yet" : "to delivery",
                     tint: driveLeftText == "—" ? nil : Brand.info)
            BH518Kpi(label: "SEAL",
                     value: sealText,
                     sub: sealSub,
                     tint: sealTint)
        }
    }

    // MARK: Driver row

    private var driverCard: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: Space.s3) {
                Circle().fill(LinearGradient.diagonal).frame(width: 38, height: 38)
                    .overlay(Text(driverInitials).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(load?.driver?.name ?? "Driver not locked")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(driverSub).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                BH518Chip(text: driverStateLabel, tint: Brand.info)
                Button { Task { await hailDriver() } } label: {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(hailInFlight)
            }
        }
    }

    // MARK: Breadcrumbs

    private var breadcrumbs: [BH518Tracking.Geotag] {
        Array((tracking?.geotags ?? []).suffix(3).reversed())
    }

    private var breadcrumbCard: some View {
        LifecycleCard {
            if breadcrumbs.isEmpty {
                Text("No geotag events have posted for this load — breadcrumbs paint as the truck reports them.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { idx, tag in
                        HStack(alignment: .center, spacing: Space.s2) {
                            Circle()
                                .fill(idx == 0 ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderStrong))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bh518Humanize(tag.eventType))
                                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                                Text(tagSub(tag)).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            Text(relTime(tag.timestamp))
                                .font(EType.mono(.micro))
                                .foregroundStyle(idx == 0 ? Brand.success : palette.textTertiary)
                        }
                        .padding(.vertical, 7)
                        if idx < breadcrumbs.count - 1 { Divider().overlay(palette.borderFaint) }
                    }
                }
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await hailDriver() } } label: {
                HStack(spacing: 6) {
                    if hailInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Image(systemName: "bubble.left.fill").font(.system(size: 13, weight: .bold)) }
                    Text(hailInFlight ? "Hailing…" : "Hail driver").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(hailInFlight)

            Button { showMapSheet = true } label: {
                Text("Live position").font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(palette.textPrimary)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Derived display

    private var hasFix: Bool { tracking?.position != nil }

    private var driverStateLabel: String {
        (driverRow?.status ?? (load?.status == "in_transit" ? "driving" : nil)).map { $0.uppercased() } ?? "—"
    }

    private var heartbeatLabel: String {
        guard let iso = tracking?.position?.updatedAt, let d = bh518ISODate(iso) else { return "GPS —" }
        let secs = max(0, Int(now.timeIntervalSince(d)))
        if secs < 90 { return "GPS HB +\(secs)s" }
        return "GPS HB \(secs / 60)m ago"
    }

    private var remainingMilesText: String {
        guard let r = tracking?.eta?.remainingMiles else { return "—" }
        return "\(Int(r.rounded()))"
    }

    private var etaClockText: String {
        guard let iso = tracking?.eta?.predictedEta, let d = bh518ISODate(iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private var etaRemainderText: String {
        guard let m = tracking?.eta?.remainingMinutes else { return "no prediction yet" }
        return bh518HoursMinutes(m)
    }

    private var hosText: String {
        guard let h = driverRow?.hoursRemaining else { return "—" }
        let whole = Int(h)
        let mins = Int((h - Double(whole)) * 60)
        return "\(whole)h \(String(format: "%02d", mins))"
    }

    private var driveLeftText: String {
        guard let m = tracking?.eta?.remainingMinutes else { return "—" }
        return bh518HoursMinutes(m)
    }

    private var sealText: String {
        guard let s = sealRollup else { return "—" }
        if let intact = s.allSealsIntact { return intact ? "INTACT" : "BROKEN" }
        return "—"
    }

    private var sealSub: String {
        guard let s = sealRollup else { return "seal checks not shared to this board" }
        if s.allSealsIntact == nil { return "no seal status on record" }
        return "\(s.sealNumbers.count) seals verified"
    }

    private var sealTint: Color? {
        guard let s = sealRollup, let intact = s.allSealsIntact else { return nil }
        return intact ? Brand.success : Brand.danger
    }

    private var driverInitials: String {
        if let i = load?.driver?.initials, !i.isEmpty { return i }
        if let n = load?.driver?.name {
            let letters = n.split(separator: " ").prefix(2).compactMap { $0.first }
            if !letters.isEmpty { return String(letters).uppercased() }
        }
        return "—"
    }

    private var driverSub: String {
        var parts: [String] = []
        if let c = load?.catalyst?.companyName ?? load?.catalyst?.name { parts.append(c) }
        if let d = load?.driver?.dotNumber { parts.append("USDOT \(d)") }
        return parts.isEmpty ? "carrier detail not on this record" : parts.joined(separator: " · ")
    }

    private var originLabel: String {
        let c = load?.pickupLocation?.city ?? tracking?.origin?.city ?? "—"
        if let s = load?.pickupLocation?.state ?? tracking?.origin?.state { return "\(c.uppercased()), \(s.uppercased())" }
        return c.uppercased()
    }

    private var destinationLabel: String {
        let c = load?.deliveryLocation?.city ?? tracking?.destination?.city ?? "—"
        if let s = load?.deliveryLocation?.state ?? tracking?.destination?.state { return "\(c.uppercased()), \(s.uppercased())" }
        return c.uppercased()
    }

    private func tagSub(_ tag: BH518Tracking.Geotag) -> String {
        var parts: [String] = []
        if let d = bh518ISODate(tag.timestamp) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            parts.append(f.string(from: d))
        }
        if let src = tag.source { parts.append(src) }
        if let cat = tag.eventCategory { parts.append(bh518Humanize(cat).lowercased()) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func relTime(_ iso: String?) -> String {
        guard let d = bh518ISODate(iso) else { return "—" }
        let secs = max(0, Int(now.timeIntervalSince(d)))
        if secs < 60 { return "now" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        return "\(secs / 3600)h ago"
    }

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
        await fetchSealRollup()
        now = Date()
    }

    private func fetchTracking() async {
        struct In: Encodable { let loadId: Int }
        guard let numeric = Int((load?.id ?? loadId).replacingOccurrences(of: "load_", with: "")) else { return }
        do {
            tracking = try await EusoTripAPI.shared.query("location.tracking.getLoadTracking", input: In(loadId: numeric))
        } catch { tracking = nil }
    }

    private func fetchDriverRow() async {
        struct In: Encodable { let limit: Int }
        do {
            let rows: [BH518DriverRow] = try await EusoTripAPI.shared.query("dispatch.getDriverStatuses", input: In(limit: 50))
            let ln = load?.loadNumber
            let dn = load?.driver?.name
            driverRow = rows.first(where: { $0.load != nil && $0.load == ln })
                ?? rows.first(where: { dn != nil && $0.name == dn })
        } catch { driverRow = nil }
    }

    private func fetchSealRollup() async {
        struct In: Encodable { let loadId: String }
        let numericId = loadId.replacingOccurrences(of: "load_", with: "")
        do {
            sealRollup = try await EusoTripAPI.shared.query("dispatch.getSealRollup", input: In(loadId: numericId))
        } catch { sealRollup = nil }
    }

    private func hailDriver() async {
        guard !hailInFlight else { return }
        hailInFlight = true; actionAck = nil; actionError = nil
        defer { hailInFlight = false }
        guard let driverId = driverRow?.id else {
            actionError = "No driver row for this load is on the company board, so the hail wasn't sent."
            return
        }
        struct In: Encodable { let driverId: String; let message: String; let priority: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.sendDriverMessage",
                input: In(driverId: driverId,
                          message: "Checking in on \(load?.loadNumber ?? "your load") — reply with your status when it's safe to do so.",
                          priority: "normal"))
            if out.success == true {
                actionAck = "Hail sent to \(driverRow?.name ?? "the driver") — replies land in Comms."
            } else {
                actionError = "The hail didn't send. Tracking stays live — try again."
            }
        } catch {
            actionError = "The hail didn't send. Tracking stays live — check the connection and try again."
        }
    }
}

// MARK: - Position evidence

/// The tracking response exposes a point fix and numeric ETA, but no exact
/// committed route geometry. Keep those facts separate instead of placing a
/// truck on an authored curve that looks operational.
private struct BH518PositionEvidence: View {
    @Environment(\.palette) private var palette
    let hasFix: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill((hasFix ? Brand.success : Brand.warning).opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: hasFix ? "location.fill.viewfinder" : "location.slash")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(hasFix ? Brand.success : Brand.warning)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(hasFix ? "GPS OBSERVATION ON FILE" : "AWAITING GPS OBSERVATION")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(hasFix ? Brand.success : Brand.warning)
                Text(hasFix
                     ? "Open Live position for the exact reported coordinate."
                     : "The exact coordinate appears after the next authorized heartbeat.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Text("Route geometry is not bound to this dispatch read.")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "truck.box.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            hasFix
                ? "GPS observation on file. Exact reported coordinate is available in Live position. Route geometry is not bound."
                : "Awaiting GPS observation. Route geometry is not bound."
        )
    }
}

// MARK: - Live-position sheet

private struct BH518MapSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let tracking: BH518Tracking?

    var body: some View {
        ZStack {
            palette.bgPrimary.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack {
                        Text("Live position").font(EType.h2).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(palette.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    LifecycleCard {
                        BH518PositionEvidence(hasFix: tracking?.position != nil)
                            .frame(height: 220)
                    }
                    LifecycleCard {
                        if let p = tracking?.position {
                            if let coordinate = LatLongParser.validatedCoordinate(
                                latitude: p.lat,
                                longitude: p.lng
                            ) {
                                row("GPS", LatLongParser.displayString(coordinate))
                            } else {
                                row("GPS", "Not recorded")
                            }
                            row("Speed", p.speed.map { String(format: "%.0f mph", $0) } ?? "—")
                            row("Remaining", tracking?.eta?.remainingMiles.map { "\(Int($0.rounded())) mi" } ?? "—")
                            row("Predicted", tracking?.eta?.predictedEta ?? "—")
                        } else {
                            Text("No GPS fix has posted for this load — the exact position appears when the truck reports.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                    Spacer(minLength: 24)
                }
                .padding(Space.s4)
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).font(EType.mono(.caption)).foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Small primitives

private struct BH518Chip: View {
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

private struct BH518Kpi: View {
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

// MARK: - File-local decode + helpers

private struct BH518Tracking: Decodable {
    struct Point: Decodable { let lat: Double?; let lng: Double?; let address: String?; let city: String?; let state: String? }
    struct Position: Decodable { let lat: Double?; let lng: Double?; let speed: Double?; let heading: Double?; let updatedAt: String? }
    struct Route: Decodable { let distanceMiles: Double?; let durationSeconds: Int? }
    struct Geotag: Decodable { let id: Int?; let eventType: String?; let eventCategory: String?; let lat: Double?; let lng: Double?; let timestamp: String?; let source: String? }
    struct Eta: Decodable { let predictedEta: String?; let remainingMiles: Double?; let remainingMinutes: Int? }
    let loadId: Int?
    let loadNumber: String?
    let status: String?
    let origin: Point?
    let destination: Point?
    let position: Position?
    let route: Route?
    let geotags: [Geotag]?
    let eta: Eta?
}

private struct BH518DriverRow: Decodable {
    let id: String?
    let name: String?
    let status: String?
    let load: String?
    let hoursRemaining: Double?
}

private func bh518Humanize(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    return raw.replacingOccurrences(of: "_", with: " ").capitalized
}

private struct BH518SealRollup: Decodable {
    let loadId: Int?
    let allSealsIntact: Bool?
    let sealNumbers: [String]
}

private func bh518HoursMinutes(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
}

private func bh518ISODate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    return ISO8601DateFormatter().date(from: s)
}

// MARK: - Previews

#Preview("518 In Transit · Dark") {
    DispatcherBHInTransit518Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("518 In Transit · Light") {
    DispatcherBHInTransit518Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
