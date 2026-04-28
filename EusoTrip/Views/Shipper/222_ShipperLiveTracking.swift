//
//  222_ShipperLiveTracking.swift
//  EusoTrip 2027 UI — brick 222 (shipper · live carrier tracking)
//
//  Live position telemetry for every in-transit load on the
//  Shipper's plate. Mirrors the shipper-relevant slice of the web
//  `/live-tracking` (`DriverTracking.tsx`) — but flipped to the
//  shipper's perspective: instead of plotting "my own driver",
//  we plot the assigned carrier driver of each active load.
//
//  Wires:
//    • `shippers.getActiveLoads` — pulls in_transit + assigned rows
//      with `driverId` (server addition this firing).
//    • `telemetry.getLiveLocation(driverId:)` — last GPS ping per row.
//    • `telemetry.getTrail(driverId:hoursBack:)` — recent breadcrumb
//      trail for the detail sheet.
//
//  Refresh cadence: 20 s polling on the list (matches the web peer's
//  `refetchInterval`). Detail sheet refreshes on appear + pull-to-
//  refresh.
//

import SwiftUI

// MARK: - Store

@MainActor
final class ShipperLiveTrackingStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var loads: [ShipperAPI.ActiveLoad] = []
    @Published private(set) var positions: [Int: ShipperTelemetryAPI.LiveLocation] = [:]
    @Published private(set) var lastRefresh: Date? = nil

    private let api: EusoTripAPI
    private var pollTask: Task<Void, Never>? = nil

    init(api: EusoTripAPI = .shared) { self.api = api }

    deinit { pollTask?.cancel() }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(nanoseconds: 20 * 1_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        if case .loaded = phase {} else { phase = .loading }
        do {
            let active = try await api.shipper.getActiveLoads(limit: 25)
            let inTransit = active.filter { l in
                let s = l.status.lowercased()
                return s == "in_transit" || s == "loading" || s == "assigned"
            }
            self.loads = inTransit
            await fanFetchPositions(for: inTransit)
            self.lastRefresh = Date()
            self.phase = .loaded
        } catch {
            self.phase = .error("Couldn't reach tracking service.")
        }
    }

    private func fanFetchPositions(for loads: [ShipperAPI.ActiveLoad]) async {
        let driverIds: [Int] = loads.compactMap { $0.driverId }
        await withTaskGroup(of: (Int, ShipperTelemetryAPI.LiveLocation?).self) { group in
            for id in driverIds {
                group.addTask { [api] in
                    let loc = try? await api.shipperTelemetry.getLiveLocation(driverId: id)
                    return (id, loc)
                }
            }
            for await (id, loc) in group {
                if let loc { self.positions[id] = loc }
            }
        }
    }
}

// MARK: - Brick

struct ShipperLiveTracking: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperLiveTrackingStore()
    @State private var detail: ShipperAPI.ActiveLoad? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                statsHero
                listSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .refreshable { await store.refresh() }
        .task {
            store.startPolling()
        }
        .onDisappear { store.stopPolling() }
        .sheet(item: $detail) { ShipperLiveTrackingDetail(load: $0) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "location.north.line.fill").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36).background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · LIVE TRACKING").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("In-transit fleet").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                if let r = store.lastRefresh {
                    Text("Updated \(Self.relative(r)) · refreshes every 20 s")
                        .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                } else {
                    Text("Live carrier coords + breadcrumb trails for every active load.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(8).background(LinearGradient.diagonal).clipShape(Circle())
            }.buttonStyle(.plain)
        }.padding(.top, 4)
    }

    private var statsHero: some View {
        let live = store.positions.values.filter { !$0.stale }.count
        let stale = store.positions.values.filter { $0.stale }.count
        let unassigned = store.loads.filter { $0.driverId == nil }.count
        return HStack(spacing: Space.s2) {
            statTile(label: "ACTIVE", value: "\(store.loads.count)", color: nil)
            statTile(label: "LIVE", value: "\(live)", color: Brand.success)
            statTile(label: "STALE", value: "\(stale + unassigned)", color: Brand.warning)
        }
    }

    private func statTile(label: String, value: String, color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient.diagonal))
                .monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private var listSection: some View {
        switch store.phase {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("Pinging carriers…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m):
            errorCard(m)
        case .loaded:
            if store.loads.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 8) {
                    ForEach(store.loads) { l in
                        Button { detail = l } label: { row(l) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ l: ShipperAPI.ActiveLoad) -> some View {
        let pos: ShipperTelemetryAPI.LiveLocation? = l.driverId.flatMap { store.positions[$0] }
        return HStack(alignment: .top, spacing: 10) {
            statusDot(for: l, position: pos)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(l.loadNumber).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                    statusPill(l.status)
                }
                Text("\(l.origin) → \(l.destination)").font(EType.caption)
                    .foregroundStyle(palette.textSecondary).lineLimit(1)
                HStack(spacing: 8) {
                    if let pos {
                        if pos.stale {
                            Label("Stale", systemImage: "wifi.exclamationmark")
                                .font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.warning)
                        } else {
                            Label(speedLabel(pos.speed), systemImage: "speedometer")
                                .font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.success)
                            if let h = pos.heading {
                                Label(headingLabel(h), systemImage: "location.north.line.fill")
                                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textSecondary)
                            }
                        }
                        if let u = pos.updatedAt {
                            Text(Self.relative(parseISO(u))).font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.textTertiary)
                        }
                    } else if l.driverId == nil {
                        Label("Unassigned", systemImage: "person.fill.questionmark")
                            .font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    } else {
                        Label("No ping", systemImage: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(rateLabel(l.rate)).font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                Text(l.eta).font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary).lineLimit(1)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func statusDot(for l: ShipperAPI.ActiveLoad, position: ShipperTelemetryAPI.LiveLocation?) -> some View {
        let color: Color = {
            if l.driverId == nil { return palette.textTertiary }
            guard let p = position else { return palette.textTertiary }
            return p.stale ? Brand.warning : Brand.success
        }()
        return Circle().fill(color)
            .frame(width: 10, height: 10)
            .overlay(Circle().fill(color.opacity(0.3)).scaleEffect(2.0))
            .padding(.top, 6)
    }

    private func statusPill(_ s: String) -> some View {
        Text(s.replacingOccurrences(of: "_", with: " ").uppercased())
            .font(.system(size: 8, weight: .heavy)).tracking(0.7)
            .foregroundStyle(palette.textTertiary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "location.slash").font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No in-transit loads").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Loads in `assigned`, `loading`, or `in_transit` status will appear here with live carrier coords.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4).frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.refresh() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - helpers

    private static func relative(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s/60))m ago" }
        if s < 86400 { return "\(Int(s/3600))h ago" }
        return "\(Int(s/86400))d ago"
    }

    private func parseISO(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
    }

    private func speedLabel(_ s: Double?) -> String {
        guard let s, s > 0 else { return "Idle" }
        return String(format: "%.0f mph", s)
    }

    private func headingLabel(_ h: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int(((h.truncatingRemainder(dividingBy: 360) + 360) / 45).rounded()) % 8
        return dirs[idx]
    }

    private func rateLabel(_ r: Double) -> String {
        if r >= 1000 { return String(format: "$%.1fK", r/1000) }
        return String(format: "$%.0f", r)
    }
}

// MARK: - Detail sheet

struct ShipperLiveTrackingDetail: View {
    let load: ShipperAPI.ActiveLoad
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var live: ShipperTelemetryAPI.LiveLocation? = nil
    @State private var trail: [ShipperTelemetryAPI.TrailPoint] = []
    @State private var phase: Phase = .loading

    enum Phase { case loading, loaded, error(String) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                hero
                if case .loading = phase {
                    loadingCard
                } else if case .error(let m) = phase {
                    errorCard(m)
                } else {
                    livePanel
                    trailCard
                }
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(palette.bgPage)
        .task { await fetch() }
        .refreshable { await fetch() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIVE LOAD").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text(load.loadNumber).font(.system(size: 24, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("\(load.origin) → \(load.destination)").font(EType.body).foregroundStyle(palette.textSecondary)
            HStack(spacing: 10) {
                if load.driverId != nil {
                    Label(load.driver, systemImage: "person.fill")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                }
                Label(load.eta, systemImage: "clock.fill")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
            }.padding(.top, 4)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var loadingCard: some View {
        HStack {
            ProgressView()
            Text("Pulling telemetry…").font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await fetch() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private var livePanel: some View {
        if let p = live {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("CURRENT POSITION").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    if p.stale {
                        Label("Stale", systemImage: "wifi.exclamationmark")
                            .font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.warning)
                    } else {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.success)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(coordsLabel(p)).font(.system(size: 18, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                }
                HStack(spacing: 8) {
                    metric("Speed", value: speedLabel(p.speed), tint: Brand.success)
                    metric("Heading", value: headingLabel(p.heading), tint: nil)
                    metric("Updated", value: updatedLabel(p.updatedAt), tint: nil)
                }
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        } else {
            Text("Carrier hasn't pinged yet.").font(EType.caption).foregroundStyle(palette.textSecondary)
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func metric(_ k: String, value: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(palette.textPrimary))
                .monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s2)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var trailCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("BREADCRUMB · LAST 4 H").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(trail.count) pts").font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if trail.isEmpty {
                Text("No trail recorded yet.").font(EType.caption).foregroundStyle(palette.textSecondary)
                    .padding(.vertical, 6)
            } else {
                BreadcrumbSparkline(points: trail).frame(height: 110)
                Text("Most recent ping: \(trail.last.map { relativeTrail($0.recordedAt) } ?? "—")")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - data

    private func fetch() async {
        guard let id = load.driverId else {
            phase = .error("This load has no driver assigned yet.")
            return
        }
        phase = .loading
        do {
            async let l = EusoTripAPI.shared.shipperTelemetry.getLiveLocation(driverId: id)
            async let t = EusoTripAPI.shared.shipperTelemetry.getTrail(driverId: id, hoursBack: 4)
            self.live  = try await l
            self.trail = (try? await t) ?? []
            self.phase = .loaded
        } catch {
            self.phase = .error("Couldn't reach tracking service.")
        }
    }

    // MARK: - formatters

    private func coordsLabel(_ p: ShipperTelemetryAPI.LiveLocation) -> String {
        guard let lat = p.lat, let lng = p.lng else { return "— · —" }
        return String(format: "%.4f° · %.4f°", lat, lng)
    }

    private func speedLabel(_ s: Double?) -> String {
        guard let s, s > 0 else { return "Idle" }
        return String(format: "%.0f mph", s)
    }

    private func headingLabel(_ h: Double?) -> String {
        guard let h else { return "—" }
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int(((h.truncatingRemainder(dividingBy: 360) + 360) / 45).rounded()) % 8
        return dirs[idx]
    }

    private func updatedLabel(_ iso: String?) -> String {
        guard let iso else { return "—" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s/60))m" }
        return "\(Int(s/3600))h"
    }

    private func relativeTrail(_ iso: String) -> String { updatedLabel(iso) + " ago" }
}

// MARK: - sparkline

private struct BreadcrumbSparkline: View {
    let points: [ShipperTelemetryAPI.TrailPoint]
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            if points.count >= 2 {
                let lats = points.map { $0.lat }
                let lngs = points.map { $0.lng }
                let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 1
                let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 1
                let dLat = max(maxLat - minLat, 0.0001)
                let dLng = max(maxLng - minLng, 0.0001)
                Path { p in
                    for (i, pt) in points.enumerated() {
                        let x = w * ((pt.lng - minLng) / dLng)
                        let y = h - h * ((pt.lat - minLat) / dLat)
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(LinearGradient.diagonal, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    let x = w * ((last.lng - minLng) / dLng)
                    let y = h - h * ((last.lat - minLat) / dLat)
                    Circle().fill(Brand.success).frame(width: 8, height: 8)
                        .overlay(Circle().fill(Brand.success.opacity(0.3)).scaleEffect(2.4))
                        .position(x: x, y: y)
                }
            } else {
                Text("Insufficient points").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

// MARK: - Previews

#Preview("Live · Dark") {
    ShipperLiveTracking().preferredColorScheme(.dark)
}

#Preview("Live · Light") {
    ShipperLiveTracking().preferredColorScheme(.light)
}
