//
//  818_VesselReeferManualReading.swift
//  EusoTrip — Vessel Operator · Reefer Manual Reading.
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/818 Vessel Reefer Manual Reading.svg" (Light + Dark),
//  built on the canonical DesignSystem at the golden-era bar. This screen IS the explicit DEGRADED
//  face of the cold-chain tick: when the reefer IoT heartbeat drops, the operator falls here to log a
//  verified manual spot reading rather than trust a stale live value. Every figure is labelled
//  last-good or manually entered — no value is presented as live. Role VESSEL_OPERATOR · nav
//  SHIPMENTS inked.
//
//  Data / wiring (endpoints confirmed on disk this fire):
//    reeferTemp.getLatestByZone EXISTS frontend/server/routers/reeferTemp.ts:149 · query ·
//      input {loadId?} · returns {front?:{tempF,tempC,status,recordedAt}, center?:{...}, rear?:{...}}
//      — the last-good per-zone reading + its age (drives the gap banner + the zone list). Empty {}
//      when there is no reading yet -> the honest empty state, never a fabricated temp.
//    reeferTemp.addReading EXISTS reeferTemp.ts:533 · mutation ·
//      input {tempF:Double, zone:"front"|"center"|"rear", loadId?, targetMin=33, targetMax=40,
//      notes?} · returns {success, status:"critical"|"warning"|"normal"}. Wired to "Record manual
//      reading" — server computes tempC + the FSMA-band status and auto-inserts a reeferAlerts row on
//      critical. RBAC roleProcedure(CATALYST/DRIVER/DISPATCH/TERMINAL_MANAGER/ADMIN/SUPER_ADMIN).
//    STUB · named-gap (carried open): reeferTemp is driver/admin-scoped by reeferReadings.driverId —
//      a vessel {operatorId,containerId} scope is flagged to the web team.
//    Reading-standard band = published cold-chain authorities (US FDA FSMA 21 CFR 1.908 33–40°F ·
//      CA CFIA °C · MX COFEPRIS °C) — regulatory constants.
//
//  ZoneReading818 is a file-scoped bespoke type. Dark + Light #Preview.
//
//  — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Data shapes (reeferTemp.getLatestByZone)

private struct ZoneReading818: Decodable {
    let tempF: Double?
    let tempC: Double?
    let status: String?
    let recordedAt: String?
}
private struct LatestByZone818: Decodable {
    let front: ZoneReading818?
    let center: ZoneReading818?
    let rear: ZoneReading818?
}

private enum ReeferZone818: String, CaseIterable, Identifiable {
    case front, center, rear
    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

// MARK: - Screen wrapper (Shell + vessel nav · SHIPMENTS inked)

struct VesselReeferManualReadingScreen: View {
    let theme: Theme.Palette
    /// Reefer FCL booking. 0 = operator's own latest readings across loads.
    var loadId: Int

    init(theme: Theme.Palette, loadId: Int = 0) { self.theme = theme; self.loadId = loadId }

    var body: some View {
        Shell(theme: theme) {
            VesselReeferManualReadingBody818(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselReeferManualReadingBody818: View {
    @Environment(\.palette) private var palette
    let loadId: Int

    @State private var zones: LatestByZone818? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var captureZone: ReeferZone818 = .rear
    @State private var manualTempF: Double = 38
    @State private var recording = false
    @State private var recordStatus: String? = nil
    @State private var recordError: String? = nil

    private let targetMin = 33.0
    private let targetMax = 40.0
    private let displayLo = 30.0
    private let displayHi = 42.0

    // Derived from the one real load ---------------------------------------
    private func reading(_ z: ReeferZone818) -> ZoneReading818? {
        switch z { case .front: return zones?.front; case .center: return zones?.center; case .rear: return zones?.rear }
    }
    private var readingsPresent: Bool { [ReeferZone818.front, .center, .rear].contains { reading($0)?.tempF != nil } }
    private var inBandCount: Int {
        [ReeferZone818.front, .center, .rear].filter { z in
            guard let t = reading(z)?.tempF else { return false }
            return t >= targetMin && t <= targetMax
        }.count
    }
    private var totalReadings: Int { [ReeferZone818.front, .center, .rear].filter { reading($0)?.tempF != nil }.count }
    /// Minutes since the most-recent reading across zones (the "telemetry gap").
    private var lastTickAgeMin: Int? {
        let dates: [Date] = [ReeferZone818.front, .center, .rear].compactMap { reading($0)?.recordedAt }.compactMap { iso in
            ISO8601DateFormatter().date(from: iso)
        }
        guard let latest = dates.max() else { return nil }
        return max(0, Int(Date().timeIntervalSince(latest) / 60))
    }
    private var worstZone: ReeferZone818 {
        let ranked = [ReeferZone818.front, .center, .rear].compactMap { z -> (ReeferZone818, Double)? in
            guard let t = reading(z)?.tempF else { return nil }
            return (z, t)
        }
        return ranked.max(by: { $0.1 < $1.1 })?.0 ?? .rear
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                topBar
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    gapHero
                    captureCard
                    zoneList
                    esangCard
                    actionRow
                    readingStandard
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Eyebrow + top bar

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · MANUAL READING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text(loadId > 0 ? "LOAD \(loadId) · OFFLINE" : "MANUAL")
                .font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Manual reading").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCardSoft).frame(height: 150)
            RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft).frame(height: 84)
        }.padding(.top, Space.s2)
    }
    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Zone feed degraded").font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Gap hero (telemetry-gap banner + setpoint band)

    private var gapHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Brand.warning).frame(width: 6, height: 6)
                    Text("TELEMETRY GAP · MANUAL").font(.system(size: 9.5, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(Brand.warning)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Brand.warning.opacity(0.16)))
                Spacer()
                Text(lastTickAgeMin.map { "last tick · \($0)m" } ?? "no reading yet")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            Text("SETPOINT BAND · 33–40°F · LAST-GOOD ZONES")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s4)
            setpointBand.padding(.top, Space.s2)
            HStack {
                Text("33°F min").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("40°F max").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            .padding(.top, 6)
            Text(readingsPresent
                 ? "\(inBandCount)/\(totalReadings) in band · \(worstZone.label) worst — capture a spot reading"
                 : "no last-good zones — capture a manual spot reading")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.warning)
                .padding(.top, Space.s3)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var setpointBand: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let lo = CGFloat((targetMin - displayLo) / (displayHi - displayLo)) * w
            let hi = CGFloat((targetMax - displayLo) / (displayHi - displayLo)) * w
            ZStack(alignment: .leading) {
                Capsule().fill(palette.bgCardSoft).frame(height: 16)
                Capsule().fill(Brand.success.opacity(0.20)).frame(width: max(0, hi - lo), height: 16).offset(x: lo)
                Rectangle().fill(Brand.success).frame(width: 2, height: 16).offset(x: lo)
                Rectangle().fill(Brand.warning).frame(width: 2, height: 16).offset(x: hi)
                ForEach([ReeferZone818.front, .center, .rear]) { z in
                    if let t = reading(z)?.tempF {
                        let x = CGFloat((min(max(t, displayLo), displayHi) - displayLo) / (displayHi - displayLo)) * w
                        Circle().fill(zoneColor(z))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.6))
                            .frame(width: 12, height: 12)
                            .offset(x: x - 6)
                            .accessibilityLabel("\(z.label) \(Int(t))°F")
                    }
                }
            }
        }
        .frame(height: 16)
    }

    private func zoneColor(_ z: ReeferZone818) -> Color {
        switch z { case .front: return Brand.success; case .center: return Brand.info; case .rear: return Brand.warning }
    }

    // MARK: Manual capture (stepper)

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("MANUAL CAPTURE")
                Spacer()
                // Zone selector (worst zone default)
                HStack(spacing: 4) {
                    ForEach(ReeferZone818.allCases) { z in
                        Button(action: { captureZone = z }) {
                            Text(z.label.uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(captureZone == z ? Color.white : palette.textSecondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(captureZone == z ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(captureZone.label) zone spot reading")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text("probe · °F · manual entry").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: Space.s2)
                stepper
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var stepper: some View {
        HStack(spacing: 10) {
            stepButton(system: "minus") { manualTempF = max(displayLo - 5, manualTempF - 1) }
            Text("\(manualTempF >= 0 ? "+" : "")\(Int(manualTempF))°F")
                .font(.system(size: 22, weight: .bold, design: .monospaced)).monospacedDigit()
                .foregroundStyle(manualTempF > targetMax ? Brand.danger : (manualTempF > targetMax - 2 ? Brand.warning : palette.textPrimary))
                .frame(width: 92, height: 40)
                .background((manualTempF > targetMax - 2 ? Brand.warning : Brand.success).opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder((manualTempF > targetMax - 2 ? Brand.warning : Brand.success).opacity(0.6)))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            stepButton(system: "plus", gradient: true) { manualTempF = min(displayHi + 5, manualTempF + 1) }
        }
    }

    private func stepButton(system: String, gradient: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 15, weight: .bold))
                .foregroundStyle(gradient ? Color.white : palette.textSecondary)
                .frame(width: 36, height: 36)
                .background(gradient ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(system == "plus" ? "Increase temperature" : "Decrease temperature")
    }

    // MARK: Zone readings list (real last-good)

    private var zoneList: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ZONE READINGS · FRONT / CENTER / REAR")
            VStack(spacing: 0) {
                ForEach(Array([ReeferZone818.front, .center, .rear].enumerated()), id: \.offset) { idx, z in
                    zoneRow(z)
                    if idx < 2 { Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 68) }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func zoneRow(_ z: ReeferZone818) -> some View {
        let r = reading(z)
        let t = r?.tempF
        let band = statusBand(z, t)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(band.color.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: "thermometer.medium").font(.system(size: 16, weight: .semibold)).foregroundStyle(band.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(z.label) zone").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(zoneSub(z, r)).font(EType.mono(.caption)).foregroundStyle(band.color == Brand.success ? palette.textSecondary : band.color).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(text: band.label, kind: band.pill)
                Text(t.map { "\($0 >= 0 ? "+" : "")\(Int($0))°F" } ?? "—")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(band.color == Brand.success ? palette.textPrimary : band.color)
            }
        }
        .padding(Space.s4)
    }

    private func zoneSub(_ z: ReeferZone818, _ r: ZoneReading818?) -> String {
        guard let t = r?.tempF else { return "no last-good reading" }
        let age = r?.recordedAt.flatMap { iso -> String? in
            guard let d = ISO8601DateFormatter().date(from: iso) else { return nil }
            let m = max(0, Int(Date().timeIntervalSince(d) / 60))
            return m < 60 ? "\(m)m ago" : "\(m/60)h ago"
        } ?? "last-good"
        if t > targetMax { return "+\(Int(t))°F · \(Int(t - targetMax))°F over max" }
        if t > targetMax - 2 { return "+\(Int(t))°F · \(Int(targetMax - t))°F below max" }
        return "+\(Int(t))°F · \(age) · in band"
    }

    private struct Band818 { let label: String; let color: Color; let pill: StatusPill.Kind }
    private func statusBand(_ z: ReeferZone818, _ t: Double?) -> Band818 {
        guard let t = t else { return Band818(label: "NO DATA", color: palette.textTertiary, pill: .neutral) }
        if t > targetMax { return Band818(label: "CRITICAL", color: Brand.danger, pill: .danger) }
        if t > targetMax - 2 { return Band818(label: "WARNING", color: Brand.warning, pill: .warning) }
        return Band818(label: "NORMAL", color: Brand.success, pill: .success)
    }

    // MARK: ESang re-check plan

    private var esangCard: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.7), .clear], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 16)).frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("ESANG · RE-CHECK PLAN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("\(worstZone.label) drifting to \(Int(targetMax))°F — re-check in 30 min")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(lastTickAgeMin.map { "escalate if it crosses the limit · telemetry gapped \($0)m" } ?? "escalate if it crosses the limit")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Actions

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let e = recordError { Text(e).font(EType.caption).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true) }
            if let s = recordStatus {
                Text("Logged · \(captureZone.label) \(Int(manualTempF))°F · \(s.uppercased()).")
                    .font(EType.caption).foregroundStyle(s == "critical" ? Brand.danger : (s == "warning" ? Brand.warning : Brand.success))
            }
            HStack(spacing: Space.s2) {
                CTAButton(title: recording ? "Recording…" : "Record manual reading",
                          action: { Task { await record() } }, isLoading: recording)
                    .frame(maxWidth: .infinity)
                Button(action: {}) {
                    Text("Telemetry")
                        .font(EType.title).foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain).frame(maxWidth: 132)
            }
        }
    }

    // MARK: Reading standard band

    private var readingStandard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("READING STANDARD · ACTIVE MARKET")
            HStack(spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("US").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 22, height: 16).background(Brand.blue).clipShape(RoundedRectangle(cornerRadius: 5))
                        Text("FDA FSMA · °F").font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text("ACTIVE").font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.info)
                    }
                    Text("21 CFR 1.908 · band 33–40°F").font(EType.mono(.micro)).foregroundStyle(Brand.info.opacity(0.85))
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.info.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.info.opacity(0.45)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                standbyMarket("CA", "CFIA °C")
                standbyMarket("MX", "COFEPRIS °C")
            }
        }
    }

    private func standbyMarket(_ code: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(code).font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textSecondary)
            Text(detail).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary).lineLimit(1)
        }
        .padding(Space.s3).frame(width: 78, height: 52, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }

    // MARK: Load + record

    private func load() async {
        loading = true; loadError = nil
        struct In818: Encodable { let loadId: Int? }
        do {
            let z: LatestByZone818 = try await EusoTripAPI.shared.query(
                "reeferTemp.getLatestByZone", input: In818(loadId: loadId > 0 ? loadId : nil))
            zones = z
            // Seed the stepper + zone selector to the worst last-good zone.
            captureZone = worstZone
            if let t = reading(worstZone)?.tempF { manualTempF = t }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func record() async {
        recording = true; recordError = nil; recordStatus = nil
        struct In818: Encodable {
            let tempF: Double
            let zone: String
            let loadId: Int?
            let targetMin: Double
            let targetMax: Double
        }
        struct Out818: Decodable { let success: Bool?; let status: String? }
        do {
            let out: Out818 = try await EusoTripAPI.shared.mutation(
                "reeferTemp.addReading",
                input: In818(tempF: manualTempF, zone: captureZone.rawValue,
                             loadId: loadId > 0 ? loadId : nil, targetMin: targetMin, targetMax: targetMax))
            recordStatus = out.status ?? "normal"
            await load()
        } catch {
            recordError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        recording = false
    }
}

// MARK: - Previews

#Preview("818 · Vessel Reefer Manual Reading · Night") {
    VesselReeferManualReadingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("818 · Vessel Reefer Manual Reading · Light") {
    VesselReeferManualReadingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
