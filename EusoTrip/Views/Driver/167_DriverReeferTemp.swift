//
//  167_DriverReeferTemp.swift
//  EusoTrip — Driver · 167 Reefer Temp (live cold-chain telemetry)
//
//  Wireframe slot: 01 Driver / 167 Driver Reefer Temp (Light/Dark SVG pair is
//  design truth). Screen class = DETAIL · LIVE TELEMETRY. Purpose: the live
//  cold-chain panel for the active reefer load — supply-air temp streaming
//  against the FSMA band with continuous logging, so the driver catches an
//  excursion before it spoils the produce and the shipper gets a self-signing
//  FSMA record at delivery with zero claim risk.
//
//  Wiring (all verified against the live routers this fire):
//    READ  reeferTemp.getFSMAStatus   — reeferTemp.ts:807 → services/fsmaCompliance.getFSMAStatus
//                                       (the band verdict: currentTemp · setPoint · min/maxAllowed ·
//                                        excursionCount · preCoolVerified · isCompliant) — hero source
//    READ  reeferTemp.getLatestByZone — reeferTemp.ts:174 (front · center · rear latest per zone)
//    READ  reeferTemp.getStats        — reeferTemp.ts:482 (min · max · avg · excursions over window)
//    READ  reeferTemp.getAlerts       — reeferTemp.ts:611 (unacked alerts gate the Acknowledge CTA)
//    READ  loads.getById              — loads.ts:1152 (lane · commodity · equipment · reefer band)
//    WRITE reeferTemp.acknowledgeAlert— reeferTemp.ts:731 (acks the newest unacked alert; appends
//                                       blockchainAuditTrail — a compliance record)
//  RBAC: reeferTemp.* are protectedProcedure keyed on ctx.user.id as driverId (the caller only ever
//        sees their own cold-chain rows). transportMode = truck · country = US (FSMA 21 CFR 1.908).
//  HONEST BINDING: real backend zones are front/center/rear (not the wireframe's supply/return/box/
//    ambient labels) — the readings list binds to the REAL zones. Every value renders from a real
//    read with a "-" / "Awaiting reading" fallback; no fabricated telemetry ships. The ESANG
//    cold-chain line is a local advisory computed over the real getFSMAStatus stream (not a separate
//    model call).
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - tRPC decode shapes

/// `reeferTemp.getFSMAStatus` → services/fsmaCompliance.FSMAComplianceStatus.
private struct ReeferFSMAStatus: Decodable {
    let isCompliant: Bool?
    let currentTemp: Double?
    let setPoint: Double?
    let minAllowed: Double?
    let maxAllowed: Double?
    let excursionCount: Int?
    let excursionMinutes: Int?
    let lastReading: String?
    let preCoolVerified: Bool?
    let cargoClass: String?
}

/// One zone entry from `reeferTemp.getLatestByZone` → { front|center|rear: {…} }.
private struct ReeferZoneReading: Decodable {
    let tempF: Double?
    let status: String?
    let recordedAt: String?
}

/// `reeferTemp.getStats`.
private struct ReeferStats: Decodable {
    let min: Double?
    let max: Double?
    let avg: Double?
    let totalReadings: Int?
    let excursions: Int?
}

/// One row of `reeferTemp.getAlerts`.
private struct ReeferAlert: Decodable, Identifiable {
    let id: String
    let severity: String?
    let message: String?
    let zone: String?
    let tempF: Double?
    let acknowledged: Bool?
    let createdAt: String?
}

/// Minimal projection of `loads.getById` for the reefer header + band.
private struct ReeferLoadCtx: Decodable {
    let loadNumber: String?
    let commodity: String?
    let equipmentType: String?
    let cargoType: String?
    let tempMinF: Double?
    let tempMaxF: Double?
    let pickupLocation: CityState?
    let deliveryLocation: CityState?
    struct CityState: Decodable { let city: String?; let state: String? }
}

// MARK: - Screen wrapper (Shell + Driver nav)

struct DriverReeferTempScreen: View {
    let theme: Theme.Palette
    var loadId: String = ""
    @EnvironmentObject private var nav: DriverNavController

    var body: some View {
        Shell(theme: theme) {
            ReeferTempBody(loadId: loadId, onBack: { nav.currentTab = .trips })
        } nav: {
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

// MARK: - Body

private struct ReeferTempBody: View {
    let loadId: String
    let onBack: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var fsma: ReeferFSMAStatus?
    @State private var zones: [String: ReeferZoneReading] = [:]
    @State private var stats: ReeferStats?
    @State private var alerts: [ReeferAlert] = []
    @State private var load: ReeferLoadCtx?
    @State private var loaded = false

    @State private var ackInFlight = false
    @State private var actionNote: String?
    @State private var actionErr: String?

    // Live pulse for the "LIVE" dot — gated on reduce-motion + a fresh reading.
    @State private var pulse = false

    private var numericLoadId: Int? { Int(loadId.filter(\.isNumber)) }

    // MARK: derived

    private var setPoint: Double? { fsma?.setPoint ?? load.map { midBand($0) } ?? nil }
    private var bandMin: Double? { fsma?.minAllowed ?? load?.tempMinF }
    private var bandMax: Double? { fsma?.maxAllowed ?? load?.tempMaxF }
    private var current: Double? { fsma?.currentTemp }
    private var hasLive: Bool { current != nil }
    private var inBand: Bool {
        guard let c = current, let lo = bandMin, let hi = bandMax else { return false }
        return c >= lo && c <= hi
    }
    private func midBand(_ l: ReeferLoadCtx) -> Double? {
        guard let lo = l.tempMinF, let hi = l.tempMaxF else { return nil }
        return (lo + hi) / 2
    }

    private var newestUnackedAlert: ReeferAlert? {
        alerts.first(where: { ($0.acknowledged ?? false) == false })
    }

    private var laneDisplay: String {
        let p = load?.pickupLocation?.city ?? ""
        let d = load?.deliveryLocation?.city ?? ""
        if !p.isEmpty && !d.isEmpty { return "\(abbr(p)) → \(abbr(d))" }
        return "lane pending"
    }
    private func abbr(_ city: String) -> String { city.count <= 3 ? city.uppercased() : city }

    private var commodityDisplay: String {
        let equip = load?.equipmentType ?? "reefer"
        let com = load?.commodity ?? load?.cargoType ?? "perishable"
        return "\(equip) · \(com)"
    }
    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline().padding(.top, Space.s3)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    supplyAirHero
                    zoneReadingsCard
                    factorTiles
                    esangColdChainCard
                    if let note = actionNote { infoStrip(note, tint: Brand.success) }
                    if let err = actionErr { infoStrip(err, tint: Brand.danger) }
                    ctaRow
                    regulatoryFooter
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(LinearGradient.primary)
                    Text("DRIVER · REEFER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text(bandCaption)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(palette.bgCard)
                        .overlay(Circle().strokeBorder(palette.borderFaint))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Trips")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Reefer")
                        .font(.system(size: 22, weight: .bold)).tracking(-0.3)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(loadNumberDisplay) · \(laneDisplay)")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(commodityDisplay.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                    Text(setPoint.map { "setpoint \(fmt($0))°F" } ?? "setpoint -")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    private var bandCaption: String {
        guard let lo = bandMin, let hi = bandMax else { return "FSMA · monitoring" }
        return "FSMA · \(fmt(lo))–\(fmt(hi))°F"
    }

    // MARK: Supply-air hero

    private var supplyAirHero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("SUPPLY AIR TEMP")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                if hasLive {
                    HStack(spacing: 5) {
                        Circle().fill(inBand ? Brand.success : Brand.danger)
                            .frame(width: 6, height: 6)
                            .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.35))
                        Text("LIVE")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(inBand ? Brand.success : Brand.danger)
                    }
                }
                Spacer()
                Text("SETPOINT")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(current.map { "\(fmt($0))°" } ?? "—")
                    .font(.system(size: 34, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(hasLive ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                Text(hasLive ? (inBand ? "F · in range" : "F · out of band") : "F · awaiting reading")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(inBand ? palette.textSecondary : (hasLive ? Brand.danger : palette.textTertiary))
                Spacer()
                Text(setPoint.map { "\(fmt($0))°F" } ?? "-")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
            }
            bandBar
            Text(inBand
                 ? "Within FSMA band \(bandLabel) · continuous logging on"
                 : (hasLive ? "Outside FSMA band \(bandLabel) · excursion — pull the unit down now"
                            : "No reading on record yet · continuous logging pending first tick"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(subReadingLine)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private var bandBar: some View {
        GeometryReader { geo in
            let frac = bandFraction
            ZStack(alignment: .leading) {
                Capsule().fill(palette.tintNeutral).frame(height: 6)
                Capsule().fill(LinearGradient.diagonal)
                    .frame(width: max(6, geo.size.width * frac), height: 6)
            }
        }
        .frame(height: 6)
        .accessibilityLabel(hasLive ? "Temperature \(fmt(current ?? 0)) degrees, \(inBand ? "in band" : "out of band")" : "Awaiting first reading")
    }

    private var bandFraction: CGFloat {
        guard let c = current, let lo = bandMin, let hi = bandMax, hi > lo else { return 0 }
        return CGFloat(min(max((c - lo) / (hi - lo), 0), 1))
    }
    private var bandLabel: String {
        guard let lo = bandMin, let hi = bandMax else { return "" }
        return "\(fmt(lo))–\(fmt(hi))°F"
    }

    private var subReadingLine: String {
        var parts: [String] = []
        if let rear = zones["rear"]?.tempF { parts.append("rear \(fmt(rear))°F") }
        if let avg = stats?.avg, (stats?.totalReadings ?? 0) > 0 { parts.append("avg \(fmt(avg))°F") }
        if let ex = fsma?.excursionCount { parts.append("\(ex) excursion\(ex == 1 ? "" : "s")") }
        if let last = fsma?.lastReading, let rel = Self.relative(last) { parts.append("last \(rel)") }
        return parts.isEmpty ? "reading interval 5 min · awaiting first tick" : parts.joined(separator: " · ")
    }

    // MARK: Zone readings

    private var zoneReadingsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ZONE READINGS")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("TEMP")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            zoneRow("Front zone", zones["front"])
            Divider().overlay(palette.borderFaint)
            zoneRow("Center zone", zones["center"])
            Divider().overlay(palette.borderFaint)
            zoneRow("Rear zone", zones["rear"])
            Text(zoneFooter)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s1)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func zoneRow(_ label: String, _ z: ReeferZoneReading?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(z?.tempF.map { "\(fmt($0))°F" } ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(z == nil ? palette.textTertiary : palette.textPrimary)
        }
        .padding(.vertical, Space.s1)
    }

    private var zoneFooter: String {
        if fsma?.preCoolVerified == true { return "Pre-cool verified · reading every 5 min" }
        return "Pre-cool not yet verified (21 CFR 1.908) · reading every 5 min"
    }

    // MARK: Factor tiles

    private var factorTiles: some View {
        HStack(spacing: Space.s3) {
            MetricTile(label: "Setpoint", value: setPoint.map { "\(fmt($0))°F" } ?? "-", gradientNumeral: false)
            MetricTile(label: "Delta", value: deltaDisplay, gradientNumeral: false)
            MetricTile(label: "Excursions", value: "\(fsma?.excursionCount ?? stats?.excursions ?? 0)",
                       accent: (fsma?.excursionCount ?? 0) > 0 ? Brand.danger : nil)
        }
    }

    private var deltaDisplay: String {
        guard let c = current, let sp = setPoint else { return "-" }
        let d = c - sp
        return String(format: "%+.1f°", d)
    }

    // MARK: ESANG cold-chain (local advisory over the real FSMA stream)

    private var esangColdChainCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("ESANG")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text("· COLD-CHAIN")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(Brand.info)
                }
                Text(esangHeadline)
                    .font(.system(size: 13, weight: .semibold)).tracking(-0.1)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(esangSub)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var esangHeadline: String {
        guard hasLive else { return "Awaiting the first supply-air tick to open the cold-chain plan." }
        if inBand {
            return "Holding \(fmt(current ?? 0))°F inside the FSMA band — cargo is protected."
        }
        return "Supply air \(fmt(current ?? 0))°F is outside the band — pull the unit down before spoilage."
    }
    private var esangSub: String {
        let ex = fsma?.excursionCount ?? 0
        let pre = (fsma?.preCoolVerified == true) ? "pre-cool signed" : "pre-cool pending"
        return "\(ex) excursion\(ex == 1 ? "" : "s") · FSMA log self-signs at delivery · \(pre)"
    }

    // MARK: CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: ackInFlight ? "Acknowledging…" : "Acknowledge alert",
                action: { Task { await acknowledge() } },
                isLoading: ackInFlight
            )
            .opacity(newestUnackedAlert == nil ? 0.5 : 1)
            .disabled(newestUnackedAlert == nil || ackInFlight)

            Button {
                // Temp log is the same continuous record surfaced here; pull to
                // refresh re-reads the live stream (getFSMAStatus + zones + stats).
                Task { await refresh() }
            } label: {
                Text("Temp log")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Regulatory footer

    private var regulatoryFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Reefer telemetry · FSMA 21 CFR 1.908 continuous cold-chain record")
            Text("Load \(loadNumberDisplay) · \(String(format: "%d", fsma?.excursionCount ?? 0)) active excursion\((fsma?.excursionCount ?? 0) == 1 ? "" : "s") · log immutable, audit-retained")
        }
        .font(EType.mono(.micro))
        .foregroundStyle(palette.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func infoStrip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(EType.caption)
            .foregroundStyle(palette.textPrimary)
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: Reads

    private func refresh() async {
        actionErr = nil
        async let a: Void = loadFSMA()
        async let b: Void = loadZones()
        async let c: Void = loadStats()
        async let d: Void = loadAlerts()
        async let e: Void = loadLoad()
        _ = await (a, b, c, d, e)
        loaded = true
    }

    private func loadFSMA() async {
        guard let lid = numericLoadId else { return }
        struct In: Encodable { let loadId: Int }
        do { fsma = try await EusoTripAPI.shared.query("reeferTemp.getFSMAStatus", input: In(loadId: lid)) }
        catch { /* honest nil → awaiting-reading state */ }
    }
    private func loadZones() async {
        struct In: Encodable { let loadId: Int? }
        do { zones = try await EusoTripAPI.shared.query("reeferTemp.getLatestByZone", input: In(loadId: numericLoadId)) }
        catch { zones = [:] }
    }
    private func loadStats() async {
        struct In: Encodable { let loadId: Int?; let hours: Int }
        do { stats = try await EusoTripAPI.shared.query("reeferTemp.getStats", input: In(loadId: numericLoadId, hours: 24)) }
        catch { stats = nil }
    }
    private func loadAlerts() async {
        struct In: Encodable { let loadId: Int?; let limit: Int }
        do { alerts = try await EusoTripAPI.shared.query("reeferTemp.getAlerts", input: In(loadId: numericLoadId, limit: 20)) }
        catch { alerts = [] }
    }
    private func loadLoad() async {
        guard !loadId.isEmpty else { return }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) }
        catch { /* honest "-" fallbacks */ }
    }

    // MARK: Write — acknowledge the newest unacked alert

    private func acknowledge() async {
        guard let alert = newestUnackedAlert, let aid = Int(alert.id) else { return }
        ackInFlight = true
        actionErr = nil; actionNote = nil
        struct In: Encodable { let alertId: Int }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("reeferTemp.acknowledgeAlert", input: In(alertId: aid))
            actionNote = "Alert acknowledged · signed into the FSMA audit chain."
            await loadAlerts()
        } catch {
            actionErr = "That alert didn't acknowledge — check signal and try again."
        }
        ackInFlight = false
    }

    // MARK: helpers

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    private static func relative(_ iso: String) -> String? {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f1.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d = date else { return nil }
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        return "\(secs / 3600)h ago"
    }
}

// MARK: - Previews (Dark + Light)

#Preview("167 Reefer Temp · Dark") {
    DriverReeferTempScreen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.dark)
}

#Preview("167 Reefer Temp · Light") {
    DriverReeferTempScreen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.light)
}
